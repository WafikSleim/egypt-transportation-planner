"""Behaviour of the place index and `/places`.

Runs with no database, no Docker and no network, the same way the rest of the
suite runs with no OTP: the seam is `api.places.EXECUTOR`, so the real SQL
text, the real parameter binding and the real row-to-model mapping are all
exercised, and only the connection is faked.

What a fake cannot check is whether Postgres accepts the statement. That is
what `python scripts/build_places.py --check` is for, and the comment on
`FakePlaces` says so.

The cases here are the ones where a regression would be quiet: search
narrowing to one language, a place with no Arabic name being dropped instead
of flagged, a result outside the covered area, the TfC attribution appearing
on OpenStreetMap data, or a typed place name reaching a log.
"""

from __future__ import annotations

import importlib.util
import logging
from pathlib import Path

import pytest

from api import config, logs, places
from tests.conftest import place_row

# No module-level asyncio mark: half of this file is synchronous, and
# pytest.ini already runs in asyncio auto mode.

REPO = Path(__file__).resolve().parents[1]

_spec = importlib.util.spec_from_file_location(
    "build_places", REPO / "scripts" / "build_places.py")
build = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(build)


# --------------------------------------------------------------------------
# Normalisation -- the whole of the fuzzy matching
# --------------------------------------------------------------------------

def test_definite_article_is_stripped_so_moneeb_finds_al_moneeb():
    """The headline case. OTP's stop search is prefix-based: `منيب` finds
    nothing there and `المنيب` finds sixteen stops. This endpoint exists to
    end that, so the normalised query has to be a substring of the normalised
    name."""
    assert places.normalize_name("منيب") in places.normalize_name("المنيب")


def test_alef_and_ta_marbuta_variants_fold_together():
    """Egyptians type these interchangeably and a phone keyboard offers both."""
    assert (places.normalize_name("جامعة القاهرة")
            == places.normalize_name("جامعه القاهره"))


def test_tashkeel_and_tatweel_are_removed():
    assert places.normalize_name("مَدِينَةُ نَصْر") == places.normalize_name("مدينة نصر")
    assert places.normalize_name("الـهــرم") == places.normalize_name("الهرم")


def test_arabic_indic_digits_match_ascii_ones():
    assert places.normalize_name("شارع ٩") == places.normalize_name("شارع 9")


def test_latin_case_and_diacritics_fold():
    assert places.normalize_name("El-Maʿādī") == places.normalize_name("maadi")


def test_normalisation_does_not_eat_a_short_name():
    """`ال` is stripped as an article, not as the first two letters of every
    word: a name that *is* short must survive."""
    assert places.normalize_name("الف") == "الف"


def test_script_detection_routes_names_to_the_right_column():
    assert places.is_arabic("المنيب")
    assert not places.is_arabic("Moneeb")


# --------------------------------------------------------------------------
# Searching -- both languages, always
# --------------------------------------------------------------------------

async def test_search_sends_the_normalised_query_not_the_raw_one(
        fake_places, client):
    fake_places.serve([place_row(1, name_ar="المنيب")])
    async with client as c:
        await c.get("/places", params={"q": "المُنيب", "lang": "ar"})

    assert fake_places.queries[0]["params"]["q"] == places.normalize_name("المنيب")


async def test_both_name_columns_are_searched_whatever_the_language(
        fake_places, client):
    """OTP's stop search is scoped to the requested language, which is why
    `Moneeb&lang=ar` returns nothing there. Reproducing that here would defeat
    the point of a second index: `lang` decides what comes back, not what is
    looked at."""
    fake_places.serve([place_row(1, name_ar="المنيب", name_en="Moneeb")])
    async with client as c:
        body = (await c.get("/places",
                            params={"q": "Moneeb", "lang": "ar"})).json()

    sql = fake_places.queries[0]["sql"]
    assert "name_norm" in sql and "name_norm_ar" in sql
    assert "lang" not in fake_places.queries[0]["params"]
    assert body["count"] == 1


async def test_results_are_confined_to_the_covered_bounding_box(
        fake_places, client):
    """A place outside Greater Cairo is a search result no itinerary can be
    planned to. The box is a WHERE clause, not a filter applied afterwards."""
    fake_places.serve([place_row(1, name_en="Somewhere")])
    async with client as c:
        await c.get("/places", params={"q": "some"})

    params = fake_places.queries[0]["params"]
    for key in ("min_lat", "max_lat", "min_lon", "max_lon"):
        assert params[key] == config.COVERAGE[key]
    assert "p.lat BETWEEN" in fake_places.queries[0]["sql"]


async def test_truncation_is_reported_rather_than_implied(fake_places, client):
    rows = [place_row(i, name_en=f"Nasr City {i}", total_matches=412)
            for i in range(30)]
    fake_places.serve(rows)
    async with client as c:
        body = (await c.get("/places",
                            params={"q": "nasr", "limit": 5})).json()

    assert body["count"] == 5
    assert body["total_matches"] == 412
    assert body["truncated"] is True
    assert fake_places.queries[0]["params"]["limit"] == 5


async def test_near_orders_by_distance_and_reports_it(fake_places, client):
    fake_places.serve([place_row(1, name_en="Festival City", distance_m=1234.6)])
    async with client as c:
        body = (await c.get("/places", params={
            "q": "festival", "near": "30.0444,31.2357"})).json()

    params = fake_places.queries[0]["params"]
    assert (params["near_lat"], params["near_lon"]) == (30.0444, 31.2357)
    assert body["places"][0]["distance_m"] == 1235


async def test_without_near_no_distance_is_invented(fake_places, client):
    fake_places.serve([place_row(1, name_en="Festival City")])
    async with client as c:
        body = (await c.get("/places", params={"q": "festival"})).json()

    assert fake_places.queries[0]["params"]["near_lat"] is None
    assert body["places"][0]["distance_m"] is None


async def test_a_near_point_outside_egypt_is_rejected(fake_places, client):
    async with client as c:
        r = await c.get("/places", params={"q": "abc", "near": "48.85,2.29"})
    assert r.status_code == 422


# --------------------------------------------------------------------------
# Names: both fallback directions, and never a transliteration
# --------------------------------------------------------------------------

async def test_arabic_name_is_used_and_labelled_arabic(fake_places, client):
    fake_places.serve([place_row(1, name_ar="المنيب", name_en="Moneeb")])
    async with client as c:
        body = (await c.get("/places",
                            params={"q": "منيب", "lang": "ar"})).json()

    place = body["places"][0]
    assert place["name"] == "المنيب"
    assert place["name_language"] == "ar"
    assert place["name_is_fallback"] is False


async def test_a_place_with_no_arabic_name_is_shown_in_latin_and_flagged(
        fake_places, client):
    """design-system.md: show the Latin name in an LTR span with a note, never
    hide the result and never transliterate — a wrong Arabic name is worse
    than an honest English one. The client needs both facts to do that."""
    fake_places.serve([place_row(1, name_en="Arkan Plaza", name_ar=None)])
    async with client as c:
        body = (await c.get("/places",
                            params={"q": "arkan", "lang": "ar"})).json()

    place = body["places"][0]
    assert place["name"] == "Arkan Plaza"     # unchanged, not transliterated
    assert place["name_language"] == "en"
    assert place["name_is_fallback"] is True


async def test_a_place_with_only_an_arabic_name_survives_an_english_search(
        fake_places, client):
    """The mirror case, and the common one: in Egypt's OSM data `name` is
    usually Arabic and `name:en` is often absent. Dropping these would empty
    an English search of most of the city."""
    fake_places.serve([place_row(1, name_ar="ميدان التحرير", name_en=None)])
    async with client as c:
        body = (await c.get("/places",
                            params={"q": "tahrir", "lang": "en"})).json()

    place = body["places"][0]
    assert place["name"] == "ميدان التحرير"
    assert place["name_language"] == "ar"
    assert place["name_is_fallback"] is True


async def test_area_disambiguates_two_places_with_the_same_name(
        fake_places, client):
    """Cairo has a Rod El Farag on Line 2 and a Rod El Farag Axis 2.4 km
    away. Same-named places are not collapsed; they are told apart."""
    fake_places.serve([
        place_row(1, name_ar="روض الفرج", area_ar="شبرا", category="station"),
        place_row(2, name_ar="محور روض الفرج", area_ar="الساحل",
                  category="station"),
    ])
    async with client as c:
        body = (await c.get("/places",
                            params={"q": "روض الفرج", "lang": "ar"})).json()

    assert [p["area"] for p in body["places"]] == ["شبرا", "الساحل"]


async def test_category_arrives_translated(fake_places, client):
    """Like `ModeInfo`: a category the thin client has to translate itself is
    a category that shows up in English on an Arabic screen."""
    fake_places.serve([place_row(1, name_ar="سيتي ستارز", category="mall")])
    async with client as c:
        body = (await c.get("/places", params={"q": "ستارز"})).json()

    cat = body["places"][0]["category"]
    assert cat["id"] == "mall"
    assert cat["label_ar"] and cat["label_en"]
    assert cat["label_ar"] != cat["label_en"]


async def test_an_unknown_category_degrades_instead_of_failing(
        fake_places, client):
    """The table is rebuilt by a script that can run ahead of a deploy."""
    fake_places.serve([place_row(1, name_en="Somewhere", category="bicycle_bell")])
    async with client as c:
        body = (await c.get("/places", params={"q": "some"})).json()

    assert body["places"][0]["category"]["id"] == "landmark"


# --------------------------------------------------------------------------
# Licence: two datasets, two credits, never merged
# --------------------------------------------------------------------------

async def test_places_carry_the_osm_attribution_not_the_transit_one(
        fake_places, client):
    """OSM is ODbL and the transit data is CC BY-NC. One credit line cannot
    satisfy both, and crediting TfC for OpenStreetMap data is a licence
    breach in both directions."""
    fake_places.serve([place_row(1, name_en="Somewhere")])
    async with client as c:
        body = (await c.get("/places", params={"q": "some"})).json()

    assert "OpenStreetMap" in body["attribution"]["text"]
    assert body["attribution"]["licence"] == "ODbL 1.0"
    assert config.TFC_ATTRIBUTION not in body["attribution"]["text"]


async def test_every_place_is_sourced_to_osm_and_not_claimed_as_verified(
        fake_places, client):
    fake_places.serve([place_row(1, name_en="Somewhere")])
    async with client as c:
        body = (await c.get("/places", params={"q": "some"})).json()

    assert body["places"][0]["source"] == "osm"
    assert body["places"][0]["confidence"] == "reported"


async def test_stops_still_carry_the_transit_attribution(fake_otp, client):
    """The other half of the same rule: adding a second attribution must not
    have changed the first."""
    fake_otp.stops = [{"gtfsId": "2:1", "name": "Moneeb",
                       "lat": 29.98, "lon": 31.21}]
    async with client as c:
        body = (await c.get("/stops", params={"q": "Mon"})).json()

    assert body["attribution"]["licence"] == "CC BY-NC 4.0"


# --------------------------------------------------------------------------
# Degradation, and what must not leak
# --------------------------------------------------------------------------

async def test_place_search_returns_503_when_the_database_is_down(
        fake_places, client):
    """503 and not 500: with the index gone, stop search and trip planning
    still work and the client is expected to fall back to them."""
    async with client as c:
        r = await c.get("/places", params={"q": "some"})

    assert r.status_code == 503
    assert "place index" in r.json()["detail"].lower()


async def test_the_failure_message_carries_neither_sql_nor_the_query(
        fake_places, client):
    """A `q` value is a place somebody typed. `api/logs.py` strips query
    strings from the access log; it cannot strip them out of an exception
    someone chose to format with the parameters in it."""
    async with client as c:
        detail = (await c.get(
            "/places", params={"q": "بيت حماتي"})).json()["detail"]

    assert "بيت حماتي" not in detail
    assert "SELECT" not in detail and "osm.places" not in detail


def test_a_typed_place_name_does_not_reach_the_access_log():
    """Same guarantee `/plan` has. The endpoint is new; the filter is not, and
    this is the assertion that it still covers the new query string."""
    record = logging.LogRecord(
        "uvicorn.access", logging.INFO, __file__, 1, '%s - "%s %s HTTP/%s" %d',
        ("127.0.0.1:1", "GET", "/places?q=%D8%A8%D9%8A%D8%AA&lang=ar", "1.1", 200),
        None,
    )
    logs.RedactQueryString().filter(record)
    assert record.args[2] == "/places" + logs.REDACTED


async def test_a_two_character_query_is_the_floor(fake_places, client):
    async with client as c:
        assert (await c.get("/places", params={"q": "a"})).status_code == 422


async def test_a_query_that_normalises_to_nothing_matches_nothing(
        fake_places, client):
    """Punctuation passes the length check and then folds away. An empty
    needle would make the `LIKE` match every row in the table, so the
    passenger would get twenty arbitrary places instead of no answer."""
    fake_places.serve([place_row(1, name_en="Somewhere")])
    async with client as c:
        body = (await c.get("/places", params={"q": "؟؟؟"})).json()

    assert body["places"] == []
    assert fake_places.queries == []          # the database was not troubled


# --------------------------------------------------------------------------
# Reverse geocoding, for the map picker
# --------------------------------------------------------------------------

async def test_reverse_geocode_asks_within_a_radius(fake_places, client):
    fake_places.serve([place_row(1, name_ar="كايرو فستيفال سيتي",
                                 distance_m=42.0)])
    async with client as c:
        body = (await c.get("/places/reverse", params={
            "at": "30.0281,31.4075", "radius_m": 800, "lang": "ar"})).json()

    params = fake_places.queries[0]["params"]
    assert (params["lat"], params["lon"]) == (30.0281, 31.4075)
    assert params["radius_m"] == 800
    assert body["places"][0]["distance_m"] == 42
    assert body["matching"] == "nearest"


async def test_nothing_nearby_is_an_answer_not_an_error(fake_places, client):
    """Large parts of Greater Cairo have no addressing a stranger could use.
    That is the reason the map picker exists, so an empty list here is a real
    result and the client says "no name here", not "no results"."""
    fake_places.serve([])
    async with client as c:
        r = await c.get("/places/reverse", params={"at": "30.05,31.30"})

    assert r.status_code == 200
    assert r.json()["places"] == []


async def test_reverse_geocode_does_not_report_a_stop(fake_places, client):
    """Nearest-stop is transit data from OTP. Joining the two datasets in one
    answer is what the licences forbid; the client asks both and labels
    them."""
    fake_places.serve([place_row(1, name_en="Festival City")])
    async with client as c:
        body = (await c.get("/places/reverse",
                            params={"at": "30.0281,31.4075"})).json()

    assert "stop" not in str(body["places"][0]).lower()


# --------------------------------------------------------------------------
# /health knows whether anyone ran the ingest
# --------------------------------------------------------------------------

async def test_health_reports_an_empty_place_index(fake_otp, fake_places,
                                                   client):
    """An empty table and a query that genuinely matched nothing are the same
    empty list at the client. The difference has to be visible somewhere."""
    fake_places.serve([])
    fake_places.stats_row = {"place_count": 0, "category_count": 0,
                            "arabic_count": 0}
    async with client as c:
        body = (await c.get("/health")).json()

    assert body["places"]["available"] is True
    assert body["places"]["place_count"] == 0
    assert "build_places" in body["places"]["detail"]


async def test_a_missing_place_database_does_not_make_the_api_degraded(
        fake_otp, fake_places, client):
    """The place index is survivable; OTP is not. A monitor has to be able to
    tell those apart."""
    async with client as c:
        body = (await c.get("/health")).json()

    assert body["status"] == "ok"
    assert body["places"]["available"] is False


# --------------------------------------------------------------------------
# The ingest script's judgement, without a 170 MB extract
# --------------------------------------------------------------------------

@pytest.mark.parametrize("tags, expected", [
    ({"shop": "mall", "name": "كايرو فستيفال سيتي"}, "mall"),
    ({"amenity": "university", "name": "جامعة القاهرة"}, "university"),
    ({"amenity": "hospital", "name": "قصر العيني"}, "hospital"),
    ({"place": "neighbourhood", "name": "المعادي"}, "neighbourhood"),
    ({"place": "suburb", "name": "مدينة نصر"}, "district"),
    ({"place": "square", "name": "ميدان التحرير"}, "square"),
    ({"highway": "residential", "name": "شارع الهرم"}, "street"),
    ({"aeroway": "aerodrome", "name": "مطار القاهرة"}, "airport"),
    ({"railway": "station", "name": "محطة مصر"}, "station"),
    ({"amenity": "place_of_worship", "religion": "muslim",
      "name": "مسجد عمرو"}, "mosque"),
    ({"amenity": "place_of_worship", "religion": "christian",
      "name": "الكنيسة المعلقة"}, "church"),
    # A metro station carries both tags. Rejecting everything with a
    # `public_transport` tag threw away 168 of Cairo's 176 stations on the
    # first real run of the ingest — and stations matter here precisely
    # because the TfC metro feed has no Arabic names for M1 and M2, so
    # `/stops` cannot find «السادات» and this index can.
    ({"railway": "station", "public_transport": "station",
      "name": "السادات"}, "station"),
])
def test_tags_that_belong_in_the_index(tags, expected):
    assert build.classify(tags) == expected


@pytest.mark.parametrize("tags", [
    {"highway": "bus_stop", "name": "موقف"},
    {"public_transport": "platform", "name": "رصيف"},
    {"public_transport": "stop_position", "name": "موقف"},
    {"railway": "tram_stop", "name": "محطة ترام"},
    {"railway": "subway_entrance", "name": "مدخل"},
    {"amenity": "bank", "name": "بنك مصر"},
    {"amenity": "pharmacy", "name": "صيدلية العزبي"},
    {"amenity": "cafe", "name": "كافيه"},
    {"amenity": "fuel", "name": "موبيل"},
    {"shop": "supermarket", "name": "كارفور"},
    {"amenity": "restaurant", "name": "مطعم"},
    {"highway": "service", "name": "ممر"},
    {"highway": "footway", "name": "ممشى"},
    {"building": "yes", "name": "عمارة"},
    {"name": "شيء ما"},
])
def test_tags_that_are_deliberately_kept_out(tags):
    """An index full of bank branches and bus shelters does not merely get
    bigger: it puts the wrong row first, and a typeahead is judged on its
    first three rows. Transit stops are excluded for a second reason — they
    are `/stops`' job, out of a differently-licensed dataset."""
    assert build.classify(tags) is None


def test_the_exclusion_list_is_honoured():
    """The written-down intent and the code agree. If someone loosens the
    filter, this is what says so."""
    for key, value in build.NEVER_INDEXED:
        assert build.classify({key: value, "name": "x"}) is None


def test_every_category_the_script_emits_has_a_label():
    """A category with no entry in api.places.CATEGORIES renders as
    'Landmark' in both languages, which is wrong rather than missing."""
    emitted = set()
    for table in (build.PLACE, build.AMENITY, build.SHOP, build.TOURISM,
                  build.LEISURE, build.HISTORIC, build.AEROWAY,
                  build.RAILWAY, build.OFFICE):
        emitted.update(table.values())
    emitted.update({"street", "mosque", "church"})
    assert emitted <= set(places.CATEGORIES)


def test_arabic_only_names_land_in_the_arabic_column():
    parts = build.names({"name": "ميدان التحرير"})
    assert parts["name_ar"] == "ميدان التحرير"
    assert parts["name_en"] is None
    assert parts["name_norm"] == ""          # nothing Latin to match on


def test_the_bare_name_tag_is_not_assumed_to_be_english():
    """In Egypt's OSM data `name` is usually Arabic. A `name_en` column filled
    from it would quietly fill with Arabic and render in a Latin slot."""
    parts = build.names({"name": "المعادي", "name:en": "Maadi"})
    assert parts["name_en"] == "Maadi"
    assert parts["name_ar"] == "المعادي"


def test_alternative_and_old_names_are_searchable_but_not_displayed():
    """Cairenes keep using a street's old name for decades."""
    parts = build.names({"name": "شارع ثروت", "old_name": "شارع فؤاد"})
    assert places.normalize_name("فؤاد") in parts["name_norm_ar"]
    assert parts["name"] == "شارع ثروت"


def test_a_feature_with_no_name_is_not_indexable():
    assert build.names({"amenity": "hospital"}) is None


def test_a_name_in_neither_script_is_not_indexable():
    """Normalisation keeps Arabic and ASCII letters; everything else folds
    away, so a name written only in Cyrillic leaves no search key and the row
    could never be reached. The Russian consulate (OSM way 775151288) is named
    exactly that way, and `verify()`'s no-search-key check caught it on the
    first full ingest — the guard doing its job rather than a passenger
    searching for a consulate and finding nothing."""
    assert build.names(
        {"name": "Консульство Российской федерации в Египте"}) is None


def test_streets_collapse_to_one_row_per_name_and_area():
    """شارع الهرم is ~10 km of ways. One row per segment floods the results
    for the most-searched streets in the city."""
    segments = [
        {"osm_type": "w", "osm_id": i, "category": "street",
         "lat": 29.99 + i * 0.001, "lon": 31.20 + i * 0.001, "importance": 25.0,
         "name": "شارع الهرم", "name_ar": "شارع الهرم", "name_en": None,
         "name_norm": "", "name_norm_ar": places.normalize_name("شارع الهرم"),
         "area_ar": "الهرم", "area_en": None}
        for i in range(12)
    ]
    merged = build.merge_streets(segments)
    assert len(merged) == 1
    assert merged[0]["segments"] == 12
    # The pin lands mid-street, which is the honest answer for a 10 km road.
    assert 29.99 < merged[0]["lat"] < 30.01


def test_the_same_street_in_two_districts_stays_two_rows():
    def segment(i, area):
        return {"osm_type": "w", "osm_id": i, "category": "street",
                "lat": 30.0 + i * 0.001, "lon": 31.2, "importance": 25.0,
                "name": "شارع النيل", "name_ar": "شارع النيل", "name_en": None,
                "name_norm": "",
                "name_norm_ar": places.normalize_name("شارع النيل"),
                "area_ar": area, "area_en": None}

    merged = build.merge_streets([segment(1, "المعادي"), segment(2, "الدقي")])
    assert len(merged) == 2


def _area_row(osm_id, category, name, lat, lon):
    return {"osm_type": "n", "osm_id": osm_id, "category": category,
            "lat": lat, "lon": lon, "importance": 70.0, "name": name,
            "name_ar": name, "name_en": None, "name_norm": "",
            "name_norm_ar": places.normalize_name(name)}


def test_a_place_is_labelled_with_the_neighbourhood_it_sits_in():
    rows = [
        _area_row(1, "neighbourhood", "المعادي", 29.9600, 31.2570),
        {"osm_type": "n", "osm_id": 2, "category": "mall", "lat": 29.9610,
         "lon": 31.2580, "importance": 76.0, "name": "جراند مول",
         "name_ar": "جراند مول", "name_en": None, "name_norm": "",
         "name_norm_ar": places.normalize_name("جراند مول")},
    ]
    build.assign_areas(rows)
    assert rows[1]["area_ar"] == "المعادي"


def test_a_neighbourhood_is_labelled_with_its_district_not_its_neighbour():
    """The area is meant to read as a parent. Ranking a neighbourhood against
    the other neighbourhoods around it makes «المعادي · دار السلام» — two
    peers, presented as a containment."""
    rows = [
        _area_row(1, "neighbourhood", "المعادي", 29.9600, 31.2570),
        _area_row(2, "neighbourhood", "دار السلام", 29.9700, 31.2600),
        _area_row(3, "district", "جنوب القاهرة", 29.9900, 31.2700),
    ]
    build.assign_areas(rows)
    assert rows[0]["area_ar"] == "جنوب القاهرة"
    assert rows[1]["area_ar"] == "جنوب القاهرة"


def test_a_city_has_no_area_above_it():
    rows = [_area_row(1, "city", "القاهرة", 30.0444, 31.2357)]
    build.assign_areas(rows)
    assert rows[0]["area_ar"] is None


def test_the_same_feature_mapped_twice_collapses():
    def row(osm_id, osm_type, lat):
        return {"osm_type": osm_type, "osm_id": osm_id, "category": "mall",
                "lat": lat, "lon": 31.4075, "importance": 76.0,
                "name": "كايرو فستيفال سيتي", "name_ar": "كايرو فستيفال سيتي",
                "name_en": None, "name_norm": "",
                "name_norm_ar": places.normalize_name("كايرو فستيفال سيتي")}

    # A node and the building outline of the same mall, 110 m apart.
    kept = build.dedupe([row(1, "n", 30.0281), row(2, "w", 30.0291)])
    assert len(kept) == 1


def test_two_real_places_sharing_a_name_are_both_kept():
    """The Line 2 Rod El Farag and the Rod El Farag Axis are 2.4 km apart and
    are different places. Collapsing them would make one of them unreachable."""
    def row(osm_id, lat):
        return {"osm_type": "n", "osm_id": osm_id, "category": "station",
                "lat": lat, "lon": 31.24, "importance": 80.0,
                "name": "روض الفرج", "name_ar": "روض الفرج", "name_en": None,
                "name_norm": "",
                "name_norm_ar": places.normalize_name("روض الفرج")}

    kept = build.dedupe([row(1, 30.0800), row(2, 30.1020)])
    assert len(kept) == 2


def test_the_build_refuses_to_write_a_row_outside_the_coverage_box(capsys):
    """Alexandria is in the same extract and has no transit data at all."""
    rows = [{"osm_type": "n", "osm_id": 1, "category": "mall",
             "lat": 31.2001, "lon": 29.9187, "importance": 76.0,
             "name": "سيتي سنتر", "name_ar": "سيتي سنتر", "name_en": None,
             "name_norm": "", "name_norm_ar": "سيتي سنتر"}]
    assert build.verify(rows) is False
    assert "coverage box" in capsys.readouterr().out


def test_the_build_refuses_when_arabic_names_have_vanished(capsys):
    """`name:ar` is on 93% of the named features in this box. A collapse means
    the extraction broke, and the failure would otherwise be invisible: the
    index still works, in English, for an Arabic-first app."""
    rows = [{"osm_type": "n", "osm_id": i, "category": "mall",
             "lat": 30.04, "lon": 31.23, "importance": 76.0,
             "name": f"Mall {i}", "name_ar": None, "name_en": f"Mall {i}",
             "name_norm": f"mall {i}", "name_norm_ar": None}
            for i in range(6000)]
    assert build.verify(rows) is False
    assert "Arabic name" in capsys.readouterr().out


def test_the_ingest_and_the_query_path_share_one_normalisation():
    """If these ever drift, search half-works -- some queries hit and some
    silently do not, which is the hardest kind of failure to notice."""
    assert build.normalize_name is places.normalize_name


def test_the_ingest_clips_to_the_same_box_the_api_serves():
    assert build.BBOX is config.COVERAGE
