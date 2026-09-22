"""Response shapes.

These are the contract the Flutter client codes against, so they are declared
explicitly rather than passed through from OTP. Two consequences worth naming:

- `source` and `confidence` appear on every route, and are derived from the
  feed the route came out of (`config.FEED_PROVENANCE`) rather than assumed.
  There are two sources in the graph already: the TfC feeds, and our own
  metro line 3, whose timetable is modelled rather than published.
- There is no fare field beyond `FareInfo`, which only ever says "unavailable".
  The feeds' fares are from 2018 and showing one would be worse than showing
  nothing.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

# "project" is data we compiled ourselves rather than took from a feed someone
# else publishes — metro line 3, which TfC's feed does not contain.
Source = Literal["tfc", "portsaid", "osm", "community", "project"]
Confidence = Literal["confirmed", "reported", "unverified"]

# Why an empty result is empty, as a value the client can switch on.
#
# `note` beside it is English prose and stays that way: it carries the detail
# (which endpoint was outside coverage, whether the coordinates look swapped)
# and it is a diagnostic. But the client is Arabic-first, and the empty-result
# screen is the most common thing a passenger in an uncovered area will see.
# Making it render English with a bounding box in decimal degrees is the one
# place the app would stop speaking to its user. So the client switches on
# this code to choose its own copy, and falls back to `note` only for a code
# it does not recognise.
NoteCode = Literal[
    "out_of_coverage",
    "outside_service_hours",
    "no_route",
]


class Attribution(BaseModel):
    text: str = Field(..., description="Required verbatim wherever data is shown.")
    licence: str
    source_url: str


class Place(BaseModel):
    name: str
    lat: float
    lon: float
    stop_id: str | None = Field(
        None, description="Feed-prefixed GTFS stop id, e.g. '2:1145'. Null for "
                          "the caller's own origin or destination."
    )


class RouteInfo(BaseModel):
    id: str
    short_name: str | None = Field(
        None, description="Route number. Null or 'Microbus' for paratransit, "
                          "which has no public numbering."
    )
    long_name: str | None = None
    display_name: str = Field(
        ..., description="What to show the user. For a route with no number "
                         "this is built from origin and destination instead."
    )
    has_line_number: bool = Field(
        ..., description="False for microbus, tomnaya and similar. The UI "
                         "should not render a route-number badge for these."
    )
    operator: str | None = None
    operator_id: str | None = None
    source: Source = "tfc"
    confidence: Confidence = "confirmed"


class ModeInfo(BaseModel):
    id: str = Field(..., description="Stable key, e.g. 'microbus', 'metro', 'walk'.")
    label_en: str
    label_ar: str
    seats: int | None = Field(None, description="Nominal capacity where fixed.")
    otp_mode: str = Field(..., description="Raw OTP mode, e.g. BUS, SUBWAY, WALK.")


class Leg(BaseModel):
    mode: ModeInfo
    is_transit: bool
    start_time: str = Field(..., description="ISO 8601, Africa/Cairo.")
    end_time: str
    duration_minutes: int
    distance_m: int
    from_: Place = Field(..., alias="from")
    to: Place
    route: RouteInfo | None = None
    headsign: str | None = None
    intermediate_stops: int = 0

    model_config = {"populate_by_name": True}


class FareInfo(BaseModel):
    available: Literal[False] = False
    reason: str = (
        "Fares in the source feed date from 2018 and are no longer accurate. "
        "Showing a wrong price is worse than showing none."
    )


class Itinerary(BaseModel):
    start_time: str
    end_time: str
    duration_minutes: int
    walk_distance_m: int
    transfers: int
    is_walk_only: bool = Field(
        False,
        description="No transit leg at all. OSM covers the whole country while "
                    "the transit feeds cover Greater Cairo only, so OTP will "
                    "cheerfully return a two-hour walk for a trip in a city "
                    "with no data. The client should not present one of these "
                    "as a transit answer.",
    )
    legs: list[Leg]
    fare: FareInfo = FareInfo()


class PlanQuery(BaseModel):
    from_: str = Field(..., alias="from")
    to: str
    date: str
    time: str
    arrive_by: bool
    language: str

    model_config = {"populate_by_name": True}


class PlanResponse(BaseModel):
    query: PlanQuery
    itinerary_count: int
    itineraries: list[Itinerary]
    note: str | None = Field(
        None,
        description="Set only when no itinerary was found, explaining the "
                    "likely reason. An empty result is usually coverage or "
                    "time of day, not an error, and the client should say so "
                    "rather than show a blank screen. English prose, and "
                    "carries detail `note_code` cannot.",
    )
    note_code: NoteCode | None = Field(
        None,
        description="The same reason as a stable key, so a localised client "
                    "can write its own sentence rather than showing English "
                    "prose to an Arabic-speaking user. Always set whenever "
                    "`note` is.",
    )
    attribution: Attribution


class StopSummary(BaseModel):
    id: str
    name: str
    lat: float
    lon: float
    modes: list[str] = Field(
        default_factory=list,
        description="Distinct mode ids served, e.g. ['microbus', 'cta_bus'].",
    )
    route_count: int = 0
    source: Source = "tfc"
    confidence: Confidence = "confirmed"


class StopsResponse(BaseModel):
    query: str
    count: int = Field(..., description="Stops returned, after `limit`.")
    total_matches: int = Field(
        0, description="Stops OTP matched before `limit` was applied. A broad "
                       "prefix matches hundreds."
    )
    truncated: bool = Field(
        False, description="True when `total_matches` exceeds `count`, so the "
                           "client can prompt for a longer query rather than "
                           "imply these are all the matches."
    )
    stops: list[StopSummary]
    attribution: Attribution


class FeedInfo(BaseModel):
    feed_id: str
    agencies: list[str]


class PlaceIndexInfo(BaseModel):
    """State of the OSM place index.

    Reported because an empty `places` table and a query that genuinely
    matched nothing look identical from the client: both are an empty list.
    The ingest script is run by hand against a 170 MB extract, so "nobody ran
    it on this box" is a real and otherwise invisible state.
    """
    available: bool = Field(
        ..., description="False when the database is unreachable. Trip "
                         "planning and stop search still work without it."
    )
    place_count: int = 0
    category_count: int = 0
    arabic_name_count: int = Field(
        0, description="Places carrying an Arabic name. Well under half would "
                       "mean the ingest lost `name:ar`."
    )
    detail: str | None = None


class HealthResponse(BaseModel):
    status: Literal["ok", "degraded"]
    otp_url: str
    otp_reachable: bool
    detail: str | None = None
    feeds: list[FeedInfo] = Field(default_factory=list)
    route_count: int = 0
    stop_count: int = 0
    places: PlaceIndexInfo | None = Field(
        None, description="Null when the place index was not checked."
    )


# --------------------------------------------------------------------------
# Places (OSM). A second index, under a different licence to everything above.
# --------------------------------------------------------------------------

class PlaceCategory(BaseModel):
    """What kind of thing this is, pre-translated.

    Shaped like `ModeInfo` and for the same reason: the client is thin, and a
    category it has to translate itself is a category that ends up in English
    on an Arabic screen the first time someone adds a new one.
    """
    id: str = Field(..., description="Stable key, e.g. 'mall', 'street'.")
    label_en: str
    label_ar: str


class PlaceResult(BaseModel):
    """One place from the OSM index.

    Naming is the part to be careful with. In Egypt's OSM data the bare `name`
    tag is usually Arabic and `name:en` is often missing, so a `name_en`
    column populated from `name` would quietly fill with Arabic and render in
    a Latin slot. The two names are therefore kept apart, and the resolution
    is done here: `name` is what to show for the requested language,
    `name_language` says which language that actually is, and
    `name_is_fallback` says we had to reach for the other one.

    Both directions happen. A place with no `name:ar` must still be findable
    and must be shown with its Latin name and a note (design-system rule:
    never transliterate automatically -- a wrong Arabic name is worse than an
    honest English one). A place with no Latin name at all is the mirror case
    and must equally not be dropped from an English search.
    """
    id: str = Field(..., description="Stable id, 'n123'/'w456' from OSM.")
    name: str = Field(..., description="What to show, for the requested `lang`.")
    name_language: Literal["ar", "en"] = Field(
        ..., description="Which language `name` is actually in. The client "
                         "needs this to set text direction."
    )
    name_is_fallback: bool = Field(
        False,
        description="True when OSM has no name in the requested language and "
                    "this is the other one. The UI says so rather than hiding "
                    "the result, and never transliterates.",
    )
    name_ar: str | None = None
    name_en: str | None = None
    category: PlaceCategory
    area: str | None = Field(
        None, description="Containing neighbourhood or district, for telling "
                          "apart two places with the same name. Cairo has a "
                          "'Rod El Farag' in two different places."
    )
    lat: float
    lon: float
    distance_m: int | None = Field(
        None, description="Straight-line metres from the `near` point, when "
                          "one was given. Not a travel distance."
    )
    # OSM, never `tfc`: this index is built from the OpenStreetMap extract and
    # is kept in a separate database for licence reasons. `reported` because
    # it is community-contributed and nobody here has verified it on the
    # ground -- which is exactly what `confidence` is for.
    source: Source = "osm"
    confidence: Confidence = "reported"


class PlacesResponse(BaseModel):
    query: str
    count: int = Field(..., description="Places returned, after `limit`.")
    total_matches: int = Field(
        0, description="Places matched before `limit`. A short query matches "
                       "thousands."
    )
    truncated: bool = Field(
        False, description="True when `total_matches` exceeds `count`, so the "
                           "client can prompt for a longer query."
    )
    places: list[PlaceResult]
    attribution: Attribution = Field(
        ..., description="OpenStreetMap's, not the transit data's. These are "
                         "two datasets under two incompatible licences and "
                         "each has to be credited where it is shown."
    )
    matching: str = Field(
        "substring",
        description="How the query was matched, so the UI can state the "
                    "difference from `/stops`. Stop search is prefix-only: "
                    "'منيب' finds nothing there and finds 'المنيب' here.",
    )
