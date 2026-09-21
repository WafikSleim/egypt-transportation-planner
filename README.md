# Egypt Transportation Planner

A non-profit trip planner for public transport in Egypt, built around the
**paratransit network** — microbuses, tomnayas and minibuses — that Google Maps
and most routing tools ignore entirely.

Roughly 500 microbus routes and 70 tomnaya routes carry a large share of Greater
Cairo's daily trips, and none of them are searchable anywhere. That is the gap
this project exists to close.

**Not for profit.** No ads, no subscriptions, no in-app purchases. This is a
licence requirement of the underlying data, not a preference — see
[Licensing](#licensing).

## Status

**Pre-alpha, but routing works.** As of 2026-09-20 OpenTripPlanner returns real
multi-leg transit itineraries over both the metro and the microbus network —
Helwan to Shubra El-Kheima via M1/M2 with an interchange, Giza to New Cairo as
three microbus legs. There is no app around it yet.

Getting there took fixing two separate faults, one hiding the other. Every
search had been returning walk-only, even across 25 km:

1. **OTP was never loading the feeds.** It identifies GTFS by matching the
   *filename* against `(?i)gtfs`. `road.zip` and `metro.zip` don't contain
   "gtfs", so OTP ignored both and built a street-only graph — silently, with no
   error. Querying the running server for `feeds` and `routes` returned zero of
   each, which is what gave it away. The feeds are now `gtfs-road.zip` and
   `gtfs-metro.zip`.
2. **Both calendars had expired** — road `20250101–20251231`, metro
   `20241028–20251027`. OTP honours `calendar.txt` literally, so this would have
   produced walk-only results too, the moment the feeds started loading.
   [`scripts/fix_gtfs_calendar.py`](scripts/fix_gtfs_calendar.py) shifts both to
   `20260101–20271231`, preserving each service's weekly and seasonal pattern.

The rebuilt graph loads 1,012 routes and 3,105 stops across both feeds, and a
[backend API](api/README.md) now sits in front of it — trip planning, stop
search, Arabic, and the licence attribution served rather than hardcoded.

Nothing beyond that has been built. The client, the API and the database below
are design intent, not code that exists.

## Planned architecture

| Layer | Choice | Why |
| --- | --- | --- |
| Client | Flutter, MVVM + Bloc/Cubit (`app/`) | Thin — UI and API calls only, no routing logic |
| API | FastAPI in front of OpenTripPlanner (`api/`) | Keeps OTP internals out of the client |
| Database | Postgres + PostGIS | Stops, routes, and later user contributions |
| NL parsing | An LLM layer for colloquial Arabic queries | A front end over real data — **never** a source of route data |
| Maps | Self-hosted Protomaps tiles; geocoding from a `places` table built off the OSM extract | Per-request billing on commercial APIs would sink a free app. Photon was rejected — Elasticsearch on top of OTP's 3.4 GB |

## Running OpenTripPlanner locally

The data files are not in this repository (see [Data](#data) for how to get
them). Place them under `OTP/` as described in [OTP/README.md](OTP/README.md),
then:

Run these from the repository root.

```powershell
# Build the graph
docker run --rm -v "${PWD}\OTP:/var/opentripplanner" `
  opentripplanner/opentripplanner:latest --build --save

# Serve it on http://localhost:8080
docker run -it --rm -p 8080:8080 `
  -v "${PWD}\OTP:/var/opentripplanner" `
  opentripplanner/opentripplanner:latest --load --serve
```

On macOS or Linux:

```bash
docker run --rm -v "$(pwd)/OTP:/var/opentripplanner"   opentripplanner/opentripplanner:latest --build --save

docker run -it --rm -p 8080:8080   -v "$(pwd)/OTP:/var/opentripplanner"   opentripplanner/opentripplanner:latest --load --serve
```

The image supplies the `/var/opentripplanner` path itself. Do **not** pass a
directory argument, or OTP fails with `You must supply a single directory name`.

If the build runs out of memory, raise Docker Desktop's memory allocation to
8 GB or pass `-e JAVA_TOOL_OPTIONS="-Xmx8G"`.

## Data

Source: Transport for Cairo's GeoNode portal at `data.transportforcairo.com`.
**Not** the TfC GitHub repository — that one is stuck on a 2018 feed with only
217 routes.

| Document | URL | Contents |
| --- | --- | --- |
| 88 | `https://data.transportforcairo.com/documents/88/download` | Road transport |
| 87 | `https://data.transportforcairo.com/documents/87/download` | Cairo Metro |

Each download is a zip containing the real GTFS zip. Unpack twice.

The road feed (fieldwork 2019–2023, updated October 2025) covers Greater Cairo
only — lat 29.745–30.352, lon 30.846–31.775, nothing outside that box. It has
roughly 995–1011 routes, 2,983 stops and 1,769 directional variants across some
35,000 km of network: 511 microbus, 229 CTA bus, 104 CTA minibus, 70 tomnaya,
49 cooperative, 18 Mwasalat Misr, 9 box and 2 Green Bus.

### Three traps in this feed

1. **Every route is `route_type = 3`**, the metro included. Modes are
   distinguished by `agency_id`, not `route_type`. Any code branching on
   `route_type` will classify the metro as a bus.
2. **Metro line 3 is missing from this feed.** It has M1 and M2 only. M3 — one
   of the busiest lines in the city — is supplied by a feed of our own, built
   from [`data/metro-l3/`](data/metro-l3/README.md). Do not add it here.
3. **Hundreds of microbus routes share the short name "Microbus"** with no route
   numbers, because real Cairo microbuses have none. The UI cannot show a line
   number for these; identify them by origin and destination instead.

Two more things worth knowing before building on this feed:

- **Stop names come with Arabic translations.** `stops.txt` is Latin
  transliteration ("Arabella Square", "3rd Settlement Station"), but the road
  feed's `translations.txt` carries 3,106 `language=ar` rows covering stops,
  routes, trip headsigns and agencies — **all 2,997 road stops are covered**, via
  1,572 distinct names. It uses the `field_value` form, matching on the original
  string rather than `record_id`. The metro feed has no `translations.txt`, so
  its 108 stops are the ones still needing Arabic.
- **Fares in the feed are from 2018 and are worthless.** Never display them.
  Fares belong in a separate table we maintain; show "unavailable" rather than a
  wrong number.

### Other Egyptian data

- **Port Said** — [`youssefelzedy/PortSaid-Transit-GTFS`](https://github.com/youssefelzedy/PortSaid-Transit-GTFS).
  13 routes, 678 stops, created December 2025. The freshest Egyptian transit
  data that exists, and it already has Arabic names. CC BY-NC 4.0, with its own
  `ATTRIBUTION.md` that must be credited separately.
- **Alexandria** — exists via Digital Transport for Africa on GitLab, but the
  licence is unconfirmed; TUMI's mirror lists it as "License not specified".
  Not to be used until the repository's LICENSE file is checked.
- **Everywhere else in Egypt** — no transit data exists at all. Not Tanta, not
  Mansoura, not Aswan, not the railways. That has to be collected.

## Roadmap

The full backlog, with acceptance criteria, is in
[docs/user-stories.md](docs/user-stories.md). The design system — tokens, type,
Egyptian-Arabic copy and the rules the UI must honour — is in
[docs/design-system.md](docs/design-system.md), with clickable prototypes for
the app and the operations console in [`design/`](design/).

1. ~~Get OTP returning a real transit itinerary~~ — done
2. Arabic names for the metro feed's 108 stops, and surfacing the road feed's
   existing `translations.txt` through the API and UI
3. ~~Add metro line 3~~ — done, as its own feed. See [data/metro-l3/](data/metro-l3/README.md)
4. ~~Backend API in front of OTP~~ — done, see [api/](api/README.md)
5. Flutter client — started, see [app/](app/README.md). Search, stop picker,
   results and itinerary detail run against the live API *(current)*. Still to
   come: map tiles, place search, saved trips, notifications, tracking.
   No auth, no accounts, no settings screen
6. Contribution pipeline: a `submissions` table kept separate from the main
   data, promoted to confirmed after two independent confirmations, with a
   `trust_score` per contributor and a `confidence` level surfaced in the UI

The two-source schema — `source` and `confidence` on every route — gets built
from day one, while only TfC data exists. Retrofitting it later means rewriting
half the database.

## Licensing

**The TfC data is CC BY-NC 4.0 — non-commercial use only.** Any revenue,
advertising included, breaks the licence. TfC's FAQ also requires that software
built on the data be shared under CC BY-NC or another open licence, with
attribution. This repository is AGPL-3.0 accordingly; see [LICENSE](LICENSE).

The following attribution is required verbatim, and ships in the app:

> This data was created by Transport for Cairo 'TfC' with DigitalMatatus and
> Takween for Integrated Community Development, under the Digital Cairo Project
> supported by ExpoLive 2020.

**OpenStreetMap data is ODbL**, which permits commercial use but carries
share-alike.

**ODbL and CC BY-NC cannot be merged.** Combined into a single derived database,
ODbL demands the result be ODbL (commercial allowed) while CC BY-NC forbids
commercial use. The two must stay separate layers and must never be merged into
one dataset. OTP loads OSM and GTFS independently, so this holds naturally.

**Never upload TfC data into OpenStreetMap.** Putting CC BY-NC data into OSM
violates OSM's own licence, and the community treats it seriously.
