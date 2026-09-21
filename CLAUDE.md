# Egypt Transportation Planner — OTP setup

## What this project is

A non-profit trip-planning app for public transport in Egypt, with a focus on
the paratransit network (microbuses, tomnayas, minibuses) that Google Maps and
most tools ignore.

Not for profit. No ads, no subscriptions, no in-app purchases — this is a
licence requirement, not a preference (see Licensing below).

Target stack:

- Flutter client in `app/`, **MVVM with Bloc/Cubit**. Thin — UI and API calls
  only, no routing logic. Settled on 2026-09-21: a Cubit is the ViewModel,
  `data/` + `domain/` are the Model, `features/*/view/` is the View. Treat
  both the pattern and the state solution as decided — do not introduce a
  second state library
- Backend API in front of OpenTripPlanner: **Python + FastAPI**, in `api/`.
  Settled on 2026-09-20 after weighing Dart (one language with the Flutter
  client) and TypeScript. Python won on two grounds: the LLM layer below is
  Python territory, and FastAPI emits the OpenAPI schema the Flutter client
  generates its models from. Treat this as decided — do not propose porting it
- Postgres + PostGIS for stops, routes, and later user contributions
- An LLM layer for parsing colloquial Arabic queries — NOT a source of route
  data, only a natural-language front end over the real data
- Self-hosted map tiles and geocoding (Protomaps / Photon), not Google APIs,
  because per-request billing would sink a free app

## Current state

Step one is **done** as of 2026-09-20: OTP returns real transit itineraries
locally, over both the metro and the microbus network. Verified end to end —
Helwan to Shubra El-Kheima routes as M1 + interchange + M2, and Giza to New
Cairo as three microbus legs. The graph holds 1,012 routes and 3,105 stops.

The backend API exists too, as of 2026-09-20: FastAPI in `api/`, in front of
OTP, verified against the live graph. See [api/README.md](api/README.md).

The Flutter client was started on 2026-09-21 and lives in `app/`. What runs
end to end today: search → stop picker over `/stops` → results over `/plan` →
itinerary detail, in Arabic and English, light and dark. See
[app/README.md](app/README.md) — read the section on `TripPresenter` before
changing any screen.

**The design-system rules are enforced in one place**,
`app/lib/core/presentation/trip_presenter.dart`, and the Views are handed
view models with no wire fields left to interpret. That is deliberate: the
rules are derived from data fields, and every one of them fails plausibly
rather than visibly. A microbus with a route-number badge looks like an
answer.

Two client-side traps found on 2026-09-21, both now covered by tests:

- **`lang` is injected by `ApiClient`, never by a call site.** Stop and route
  names are localised server-side, so a request missing `lang` renders a
  fully Arabic screen with Latin stop names — indistinguishable from an app
  that works.
- **The metro circle already *is* the line number.** Drawing a number chip
  beside it printed "M1" twice; the presenter now suppresses the chip for
  metro legs.
- **`/plan` now returns `note_code` beside `note`.** `note` is English
  diagnostic prose with a bounding box in decimal degrees; showing it to the
  user would make the empty-results screen — the most common screen outside
  the covered area — the one place the app stops speaking Arabic. The client
  switches on the code and writes its own copy, falling back to `note` only
  for a code it does not recognise. Set `note_code` whenever you set `note`.

Sizing goes through `flutter_screenutil` against a 390x844 frame, so `Insets`
and `Radii` are scaled getters rather than constants — which is why widgets
using them are not `const`.

Tests live in `tests/` (Python, 74) and `app/test/` (Dart, 63). The Dart
suite runs with no device, no emulator and no network, against real API
responses captured in `app/test/fixtures/`. Run them with `pytest` — no Docker, no graph, no network,
and `cd app && flutter test`, before and after any change to `api/`,
`app/` or `scripts/fix_gtfs_calendar.py`. OTP is stubbed at the transport layer via
`api.otp.TRANSPORT`, which exists purely so tests can drive the real request
path; leave it `None` in production.

**Geocoding is a v1 dependency, not a later nicety.** The passenger search
covers stops, places and map-picking, so it needs a place index. Do **not**
stand up Photon — it needs Elasticsearch on top of OTP's 3.4 GB. Build a
`places` table from the OSM extract already on disk (`OTP/*.osm.pbf`), clipped
to the Cairo bbox, with `pg_trgm` for fuzzy matching and OSM `name:ar` for
Arabic. Postgres was Phase 4; this pulls it into Phase 3.

Keep that table **separate from the TfC data**. OSM is ODbL, TfC is CC BY-NC,
and the two cannot be merged into one derived database.

The backlog is in [docs/user-stories.md](docs/user-stories.md) — 36 stories
across passenger, contributor, moderator and maintainer. Priority there is
scoped to each story's own phase; the v1 release gate is the 20 Phase 2 and
Phase 3 `must` stories.

Design is done and is **core product value here, not surface**. The tokens,
type, Egyptian-Arabic copy and the non-negotiable rules live in
[docs/design-system.md](docs/design-system.md) — build from that, not by
reading colours out of the prototypes in `design/`.

Two things in there are easy to undo by accident:

- **Mode colours are real licence-plate colours** (microbus orange, tomnaya
  blue, cooperative grey), because that is how Cairenes identify a vehicle
  before reading it. Mode comes from `agency_id`, never `route_type`.
- **Metro uses circular line badges, not pills.** That form difference is the
  only thing keeping M1's blue from reading as a tomnaya.

Next: deployment to Oracle Cloud Always Free
(chosen because the licence forbids revenue; OTP measures 3.4 GB serving, and
the official image has an arm64 build). The full plan is in the approved
project plan.

Repository: `https://github.com/WafikSleim/egypt-transportation-planner`
(public, AGPL-3.0). Working directory: `E:\EgyptTransportationPlanner\OTP`

Actually on disk today:

```
OTP/
├── egypt-260919.osm.pbf     OSM extract for Egypt (Geofabrik), date-stamped
├── gtfs-road.zip            TfC GTFS — road transport
├── gtfs-metro.zip           TfC GTFS — Cairo Metro (M1 and M2 only)
├── gtfs-metro-l3.zip        ours, generated by scripts/build_metro_l3.py
├── gtfs-road.zip.bak        pre-rewrite original, kept by fix_gtfs_calendar.py
├── gtfs-metro.zip.bak       pre-rewrite original
└── graph.obj                built by OTP
```

`gtfs-metro-l3.zip` is the only feed here that is reproducible from the
repository: `data/metro-l3/` is tracked, so regenerate it with
`python scripts/build_metro_l3.py` rather than re-fetching it from anywhere.

The OSM filename carries its download date so it is obvious how stale the
graph's base map is — do not assume `egypt-latest.osm.pbf`.

`data/road/` and `data/metro/` do **not** exist yet. They are where the feeds
get unzipped for the calendar rewrite below; OTP itself reads the zips
directly and does not need them.

None of the above is tracked in git. `graph.obj` (~490 MB) and the OSM extract
(~170 MB) are over GitHub's 100 MB file limit, and the TfC feeds are CC BY-NC,
so committing them would make the repo a redistribution of non-commercial data.
`OTP/README.md` records where to re-fetch everything.

OTP runs via Docker. The image expects the data mounted at
`/var/opentripplanner` and supplies that path itself — do NOT pass a directory
argument, or OTP errors with "You must supply a single directory name".

```powershell
# build the graph
docker run --rm -v "E:\EgyptTransportationPlanner\OTP:/var/opentripplanner" `
  opentripplanner/opentripplanner:latest --build --save

# serve it
docker run -it --rm -p 8080:8080 `
  -v "E:\EgyptTransportationPlanner\OTP:/var/opentripplanner" `
  opentripplanner/opentripplanner:latest --load --serve
```

## Solved: why every search returned walk-only

_Resolved 2026-09-20. Kept in full because both faults are easy to reintroduce._

**Root cause: the feed filenames.** OTP only treats a file as GTFS if its
*filename* matches the regex `(?i)gtfs`. `road.zip` and `metro.zip` do not
contain the string "gtfs", so OTP silently ignored both, built a street-only
graph, and every search fell back to walking. No error, no warning — the feeds
just never appear in the build log.

Proven on 2026-09-20 by building the identical bytes under two names:

```
road.zip       -> "Unable to build graph, no transit nor OSM data available."
gtfs-road.zip  -> "- 🚌 gtfs-road.zip  /var/opentripplanner  5.5 MB"   loaded
```

The running server confirmed it beforehand: a GraphQL query for `feeds` and
`routes` returned **zero of each**, so the GTFS had never been in the graph at
all. That is the check to run first next time — it distinguishes "transit is
loaded but not being used" from "transit was never loaded", and those have
completely different causes:

```bash
curl -s -X POST http://localhost:8080/otp/gtfs/v1   -H "Content-Type: application/json"   -d '{"query":"{ feeds { feedId } routes { gtfsId } }"}'
```

So the feeds are now named `gtfs-road.zip` and `gtfs-metro.zip`. Keep "gtfs" in
the filename of any feed added later — Port Said, Alexandria, anything. The
alternative is a `build-config.json` with a custom
`storage.localFileNamePatterns.gtfs`, which is more configuration for no gain.

Note the `.bak` files are correctly ignored by OTP as an unknown type, so
keeping them in the data directory is safe.

### The expired calendars were real, but were not this bug

Both feeds also shipped calendars that had lapsed — road `20250101–20251231`,
metro `20241028–20251027`. That would have caused walk-only results too, as soon
as the feeds loaded at all. It was a genuine second fault hiding behind the
first, which is why fixing it changed nothing visible.

This also means the old diagnostic in this file was wrong twice over: setting
the trip date to **2023** shows no transit either, since no service ran in 2023.
A date inside the original windows — **2025-06-15** — is what discriminates, and
only once the feeds actually load.

`scripts/fix_gtfs_calendar.py` shifts both feeds to `20260101–20271231`. It reads
and writes the zips directly, so there is no unzip/re-zip step. Originals are
kept as `gtfs-road.zip.bak` / `gtfs-metro.zip.bak`, and those backups are the
read source on every run, so re-running is idempotent rather than compounding.

It does **not** flatten every service to daily, which was the original plan here
and is a trap. The metro's four services partition the year — `winter_std` and
`summer_std` are both Mon–Thu+Sun and never collide only because their date
ranges don't. Forcing them daily makes both active every weekday, and since the
metro is frequency-based that surfaces as roughly halved headways: wrong, and
plausible enough to miss. So each service keeps its weekly pattern and its
seasonal window, with out-of-season days removed via `calendar_dates.txt`. The
script verifies this by checking that every pair of service_ids shares days
after the rewrite exactly as it did before, and refuses to write if not.
`--daily` still exists and is correctly rejected on the metro feed.

Neither feed originally had a `calendar_dates.txt` at all, so the old
instruction to "clear" it was a no-op. The metro now has one, created by the
rewrite.

**Rebuild after any feed change.** Delete `graph.obj` first, or OTP loads the
stale graph and nothing takes effect.

### Still worth watching

1. Stops not linked to the street network. Look for `unlinked` or `isolated`
   warnings in the build log.
2. Out of memory during the build — raise Docker Desktop's memory to 8 GB, or
   pass `-e JAVA_TOOL_OPTIONS="-Xmx8G"`.
3. The OSM extract is all of Egypt (170 MB) while the feeds cover Greater Cairo
   only. Clipping it to the feed bounding box would make every rebuild faster.

## The data

Source: Transport for Cairo's GeoNode portal at `data.transportforcairo.com`.
Not the GitHub repo — that one is stuck on a 2018 feed with only 217 routes.

```
doc 88 → https://data.transportforcairo.com/documents/88/download   road transport
doc 87 → https://data.transportforcairo.com/documents/87/download   metro
```

Each download is a zip containing the real GTFS zip. Unpack twice. This is
currently manual — `fetch_tfc_gtfs.py`, which would handle the double-unzip and
print a report on the feed, is **not written yet**.

What is in the road feed (fieldwork 2019–2023, updated October 2025):

- ~995–1011 routes, ~2,983 stops, ~1,769 directional variants
- ~35,000 km of network
- By operator, counted from `routes.txt` on 2026-09-20 (1011 total):
  511 microbus `P_O_14`, 244 CTA bus `CTA`, 107 CTA minibus `CTA_M`,
  70 tomnaya `P_B_8`, 49 cooperative `COOP`, 18 Mwasalat Misr `MM`,
  9 box `BOX`, 2 Green Bus `GRN`, 1 LTRA minibus `LTRA_M`.
  (Earlier notes here said 229 CTA and 104 CTA minibus; those were low.)
- Coverage: Greater Cairo only — lat 29.745–30.352, lon 30.846–31.775.
  Nothing outside this box.

### Three traps in this feed

1. **Every route in the road feed is `route_type = 3`.** All 1011 of them,
   including 14-seater microbuses, because GTFS has no code for paratransit.
   Modes must be distinguished by `agency_id`. `api/modes.py` does this.

   Checked on 2026-09-20: this file previously claimed the metro was also
   `route_type = 3`. It is not — the metro is a separate feed and types itself
   correctly as `route_type = 1`, which OTP reports as `SUBWAY`. The road feed
   declares a `NAT` (National Authority for Tunnels) agency but has zero routes
   under it, which is the likely source of the confusion.
2. **Metro line 3 is missing from the TfC feed.** It has M1 and M2 only, and M3
   is one of the busiest lines in the city. We supply it ourselves as a third
   feed — see [Line 3 is our own feed](#line-3-is-our-own-feed) below. Do not
   add it to `gtfs-metro.zip`.
3. **Hundreds of microbus routes share the short name "Microbus"** and have no
   public route numbers — because real microbuses in Cairo have none. The UI
   cannot show a line number for these; identify them by origin and destination
   instead.

Also: `stops.txt` is Latin transliteration ("Arabella Square", "3rd Settlement
Station"), but the road feed ships a `translations.txt` that this file previously
overlooked — 3,106 rows, every one of them `language=ar`, covering stop names,
route names, trip headsigns and agency names.

Checked on 2026-09-20: **all 2,997 road stops already have an Arabic name**, via
1,572 distinct names (many stops share a name across directions). Coverage is
100%, not zero. Note the feed uses the `field_value` form of `translations.txt`
— rows match on the original string, not on `record_id`.

OTP serves these, but **inconsistently**, and this bit. With
`Accept-Language: ar`:

- `stop(id:)` and `stops(ids:)` return the Arabic name — correct
- the same stop reached through `plan { legs { from { stop { name } } } }`
  returns Latin

Verified in a single request against 2.11.0-SNAPSHOT on 2026-09-21: stop
`2:1145` came back as `المنيب` from `stop(id:)` and `Moneeb` from the plan leg.
So itineraries — the thing the whole app is — were English-only while stop
search looked fine, which is why this was easy to miss.

`api/main.py` works around it: `_stop_names()` fetches localised names by id
before the itinerary is built, so names derived from stops (a microbus route's
display name is its origin and destination) are localised too. Skipped for
English, where it would be a wasted round trip. If a later OTP fixes the
resolver, this can go.

OTP also labels the caller's own coordinates `Origin` / `Destination` in
English; `modes.endpoint_label()` translates those. And OTP's stop search is
prefix-based and searches in the requested language — `منيب` finds nothing,
`المنيب` finds 16.

What actually still needs Arabic is the **metro feed's 108 stops**, which has no
`translations.txt` at all. That is a small enough set to do by hand; the planned
Overpass matching against OSM `name:ar` is not needed for the road network.

Fares in the feed are from the 2018 era and are worthless now. Never show them.
Keep fares in a separate table that we maintain, and show "unavailable" rather
than a wrong number.

## Line 3 is our own feed

Added 2026-09-21. `OTP/gtfs-metro-l3.zip` is built by
`scripts/build_metro_l3.py` from three tracked files in `data/metro-l3/`:
`line3.json` (topology, 34 stations, both branches, Arabic names),
`coordinates.csv` (Wikidata, CC0, with each station's Q-id) and `service.json`
(the modelled timetable inputs). It is **not** merged into `gtfs-metro.zip`, for
two independent reasons:

- **Licence.** The TfC feed is CC BY-NC and these coordinates are not TfC's.
  Writing them in would make one derived database out of sources we are required
  to keep apart — the same reason the `places` table stays separate.
- **`fix_gtfs_calendar.py` reads `gtfs-metro.zip.bak` as its input on every
  run.** Anything added to `gtfs-metro.zip` is silently deleted the next time the
  calendar is fixed. Never run that script on the L3 feed either; its calendar is
  generated with an explicit window, so regenerate instead.

Nothing is lost by splitting it. OTP links stops across feeds by proximity, and
the L3 interchange points measure **2 m** from the TfC Attaba stops, **26 m**
from Nasser and **2 m** from Cairo University — inside the metro feed's own
same-station range of 2–38 m (Sadat is 16 m apart, Al-Shohadaa 38 m). M3↔M1 at
Nasser transfers exactly as M1↔M2 at Sadat does. `api/` needed no change at all:
`modes.py` keys off `agency_id`, which this feed sets to `NAT` to match.

Three things in here are easy to break:

1. **The timetable is modelled, not published.** Running time uses the rule the
   TfC feed itself uses — measured off its own M1 and M2 trips at a uniform
   40.4 km/h between stops with a 30 s dwell — and straight-line distances are
   scaled ×1.108 so the total matches the published 41.2 km. That gives 53 min
   Adly Mansour → Kit Kat and ~65 min to either western terminus. Headways are
   modelled on M2's window shape, halved per branch because trains alternate at
   Kit Kat. The builder refuses to write if any run time leaves its band. Treat
   these like the fares: never present them as operator times.
2. **The station `sequence` in `line3.json` is not a stop order.** It numbers all
   34 stations 1–34 in one chain, so Kit Kat (23) is followed by *both* Sudan
   (24) and El Tawfikia (30). Patterns are built by splitting on `branch`; using
   `sequence` splices both tails into one impossible trip.
3. **Line 3's terminus is named `Rod El Farag Axis`, not `Rod El Farag`.** The
   TfC feed already has a `Rod El Farag` — the Line 2 station, 2.4 km away. Two
   identically-named stops in different parts of the city make place search
   useless. The override lives in `STATION_NAME_OVERRIDES`.

The feed also ships a `translations.txt` giving all 34 stations their Arabic
name, in the `field_value` form the road feed uses. That makes M3 the only metro
line with Arabic stop names so far; M1 and M2 are still Latin.

Not in this feed: fares, real track geometry (shapes are straight lines between
stations), and the unbuilt Sheraton/Airport extension stations.

### Other Egyptian data

- **Port Said**: `github.com/youssefelzedy/PortSaid-Transit-GTFS` — 13 routes,
  678 stops, created December 2025. The freshest Egyptian transit data in
  existence, and it already has Arabic names. CC BY-NC 4.0.
- **Alexandria**: exists via Digital Transport for Africa on GitLab, but the
  licence is unconfirmed — TUMI's mirror lists it as "License not specified".
  Do not use until the repo's LICENSE file is checked.
- **Everywhere else in Egypt**: no transit data exists. Not Tanta, not
  Mansoura, not Aswan, not the railways. That part has to be collected.

## Licensing — these are hard constraints

**TfC data is CC BY-NC 4.0.** Non-commercial use only. Any revenue, including
advertising, breaks the licence. TfC's own FAQ also requires that software
built on it be shared under CC BY-NC or another open licence, with attribution.

Attribution text, required verbatim in the app:

> This data was created by Transport for Cairo 'TfC' with DigitalMatatus and
> Takween for Integrated Community Development, under the Digital Cairo Project
> supported by ExpoLive 2020.

Port Said has its own attribution in the repo's `ATTRIBUTION.md` — credit it
separately.

**OSM is ODbL**, which permits commercial use but carries share-alike.

**Wikidata is CC0** — no attribution required and no share-alike. That is why the
Line 3 station coordinates come from there rather than from the OSM extract on
disk: a CC0 source can sit in a feed of our own without dragging share-alike
terms across. Credit it anyway, in `data/metro-l3/README.md`.

ODbL and CC BY-NC are incompatible if merged into a single derived database:
ODbL requires the result be ODbL (commercial allowed), CC BY-NC forbids
commercial. Keep them as separate layers and never merge them into one dataset.
OTP already loads OSM and GTFS independently, so this happens naturally.

Never upload TfC data into OpenStreetMap — putting CC BY-NC data into OSM
violates OSM's own licence and the community treats it seriously.

## Next steps once routing works

1. Arabic names for the metro feed's 108 stops (the road feed is already
   covered by its `translations.txt`; wire that through to the API/UI). The L3
   feed already carries its own Arabic, so this is M1 and M2 only
2. ~~Add metro line 3~~ — done 2026-09-21, `OTP/gtfs-metro-l3.zip`. Still worth
   replacing the modelled timetable with published headways and run times
3. ~~Backend API in front of OTP~~ — done, `api/`
4. Flutter client — started, `app/`. Search, stop picker, results and
   itinerary detail work. Still missing: map tiles, place search and map
   picking (blocked on the `places` table), recents and saved trips,
   notifications, background tracking. No auth, no accounts, no settings
   screen — language and theme are the only two choices offered, and they
   live on the About screen
5. Contribution pipeline: a `submissions` table separate from the main data,
   promoted to confirmed after two independent confirmations, with a
   `trust_score` per contributor and a `confidence` level exposed in the UI

Build the two-source schema (`source`, `confidence` on every route) from day
one even while only TfC data exists. Retrofitting it later means rewriting half
the database.
