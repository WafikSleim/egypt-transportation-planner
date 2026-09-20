# OTP data directory

This directory holds the OpenTripPlanner inputs and the graph it builds. None of
it is tracked in git — the files are too large for GitHub (`graph.obj` is around
490 MB, the OSM extract around 170 MB) and the GTFS feeds are CC BY-NC 4.0, so
redistributing them here would pull non-commercial terms over the repository.

Expected layout once populated:

```
OTP/
├── egypt-260919.osm.pbf     OSM extract for Egypt (Geofabrik)
├── road.zip                 TfC GTFS — road transport
├── metro.zip                TfC GTFS — Cairo Metro
└── graph.obj                built by OTP, not fetched
```

## Where the files come from

**OSM extract** — download `egypt-latest.osm.pbf` from
[Geofabrik](https://download.geofabrik.de/africa/egypt.html). The file committed
to this layout is date-stamped (`egypt-260919.osm.pbf`) so it is obvious how
stale the graph's base map is.

**GTFS feeds** — from Transport for Cairo's GeoNode portal:

- road transport: `https://data.transportforcairo.com/documents/88/download`
- metro: `https://data.transportforcairo.com/documents/87/download`

Each download is a zip *containing* the real GTFS zip, so unpack twice. Save the
inner zips here as `road.zip` and `metro.zip`.

One packaging detail matters: `routes.txt` and the other `.txt` files must sit at
the **root** of the zip, not nested inside a folder. A nested layout is the most
common reason a feed silently fails to enter the graph — check the build log for
`road.zip` if no transit appears.

## Scripts

**`scripts/fix_gtfs_calendar.py`** — shifts a feed's calendar onto a current
date range. Both feeds shipped expired: road `20250101–20251231`, metro
`20241028–20251027`. OTP honours `calendar.txt` literally, finds nothing running
today, and silently returns a walk-only itinerary instead of reporting an error.

```bash
python ../scripts/fix_gtfs_calendar.py road.zip metro.zip --dry-run   # inspect
python ../scripts/fix_gtfs_calendar.py road.zip metro.zip             # apply
```

It reads and writes the zips directly — no unzip/re-zip round trip — and keeps
the originals as `road.zip.bak` / `metro.zip.bak`. Those backups are the read
source on every run, so re-running does not compound earlier rewrites.

Each service keeps its weekly pattern and seasonal window rather than being
flattened to "runs daily"; the script explains why in its module docstring, and
verifies it by checking that service overlap is unchanged after the rewrite.

**Delete `graph.obj` before rebuilding.** OTP loads a stale graph rather than
rebuilding, so skipping this makes the fix look like it did nothing.

**`fetch_tfc_gtfs.py`** — still **not written**. It would handle the double-unzip
and print a report on the feed. For now that is manual.
