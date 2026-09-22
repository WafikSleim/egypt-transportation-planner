# Backend API

A thin FastAPI service in front of OpenTripPlanner. It holds no routing logic
and no database — OTP has the graph, and this translates between OTP's
vocabulary and one that makes sense to a passenger in Cairo.

## Running it

OTP must be up first (see [../OTP/README.md](../OTP/README.md)).

```bash
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt   # Windows
.venv/Scripts/python -m uvicorn api.main:app --reload --port 8000
```

Interactive docs at `http://localhost:8000/docs`; the OpenAPI schema at
`/openapi.json` is what the Flutter client should generate its models from.

### Configuration

All optional, all environment variables.

| Variable | Default | Why you would change it |
| --- | --- | --- |
| `OTP_URL` | `http://localhost:8080/otp/gtfs/v1` | OTP on another host or port |
| `OTP_TIMEOUT` | `30` | A cold OTP is slow until the graph finishes loading |
| `TIMEZONE` | `Africa/Cairo` | Departure times are rendered in this zone |
| `CORS_ORIGINS` | `*` | Lock down before this is public |

## Tests

```bash
.venv/Scripts/python -m pip install -r requirements-dev.txt
.venv/Scripts/python -m pytest
```

**No Docker, no graph, no network.** OTP is stubbed with an
`httpx.MockTransport` injected at `api.otp.TRANSPORT`, and the app is driven
over an in-process ASGI transport. The whole suite runs in under a second, so
there is no excuse not to run it.

The stub sits at the transport layer rather than replacing `otp.query`, so the
tests still exercise the real request path — the `Accept-Language` header,
HTTP status handling, and GraphQL error unwrapping. Those are the parts most
likely to break quietly.

Covered: mode mapping by operator, paratransit display names, walk-only
detection, empty-result explanations, fare suppression (including that fare
fields are never *requested*), coordinate validation, language forwarding,
`/stops` truncation and the two-hop route lookup, and degradation when OTP is
down. `tests/test_fix_gtfs_calendar.py` covers the calendar script separately,
including the two bugs that already shipped: the non-idempotent re-run, and
`--daily` quietly quadrupling metro service.

The suite has been mutation-checked — disabling mode mapping, walk-only
detection, the microbus display name, `Accept-Language`, or the calendar
overlap guard each makes it fail.

## Endpoints

| Endpoint | Purpose |
| --- | --- |
| `GET /plan` | Plan a trip. `from`/`to` as `lat,lon`, optional `date`, `time`, `arrive_by`, `max_itineraries`, `lang` |
| `GET /stops` | Search stops by name. `q`, `limit`, `lang` |
| `GET /health` | OTP reachability plus feed, route and stop counts |
| `GET /attribution` | The licence attribution, verbatim |

```bash
curl "http://localhost:8000/plan?from=29.8490,31.3340&to=30.1220,31.2450&date=2026-09-21&time=08:00"
curl "http://localhost:8000/stops?q=Tahrir"
```

## What it does that OTP does not

**Speaks Cairo's vocabulary.** OTP reports a microbus leg as `BUS`, because
GTFS has no code for a 14-seater. Mode comes from `agency_id`, not
`route_type`, and each leg carries a `mode` object with `id`, `label_en`,
`label_ar` and nominal `seats` — `microbus`, `tomnaya`, `coop_minibus`,
`cta_bus`, `metro` and so on. See [modes.py](modes.py).

**Gives paratransit routes something to display.** Hundreds of microbus routes
are named literally "Microbus" and carry no route number, because real
microbuses in Cairo have none. Those legs get a `display_name` built from
origin and destination, and `has_line_number: false` so the client knows not to
render a route-number badge.

**Flags walk-only results.** The OSM extract covers all of Egypt while the
transit feeds cover Greater Cairo only, so OTP will happily return a two-hour
walk for a trip in Alexandria or Aswan. Those itineraries carry
`is_walk_only: true`, and the response's `note` explains that the city has no
transit data at all. A blank or walking result is otherwise indistinguishable
from a routing failure — which is exactly the confusion that cost this project
several days.

`note` is English prose and carries the detail — which endpoint fell outside
coverage, and whether the coordinates look swapped. Alongside it, `note_code`
gives the same reason as a stable key (`out_of_coverage`,
`outside_service_hours`, `no_route`), so the Arabic client can write its own
sentence instead of showing a passenger a bounding box in decimal degrees.
Both are set together, or neither is.

**Never serves a fare.** The feeds carry 2018 prices. The GraphQL query does
not even request fare fields, and every itinerary carries
`fare: {available: false}` with a reason.

**Carries `source` and `confidence`** on every route, derived from the feed the
route came out of rather than assumed — the mapping is `config.FEED_PROVENANCE`,
keyed on the feed id in front of the colon in a `gtfsId`. There are two sources
in the graph already: the TfC feeds come back as `tfc` / `confirmed`, and metro
line 3, which we compile ourselves from the operator's published stations and
Wikidata coordinates, comes back as `project` / `reported` — its timetable is
modelled, so calling it confirmed would claim a verification we never did. A
feed added later without an entry inherits the TfC labels, which is the one
thing to watch.

**Serves Arabic — including in itineraries, which OTP will not do.**
`lang=ar` is forwarded as `Accept-Language`, applying the road feed's
`translations.txt`; all 2,997 road stops have an Arabic name. But OTP applies
it inconsistently: `stop(id:)` returns Arabic while the *same stop* inside a
plan leg returns Latin. So localised names are fetched by id and merged in
before the itinerary is built — which also localises the microbus display
name, since that is built from its origin and destination. The metro feed has
no translations at all, so its 108 stops stay Latin and are passed through
unchanged rather than coming back blank.

Note that OTP's stop search is **prefix-based, not substring**, and it searches
in the requested language: `q=المنيب&lang=ar` matches, `q=منيب` does not, and
`q=Moneeb&lang=ar` returns nothing.

`/stops` responses carry `total_matches` and `truncated` alongside `count`,
because OTP has no limit argument and a broad prefix matches a lot: `q=Al` hits
757 stops. The client should prompt for a longer query rather than imply the
first 20 are everything.

That also shapes how the search is implemented: names are fetched first, the
page is cut to `limit`, and only then are routes fetched for those few stops.
Asking OTP for every matching stop's routes up front costs 2 MB on `q=Al`
against about 70 kB this way — and stop search is a typeahead, so that lands on
every keystroke.

## Not here on purpose

No auth, no accounts, no settings — the project brief rules them out. No
Postgres: OTP already holds the stops and routes, and the `source` /
`confidence` fields give forward compatibility without the infrastructure. The
contribution pipeline and the LLM layer for colloquial Arabic both come later.
