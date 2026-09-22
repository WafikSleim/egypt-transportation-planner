"""The place index: a Postgres/PostGIS table built from OpenStreetMap.

Why this exists at all. `/stops` searches OTP, whose stop search is
*prefix*-based and language-scoped: `المنيب` matches, `منيب` does not, and
`Moneeb&lang=ar` returns nothing. A passenger does not know the name of the
stop that serves Cairo Festival City, and does not type the definite article.
So this is a second index with different behaviour -- substring and fuzzy,
across both scripts at once -- and the UI says so, because the difference is
visible and would otherwise read as the app being broken.

Why it is a *separate database*. OSM is ODbL and the TfC transit data is
CC BY-NC. The two licences are incompatible if merged into one derived
database: ODbL requires the result be ODbL (commercial allowed), CC BY-NC
forbids commercial use. Kept side by side as independent databases they are a
"collective" database, which neither licence objects to. Hence
`PLACES_DATABASE_URL` rather than a general-purpose `DATABASE_URL`: the
connection is named for the one dataset it may hold, so pointing it at a
transit database and joining is an obvious mistake rather than the path of
least resistance. Nothing derived from TfC is ever written here, and `/places`
answers carry OSM's attribution, not TfC's.

Everything that knows SQL lives in this module, exactly as everything that
knows GraphQL lives in `otp.py`. `main.py` deals in plain dicts and turns them
into response models.
"""

from __future__ import annotations

import asyncio
import re
import threading
import unicodedata
from typing import Any, Awaitable, Callable, NamedTuple

from . import config

# Injection point for tests, the counterpart of `otp.TRANSPORT`. Left None in
# production. A test sets it to a coroutine taking (sql, params) and returning
# rows, which still exercises the real SQL text, the real parameter binding and
# the real row-to-model mapping -- the parts that break quietly. What it cannot
# exercise is whether Postgres accepts the SQL, so the schema and these queries
# are also run against a real database by hand; see scripts/build_places.py.
EXECUTOR: Callable[[str, dict[str, Any]], Awaitable[list[dict]]] | None = None


class PlacesUnavailable(RuntimeError):
    """The place database could not be reached, or refused the query.

    Deliberately carries no SQL and no parameters: the message ends up in a
    503 body and, in some deployments, a log line, and a `q` parameter is a
    place somebody typed. `api/logs.py` strips query strings from the access
    log; it cannot strip them out of an exception someone chose to format.
    """


# --------------------------------------------------------------------------
# Categories
# --------------------------------------------------------------------------

class Category(NamedTuple):
    id: str    # stable key for the client to switch on
    en: str
    ar: str
    rank: int  # tie-break between equally good name matches; see `importance`

    def label(self, lang: str) -> str:
        return self.ar if lang == "ar" else self.en


# The vocabulary the client sees. Ranks are "how likely is this to be what
# somebody meant when two names match equally well" -- a district beats a
# residential street of the same name, an airport beats a school.
CATEGORIES: dict[str, Category] = {
    "city": Category("city", "City", "مدينة", 95),
    "district": Category("district", "District", "حي", 80),
    "neighbourhood": Category("neighbourhood", "Neighbourhood", "منطقة", 70),
    "village": Category("village", "Village", "قرية", 60),
    "square": Category("square", "Square", "ميدان", 78),
    "street": Category("street", "Street", "شارع", 25),
    "mall": Category("mall", "Mall", "مول", 76),
    "market": Category("market", "Market", "سوق", 55),
    "university": Category("university", "University", "جامعة", 82),
    "school": Category("school", "School", "مدرسة", 35),
    "hospital": Category("hospital", "Hospital", "مستشفى", 74),
    "clinic": Category("clinic", "Clinic", "عيادة", 40),
    # "Station", not "train station": OSM tags mainline and metro stations
    # alike as railway=station, and the metro is what most of these are.
    "station": Category("station", "Station", "محطة", 80),
    "bus_station": Category("bus_station", "Bus terminal", "موقف", 72),
    "airport": Category("airport", "Airport", "مطار", 96),
    "park": Category("park", "Park", "حديقة", 50),
    "stadium": Category("stadium", "Stadium", "استاد", 68),
    "club": Category("club", "Sports club", "نادي", 58),
    "museum": Category("museum", "Museum", "متحف", 66),
    "landmark": Category("landmark", "Landmark", "معلم", 62),
    "mosque": Category("mosque", "Mosque", "مسجد", 52),
    "church": Category("church", "Church", "كنيسة", 52),
    "place_of_worship": Category("place_of_worship", "Place of worship",
                                 "دار عبادة", 50),
    "government": Category("government", "Government office", "جهة حكومية", 60),
    "embassy": Category("embassy", "Embassy", "سفارة", 60),
    "police": Category("police", "Police station", "قسم شرطة", 55),
    "courthouse": Category("courthouse", "Courthouse", "محكمة", 58),
    "post_office": Category("post_office", "Post office", "مكتب بريد", 45),
    "library": Category("library", "Library", "مكتبة", 48),
    "theatre": Category("theatre", "Theatre", "مسرح", 50),
    "cinema": Category("cinema", "Cinema", "سينما", 50),
    "hotel": Category("hotel", "Hotel", "فندق", 54),
}

FALLBACK_CATEGORY = CATEGORIES["landmark"]


def category(cat_id: str) -> Category:
    """Never raise on a category the database holds and this build does not.

    The table is rebuilt by a script that can run ahead of a deploy, so an
    unknown key has to degrade rather than 500 a typeahead.
    """
    return CATEGORIES.get(cat_id, FALLBACK_CATEGORY)


# --------------------------------------------------------------------------
# Name normalisation
# --------------------------------------------------------------------------
#
# This is the whole of the fuzzy matching, and it has to be byte-identical on
# both sides: `build_places.py` normalises the OSM names into `name_norm` /
# `name_norm_ar`, and a search normalises the passenger's query the same way
# before it goes near the database. If the two ever drift, search half-works --
# some queries hit, some silently do not -- which is the hardest kind of
# failure to notice. One function, imported by both.

_ARABIC_DIACRITICS = re.compile(
    "[ؐ-ًؚ-ٰٟۖ-ۜ۟-ۨ"
    "۪-ۭـ]"          # includes tatweel U+0640
)
_ARABIC_LETTER = re.compile(r"[؀-ۿݐ-ݿ]")
# Deleted outright rather than turned into a separator: the apostrophes and
# modifier letters of Arabic transliteration. "El-Maʿādī" and "Ma'adi" must
# fold to "maadi", not to "ma adi" -- splitting the word there loses the
# match, which is the opposite of the point.
_DROPPED = re.compile(r"[ʰ-˿‘’´'`]")
# Everything else that is not an ASCII letter, an ASCII digit or an Arabic
# *letter* is a separator. By the time this runs the string has been
# casefolded and its Latin diacritics removed. Note the ranges are the letter
# blocks rather than the whole of U+0600-06FF: that block also holds Arabic
# punctuation — ، ؛ ؟ ٪ ۔ — and keeping those would let a query of nothing but
# question marks survive normalisation.
_NON_WORD = re.compile(
    r"[^0-9a-zء-غف-يٮ-ۓەۺ-ۼ]+")

# Orthographic variants Egyptians type interchangeably. Search has to treat
# them as the same letter or half the queries in the country miss.
_ARABIC_FOLD = str.maketrans({
    "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا",
    "ة": "ه",
    "ى": "ي", "ئ": "ي",
    "ؤ": "و",
    "ک": "ك", "ﻻ": "لا",
    # Arabic-Indic digits: street names are full of them, and a phone keyboard
    # will produce either set.
    "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
    "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
    "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
    "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
})

# Stripped from the front of a name so that «منيب» finds «المنيب» and
# «شارع الهرم» finds «الهرم». Only ever from the start, and only as a whole
# word: "الف" is a word, not "the F".
_LEADING_NOISE = ("ال", "el ", "al ", "the ")


def is_arabic(text: str) -> bool:
    """True if the string contains Arabic letters. Used to decide which of the
    two name columns a string belongs in, and which language a name is in."""
    return bool(_ARABIC_LETTER.search(text or ""))


def normalize_name(text: str) -> str:
    """Fold a name or a query down to a comparable key.

    Deliberately aggressive: it is a search key, never displayed.
    """
    if not text:
        return ""
    # NFKC first, so presentation forms and ligatures collapse before folding.
    s = unicodedata.normalize("NFKC", text)
    s = _ARABIC_DIACRITICS.sub("", s)
    s = s.translate(_ARABIC_FOLD)
    s = s.casefold()
    # Latin diacritics (El-Maʿādī) folded to ASCII.
    s = "".join(c for c in unicodedata.normalize("NFD", s)
                if not unicodedata.combining(c))
    s = _DROPPED.sub("", s)
    s = _NON_WORD.sub(" ", s).strip()
    for prefix in _LEADING_NOISE:
        if s.startswith(prefix) and len(s) > len(prefix) + 1:
            s = s[len(prefix):].strip()
            break
    return re.sub(r"\s+", " ", s)


# --------------------------------------------------------------------------
# Queries
# --------------------------------------------------------------------------
#
# Two notes on the SQL below.
#
# * `%%` is a literal percent under psycopg's pyformat binding, so the trigram
#   operator `%` and the wildcards in LIKE are both doubled. Getting this wrong
#   fails at the database, not here, which is why these queries are exercised
#   against a real PostGIS instance and not only against the test fake.
# * The bounding box is in the WHERE clause on every query, not applied
#   afterwards. A place outside Greater Cairo is a place no itinerary can be
#   planned to, and offering one produces a search result that leads to an
#   empty trip -- the single most disappointing thing this app can do.

_COLUMNS = """
    p.osm_type, p.osm_id, p.category,
    p.name, p.name_ar, p.name_en,
    p.area_ar, p.area_en,
    p.lat, p.lon, p.importance
"""

# Both name columns are searched on every request, whatever `lang` says.
# `lang` decides which name comes *back*. Scoping the search by language is
# what makes OTP's stop search return nothing for `Moneeb&lang=ar`, and this
# endpoint exists to end that confusion rather than reproduce it.
SEARCH_SQL = f"""
SELECT {_COLUMNS},
       CASE WHEN %(near_lat)s::double precision IS NULL THEN NULL
            ELSE ST_Distance(
                p.geom,
                ST_SetSRID(ST_MakePoint(%(near_lon)s::double precision,
                                        %(near_lat)s::double precision),
                           4326)::geography)
       END AS distance_m,
       GREATEST(similarity(p.name_norm, %(q)s),
                similarity(COALESCE(p.name_norm_ar, ''), %(q)s)) AS score,
       COUNT(*) OVER () AS total_matches
FROM osm.places p
WHERE p.lat BETWEEN %(min_lat)s AND %(max_lat)s
  AND p.lon BETWEEN %(min_lon)s AND %(max_lon)s
  AND (p.name_norm LIKE '%%' || %(q)s || '%%'
       OR COALESCE(p.name_norm_ar, '') LIKE '%%' || %(q)s || '%%'
       OR p.name_norm %% %(q)s
       OR COALESCE(p.name_norm_ar, '') %% %(q)s)
ORDER BY
    (p.name_norm = %(q)s OR p.name_norm_ar = %(q)s) DESC,
    (p.name_norm LIKE %(q)s || '%%'
     OR COALESCE(p.name_norm_ar, '') LIKE %(q)s || '%%') DESC,
    GREATEST(similarity(p.name_norm, %(q)s),
             similarity(COALESCE(p.name_norm_ar, ''), %(q)s)) DESC,
    CASE WHEN %(near_lat)s::double precision IS NULL THEN 0
         ELSE ST_Distance(
             p.geom,
             ST_SetSRID(ST_MakePoint(%(near_lon)s::double precision,
                                     %(near_lat)s::double precision),
                        4326)::geography)
    END ASC,
    p.importance DESC,
    p.osm_id ASC
LIMIT %(limit)s
"""

# Reverse geocoding for the map picker (P-18): what is the passenger pointing
# at? Ordered by distance in 100 m buckets and by importance inside a bucket,
# so that standing in the car park of a mall names the mall rather than the
# service road beside it. Pure nearest-neighbour ordering gets that wrong
# often enough to matter, and residential streets are the most common thing
# within 50 m of anywhere in Cairo.
REVERSE_SQL = f"""
SELECT {_COLUMNS},
       ST_Distance(
           p.geom,
           ST_SetSRID(ST_MakePoint(%(lon)s::double precision,
                                   %(lat)s::double precision),
                      4326)::geography) AS distance_m,
       NULL::real AS score,
       COUNT(*) OVER () AS total_matches
FROM osm.places p
WHERE p.lat BETWEEN %(min_lat)s AND %(max_lat)s
  AND p.lon BETWEEN %(min_lon)s AND %(max_lon)s
  AND ST_DWithin(
        p.geom,
        ST_SetSRID(ST_MakePoint(%(lon)s::double precision,
                                %(lat)s::double precision),
                   4326)::geography,
        %(radius_m)s)
ORDER BY
    floor(ST_Distance(
        p.geom,
        ST_SetSRID(ST_MakePoint(%(lon)s::double precision,
                                %(lat)s::double precision),
                   4326)::geography) / 100.0) ASC,
    p.importance DESC,
    ST_Distance(
        p.geom,
        ST_SetSRID(ST_MakePoint(%(lon)s::double precision,
                                %(lat)s::double precision),
                   4326)::geography) ASC
LIMIT %(limit)s
"""

# Cheap liveness probe for /health. Counts are what tell a maintainer the
# ingest ran, and an empty table is the failure mode that looks exactly like
# "nothing matched your search".
STATS_SQL = """
SELECT COUNT(*) AS place_count,
       COUNT(DISTINCT p.category) AS category_count,
       COUNT(p.name_ar) AS arabic_count
FROM osm.places p
"""


# --------------------------------------------------------------------------
# Connection handling
# --------------------------------------------------------------------------

#
# Two decisions here, both of which cost a working afternoon to find and
# neither of which any amount of stubbing would have surfaced.
#
# 1. The *synchronous* driver, in a worker thread, rather than psycopg's
#    async mode. Async psycopg refuses to run on asyncio's ProactorEventLoop
#    -- "Psycopg cannot use the 'ProactorEventLoop' to run in async mode" --
#    which is the default on Windows and what uvicorn installs there. The
#    policy is set before uvicorn imports the app, so nothing this module can
#    do at import time changes it. Against a real database every /places
#    request answered 503 after a five-second timeout.
#
# 2. A thread-local connection rather than `psycopg_pool`. Its worker threads
#    never start under Python 3.14 (psycopg-pool 3.3.2): every checkout ends
#    in `PoolTimeout` with no connection attempt logged, while a plain
#    `psycopg.connect()` to the same URL succeeds. `asyncio.to_thread` runs on
#    the loop's default executor, whose threads are reused, so one connection
#    per thread reopened on failure gives the reuse a pool would have given,
#    with nothing to go wrong. Measured: ~14 ms to open the connection, 2-3 ms
#    per query after it. (If that first number is ever seconds rather than
#    milliseconds, the host in PLACES_DATABASE_URL has become `localhost` --
#    see config.py.)
#
# The number of connections is therefore bounded by that executor
# (min(32, cpu+4) threads), not by a pool size. On one box serving one city
# that is well inside Postgres's default 100.

_local = threading.local()


def _connect():
    """One connection per worker thread, opened on first use.

    psycopg is imported here, not at module scope, so that importing `api` --
    which the whole test suite does -- needs neither the driver nor a database.
    """
    conn = getattr(_local, "conn", None)
    if conn is not None and not conn.closed:
        return conn
    try:
        import psycopg
        from psycopg.rows import dict_row
    except ImportError as exc:  # pragma: no cover - deployment error
        raise PlacesUnavailable(
            "The place database driver is not installed. Install "
            "requirements.txt (psycopg)."
        ) from exc
    conn = psycopg.connect(
        config.PLACES_DATABASE_URL,
        autocommit=True,                      # read-only; nothing to commit
        row_factory=dict_row,
        connect_timeout=int(config.PLACES_TIMEOUT),
    )
    _local.conn = conn
    return conn


def _drop_connection() -> None:
    conn = getattr(_local, "conn", None)
    _local.conn = None
    if conn is not None:
        try:
            conn.close()
        except Exception:
            pass


def _fetch_blocking(sql: str, params: dict[str, Any]) -> list[dict]:
    try:
        return list(_connect().execute(sql, params).fetchall())
    except PlacesUnavailable:
        raise
    except Exception:
        # A connection that has been idle across a Postgres restart fails on
        # use, not on checkout. Reopen once; a second failure is real.
        _drop_connection()
        return list(_connect().execute(sql, params).fetchall())


async def fetch(sql: str, params: dict[str, Any]) -> list[dict]:
    """Run one query and return its rows as dicts.

    Failures are collapsed into `PlacesUnavailable` with a message that names
    neither the SQL nor the parameters -- see the note on that exception.
    """
    if EXECUTOR is not None:
        return await EXECUTOR(sql, params)

    try:
        return await asyncio.to_thread(_fetch_blocking, sql, params)
    except PlacesUnavailable:
        raise
    except Exception as exc:
        # The class name is the diagnostic; the text of a psycopg error can
        # quote the statement back, parameters included.
        raise PlacesUnavailable(
            "The place index is unavailable "
            f"({type(exc).__name__}). Place search needs Postgres; trip "
            "planning and stop search do not."
        ) from exc


# --------------------------------------------------------------------------
# The two searches
# --------------------------------------------------------------------------

def _bbox(coverage: dict[str, float]) -> dict[str, float]:
    return {k: coverage[k] for k in
            ("min_lat", "max_lat", "min_lon", "max_lon")}


async def search(q: str, coverage: dict[str, float], limit: int,
                 near: dict[str, float] | None = None) -> list[dict]:
    """Substring-and-fuzzy search over both name columns, inside the bbox."""
    needle = normalize_name(q)
    if not needle:
        # Normalisation can empty a query that passed the length check --
        # "؟؟" or "..." -- and an empty needle makes the LIKE match every row
        # in the table, so the passenger would get twenty arbitrary places
        # rather than nothing.
        return []
    params = _bbox(coverage)
    params.update({
        "q": needle,
        "limit": limit,
        "near_lat": near["lat"] if near else None,
        "near_lon": near["lon"] if near else None,
    })
    return await fetch(SEARCH_SQL, params)


async def nearest(lat: float, lon: float, coverage: dict[str, float],
                  limit: int, radius_m: float) -> list[dict]:
    params = _bbox(coverage)
    params.update({"lat": lat, "lon": lon, "limit": limit,
                   "radius_m": radius_m})
    return await fetch(REVERSE_SQL, params)


async def stats() -> dict:
    rows = await fetch(STATS_SQL, {})
    return rows[0] if rows else {"place_count": 0, "category_count": 0,
                                 "arabic_count": 0}
