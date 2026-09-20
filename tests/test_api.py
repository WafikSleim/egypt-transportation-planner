"""Behaviour of the backend API.

Every case here was verified by hand against a live OTP while building the API,
and then protected by nothing. These are the ones where a regression would be
quiet: a mode silently reverting to "bus", a fare appearing, a walk-only result
presented as an answer.
"""

from __future__ import annotations

import pytest

from tests.conftest import (
    CTA_ROUTE,
    MICROBUS_ROUTE,
    cta_itinerary,
    metro_itinerary,
    microbus_itinerary,
    walk_only_itinerary,
)

pytestmark = pytest.mark.asyncio

CAIRO = {"from": "30.0080,31.2100", "to": "30.0280,31.4750",
         "date": "2026-09-21", "time": "09:00"}


# --------------------------------------------------------------------------
# Mode mapping -- agency_id, not route_type
# --------------------------------------------------------------------------

async def test_metro_leg_is_metro_not_bus(fake_otp, client):
    fake_otp.itineraries = [metro_itinerary()]
    async with client as c:
        body = (await c.get("/plan", params=CAIRO)).json()

    transit = [l for l in body["itineraries"][0]["legs"] if l["is_transit"]]
    assert [l["mode"]["id"] for l in transit] == ["metro", "metro"]
    assert transit[0]["mode"]["otp_mode"] == "SUBWAY"
    assert transit[0]["mode"]["label_ar"]


async def test_microbus_leg_is_microbus_not_bus(fake_otp, client):
    """OTP reports this as BUS. GTFS has no code for a 14-seater, so the
    operator is the only thing that distinguishes it."""
    fake_otp.itineraries = [microbus_itinerary()]
    async with client as c:
        body = (await c.get("/plan", params=CAIRO)).json()

    leg = [l for l in body["itineraries"][0]["legs"] if l["is_transit"]][0]
    assert leg["mode"]["otp_mode"] == "BUS"      # what OTP said
    assert leg["mode"]["id"] == "microbus"       # what we tell the client
    assert leg["mode"]["seats"] == 14


async def test_unknown_agency_falls_back_without_crashing(fake_otp, client):
    """A feed added later -- Port Said, Alexandria -- must not break routing."""
    itin = microbus_itinerary()
    itin["legs"][1]["route"]["agency"] = {"gtfsId": "9:WHO", "name": "Unknown"}
    fake_otp.itineraries = [itin]
    async with client as c:
        body = (await c.get("/plan", params=CAIRO)).json()

    leg = [l for l in body["itineraries"][0]["legs"] if l["is_transit"]][0]
    assert leg["mode"]["id"] == "transit"


# --------------------------------------------------------------------------
# Paratransit has no route numbers
# --------------------------------------------------------------------------

async def test_microbus_route_gets_name_from_endpoints(fake_otp, client):
    fake_otp.itineraries = [microbus_itinerary()]
    async with client as c:
        body = (await c.get("/plan", params=CAIRO)).json()

    route = [l for l in body["itineraries"][0]["legs"] if l["is_transit"]][0]["route"]
    assert route["has_line_number"] is False
    assert route["short_name"] == MICROBUS_ROUTE["shortName"] == "Microbus"
    # "Microbus" alone identifies nothing -- hundreds of routes share it.
    assert route["display_name"] != "Microbus"
    assert "Moneeb" in route["display_name"]
    assert "Cairo Festival City" in route["display_name"]


async def test_numbered_route_keeps_its_number(fake_otp, client):
    fake_otp.itineraries = [cta_itinerary()]
    async with client as c:
        body = (await c.get("/plan", params=CAIRO)).json()

    route = body["itineraries"][0]["legs"][0]["route"]
    assert route["has_line_number"] is True
    assert route["display_name"] == CTA_ROUTE["shortName"] == "381"


# --------------------------------------------------------------------------
# Walk-only results are not answers
# --------------------------------------------------------------------------

async def test_walk_only_is_flagged_and_explained(fake_otp, client):
    """OSM covers all of Egypt while the feeds cover Greater Cairo, so OTP
    returns a cheerful 45-minute walk for a trip in Aswan."""
    fake_otp.itineraries = [walk_only_itinerary()]
    async with client as c:
        body = (await c.get("/plan", params={
            "from": "24.0889,32.8998", "to": "24.1000,32.9100",
            "date": "2026-09-21", "time": "09:00"}))
    body = body.json()

    assert body["itinerary_count"] == 1
    assert body["itineraries"][0]["is_walk_only"] is True
    assert body["note"] and "Greater" in body["note"]


async def test_late_night_empty_result_blames_the_hour(fake_otp, client):
    fake_otp.itineraries = []
    async with client as c:
        body = (await c.get("/plan", params={**CAIRO, "time": "23:30"})).json()

    assert body["itinerary_count"] == 0
    assert "Late-night" in body["note"]


async def test_good_result_has_no_note(fake_otp, client):
    fake_otp.itineraries = [metro_itinerary()]
    async with client as c:
        body = (await c.get("/plan", params=CAIRO)).json()
    assert body["note"] is None


# --------------------------------------------------------------------------
# Fares: a licence and correctness requirement, not a feature
# --------------------------------------------------------------------------

async def test_fares_are_never_available(fake_otp, client):
    fake_otp.itineraries = [metro_itinerary(), microbus_itinerary()]
    async with client as c:
        body = (await c.get("/plan", params=CAIRO)).json()

    for itin in body["itineraries"]:
        assert itin["fare"]["available"] is False
        assert itin["fare"]["reason"]


async def test_fare_fields_are_never_requested_from_otp(fake_otp, client):
    """The metro feed ships fare_attributes.txt and a 353 kB fare_rules.txt.
    Not asking is stronger than asking and discarding."""
    fake_otp.itineraries = [metro_itinerary()]
    async with client as c:
        await c.get("/plan", params=CAIRO)

    sent = fake_otp.requests[0]["query"].lower()
    assert "fare" not in sent


# --------------------------------------------------------------------------
# Timing -- frequency-based service makes identical-looking itineraries
# --------------------------------------------------------------------------

async def test_itineraries_carry_departure_times(fake_otp, client):
    itin_a = metro_itinerary()
    itin_b = metro_itinerary()
    itin_b["startTime"] += 60_000
    fake_otp.itineraries = [itin_a, itin_b]
    async with client as c:
        body = (await c.get("/plan", params=CAIRO)).json()

    starts = [i["start_time"] for i in body["itineraries"]]
    assert all(starts), "a client cannot tell two departures apart without these"
    assert starts[0] != starts[1]
    assert "+03:00" in starts[0] or "+02:00" in starts[0]  # rendered in Cairo time


async def test_transfers_counted_from_transit_legs_only(fake_otp, client):
    fake_otp.itineraries = [metro_itinerary()]
    async with client as c:
        body = (await c.get("/plan", params=CAIRO)).json()
    # two metro legs, three walking legs -> one transfer
    assert body["itineraries"][0]["transfers"] == 1


# --------------------------------------------------------------------------
# Input validation
# --------------------------------------------------------------------------

@pytest.mark.parametrize("bad", ["nonsense", "30.0", "a,b", ""])
async def test_malformed_coordinates_rejected(fake_otp, client, bad):
    async with client as c:
        r = await c.get("/plan", params={**CAIRO, "from": bad})
    assert r.status_code == 422


async def test_coordinates_outside_egypt_rejected(fake_otp, client):
    async with client as c:
        r = await c.get("/plan", params={**CAIRO, "from": "48.8566,2.3522"})
    assert r.status_code == 422
    assert "outside Egypt" in r.json()["detail"]


async def test_swapped_cairo_coordinates_are_explained(fake_otp, client):
    """Cairo reversed is (31.24, 30.04) -- a point in the Mediterranean that
    sits inside Egypt's bounding box, so it cannot be rejected outright. It
    can be recognised: swapping it back lands in coverage."""
    fake_otp.itineraries = []
    async with client as c:
        body = (await c.get("/plan", params={
            **CAIRO, "from": "31.2357,30.0444"})).json()

    assert body["itinerary_count"] == 0
    assert "other way round" in body["note"]
    assert "lat,lon" in body["note"]


# --------------------------------------------------------------------------
# Language
# --------------------------------------------------------------------------

async def test_lang_is_forwarded_to_otp_as_accept_language(fake_otp, client):
    """All Arabic support rests on this one header."""
    fake_otp.itineraries = [metro_itinerary()]
    async with client as c:
        await c.get("/plan", params={**CAIRO, "lang": "ar"})
    assert fake_otp.requests[0]["lang"] == "ar"


async def test_unsupported_language_rejected(fake_otp, client):
    async with client as c:
        r = await c.get("/plan", params={**CAIRO, "lang": "fr"})
    assert r.status_code == 422


# --------------------------------------------------------------------------
# /stops
# --------------------------------------------------------------------------

async def test_stops_reports_truncation(fake_otp, client):
    """OTP's stops(name:) has no limit argument and matches on prefix, so a
    broad query matches hundreds. The client must be able to say so."""
    fake_otp.stops = [
        {"gtfsId": f"2:{i}", "name": f"Al-Something {i}", "lat": 30.0, "lon": 31.2}
        for i in range(100)
    ]
    async with client as c:
        body = (await c.get("/stops", params={"q": "Al", "limit": 5})).json()

    assert body["count"] == 5
    assert body["total_matches"] == 100
    assert body["truncated"] is True


async def test_stops_fetches_routes_only_for_the_returned_page(fake_otp, client):
    """The whole point of the two-hop lookup: asking OTP for every matching
    stop's routes cost 2 MB on a broad prefix."""
    fake_otp.stops = [
        {"gtfsId": f"2:{i}", "name": f"Stop {i}", "lat": 30.0, "lon": 31.2}
        for i in range(100)
    ]
    fake_otp.stop_routes = {
        "2:0": [{"gtfsId": "2:r1", "agency": {"gtfsId": "2:P_O_14"}}]
    }
    async with client as c:
        body = (await c.get("/stops", params={"q": "St", "limit": 3})).json()

    ids_requested = fake_otp.requests[1]["variables"]["ids"]
    assert len(ids_requested) == 3, "routes fetched for more stops than returned"
    assert body["stops"][0]["modes"] == ["microbus"]


async def test_stops_query_does_not_ask_for_routes(fake_otp, client):
    fake_otp.stops = []
    async with client as c:
        await c.get("/stops", params={"q": "Al"})
    assert "routes" not in fake_otp.requests[0]["query"]


# --------------------------------------------------------------------------
# Degradation -- OTP is a separate process and will not always be there
# --------------------------------------------------------------------------

async def test_health_reports_degraded_rather_than_failing(fake_otp, client):
    import httpx
    fake_otp.fail_with = httpx.ConnectError("refused")
    async with client as c:
        r = await c.get("/health")

    assert r.status_code == 200, "a monitor needs a body, not a stack trace"
    assert r.json()["status"] == "degraded"
    assert r.json()["otp_reachable"] is False


async def test_plan_returns_503_when_otp_is_down(fake_otp, client):
    import httpx
    fake_otp.fail_with = httpx.ConnectError("refused")
    async with client as c:
        r = await c.get("/plan", params=CAIRO)
    assert r.status_code == 503


async def test_health_flags_a_graph_with_no_transit(fake_otp, client):
    """The exact failure that made every search walk-only for days: OTP up,
    answering, holding zero transit."""
    fake_otp.health = {"feeds": [], "routes": [], "stops": []}
    async with client as c:
        body = (await c.get("/health")).json()

    assert body["status"] == "degraded"
    assert body["otp_reachable"] is True
    assert "gtfs" in body["detail"].lower()


async def test_health_ok_when_transit_present(fake_otp, client):
    async with client as c:
        body = (await c.get("/health")).json()
    assert body["status"] == "ok"
    assert body["route_count"] == 1012
    assert body["stop_count"] == 3105


async def test_graphql_errors_surface_as_502(fake_otp, client):
    fake_otp.graphql_errors = [{"message": "Unknown field 'bogus'"}]
    async with client as c:
        r = await c.get("/plan", params=CAIRO)
    assert r.status_code == 502
    assert "bogus" in r.json()["detail"]


# --------------------------------------------------------------------------
# Attribution -- a licence obligation
# --------------------------------------------------------------------------

async def test_attribution_is_verbatim_and_needs_no_otp(fake_otp, client):
    import httpx
    fake_otp.fail_with = httpx.ConnectError("refused")
    async with client as c:
        body = (await c.get("/attribution")).json()

    assert body["text"].startswith("This data was created by Transport for Cairo")
    assert "DigitalMatatus" in body["text"]
    assert "ExpoLive 2020" in body["text"]
    assert body["licence"] == "CC BY-NC 4.0"


async def test_plan_and_stops_carry_attribution(fake_otp, client):
    fake_otp.itineraries = [metro_itinerary()]
    fake_otp.stops = []
    async with client as c:
        plan = (await c.get("/plan", params=CAIRO)).json()
        stops = (await c.get("/stops", params={"q": "Al"})).json()

    assert plan["attribution"]["text"] == stops["attribution"]["text"]


# --------------------------------------------------------------------------
# Forward compatibility
# --------------------------------------------------------------------------

async def test_routes_carry_source_and_confidence(fake_otp, client):
    """Present from the first version so a second data source does not mean
    revising the client too."""
    fake_otp.itineraries = [microbus_itinerary()]
    async with client as c:
        body = (await c.get("/plan", params=CAIRO)).json()

    route = [l for l in body["itineraries"][0]["legs"] if l["is_transit"]][0]["route"]
    assert route["source"] == "tfc"
    assert route["confidence"] == "confirmed"
