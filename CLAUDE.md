# Egypt Transportation Planner — OTP setup

## What this project is

A non-profit trip-planning app for public transport in Egypt, with a focus on
the paratransit network (microbuses, tomnayas, minibuses) that Google Maps and
most tools ignore.

Not for profit. No ads, no subscriptions, no in-app purchases — this is a
licence requirement, not a preference (see Licensing below).

Target stack:

- Flutter client (thin — UI and API calls only, no routing logic)
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

Tests live in `tests/` and run with `pytest` — no Docker, no graph, no network,
under a second. Run them before and after any change to `api/` or
`scripts/fix_gtfs_calendar.py`. OTP is stubbed at the transport layer via
`api.otp.TRANSPORT`, which exists purely so tests can drive the real request
path; leave it `None` in production.

Next: the app design prototype and user stories, then deployment to Oracle
Cloud. The full plan, including hosting, is in the approved project plan.

Repository: `https://github.com/WafikSleim/egypt-transportation-planner`
(public, AGPL-3.0). Working directory: `E:\EgyptTransportationPlanner\OTP`

Actually on disk today:

```
OTP/
├── egypt-260919.osm.pbf     OSM extract for Egypt (Geofabrik), date-stamped
├── gtfs-road.zip            TfC GTFS — road transport
├── gtfs-metro.zip           TfC GTFS — Cairo Metro
├── gtfs-road.zip.bak        pre-rewrite original, kept by fix_gtfs_calendar.py
├── gtfs-metro.zip.bak       pre-rewrite original
└── graph.obj                built by OTP
```

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
2. **Metro line 3 is missing.** The feed has M1 and M2 only. M3 has to be added
   by hand, and it is one of the busiest lines in the city.
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

ODbL and CC BY-NC are incompatible if merged into a single derived database:
ODbL requires the result be ODbL (commercial allowed), CC BY-NC forbids
commercial. Keep them as separate layers and never merge them into one dataset.
OTP already loads OSM and GTFS independently, so this happens naturally.

Never upload TfC data into OpenStreetMap — putting CC BY-NC data into OSM
violates OSM's own licence and the community treats it seriously.

## Next steps once routing works

1. Arabic names for the metro feed's 108 stops (the road feed is already
   covered by its `translations.txt`; wire that through to the API/UI)
2. Add metro line 3
3. ~~Backend API in front of OTP~~ — done, `api/`
4. Flutter client — search, map, itinerary. No auth, no accounts, no settings
5. Contribution pipeline: a `submissions` table separate from the main data,
   promoted to confirmed after two independent confirmations, with a
   `trust_score` per contributor and a `confidence` level exposed in the UI

Build the two-source schema (`source`, `confidence` on every route) from day
one even while only TfC data exists. Retrofitting it later means rewriting half
the database.
