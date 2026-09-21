"""Egypt Transportation Planner - backend API.

Sits in front of OpenTripPlanner and does three things OTP does not:

1. Speaks in Cairo's vocabulary. OTP reports a microbus leg as `BUS`, because
   GTFS has no code for a 14-seater. This maps operators onto modes a passenger
   would recognise -- microbus, tomnaya, CTA bus, metro.
2. Gives paratransit routes something displayable. Hundreds of microbus routes
   share the name "Microbus" and have no route number, because real microbuses
   in Cairo have none. Those legs get a name built from origin and destination
   instead, and a flag telling the client not to render a number badge.
3. Refuses to serve fares. The feeds' fares are from 2018. Every itinerary
   carries an explicit "unavailable" instead.

The client stays thin: no routing logic, and the licence attribution is served
from here rather than hardcoded there.
"""

from __future__ import annotations

import datetime as dt
from contextlib import asynccontextmanager
from zoneinfo import ZoneInfo

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from . import config, modes, otp
from .models import (
    Attribution,
    FeedInfo,
    HealthResponse,
    Itinerary,
    Leg,
    ModeInfo,
    Place,
    PlanQuery,
    PlanResponse,
    RouteInfo,
    StopSummary,
    StopsResponse,
)

TZ = ZoneInfo(config.TIMEZONE)

# The road feed's own extent. Outside this box there is simply no data -- not
# Alexandria, not Tanta, nowhere. Worth saying so explicitly, because "no
# itineraries" and "this city has no transit data at all" look identical to a
# client otherwise.
COVERAGE = {"min_lat": 29.745, "max_lat": 30.352,
            "min_lon": 30.846, "max_lon": 31.775}


def _in_coverage(point: dict[str, float]) -> bool:
    return (COVERAGE["min_lat"] <= point["lat"] <= COVERAGE["max_lat"]
            and COVERAGE["min_lon"] <= point["lon"] <= COVERAGE["max_lon"])


def _why_empty(frm: dict, to: dict, time: str) -> tuple[str, str]:
    """Explain a result with no transit in it. Coverage first: it is the
    permanent reason, and the one a user cannot do anything about.

    Returns `(code, prose)`. The code is what a localised client switches on;
    the prose carries the detail a code cannot -- which endpoint was outside
    coverage, and whether the coordinates look swapped.
    """
    outside = [n for n, p in (("origin", frm), ("destination", to))
               if not _in_coverage(p)]
    if outside:
        # Swapped lat/lon is the most common way to get here, and inside Egypt
        # it cannot be rejected outright: Cairo reversed (31.24, 30.04) is a
        # point in the Mediterranean, valid-looking and firmly inside the
        # country's bounding box. If swapping would land in coverage, say so.
        swapped = [
            n for n, p in (("origin", frm), ("destination", to))
            if n in outside and _in_coverage({"lat": p["lon"], "lon": p["lat"]})
        ]
        hint = (
            f" The {' and '.join(swapped)} would be inside coverage with lat "
            "and lon the other way round — the expected order is 'lat,lon'."
            if swapped else ""
        )
        return "out_of_coverage", (
            f"No data for the {' and '.join(outside)}. Coverage is Greater "
            "Cairo only (roughly lat 29.75-30.35, lon 30.85-31.78); no other "
            f"part of Egypt has transit data yet.{hint}"
        )
    try:
        hour = int(time.split(":")[0])
    except (ValueError, IndexError):
        hour = -1
    if hour >= 22 or hour < 5:
        return "outside_service_hours", (
            f"No service found around {time}. Late-night service is sparse or "
            "absent across much of the network; try a daytime departure."
        )
    return "no_route", (
        "No itinerary found. Both points are inside the covered area, so this "
        "is more likely a gap in the network data than an error."
    )


ATTRIBUTION = Attribution(
    text=config.TFC_ATTRIBUTION,
    licence="CC BY-NC 4.0",
    source_url="https://data.transportforcairo.com",
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Nothing to warm up: OTP holds the graph and this process is stateless.
    yield


app = FastAPI(
    title="Egypt Transportation Planner API",
    description=__doc__,
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=config.CORS_ORIGINS,
    allow_methods=["GET"],
    allow_headers=["*"],
)


# --------------------------------------------------------------------------
# Translation from OTP's shapes to ours
# --------------------------------------------------------------------------

def _iso(epoch_millis: int | None) -> str:
    """OTP reports instants as epoch milliseconds. Render them in Cairo time,
    which is what a passenger means by a departure time."""
    if epoch_millis is None:
        return ""
    return dt.datetime.fromtimestamp(epoch_millis / 1000, tz=TZ).isoformat()


def _place(raw: dict, names: dict[str, str], lang: str) -> Place:
    stop = raw.get("stop") or {}
    stop_id = stop.get("gtfsId")
    return Place(
        # `names` carries localised stop names fetched separately; see
        # otp.STOP_NAMES_QUERY for why OTP cannot supply them inline.
        name=(names.get(stop_id)
              or modes.endpoint_label(raw.get("name") or "", lang)),
        lat=raw.get("lat") or 0.0,
        lon=raw.get("lon") or 0.0,
        stop_id=stop_id,
    )


def _route_info(raw_route: dict, mode: modes.Mode, frm: Place, to: Place,
                lang: str) -> RouteInfo:
    """Build something displayable, which for paratransit means not relying on
    a route number that does not exist."""
    short = (raw_route.get("shortName") or "").strip() or None
    long_name = (raw_route.get("longName") or "").strip() or None
    agency = raw_route.get("agency") or {}

    if mode.has_line_number and short:
        display = short
    elif long_name and mode.has_line_number:
        display = long_name
    else:
        # Hundreds of routes are literally named "Microbus". Origin and
        # destination are the only things that distinguish them, so that is
        # what the passenger gets.
        display = f"{mode.label(lang)}: {frm.name} → {to.name}"

    # Both conditions, not just the operator: a route whose operator normally
    # numbers its lines but which has no shortName has no badge to render.
    # No route in either feed is currently in that state.
    return RouteInfo(
        id=raw_route.get("gtfsId") or "",
        short_name=short,
        long_name=long_name,
        display_name=display,
        has_line_number=bool(mode.has_line_number and short),
        operator=agency.get("name"),
        operator_id=agency.get("gtfsId"),
        source="tfc",
        confidence="confirmed",
    )


def _leg(raw: dict, names: dict[str, str], lang: str) -> Leg:
    raw_route = raw.get("route") or {}
    agency = (raw_route.get("agency") or {}).get("gtfsId")
    otp_mode = raw.get("mode") or "WALK"
    mode = modes.resolve(agency, otp_mode)

    frm = _place(raw.get("from") or {}, names, lang)
    to = _place(raw.get("to") or {}, names, lang)
    trip = raw.get("trip") or {}

    return Leg(
        mode=ModeInfo(
            id=mode.id,
            label_en=mode.en,
            label_ar=mode.ar,
            seats=mode.seats,
            otp_mode=otp_mode,
        ),
        is_transit=bool(raw.get("transitLeg")),
        start_time=_iso(raw.get("startTime")),
        end_time=_iso(raw.get("endTime")),
        duration_minutes=round((raw.get("duration") or 0) / 60),
        distance_m=round(raw.get("distance") or 0),
        **{"from": frm},
        to=to,
        route=_route_info(raw_route, mode, frm, to, lang) if raw_route else None,
        headsign=raw.get("headsign") or trip.get("tripHeadsign") or None,
        intermediate_stops=len(raw.get("intermediatePlaces") or []),
    )


def _itinerary(raw: dict, names: dict[str, str], lang: str) -> Itinerary:
    legs = [_leg(leg, names, lang) for leg in raw.get("legs") or []]
    transit_legs = sum(1 for leg in legs if leg.is_transit)
    return Itinerary(
        start_time=_iso(raw.get("startTime")),
        end_time=_iso(raw.get("endTime")),
        duration_minutes=round((raw.get("duration") or 0) / 60),
        walk_distance_m=round(raw.get("walkDistance") or 0),
        transfers=max(0, transit_legs - 1),
        is_walk_only=transit_legs == 0,
        legs=legs,
    )


def _coords(value: str, field: str) -> dict[str, float]:
    """Parse "lat,lon". Rejecting anything outside Egypt early gives a far
    better error than an empty itinerary list."""
    try:
        lat_s, lon_s = value.split(",")
        lat, lon = float(lat_s), float(lon_s)
    except ValueError:
        raise HTTPException(
            422, f"'{field}' must be 'lat,lon', e.g. '30.0444,31.2357'"
        ) from None
    if not (22.0 <= lat <= 32.0) or not (24.0 <= lon <= 37.0):
        raise HTTPException(
            422,
            f"'{field}' ({lat}, {lon}) is outside Egypt. Note the order is "
            "lat,lon.",
        )
    return {"lat": lat, "lon": lon}


async def _stop_names(raw_itineraries: list[dict], lang: str) -> dict[str, str]:
    """Fetch localised names for every stop the itineraries touch.

    Done before the itineraries are built rather than patched afterwards, so
    that names derived from stops -- a microbus route's display name, which is
    origin and destination -- are localised too.

    Skipped entirely for English, where it would be a wasted round trip.
    """
    if lang == "en":
        return {}
    ids = {
        stop["gtfsId"]
        for itin in raw_itineraries
        for leg in itin.get("legs") or []
        for end in ("from", "to")
        for stop in [(leg.get(end) or {}).get("stop") or {}]
        if stop.get("gtfsId")
    }
    if not ids:
        return {}
    data = await _otp(otp.STOP_NAMES_QUERY, {"ids": sorted(ids)}, lang)
    return {
        s["gtfsId"]: s["name"]
        for s in data.get("stops") or []
        if s and s.get("gtfsId") and s.get("name")
    }


async def _otp(query: str, variables: dict, lang: str) -> dict:
    try:
        return await otp.query(query, variables, lang)
    except otp.OTPUnavailable as exc:
        raise HTTPException(503, str(exc)) from exc
    except otp.OTPError as exc:
        raise HTTPException(502, f"OTP rejected the query: {exc}") from exc


# --------------------------------------------------------------------------
# Endpoints
# --------------------------------------------------------------------------

@app.get("/", tags=["meta"])
async def root() -> dict:
    return {
        "name": "Egypt Transportation Planner API",
        "version": app.version,
        "docs": "/docs",
        "endpoints": ["/health", "/plan", "/stops", "/attribution"],
        "coverage": "Greater Cairo only. No other Egyptian city has transit "
                    "data yet.",
    }


@app.get("/attribution", response_model=Attribution, tags=["meta"])
async def attribution() -> Attribution:
    """The attribution the data licence requires, served so the client need not
    hardcode it."""
    return ATTRIBUTION


@app.get("/health", response_model=HealthResponse, tags=["meta"])
async def health() -> HealthResponse:
    """Reports OTP being down rather than failing, so a monitor can tell the
    difference between this process being broken and OTP being absent."""
    try:
        data = await otp.query(otp.HEALTH_QUERY)
    except (otp.OTPUnavailable, otp.OTPError) as exc:
        return HealthResponse(
            status="degraded",
            otp_url=config.OTP_URL,
            otp_reachable=False,
            detail=str(exc),
        )

    feeds = [
        FeedInfo(
            feed_id=f.get("feedId") or "",
            agencies=[a.get("name") or "" for a in f.get("agencies") or []],
        )
        for f in data.get("feeds") or []
    ]
    routes = len(data.get("routes") or [])
    stops = len(data.get("stops") or [])
    # OTP answering while holding no transit is the exact failure that made
    # every search return walk-only for days. Call it out rather than report ok.
    if not routes or not stops:
        return HealthResponse(
            status="degraded",
            otp_url=config.OTP_URL,
            otp_reachable=True,
            detail="OTP is up but its graph contains no transit. Check that "
                   "the feed filenames match (?i)gtfs and rebuild.",
            feeds=feeds,
            route_count=routes,
            stop_count=stops,
        )
    return HealthResponse(
        status="ok",
        otp_url=config.OTP_URL,
        otp_reachable=True,
        feeds=feeds,
        route_count=routes,
        stop_count=stops,
    )


@app.get("/plan", response_model=PlanResponse, tags=["routing"])
async def plan(
    from_: str = Query(
        ..., alias="from", description="Origin as 'lat,lon'.",
        examples=["29.8490,31.3340"],
    ),
    to: str = Query(
        ..., description="Destination as 'lat,lon'.",
        examples=["30.1220,31.2450"],
    ),
    date: str | None = Query(
        None, description="YYYY-MM-DD in Cairo time. Defaults to today."
    ),
    time: str | None = Query(
        None, description="HH:MM in Cairo time. Defaults to now."
    ),
    arrive_by: bool = Query(
        False, description="Treat date/time as the desired arrival instead."
    ),
    max_itineraries: int = Query(3, ge=1, le=10),
    lang: str = Query(
        "en", pattern="^(en|ar)$",
        description="'ar' returns Arabic stop and route names where the feed "
                    "provides them. Every road stop has one; metro stops do not.",
    ),
) -> PlanResponse:
    """Plan a trip.

    Coverage is Greater Cairo only, so a request outside roughly
    lat 29.7-30.4, lon 30.8-31.8 will return nothing useful even though the
    coordinates are valid.
    """
    now = dt.datetime.now(TZ)
    variables = {
        "from": _coords(from_, "from"),
        "to": _coords(to, "to"),
        "date": date or now.strftime("%Y-%m-%d"),
        "time": time or now.strftime("%H:%M"),
        "arriveBy": arrive_by,
        "num": max_itineraries,
    }
    data = await _otp(otp.PLAN_QUERY, variables, lang)
    raw = (data.get("plan") or {}).get("itineraries") or []
    names = await _stop_names(raw, lang)
    itineraries = [_itinerary(i, names, lang) for i in raw]
    # A walk-only itinerary is not an answer to "how do I get there by
    # transit". Outside Greater Cairo OTP returns them readily, because the
    # OSM extract covers the whole country while the feeds do not.
    has_transit = any(not i.is_walk_only for i in itineraries)
    note_code, note = (None, None) if has_transit else _why_empty(
        variables["from"], variables["to"], variables["time"]
    )

    return PlanResponse(
        query=PlanQuery(
            **{"from": from_},
            to=to,
            date=variables["date"],
            time=variables["time"],
            arrive_by=arrive_by,
            language=lang,
        ),
        itinerary_count=len(itineraries),
        itineraries=itineraries,
        note=note,
        note_code=note_code,
        attribution=ATTRIBUTION,
    )


@app.get("/stops", response_model=StopsResponse, tags=["places"])
async def stops(
    q: str = Query(..., min_length=2, description="Part of a stop name."),
    limit: int = Query(20, ge=1, le=100),
    lang: str = Query("en", pattern="^(en|ar)$"),
) -> StopsResponse:
    """Search stops by name.

    Searching matches the names in the requested language, so `lang=ar` expects
    an Arabic query string and `lang=en` a Latin one.
    """
    data = await _otp(otp.STOPS_QUERY, {"name": q}, lang)
    found = (data.get("stops") or [])
    total = len(found)
    page = found[:limit]

    # Routes are fetched only for the page being returned. Asking OTP for them
    # up front costs 2 MB on a broad prefix; this costs a couple of kB.
    routes_by_stop: dict[str, list[dict]] = {}
    if page:
        ids = [s.get("gtfsId") for s in page if s.get("gtfsId")]
        extra = await _otp(otp.STOP_ROUTES_QUERY, {"ids": ids}, lang)
        for s in extra.get("stops") or []:
            if s and s.get("gtfsId"):
                routes_by_stop[s["gtfsId"]] = s.get("routes") or []

    results = []
    for s in page:
        stop_id = s.get("gtfsId") or ""
        stop_routes = routes_by_stop.get(stop_id, [])
        mode_ids: list[str] = []
        for r in stop_routes:
            agency = (r.get("agency") or {}).get("gtfsId")
            # "BUS" is only a fallback for a route whose agency we cannot
            # place; agency_id is what actually decides the mode.
            resolved = modes.resolve(agency, "BUS")
            if resolved.id not in mode_ids:
                mode_ids.append(resolved.id)
        results.append(
            StopSummary(
                id=stop_id,
                name=s.get("name") or "",
                lat=s.get("lat") or 0.0,
                lon=s.get("lon") or 0.0,
                modes=mode_ids,
                route_count=len(stop_routes),
            )
        )

    return StopsResponse(
        query=q,
        count=len(results),
        total_matches=total,
        truncated=total > len(results),
        stops=results,
        attribution=ATTRIBUTION,
    )
