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

**Never serves a fare.** The feeds carry 2018 prices. The GraphQL query does
not even request fare fields, and every itinerary carries
`fare: {available: false}` with a reason.

**Carries `source` and `confidence`** on every route, fixed at `tfc` /
`confirmed` for now. They exist from the first version deliberately: the client
codes against this shape, and adding them once a second data source arrives
would mean revising the client too.

**Serves Arabic.** `lang=ar` is forwarded to OTP as `Accept-Language`, which
applies the road feed's `translations.txt` — all 2,997 road stops have an
Arabic name. The metro feed has no translations, so its 108 stops stay Latin.

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
