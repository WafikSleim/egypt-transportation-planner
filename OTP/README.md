# OTP data directory

This directory holds the OpenTripPlanner inputs and the graph it builds. None of
it is tracked in git — the files are too large for GitHub (`graph.obj` is around
490 MB, the OSM extract around 170 MB) and the GTFS feeds are CC BY-NC 4.0, so
redistributing them here would pull non-commercial terms over the repository.

Expected layout once populated:

```
OTP/
├── egypt-260919.osm.pbf     OSM extract for Egypt (Geofabrik)
├── gtfs-road.zip            TfC GTFS — road transport
├── gtfs-metro.zip           TfC GTFS — Cairo Metro (M1 and M2 only)
├── gtfs-metro-l3.zip        Metro Line 3 — ours, generated, not fetched
└── graph.obj                built by OTP, not fetched
```

## Running docker on this machine

Docker Desktop here installs per-user and puts nothing on `PATH`, so a bare
`docker` in PowerShell fails with "The term 'docker' is not recognized" even
while Docker Desktop is running. Use the full path, or add it to `PATH` once:

```powershell
$docker = "C:\Users\wafik\AppData\Local\Programs\DockerDesktop\resources\bin\docker.exe"
& $docker ps
```

```powershell
# permanent, for the current user
[Environment]::SetEnvironmentVariable("PATH",
  $env:PATH + ";C:\Users\wafik\AppData\Local\Programs\DockerDesktop\resources\bin",
  "User")
```

## Where the files come from

**OSM extract** — download `egypt-latest.osm.pbf` from
[Geofabrik](https://download.geofabrik.de/africa/egypt.html). The file committed
to this layout is date-stamped (`egypt-260919.osm.pbf`) so it is obvious how
stale the graph's base map is.

**GTFS feeds** — from Transport for Cairo's GeoNode portal:

- road transport: `https://data.transportforcairo.com/documents/88/download`
- metro: `https://data.transportforcairo.com/documents/87/download`

Each download is a zip *containing* the real GTFS zip, so unpack twice.

**The filename must contain "gtfs".** OTP decides what a file is by matching its
name against `(?i)gtfs`; anything else is ignored without so much as a warning.
A feed saved as `road.zip` is invisible to OTP, and the symptom is not an error
but walk-only itineraries. Save the inner zips as `gtfs-road.zip` and
`gtfs-metro.zip`, and keep "gtfs" in the name of any feed added later.

Two more packaging details: `routes.txt` and the other `.txt` files must sit at
the **root** of the zip, not nested in a folder; and the build log should list
every feed with a bus glyph, like `- 🚌 gtfs-road.zip`. If a feed is not in
that list, OTP did not load it.

## Scripts

**`scripts/fix_gtfs_calendar.py`** — shifts a feed's calendar onto a current
date range. Both feeds shipped expired: road `20250101–20251231`, metro
`20241028–20251027`. OTP honours `calendar.txt` literally, finds nothing running
today, and silently returns a walk-only itinerary instead of reporting an error.
(Note this was a second, hidden fault — the feeds were not loading at all until
they were renamed to match OTP's `gtfs` pattern, above.)

```bash
python ../scripts/fix_gtfs_calendar.py gtfs-road.zip gtfs-metro.zip --dry-run
python ../scripts/fix_gtfs_calendar.py gtfs-road.zip gtfs-metro.zip
```

It reads and writes the zips directly — no unzip/re-zip round trip — and keeps
the originals as `gtfs-road.zip.bak` / `gtfs-metro.zip.bak`. Those backups are the read
source on every run, so re-running does not compound earlier rewrites.

Each service keeps its weekly pattern and seasonal window rather than being
flattened to "runs daily"; the script explains why in its module docstring, and
verifies it by checking that service overlap is unchanged after the rewrite.

**Delete `graph.obj` before rebuilding.** OTP loads a stale graph rather than
rebuilding, so skipping this makes the fix look like it did nothing.

**`scripts/build_metro_l3.py`** — builds `gtfs-metro-l3.zip`, the Cairo Metro
Line 3 feed, which TfC's metro feed does not contain. Unlike everything else in
this directory it is not fetched from anywhere: it is generated from the tracked
source data in [`data/metro-l3/`](../data/metro-l3/README.md), so rebuild it
rather than looking for a download.

```bash
python ../scripts/build_metro_l3.py --dry-run
python ../scripts/build_metro_l3.py
```

Two warnings. **Never run `fix_gtfs_calendar.py` on this feed** — its calendar is
generated with an explicit window, and the calendar fixer would take a backup of
generated output and treat it as an original. And **Line 3 must not be added to
`gtfs-metro.zip`**: that mixes CC BY-NC data with data that is not TfC's, and the
calendar fixer reads `gtfs-metro.zip.bak` on every run, so it would silently
delete Line 3 the next time it ran.

Line 3's timetable is modelled rather than published; `data/metro-l3/README.md`
says exactly how, and it matters before showing any duration as a fact.

**`fetch_tfc_gtfs.py`** — still **not written**. It would handle the double-unzip
and print a report on the feed. For now that is manual.
