#!/usr/bin/env python3
"""Build the `places` search index from the OpenStreetMap extract on disk.

A passenger cannot search for a mall, a street or a landmark today. `/stops`
searches OTP, whose stop search is prefix-based and scoped to one language, so
`منيب` finds nothing and `Moneeb&lang=ar` finds nothing. Nobody knows the name
of the stop that serves Cairo Festival City. This builds the second index the
app needs, out of `OTP/egypt-260919.osm.pbf`, which is already on disk for the
street network.

Not Photon. Photon wants Elasticsearch alongside OTP's measured 3.4 GB, on a
free-tier box that has to hold both.

LICENCE - the constraint that shapes everything here
----------------------------------------------------
OSM is ODbL. The TfC transit data is CC BY-NC. Merged into one derived
database the two contradict each other: ODbL requires the result be ODbL, which
permits commercial use, and CC BY-NC forbids it. Kept side by side as
independent databases they are a collective database, which neither licence
objects to - the same arrangement OTP already has, loading OSM and GTFS
separately.

So this writes to its own database (`PLACES_DATABASE_URL`, default
`masar_places`), it never reads the GTFS feeds, and nothing derived from them
is ever written into it. `/places` answers carry OpenStreetMap's attribution,
not TfC's. Do not "improve" this by joining stops into the same table.

WHICH TAGS, AND WHY
-------------------
The index holds things a passenger names as a destination. It deliberately
does not hold everything named.

Counted inside the coverage box on the 2026-09-19 extract: 139,089 named
features, of which 129,730 carry `name:ar` - 93%. The excluded tail is large:
998 supermarkets, 650 restaurants, 446 cafes, 321 takeaways, 308 bank
branches, 226 filling stations, 211 pharmacies. Those are chains and corner
shops. Indexing them does not merely make the table bigger, it makes the
*top* result wrong - a search for a district returns the branch of a bank
named after it - and a typeahead is judged entirely on its first three rows.
A smaller index whose first row is right beats a complete one.

Transit stops are excluded too, and not only for size: `highway=bus_stop`,
`public_transport=*` and `railway=stop|halt|tram_stop` are what `/stops`
serves out of the transit feeds. Conflating the two is the thing the licences
forbid and the thing design-system rule 4 forbids independently, because a
passenger needs to know whether a result is somewhere a vehicle calls or
somewhere they are going.

Usage
-----
    docker compose up -d places-db          # once; see docker-compose.yml
    python scripts/build_places.py --dry-run
    python scripts/build_places.py
    python scripts/build_places.py --check  # run the API's own SQL against it

Reading the extract needs pyosmium, which is not a runtime dependency of the
API and is not installed by requirements.txt:

    python -m pip install osmium

Like the other scripts here this is idempotent - it truncates and rewrites in
one transaction, so re-running produces the same table rather than a doubled
one - and it refuses to write when a sanity check fails.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))

# The normalisation has to be the same function the query path uses. If the
# two ever drift, search half-works: some queries hit, some silently do not.
from api import config                       # noqa: E402
from api.places import is_arabic, normalize_name  # noqa: E402

BBOX = config.COVERAGE


def default_pbf() -> Path | None:
    """The newest extract in OTP/, found rather than named.

    The filename carries its download date on purpose — `egypt-260919.osm.pbf`
    — so that it is obvious how stale the base map is, which means hardcoding
    one here would break on the next download. Sorting is by name because the
    date is in it; ties go to whichever the filesystem lists last.
    """
    candidates = sorted((REPO / "OTP").glob("*.osm.pbf"))
    return candidates[-1] if candidates else None


# --------------------------------------------------------------------------
# Classification
# --------------------------------------------------------------------------
#
# Checked in priority order, so a university tagged `building=yes` as well
# comes out a university. The category keys must exist in
# `api.places.CATEGORIES`, which holds their Arabic and English labels; a
# check below enforces that rather than leaving it to be noticed in the UI.

PLACE = {
    "city": "city", "town": "city",
    "suburb": "district", "quarter": "district", "borough": "district",
    "neighbourhood": "neighbourhood", "city_block": "neighbourhood",
    "village": "village", "hamlet": "village",
    "square": "square",
}

AMENITY = {
    "university": "university", "college": "university",
    "school": "school", "kindergarten": "school",
    "hospital": "hospital",
    "clinic": "clinic", "doctors": "clinic",
    "marketplace": "market",
    "bus_station": "bus_station",
    "ferry_terminal": "station",
    "place_of_worship": "place_of_worship",   # refined by `religion` below
    "police": "police",
    "courthouse": "courthouse",
    "townhall": "government",
    "embassy": "embassy",
    "library": "library",
    "theatre": "theatre",
    "cinema": "cinema",
    "post_office": "post_office",
    "exhibition_centre": "landmark",
    "conference_centre": "landmark",
}

SHOP = {"mall": "mall", "department_store": "mall"}

TOURISM = {
    "museum": "museum",
    "attraction": "landmark", "theme_park": "landmark", "zoo": "landmark",
    "hotel": "hotel", "resort": "hotel",
}

LEISURE = {
    "park": "park", "garden": "park",
    "stadium": "stadium",
    "sports_centre": "club", "sports_club": "club", "fitness_centre": "club",
}

HISTORIC = {
    "archaeological_site": "landmark", "monument": "landmark",
    "memorial": "landmark", "castle": "landmark", "fort": "landmark",
    "tomb": "landmark", "ruins": "landmark",
}

AEROWAY = {"aerodrome": "airport"}

# `railway=station` covers mainline and metro alike, which is why the label is
# the neutral "Station" / "محطة" rather than "train station". `stop`, `halt`,
# `tram_stop` and `subway_entrance` are excluded: those are /stops' territory.
RAILWAY = {"station": "station"}

OFFICE = {"government": "government", "diplomatic": "embassy"}

# Named roads only. `service`, `footway`, `path`, `track`, `steps` and the
# `_link` ramps are excluded - a named slip road is not a destination.
STREET_HIGHWAYS = frozenset({
    "motorway", "trunk", "primary", "secondary", "tertiary",
    "residential", "living_street", "unclassified", "pedestrian",
})

# Written down so the intent survives, and asserted against the output. These
# are the things whose presence would mean the filter had been loosened by
# accident.
NEVER_INDEXED = {
    ("highway", "bus_stop"), ("railway", "stop"), ("railway", "halt"),
    ("railway", "tram_stop"), ("railway", "subway_entrance"),
    ("amenity", "bench"), ("amenity", "post_box"), ("amenity", "atm"),
    ("amenity", "bank"), ("amenity", "pharmacy"), ("amenity", "cafe"),
    ("amenity", "restaurant"), ("amenity", "fast_food"), ("amenity", "fuel"),
    ("amenity", "parking"), ("amenity", "toilets"),
    ("shop", "supermarket"), ("shop", "convenience"), ("shop", "clothes"),
}

_WORSHIP = {"muslim": "mosque", "christian": "church"}


def classify(tags: dict) -> str | None:
    """The category for a feature, or None if it does not belong in the index.

    A pure function of the tag dictionary, so the whole of this file's
    judgement is testable without a 170 MB extract and without osmium.
    """
    # Exclude the *stop*, not the station. A metro station in OSM carries
    # `railway=station` and `public_transport=station` together, so rejecting
    # everything with a `public_transport` tag threw away 168 of Cairo's 176
    # stations -- which was measured, not guessed. Stations belong here:
    # the TfC metro feed has no Arabic names for M1 and M2, so `/stops` cannot
    # find «السادات» at all and this index can.
    if tags.get("public_transport") in {"platform", "stop_position",
                                        "stop_area"}:
        return None
    if tags.get("highway") == "bus_stop":
        return None
    if tags.get("railway") in {"stop", "halt", "tram_stop",
                               "subway_entrance", "platform"}:
        return None
    # Disused and demolished features keep their name tags in OSM.
    if tags.get("disused") == "yes" or "disused:amenity" in tags:
        return None
    if tags.get("abandoned") == "yes" or tags.get("highway") == "construction":
        return None

    amenity = tags.get("amenity")
    if amenity == "place_of_worship":
        return _WORSHIP.get(tags.get("religion", ""), "place_of_worship")
    for key, table in (("aeroway", AEROWAY), ("amenity", AMENITY),
                       ("shop", SHOP), ("railway", RAILWAY),
                       ("tourism", TOURISM), ("historic", HISTORIC),
                       ("leisure", LEISURE), ("office", OFFICE),
                       ("place", PLACE)):
        value = tags.get(key)
        if value and value in table:
            return table[value]

    if tags.get("highway") in STREET_HIGHWAYS:
        return "street"
    return None


# --------------------------------------------------------------------------
# Names
# --------------------------------------------------------------------------
#
# In Egypt's OSM data the bare `name` tag is usually Arabic and `name:en` is
# often missing. A `name_en` column filled from `name` would therefore end up
# full of Arabic strings, which an English client renders in a Latin slot with
# nothing to warn it. So each string is routed by the script it is written in,
# not by the tag it came from.

SEARCH_ONLY_TAGS = ("alt_name", "alt_name:ar", "alt_name:en", "short_name",
                    "official_name", "official_name:ar", "int_name",
                    "old_name", "old_name:ar", "name:fr")


def names(tags: dict) -> dict | None:
    """Split a feature's names into what to display and what to match on.

    Returns None when there is nothing searchable, which is most of OSM.
    """
    primary = (tags.get("name") or "").strip()
    tagged_ar = (tags.get("name:ar") or "").strip()
    tagged_en = (tags.get("name:en") or "").strip()

    name_ar = tagged_ar or (primary if primary and is_arabic(primary) else "")
    name_en = tagged_en or (primary if primary and not is_arabic(primary)
                            else "")
    if not (name_ar or name_en):
        return None

    # Every spelling anyone might type goes into the match keys, including the
    # old name of a renamed street, which people keep using for decades.
    ar_keys, en_keys = [], []
    for value in [primary, tagged_ar, tagged_en] + [
            (tags.get(t) or "").strip() for t in SEARCH_ONLY_TAGS]:
        if not value:
            continue
        key = normalize_name(value)
        if not key:
            continue
        bucket = ar_keys if is_arabic(value) else en_keys
        if key not in bucket:
            bucket.append(key)

    if not (ar_keys or en_keys):
        # A name that normalisation empties is a row nobody can ever reach. It
        # happens: way 775151288 is the Russian consulate, named in OSM only
        # as «Консульство Российской федерации в Египте», and Cyrillic folds
        # away entirely. Better absent than present and unfindable — and it is
        # `verify()`'s "no search key" check that caught this on the first
        # full run rather than a user searching for a consulate and getting
        # nothing.
        return None

    return {
        "name": primary or name_ar or name_en,
        "name_ar": name_ar or None,
        "name_en": name_en or None,
        # " | " keeps two names from forming trigrams across their join.
        "name_norm": " | ".join(en_keys),
        "name_norm_ar": " | ".join(ar_keys) or None,
    }


def importance(cat: str, tags: dict, is_area: bool) -> float:
    """Tie-break between equally good name matches.

    Mostly the category's own rank. A feature with a Wikidata id or an Arabic
    name has been looked at by a human, which is weak but real evidence it is
    the one somebody means.
    """
    from api.places import category as category_of
    score = float(category_of(cat).rank)
    if "wikidata" in tags:
        score += 6
    if "name:ar" in tags:
        score += 2
    if is_area:
        score += 1
    return score


# --------------------------------------------------------------------------
# Reading the extract
# --------------------------------------------------------------------------

def _inside(lat: float, lon: float) -> bool:
    return (BBOX["min_lat"] <= lat <= BBOX["max_lat"]
            and BBOX["min_lon"] <= lon <= BBOX["max_lon"])


def read_features(pbf: Path, progress=None) -> list[dict]:
    """Every candidate inside the coverage box, as plain dicts.

    Nodes and ways only. Multipolygon relations would need an area assembler
    and a second pass for a handful of features that are, almost without
    exception, also mapped as a way or a node - see the module docstring's
    counts. Osmium is imported here so that the rest of this file, and its
    tests, do not need it.
    """
    try:
        import osmium
    except ImportError:  # pragma: no cover - depends on the machine
        raise SystemExit(
            "pyosmium is needed to read the extract and is not installed:\n"
            "    python -m pip install osmium\n"
            "It is a build-time dependency only; the API does not use it."
        )

    out: list[dict] = []
    seen = 0
    # `.with_locations()` needs the node pass in the same run, so the file
    # processor is not filtered to ways.
    for obj in osmium.FileProcessor(pbf).with_locations():
        seen += 1
        if progress and seen % 5_000_000 == 0:
            progress(seen, len(out))
        tags = dict(obj.tags)
        if "name" not in tags and "name:ar" not in tags:
            continue
        cat = classify(tags)
        if cat is None:
            continue
        parts = names(tags)
        if parts is None:
            continue

        if obj.is_node():
            lat, lon, is_area, osm_type = obj.location.lat, obj.location.lon, \
                False, "n"
        elif obj.is_way():
            try:
                points = [(n.lat, n.lon) for n in obj.nodes if n.location.valid()]
            except Exception:
                continue
            if not points:
                continue
            lat = sum(p[0] for p in points) / len(points)
            lon = sum(p[1] for p in points) / len(points)
            is_area = points[0] == points[-1] and len(points) > 3
            osm_type = "w"
        else:
            continue

        if not _inside(lat, lon):
            continue

        out.append({
            "osm_type": osm_type, "osm_id": obj.id, "category": cat,
            "lat": lat, "lon": lon,
            "importance": importance(cat, tags, is_area),
            **parts,
        })
    return out


# --------------------------------------------------------------------------
# Areas, duplicates, and streets
# --------------------------------------------------------------------------
#
# Duplicate and near-duplicate names are the norm in OSM, and there are two
# different problems wearing that one name.
#
# The first is the *same* feature mapped twice - a mall as a node and again as
# a building outline, a hospital as both an amenity node and a way. Those
# collapse: same normalised name, same category, within 250 m.
#
# The second is *different* features that share a name, which must not
# collapse. Cairo has a "Rod El Farag" on Line 2 and a "Rod El Farag Axis"
# 2.4 km away; it has a dozen streets called شارع النيل. Those stay, and are
# told apart by `area` - the district or neighbourhood containing them - which
# is why the area pass runs first.

# In containment order, finest first. A place's own area must be something
# strictly coarser than itself: rank it against its neighbours instead and
# المعادي comes back labelled with whichever district happens to sit nearest,
# which reads as a parent and is not one.
AREA_CATEGORIES = ("neighbourhood", "village", "district", "city")
FINE_AREAS = ("neighbourhood", "village")

# How far an anchor of each kind reaches. A `place=` node sits at the centre
# of the thing it names, so the coarser the anchor the further away it can
# legitimately be: Cairo's own node is 10 km from most of Cairo.
ANCHOR_RADIUS_M = {"neighbourhood": 4_000, "village": 6_000,
                   "district": 9_000, "city": 25_000}

CELL = 0.01          # ~1.1 km of latitude


def _cell(lat, lon, size=CELL):
    return (int(math.floor(lat / size)), int(math.floor(lon / size)))


def _metres(a_lat, a_lon, b_lat, b_lon) -> float:
    """Equirectangular approximation. At Cairo's latitude over the distances
    that matter here (metres to a few km) the error is under a percent, and
    this runs a hundred thousand times."""
    x = math.radians(b_lon - a_lon) * math.cos(math.radians((a_lat + b_lat) / 2))
    y = math.radians(b_lat - a_lat)
    return 6371000.0 * math.hypot(x, y)


class Grid:
    """Bucket-per-cell lookup, so nearest-neighbour work stays linear."""

    def __init__(self, rows, size=CELL):
        self.size = size
        self.cells = defaultdict(list)
        for row in rows:
            self.cells[_cell(row["lat"], row["lon"], size)].append(row)

    def around(self, lat, lon, rings=1):
        cx, cy = _cell(lat, lon, self.size)
        for dx in range(-rings, rings + 1):
            for dy in range(-rings, rings + 1):
                yield from self.cells.get((cx + dx, cy + dy), ())


def assign_areas(rows: list[dict]) -> None:
    """Attach the containing neighbourhood or district to every row.

    Nearest anchor wins, with a bias towards the more specific: a
    neighbourhood beats the district it sits in, which beats the city, because
    "المعادي" tells you more than "القاهرة".
    """
    rank = {c: i for i, c in enumerate(AREA_CATEGORIES)}
    # Neighbourhoods and villages are numerous (5,000+) and close by, so they
    # go in a grid. Districts and cities number in the low hundreds and reach
    # tens of kilometres, which no sane grid ring covers; they are scanned
    # linearly, and only for the rows that need them.
    grid = Grid([r for r in rows if r["category"] in FINE_AREAS], size=0.02)
    coarse = [r for r in rows
              if r["category"] in rank and r["category"] not in FINE_AREAS]

    def pick(row, candidates, floor):
        best, best_score = None, None
        for anchor in candidates:
            if anchor is row:
                continue
            if floor is not None and rank[anchor["category"]] <= floor:
                continue
            d = _metres(row["lat"], row["lon"], anchor["lat"], anchor["lon"])
            if d > ANCHOR_RADIUS_M[anchor["category"]]:
                continue
            score = (rank[anchor["category"]], d)
            if best_score is None or score < best_score:
                best, best_score = anchor, score
        return best

    for row in rows:
        floor = rank.get(row["category"])
        best = pick(row, grid.around(row["lat"], row["lon"], rings=3), floor)
        if best is None:
            best = pick(row, coarse, floor)
        row["area_ar"] = best["name_ar"] if best else None
        row["area_en"] = best["name_en"] if best else None


def _key(row: dict) -> str:
    return (row.get("name_norm_ar") or "").split(" | ")[0] \
        or (row.get("name_norm") or "").split(" | ")[0]


def merge_streets(rows: list[dict]) -> list[dict]:
    """One row per (street name, area), at the centroid of its segments.

    A named street is dozens of ways in OSM: شارع الهرم alone is ~10 km of
    them. Emitting one row per way floods the results for the most-searched
    streets in the city with identical entries. Grouping on a fixed distance
    instead would split a long street into an arbitrary number of pieces; the
    area is the unit a passenger actually uses to say which one they mean.
    """
    streets = [r for r in rows if r["category"] == "street"]
    others = [r for r in rows if r["category"] != "street"]

    groups: dict[tuple, list[dict]] = defaultdict(list)
    for row in streets:
        groups[(_key(row), row.get("area_ar"), row.get("area_en"))].append(row)

    merged = []
    for members in groups.values():
        # The representative is the richest-named member, so the display name
        # is not taken from an unnamed-in-Arabic fragment of a street that has
        # an Arabic name elsewhere.
        members.sort(key=lambda r: (bool(r["name_ar"]), bool(r["name_en"]),
                                    len(r["name_norm_ar"] or ""), -r["osm_id"]),
                     reverse=True)
        best = dict(members[0])
        best["lat"] = sum(m["lat"] for m in members) / len(members)
        best["lon"] = sum(m["lon"] for m in members) / len(members)
        best["segments"] = len(members)
        merged.append(best)
    return others + merged


def dedupe(rows: list[dict], radius_m: float = 250.0) -> list[dict]:
    """Drop the same feature mapped twice; keep genuinely distinct namesakes."""
    rows = sorted(rows, key=lambda r: (-r["importance"], r["osm_id"]))
    kept: list[dict] = []
    grid = Grid([])
    for row in rows:
        key = (row["category"], _key(row))
        duplicate = False
        for other in grid.around(row["lat"], row["lon"]):
            if (other["category"], _key(other)) != key:
                continue
            if _metres(row["lat"], row["lon"],
                       other["lat"], other["lon"]) <= radius_m:
                duplicate = True
                break
        if duplicate:
            continue
        kept.append(row)
        grid.cells[_cell(row["lat"], row["lon"])].append(row)
    return kept


# --------------------------------------------------------------------------
# Verification. Nothing is written unless all of this passes.
# --------------------------------------------------------------------------

MIN_ROWS, MAX_ROWS = 5_000, 400_000
MIN_ARABIC_SHARE = 0.50
MIN_CATEGORIES = 12

# Places that must be findable by the same substring rule the SQL uses. Each
# is the headline case for something: the definite article that OTP's prefix
# search cannot see past, a mall nobody knows the stop for, a square, a
# university, a street. A silent failure in normalisation or in the tag filter
# shows up here and nowhere else.
PROBES = [
    ("منيب", None),
    ("تحرير", "square"),
    ("جامعه القاهره", None),
    ("هرم", "street"),
    ("مدينه نصر", None),
]


def verify(rows: list[dict]) -> bool:
    from api.places import CATEGORIES

    ok = True

    def fail(msg):
        nonlocal ok
        print("  ERROR: {}".format(msg))
        ok = False

    if not MIN_ROWS <= len(rows) <= MAX_ROWS:
        fail("{} rows is outside the expected {}-{}. Either the tag filter "
             "changed or the extract did.".format(len(rows), MIN_ROWS, MAX_ROWS))

    outside = [r for r in rows if not _inside(r["lat"], r["lon"])]
    if outside:
        fail("{} rows fall outside the coverage box; every one of them is a "
             "search result no trip can be planned to".format(len(outside)))

    unknown = sorted({r["category"] for r in rows} - set(CATEGORIES))
    if unknown:
        fail("categories with no label in api.places.CATEGORIES: {}. They "
             "would render as 'Landmark' in both languages."
             .format(", ".join(unknown)))

    distinct = len({r["category"] for r in rows})
    if distinct < MIN_CATEGORIES:
        fail("only {} distinct categories; expected at least {}"
             .format(distinct, MIN_CATEGORIES))

    with_ar = sum(1 for r in rows if r["name_ar"])
    share = with_ar / len(rows) if rows else 0
    if share < MIN_ARABIC_SHARE:
        fail("only {:.0%} of rows have an Arabic name (expected >= {:.0%}). "
             "name:ar is on 93% of named features in this box, so this means "
             "the extraction dropped it.".format(share, MIN_ARABIC_SHARE))

    nameless = [r for r in rows if not (r["name_ar"] or r["name_en"])]
    if nameless:
        fail("{} rows have no displayable name at all".format(len(nameless)))

    keyless = [r for r in rows if not (r["name_norm"] or r["name_norm_ar"])]
    if keyless:
        fail("{} rows have no search key and could never be found"
             .format(len(keyless)))

    for needle, expect_category in PROBES:
        key = normalize_name(needle)
        hits = [r for r in rows
                if key in (r["name_norm"] or "")
                or key in (r["name_norm_ar"] or "")]
        if not hits:
            fail("probe {!r} (normalised {!r}) matches nothing. Either the "
                 "normalisation or the tag filter has regressed."
                 .format(needle, key))
        elif expect_category and not any(h["category"] == expect_category
                                         for h in hits):
            fail("probe {!r} matched {} rows but none is a {}"
                 .format(needle, len(hits), expect_category))
    return ok


def report(rows: list[dict]) -> None:
    by_cat = defaultdict(int)
    for row in rows:
        by_cat[row["category"]] += 1
    with_ar = sum(1 for r in rows if r["name_ar"])
    with_en = sum(1 for r in rows if r["name_en"])
    print("  rows                   : {}".format(len(rows)))
    print("  with an Arabic name    : {} ({:.0%})".format(
        with_ar, with_ar / len(rows) if rows else 0))
    print("  with a Latin name      : {} ({:.0%})".format(
        with_en, with_en / len(rows) if rows else 0))
    print("  with an area           : {}".format(
        sum(1 for r in rows if r.get("area_ar") or r.get("area_en"))))
    print("  categories             : {}".format(len(by_cat)))
    for cat, count in sorted(by_cat.items(), key=lambda kv: -kv[1]):
        print("      {:<18} {:>7}".format(cat, count))


# --------------------------------------------------------------------------
# The table
# --------------------------------------------------------------------------
#
# Held here rather than in a .sql file for the same reason build_metro_l3.py
# holds its feed layout: one file to read, and no way for the schema and the
# loader to disagree about the column order.

SCHEMA_SQL = """
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- A schema of its own, in a database of its own. This holds ODbL data and
-- nothing else; the CC BY-NC transit data must never be written here or
-- joined into a table here. See the module docstring.
CREATE SCHEMA IF NOT EXISTS osm;

CREATE TABLE IF NOT EXISTS osm.places (
    osm_type     char(1)          NOT NULL,
    osm_id       bigint           NOT NULL,
    category     text             NOT NULL,
    name         text             NOT NULL,
    name_ar      text,
    name_en      text,
    name_norm    text             NOT NULL DEFAULT '',
    name_norm_ar text,
    area_ar      text,
    area_en      text,
    importance   real             NOT NULL DEFAULT 0,
    lat          double precision NOT NULL,
    lon          double precision NOT NULL,
    geom         geography(Point, 4326)
                 GENERATED ALWAYS AS
                 (ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography) STORED,
    PRIMARY KEY (osm_type, osm_id)
);

-- Trigram indexes on both name columns: these are what make a substring
-- search, rather than a prefix search, cheap enough for a typeahead.
CREATE INDEX IF NOT EXISTS places_name_norm_trgm
    ON osm.places USING gin (name_norm gin_trgm_ops);
CREATE INDEX IF NOT EXISTS places_name_norm_ar_trgm
    ON osm.places USING gin (name_norm_ar gin_trgm_ops);
CREATE INDEX IF NOT EXISTS places_geom
    ON osm.places USING gist (geom);
CREATE INDEX IF NOT EXISTS places_bbox
    ON osm.places (lat, lon);
"""

COLUMNS = ("osm_type", "osm_id", "category", "name", "name_ar", "name_en",
           "name_norm", "name_norm_ar", "area_ar", "area_en", "importance",
           "lat", "lon")


def connect(url: str):
    try:
        import psycopg
    except ImportError:  # pragma: no cover
        raise SystemExit(
            "psycopg is needed to write the table:\n"
            "    python -m pip install -r requirements.txt"
        )
    try:
        return psycopg.connect(url, autocommit=False)
    except Exception as exc:
        raise SystemExit(
            "could not connect to the place database ({}).\n"
            "Start it with:  docker compose up -d places-db\n"
            "or point PLACES_DATABASE_URL somewhere else."
            .format(type(exc).__name__)
        )


def write(rows: list[dict], url: str) -> None:
    """Truncate and reload inside one transaction.

    Idempotent by construction: a second run produces the same table, and an
    interrupted run leaves the previous one intact rather than a half-built
    index that answers some searches and not others.
    """
    conn = connect(url)
    with conn:
        with conn.cursor() as cur:
            cur.execute(SCHEMA_SQL)
            cur.execute("TRUNCATE osm.places")
            copy_sql = "COPY osm.places ({}) FROM STDIN".format(
                ", ".join(COLUMNS))
            with cur.copy(copy_sql) as copy:
                for row in rows:
                    copy.write_row([row.get(c) for c in COLUMNS])
            cur.execute("ANALYZE osm.places")
    conn.close()


# --------------------------------------------------------------------------
# --check: the part a no-database test suite cannot do
# --------------------------------------------------------------------------

CHECK_QUERIES = [
    ("منيب", "ar", "the definite article OTP's prefix search cannot see past"),
    ("فستيفال", "ar", "a mall nobody knows the stop for"),
    ("tahrir", "en", "Latin query, Arabic data"),
    ("مدينه نصر", "ar", "folded spelling: ة and diacritics"),
    # The two that decide whether this is usable rather than merely correct.
    ("شارع", "ar", "WORST CASE: a word inside ~97,000 street names"),
    ("المعادي", "ar", "the district must outrank the streets named after it"),
    ("ال", "ar", "two characters: too short for a trigram index"),
]


def check(url: str) -> bool:
    """Run the API's own SQL against the real database.

    The test suite stubs `api.places.EXECUTOR`, which exercises the SQL text
    and the parameter binding but cannot tell you whether Postgres accepts the
    statement - whether the doubled `%%` is right, whether the trigram
    operator resolves, whether the indexes are used. That is what this is for.
    """
    from api.places import REVERSE_SQL, SEARCH_SQL, normalize_name as norm

    conn = connect(url)
    ok = True
    with conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM osm.places")
        total = cur.fetchone()[0]
        print("  rows in osm.places     : {}".format(total))
        if not total:
            print("  ERROR: the table is empty; run this script without "
                  "--check first")
            return False

        for needle, lang, why in CHECK_QUERIES:
            params = dict(BBOX, q=norm(needle), limit=5,
                          near_lat=None, near_lon=None)
            t0 = time.time()
            cur.execute(SEARCH_SQL, params)
            hits = cur.fetchall()
            ms = (time.time() - t0) * 1000
            print("\n  {!r} ({}) - {}".format(needle, lang, why))
            print("      {} of {} matches in {:.0f} ms".format(
                len(hits), hits[0][-1] if hits else 0, ms))
            for hit in hits[:3]:
                print("      - {} / {}  [{}]  {}".format(
                    hit[3], hit[5] or "-", hit[2], hit[6] or hit[7] or ""))
            if not hits:
                print("      ERROR: no match")
                ok = False

        params = dict(BBOX, lat=30.0281, lon=31.4075, limit=3, radius_m=800)
        cur.execute(REVERSE_SQL, params)
        near = cur.fetchall()
        print("\n  reverse geocode at 30.0281,31.4075 (Cairo Festival City):")
        for hit in near:
            print("      - {} / {}  [{}]  {:.0f} m".format(
                hit[3], hit[5] or "-", hit[2], hit[11]))
        if not near:
            print("      ERROR: nothing within 800 m")
            ok = False

        # The bounding box is a WHERE clause, not a filter applied afterwards,
        # and this is the assertion that says so.
        cur.execute("SELECT count(*) FROM osm.places WHERE lat NOT BETWEEN %s "
                    "AND %s OR lon NOT BETWEEN %s AND %s",
                    (BBOX["min_lat"], BBOX["max_lat"],
                     BBOX["min_lon"], BBOX["max_lon"]))
        stray = cur.fetchone()[0]
        if stray:
            print("\n  ERROR: {} rows outside the coverage box".format(stray))
            ok = False
    conn.close()
    return ok


# --------------------------------------------------------------------------

def build(pbf: Path | None, out_jsonl: Path | None, dry_run: bool,
          url: str) -> bool:
    if pbf is None or not pbf.is_file():
        raise SystemExit(
            "no OSM extract found in {}.\nIt is gitignored (170 MB) — see "
            "OTP/README.md for where to fetch it, or pass --pbf.\n(Note a git "
            "worktree has its own empty OTP/; point --pbf at the main "
            "checkout's.)".format(REPO / "OTP"))

    print("\n{}".format(pbf.name))
    print("-" * 62)
    print("  coverage box           : lat {min_lat}-{max_lat}, "
          "lon {min_lon}-{max_lon}".format(**BBOX))

    t0 = time.time()

    def progress(seen, kept):
        # Flushed: this pass takes about ten minutes, and redirected to a
        # file Python block-buffers, so without it the log stays empty until
        # the run is over and there is no way to tell it from a hang.
        print("      {:>12,} objects read, {:,} kept".format(seen, kept),
              flush=True)

    rows = read_features(pbf, progress)
    print("  candidates in box      : {} in {:.0f}s".format(
        len(rows), time.time() - t0))

    assign_areas(rows)
    before = len(rows)
    rows = merge_streets(rows)
    print("  after merging streets  : {} (-{})".format(len(rows),
                                                       before - len(rows)))
    before = len(rows)
    rows = dedupe(rows)
    print("  after dedupe           : {} (-{})".format(len(rows),
                                                       before - len(rows)))
    report(rows)

    # Dumped before verification, not after: `--out` exists to let somebody
    # look at what the filter produced, and a failed check is exactly when
    # they need to.
    if out_jsonl:
        out_jsonl.parent.mkdir(parents=True, exist_ok=True)
        with out_jsonl.open("w", encoding="utf-8") as fh:
            for row in rows:
                fh.write(json.dumps(row, ensure_ascii=False) + "\n")
        print("  written                : {}".format(out_jsonl))

    if not verify(rows):
        print("\n  Refusing to write. Nothing has been changed.")
        return False

    if dry_run:
        print("  --dry-run: the database was not touched")
        return True

    write(rows, url)
    print("  written                : {} rows into osm.places".format(len(rows)))
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Build the OSM place index for /places. Writes to its own "
                    "database; never merges with the transit data.")
    ap.add_argument("--pbf", type=Path, default=default_pbf(),
                    help="OSM extract (default: the newest *.osm.pbf in OTP/)")
    ap.add_argument("--database-url", default=config.PLACES_DATABASE_URL,
                    help="where to write (default PLACES_DATABASE_URL)")
    ap.add_argument("--out", type=Path, default=None,
                    help="also dump the rows as JSONL, for inspection without "
                         "a database")
    ap.add_argument("--dry-run", action="store_true",
                    help="read, classify and verify; write nothing")
    ap.add_argument("--check", action="store_true",
                    help="run the API's own queries against the built table "
                         "and print what comes back. Reads nothing else.")
    args = ap.parse_args(argv)

    # Windows consoles default to cp1252, and every name this script prints is
    # Arabic. Without this, --check dies in `print` after the query it was
    # meant to be testing has already succeeded.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):  # pragma: no cover - redirected output
        pass

    if args.check:
        return 0 if check(args.database_url) else 1
    if not build(args.pbf, args.out, args.dry_run, args.database_url):
        return 1
    if not args.dry_run:
        print("\nDone. Check it with:\n"
              "    python scripts/build_places.py --check")
    return 0


if __name__ == "__main__":
    sys.exit(main())
