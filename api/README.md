# Backend API

A thin FastAPI service in front of OpenTripPlanner. It holds no routing logic —
OTP has the graph, and this translates between OTP's vocabulary and one that
makes sense to a passenger in Cairo.

It has one database, and only one: the OpenStreetMap place index behind
`/places`. Everything transit-related still comes from OTP.

## Running it

OTP must be up first (see [../OTP/README.md](../OTP/README.md)).

```bash
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt   # Windows
.venv/Scripts/python -m uvicorn api.main:app --reload --port 8000
```

`/places` additionally needs Postgres. It is optional — without it that one
endpoint answers 503 and everything else works:

```bash
docker compose up -d places-db          # from the repo root
.venv/Scripts/python -m pip install -r requirements-dev.txt   # pyosmium
.venv/Scripts/python scripts/build_places.py                  # ~11 minutes
.venv/Scripts/python scripts/build_places.py --check
```

`GET /health` reports whether the index is reachable and whether anyone has
filled it, because an empty table and a search that genuinely matched nothing
are the same empty list at the client.

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
| `PLACES_DATABASE_URL` | `postgresql://masar:masar@127.0.0.1:5432/masar_places` | Where the OSM place index lives |
| `PLACES_TIMEOUT` | `5` | Place search is a typeahead; a slow answer is a wrong one |

`PLACES_DATABASE_URL` is deliberately not called `DATABASE_URL`. It names the
one dataset that connection is allowed to hold: OpenStreetMap is ODbL and the
transit data is CC BY-NC, and the two must not end up in one derived database.
A generic name invites someone to point it at the transit data and join.

**Keep the `127.0.0.1` in it, and do not write `localhost`.** Compose binds
the port to the IPv4 loopback; `localhost` resolves to `::1` first on Windows
and on many Linux distributions, so the connection pays the IPv6 attempt's
timeout before falling back. Measured on this machine: `localhost` **130
seconds**, `127.0.0.1` **14 ms**, same database.

### Logging

**The access log keeps the path and throws the query string away.** A `/plan`
query string is a person's origin, their destination and a timestamp, and the
app promises in the dialog before the OS location prompt that there is «مافيش
سجل للأماكن اللي رحتها» — no record of the places you have been. A default
uvicorn access log makes that sentence false.

Before:

```
INFO: 127.0.0.1:52104 - "GET /plan?from=30.0444,31.2357&to=30.1220,31.2450&date=2026-09-22&time=08:00&lang=ar HTTP/1.1" 200
```

After:

```
INFO: 127.0.0.1:52104 - "GET /plan?<redacted> HTTP/1.1" 200
```

What is still logged: client address, method, path, HTTP version, status. That
is error rates per endpoint and evidence a request arrived, which is what one
maintainer on one box actually uses. What is deliberately gone: every query
parameter, on every endpoint — `/stops?q=` is a place someone typed, not just
`/plan`. The `?<redacted>` marker is only present when there *was* a query
string, so a plain path in the log means a plain request.

This is a filter on the `uvicorn.access` logger, installed at import of
`api.main` — see [logs.py](logs.py) for why it is not a `--log-config` file.
Because it is attached at import, it applies however the app is started, and
there is no launch command that produces the unredacted log. **Do not "fix"
this by turning access logging back on or passing a log config that bypasses
it**; `tests/test_access_log.py` will fail, which is the point.

Three other doors the same data could walk out of:

- **Whatever terminates TLS.** Caddy is planned for that, and its `log`
  directive records the full URI, query string included — fixing uvicorn does
  not fix Caddy. There is no deploy config in this repo yet (no Caddyfile, no
  Dockerfile, no compose file), so there is nothing here to correct; whoever
  adds one has to handle it there — Caddy's log encoder supports field
  filters, which is where this would go, but the exact directive has not been
  checked against a running Caddy and should not be copied from here.
- **`httpx` at DEBUG.** At INFO it logs `HTTP Request: POST <OTP_URL>`, which
  is harmless — the coordinates travel in the GraphQL POST body, not the URL.
  At DEBUG, `httpcore` logs that body. Do not raise either logger in
  production.
- **`HTTPException` detail.** `_coords` puts the rejected coordinates into its
  422 message so the caller can see what was wrong with them. That is a
  response, not a log line, and it should stay that way — never log
  `exc.detail`.

## Tests

```bash
.venv/Scripts/python -m pip install -r requirements-dev.txt
.venv/Scripts/python -m pytest
```

**No Docker, no graph, no database, no network.** OTP is stubbed with an
`httpx.MockTransport` injected at `api.otp.TRANSPORT`, the place database with
a coroutine injected at `api.places.EXECUTOR`, and the app is driven over an
in-process ASGI transport. The whole suite runs in under a second, so there is
no excuse not to run it.

Both stubs sit one layer below the code under test rather than replacing it,
so the tests still exercise the real request path — the `Accept-Language`
header, HTTP status handling and GraphQL error unwrapping on one side; the
real SQL text, parameter binding, query normalisation and row-to-model mapping
on the other. Those are the parts most likely to break quietly.

The place stub is `autouse`, and its default state is "no database
configured". A test that forgets to arrange one therefore gets an instant,
honest failure instead of a five-second attempt to open a socket to
localhost:5432.

What a fake cannot check is whether the endpoint works at all against a real
database. Two faults got through a green suite and were only found by running
the live one, and both are recorded in `api/places.py`: psycopg's **async mode
refuses to run on Windows' default event loop**, which is the one uvicorn
installs there, and **`psycopg_pool`'s worker threads never start under Python
3.14**, so every checkout ends in `PoolTimeout` while a plain `connect()` to
the same URL succeeds. Hence the synchronous driver on a thread-local
connection. Nor can a fake check that Postgres accepts the SQL — the doubled
`%%`, the trigram operator, the generated geography column.
`python scripts/build_places.py --check` runs the API's own statements against
a real PostGIS instance and prints what comes back; that is the step the suite
structurally cannot replace.

Covered: mode mapping by operator, paratransit display names, walk-only
detection, empty-result explanations, fare suppression (including that fare
fields are never *requested*), coordinate validation, language forwarding,
`/stops` truncation and the two-hop route lookup, degradation when OTP is
down, and that a `/plan` request's coordinates never reach the access log.
`tests/test_places.py` covers the place index: the normalisation that makes
منيب find المنيب, that both name columns are searched whatever `lang` says,
both name-fallback directions, the bounding box, the OSM attribution not being
TfC's, 503 rather than 500 when the database is gone, that a typed place name
reaches neither the log nor the error body, and the ingest script's tag filter
and de-duplication (including that two real places sharing a name both
survive). `tests/test_fix_gtfs_calendar.py` covers the calendar script separately,
including the two bugs that already shipped: the non-idempotent re-run, and
`--daily` quietly quadrupling metro service.

The suite has been mutation-checked — disabling mode mapping, walk-only
detection, the microbus display name, `Accept-Language`, the access-log
redaction, or the calendar overlap guard each makes it fail.

## Endpoints

| Endpoint | Purpose |
| --- | --- |
| `GET /plan` | Plan a trip. `from`/`to` as `lat,lon`, optional `date`, `time`, `arrive_by`, `max_itineraries`, `lang` |
| `GET /stops` | Search stops by name. `q`, `limit`, `lang` |
| `GET /places` | Search the OSM place index. `q`, `near`, `limit`, `lang` |
| `GET /places/reverse` | Name the point a map pin settled on. `at`, `radius_m`, `limit`, `lang` |
| `GET /health` | OTP reachability, feed/route/stop counts, and the place index's state |
| `GET /attribution` | The transit licence attribution, verbatim |

```bash
curl "http://localhost:8000/plan?from=29.8490,31.3340&to=30.1220,31.2450&date=2026-09-21&time=08:00"
curl "http://localhost:8000/stops?q=Tahrir"
curl "http://localhost:8000/places?q=%D9%85%D9%86%D9%8A%D8%A8&lang=ar"
curl "http://localhost:8000/places/reverse?at=30.0281,31.4075&lang=ar"
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

## `/places` — the second index

**Searches for a mall, a street or a landmark, which `/stops` cannot answer.**
Nobody knows the name of the stop that serves Cairo Festival City. OTP's stop
search is prefix-based and scoped to the requested language, so `منيب` finds
nothing and `Moneeb&lang=ar` finds nothing. `/places` is a different index
with deliberately different behaviour, and the UI is expected to say so —
design-system.md calls for stating the difference, because a user who types
منيب and gets nothing concludes the app is broken.

**Matching.** Query and stored names go through the same
`api.places.normalize_name`: NFKC, tashkeel and tatweel removed, أ إ آ → ا,
ة → ه, ى ئ → ي, Arabic-Indic digits → ASCII, Latin diacritics and
transliteration marks folded (`El-Maʿādī` → `maadi`), the leading definite
article dropped. Then substring `LIKE`, ORed with `pg_trgm` similarity for
typos, against **both** name columns whatever `lang` says — `lang` decides
which name comes back, never what is looked at. Results are ordered exact
match, then prefix, then similarity, then distance from `near`, then category
prominence.

That normalisation is one function used by both the ingest and the query. If
the two ever drift, search half-works — some queries hit, some silently do not
— so `tests/test_places.py` asserts they are literally the same object.

**Arabic, and the two fallback directions.** In Egypt's OSM the bare `name`
tag is usually Arabic and `name:en` is often absent; 99% of the indexed rows
have an Arabic name. A `name_en` column filled from `name` would quietly fill
with Arabic, so names are routed by the script they are written in. Each
result carries `name` (what to show), `name_language` (what it actually is,
so the client can set direction) and `name_is_fallback`. A place with no
Arabic name is shown in Latin with a note and **never transliterated** — a
wrong Arabic name is worse than an honest English one — and a place with no
Latin name is not dropped from an English search either.

**Bounded by coverage.** Every query carries the coverage box in its `WHERE`
clause. A place outside Greater Cairo is a search result no itinerary can be
planned to.

**Attribution is OpenStreetMap's, not TfC's.** Two datasets, two incompatible
licences, two credits — see below.

`/places/reverse` names the point a map pin settled on (P-18). It orders by
distance in 100 m bands and by prominence within a band, so standing in a
mall's car park names the mall rather than the service road beside it. It does
**not** report the nearest stop: that is transit data out of OTP, and the
client asks both and labels them separately.

### The licence line, in code

OSM is ODbL; the TfC transit data is CC BY-NC. Merged into one derived
database the two contradict each other — ODbL requires the result be ODbL,
which permits commercial use, and CC BY-NC forbids it. Kept side by side they
are a collective database, which neither licence objects to.

So the place index is a **separate database**, `PLACES_DATABASE_URL`, holding
schema `osm` and nothing else. Nothing derived from the feeds is written into
it, there is no join between the two, and `/places` answers carry
`© OpenStreetMap contributors` / ODbL while `/plan` and `/stops` carry TfC's
text / CC BY-NC. `/attribution` is unchanged and still serves the transit one.

### Building the index

`scripts/build_places.py` reads `OTP/*.osm.pbf` — already on disk for the
street network — clips it to the coverage box and writes `osm.places`. It is
idempotent (truncate and reload in one transaction) and refuses to write when
a check fails: row count outside its band, a row outside the box, Arabic names
below half, a category with no label, or any of five probe searches matching
nothing.

**Not Photon**: it wants Elasticsearch alongside OTP's measured 3.4 GB on a
free-tier box.

What it indexes: districts and neighbourhoods, squares, named streets, malls,
universities, schools, hospitals and clinics, stations and bus terminals, the
airport, parks, stadiums and clubs, museums and monuments, mosques and
churches, government offices and embassies, libraries, theatres, cinemas,
hotels. What it deliberately does not: bus stops and platforms (that is
`/stops`, out of the other dataset), and the long tail of chains and corner
shops — supermarkets, cafes, restaurants, bank branches, pharmacies, filling
stations. Those do not merely make the table bigger; they make the *top*
result wrong, and a typeahead is judged on its first three rows.

Stations are the one deliberate overlap: OSM's metro stations stay in, because
the TfC metro feed has no Arabic names for M1 and M2 and `/stops` therefore
cannot find «السادات» at all.

## Not here on purpose

No auth, no accounts, no settings — the project brief rules them out. The only
database is the OSM place index; stops and routes still come from OTP, and the
`source` / `confidence` fields give forward compatibility without more
infrastructure. The contribution pipeline and the LLM layer for colloquial
Arabic both come later, and when they arrive they get their own database
beside the place one rather than a schema inside it.
