# Egypt Transportation Planner — OTP setup

## What this project is

A non-profit trip-planning app for public transport in Egypt, with a focus on
the paratransit network (microbuses, tomnayas, minibuses) that Google Maps and
most tools ignore.

Not for profit. No ads, no subscriptions, no in-app purchases — this is a
licence requirement, not a preference (see Licensing below).

Target stack:

- Flutter client (thin — UI and API calls only, no routing logic)
- Backend API in front of OpenTripPlanner
- Postgres + PostGIS for stops, routes, and later user contributions
- An LLM layer for parsing colloquial Arabic queries — NOT a source of route
  data, only a natural-language front end over the real data
- Self-hosted map tiles and geocoding (Protomaps / Photon), not Google APIs,
  because per-request billing would sink a free app

## Current state

We are at step one: get OTP to return a real transit itinerary locally. The
only code in the repo is `scripts/fix_gtfs_calendar.py`; no application code
exists yet.

Repository: `https://github.com/WafikSleim/egypt-transportation-planner`
(public, AGPL-3.0). Working directory: `E:\EgyptTransportationPlanner\OTP`

Actually on disk today:

```
OTP/
├── egypt-260919.osm.pbf     OSM extract for Egypt (Geofabrik), date-stamped
├── road.zip                 TfC GTFS — road transport
├── metro.zip                TfC GTFS — Cairo Metro
├── road.zip.bak             pre-rewrite original, kept by fix_gtfs_calendar.py
├── metro.zip.bak            pre-rewrite original
└── graph.obj                built by OTP — STALE, predates the calendar fix
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

## Open problem

Every search returns a walk-only itinerary, even for 25 km trips. OTP is not
using transit at all.

Leading hypothesis: expired calendars. OTP honours `calendar.txt` literally,
finds no service running today, and silently falls back to walking rather than
reporting an error.

The calendars were read on 2026-09-20 and both were indeed expired — but **not**
from the 2019–2023 fieldwork period, which is what this file used to claim. The
actual windows were:

- road: `20250101–20251231`
- metro: `20241028–20251027`

This matters for the diagnostic. Setting the trip date to **2023** would show no
transit either, and would wrongly clear the calendar as the cause. The date that
discriminates is one inside those windows — **2025-06-15** sits in both.

Fix: `scripts/fix_gtfs_calendar.py`, written 2026-09-20 and already applied to
both feeds, which now run `20260101–20271231`. It reads and writes the zips
directly, so there is no unzip/re-zip step. Originals are kept as
`road.zip.bak` / `metro.zip.bak`, and those backups are the read source on every
run, so re-running is idempotent rather than compounding.

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

Note also that neither feed originally had a `calendar_dates.txt` at all, so the
old instruction to "clear" it was a no-op. The metro now has one, created by the
rewrite.

**The graph must be rebuilt** — `graph.obj` predates all of this. Delete it
first, or OTP loads the stale graph and none of it takes effect.

Other candidates, in order:

1. ~~The GTFS never entered the graph.~~ **Ruled out** on 2026-09-20: both zips
   have `routes.txt` and the rest at the root, not nested in a folder. The
   script re-checks this and errors out if a feed is ever packaged that way.
2. Stops not linked to the street network. Look for `unlinked` or `isolated`
   warnings in the build log.
3. Out of memory during the build — raise Docker Desktop's memory to 8 GB, or
   pass `-e JAVA_TOOL_OPTIONS="-Xmx8G"`.

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
- By operator: 511 microbus (14-seater), 229 CTA bus, 104 CTA minibus,
  70 tomnaya, 49 cooperative, 18 Mwasalat Misr, 9 box, 2 Green Bus
- Coverage: Greater Cairo only — lat 29.745–30.352, lon 30.846–31.775.
  Nothing outside this box.

### Three traps in this feed

1. **Every route is `route_type = 3`**, including the metro. Modes are
   distinguished by `agency_id`, not by `route_type`. Any code that branches on
   `route_type` will classify the metro as a bus.
2. **Metro line 3 is missing.** The feed has M1 and M2 only. M3 has to be added
   by hand, and it is one of the busiest lines in the city.
3. **Hundreds of microbus routes share the short name "Microbus"** and have no
   public route numbers — because real microbuses in Cairo have none. The UI
   cannot show a line number for these; identify them by origin and destination
   instead.

Also: all stop names are Latin transliteration ("Arabella Square", "3rd
Settlement Station"). Zero Arabic. Roughly 2,983 stops need Arabic names before
this is usable in Egypt. Plan: match stops by coordinates against OSM `name:ar`
via Overpass to cover most of them automatically, then translate the remainder
by hand.

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

1. Arabic stop names via OSM `name:ar` matching
2. Add metro line 3
3. Backend API in front of OTP
4. Flutter client — search, map, itinerary. No auth, no accounts, no settings
5. Contribution pipeline: a `submissions` table separate from the main data,
   promoted to confirmed after two independent confirmations, with a
   `trust_score` per contributor and a `confidence` level exposed in the UI

Build the two-source schema (`source`, `confidence` on every route) from day
one even while only TfC data exists. Retrofitting it later means rewriting half
the database.
