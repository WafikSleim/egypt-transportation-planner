#!/usr/bin/env python3
"""Build a GTFS feed for Cairo Metro Line 3 from the data in data/metro-l3/.

Line 3 is missing from the TfC metro feed, which has M1 and M2 only. It is one
of the busiest lines in the city, so every itinerary through Heliopolis,
Abbassia, Imbaba or Boulak El Dakrour was either wrong or fell back to
microbuses. This builds the line as its own feed rather than editing
gtfs-metro.zip, for two reasons:

  1. Licence. The TfC feed is CC BY-NC. The station coordinates here are from
     Wikidata (CC0) and the topology from the operator's published station list.
     Writing them into the TfC feed would make one derived database out of
     sources we are required to keep apart. A separate feed keeps the layers
     separate exactly as OTP already keeps OSM and GTFS apart.
  2. fix_gtfs_calendar.py reads gtfs-metro.zip.bak as its input on every run, so
     anything added to gtfs-metro.zip is silently deleted the next time the
     calendar is fixed.

Nothing is lost by splitting the feed. OTP links stops across feeds by
proximity, and the Line 3 interchange points measure 2 m from the TfC Attaba
stops, 26 m from Nasser and 2 m from Cairo University - inside the metro feed's
own same-station range of 2-38 m (Sadat is 16 m apart, Al-Shohadaa 38 m). It
transfers exactly as M1 <-> M2 already does.

The filename must keep the string "gtfs": OTP only recognises a file as GTFS if
the filename matches (?i)gtfs, and ignores it silently otherwise.

The timetable is MODELLED, not observed. Running time comes from the rule the
TfC feed itself uses - both M1 and M2 run at a uniform 40.4 km/h between stops
with a 30 s dwell everywhere - so Line 3 is consistent with the rest of the
graph. Headways are modelled on M2's window shape, halved per branch because
trains alternate at Kit Kat. Never present these as published times.

Two things here are easy to get wrong:

  * The station "sequence" in line3.json is NOT a stop order. It numbers all 34
    stations 1-34 in one chain, so Kit Kat (23) is followed by both Sudan (24)
    and El Tawfikia (30). Patterns are built by splitting on "branch".
  * "Rod El Farag" is already a station name in the TfC metro feed, on Line 2,
    2.4 km away from this one. Line 3's terminus is published as the Rod El
    Farag Axis, and is named that way here (STATION_NAME_OVERRIDES) so place
    search cannot return two indistinguishable results.

Usage:
    python build_metro_l3.py                       # writes ../OTP/gtfs-metro-l3.zip
    python build_metro_l3.py --dry-run
    python build_metro_l3.py --out /tmp/feed.zip
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import importlib.util
import io
import json
import math
import os
import sys
import tempfile
import zipfile
from pathlib import Path

# scripts/ is not a package, so the shared GTFS helpers are loaded by path the
# same way the tests load these scripts.
_spec = importlib.util.spec_from_file_location(
    "fix_gtfs_calendar", Path(__file__).resolve().parent / "fix_gtfs_calendar.py")
_fixcal = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_fixcal)

parse_date = _fixcal.parse_date
fmt_date = _fixcal.fmt_date
read_table = _fixcal.read_table
render_table = _fixcal.render_table

DAYS = _fixcal.DAYS
DEFAULT_START = _fixcal.DEFAULT_START
DEFAULT_END = _fixcal.DEFAULT_END

REPO = Path(__file__).resolve().parents[1]
DATA = REPO / "data" / "metro-l3"
DEFAULT_OUT = REPO / "OTP" / "gtfs-metro-l3.zip"
METRO_FEED = REPO / "OTP" / "gtfs-metro.zip"

FEED_ID = "metro-l3"
ROUTE_ID = "L3"
AGENCY_ID = "NAT"

# The TfC metro feed already has a "Rod El Farag" - the Line 2 station, 2.4 km
# from this one. The operator publishes Line 3's terminus as the Rod El Farag
# Axis, which is also what the Arabic in line3.json says (محور روض الفرج).
STATION_NAME_OVERRIDES = {
    "rod_el_farag": "Rod El Farag Axis",
}

# Patterns: (suffix, branch key, direction_id westbound, direction_id eastbound)
BRANCHES = (
    ("RF", "rod_el_farag_branch"),
    ("CU", "cairo_university_branch"),
)


# --------------------------------------------------------------------------
# Geometry
# --------------------------------------------------------------------------

def haversine(lat1, lon1, lat2, lon2):
    """Great-circle distance in metres."""
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def hms(seconds):
    """GTFS time. Hours past midnight are allowed to exceed 24."""
    h, rem = divmod(int(seconds), 3600)
    m, s = divmod(rem, 60)
    return "{:02d}:{:02d}:{:02d}".format(h, m, s)


def parse_hms(text):
    h, m, s = (int(x) for x in text.split(":"))
    return h * 3600 + m * 60 + s


# --------------------------------------------------------------------------
# Source data
# --------------------------------------------------------------------------

class Line:
    """line3.json plus coordinates.csv, validated against each other."""

    def __init__(self, line, coords):
        self.raw = line
        self.short_name = line["shortName"]
        self.long_name = line["name"]
        self.long_name_ar = line["nameAr"]
        self.total_km = float(line["totalLengthKm"])

        self.stations = {}
        for st in line["stations"]:
            sid = st["id"]
            self.stations[sid] = {
                "id": sid,
                "name": STATION_NAME_OVERRIDES.get(sid, st["name"]),
                "name_ar": st["nameAr"],
                "branch": st.get("branch"),
                "sequence": int(st["sequence"]),
            }

        json_ids = set(self.stations)
        csv_ids = set(coords)
        if json_ids != csv_ids:
            missing = sorted(json_ids - csv_ids)
            extra = sorted(csv_ids - json_ids)
            raise SystemExit(
                "line3.json and coordinates.csv disagree on the station set.\n"
                "  no coordinates for: {}\n"
                "  not a station     : {}".format(missing or "-", extra or "-"))

        for sid, (lat, lon, source, ref) in coords.items():
            self.stations[sid].update(lat=lat, lon=lon,
                                      coord_source=source, coord_ref=ref)

        # translations.txt matches on the field value, not on a record id, so
        # two stations sharing a stop_name would make their Arabic ambiguous.
        seen = {}
        for st in self.stations.values():
            if st["name"] in seen:
                raise SystemExit(
                    "two stations share the name {!r} ({} and {}); "
                    "translations.txt matches on the name, so this would be "
                    "ambiguous. Add an entry to STATION_NAME_OVERRIDES."
                    .format(st["name"], seen[st["name"]], st["id"]))
            seen[st["name"]] = st["id"]

        # The sequence field is a single 1-34 chain across both branches, so it
        # cannot be used as a stop order. Trunk = the stations with no branch.
        self.trunk = [s["id"] for s in
                      sorted((s for s in self.stations.values() if not s["branch"]),
                             key=lambda s: s["sequence"])]
        self.branch_tails = {}
        for _, key in BRANCHES:
            tail = [s["id"] for s in
                    sorted((s for s in self.stations.values() if s["branch"] == key),
                           key=lambda s: s["sequence"])]
            if not tail:
                raise SystemExit("no stations found for branch {}".format(key))
            self.branch_tails[key] = tail

        junction = line["structure"]["mainJunction"]
        if self.trunk[-1] != junction:
            raise SystemExit(
                "the trunk should end at the junction {} but ends at {}"
                .format(junction, self.trunk[-1]))

        # Every straight-line segment is scaled so the whole line matches the
        # published route length; the track is not straight between stations.
        # Each segment counts once - the trunk and both tails, not per pattern,
        # which would count the trunk twice.
        chain = self.trunk + self.branch_tails["rod_el_farag_branch"]
        straight = sum(self.segment_metres(a, b, factor=1.0)
                       for a, b in zip(chain, chain[1:]))
        cu = [self.trunk[-1]] + self.branch_tails["cairo_university_branch"]
        straight += sum(self.segment_metres(a, b, factor=1.0)
                        for a, b in zip(cu, cu[1:]))
        self.straight_km = straight / 1000.0
        self.route_factor = self.total_km / self.straight_km

    def segment_metres(self, a, b, factor=None):
        sa, sb = self.stations[a], self.stations[b]
        d = haversine(sa["lat"], sa["lon"], sb["lat"], sb["lon"])
        return d * (self.route_factor if factor is None else factor)

    def patterns(self):
        """pattern suffix -> westbound stop order (Adly Mansour first)."""
        out = {}
        for suffix, key in BRANCHES:
            out[suffix] = self.trunk + self.branch_tails[key]
        return out


def load_coordinates(path):
    coords = {}
    with path.open(encoding="utf-8-sig", newline="") as fh:
        for row in csv.DictReader(fh):
            sid = row["station_id"].strip()
            if not sid:
                continue
            try:
                lat, lon = float(row["lat"]), float(row["lon"])
            except (TypeError, ValueError):
                raise SystemExit("station {} has no usable coordinates".format(sid))
            if not (29.0 <= lat <= 31.0 and 30.0 <= lon <= 32.0):
                raise SystemExit(
                    "station {} at {},{} is outside Greater Cairo"
                    .format(sid, lat, lon))
            coords[sid] = (lat, lon,
                           row.get("source", "").strip(),
                           row.get("source_ref", "").strip())
    if not coords:
        raise SystemExit("coordinates.csv is empty")
    return coords


# --------------------------------------------------------------------------
# Feed tables
# --------------------------------------------------------------------------

def build_tables(line, service, lo, hi):
    tables = {}

    tables["agency.txt"] = ([
        "agency_id", "agency_name", "agency_url", "agency_timezone", "agency_lang",
    ], [{
        "agency_id": AGENCY_ID,
        # Mirrors the TfC metro feed so api/modes.py resolves this to the metro
        # mode with no change: it keys off agency_id, never route_type.
        "agency_name": "Cairo Metro",
        "agency_url": "https://cairometro.gov.eg/",
        "agency_timezone": "Africa/Cairo",
        "agency_lang": "en",
    }])

    termini = {
        "RF": line.stations[line.branch_tails["rod_el_farag_branch"][-1]]["name"],
        "CU": line.stations[line.branch_tails["cairo_university_branch"][-1]]["name"],
    }
    origin = line.stations[line.trunk[0]]["name"]

    tables["routes.txt"] = ([
        "route_id", "agency_id", "route_short_name", "route_long_name",
        "route_desc", "route_type",
    ], [{
        "route_id": ROUTE_ID,
        "agency_id": AGENCY_ID,
        "route_short_name": line.short_name,
        "route_long_name": "Metro Line 3",
        "route_desc": "{} - {} / {}".format(origin, termini["RF"], termini["CU"]),
        "route_type": "1",
    }])

    stop_rows = []
    for sid in line.trunk + [s for _, k in BRANCHES for s in line.branch_tails[k]]:
        st = line.stations[sid]
        stop_rows.append({
            "stop_id": sid,
            "stop_name": st["name"],
            "stop_lat": "{:.6f}".format(st["lat"]),
            "stop_lon": "{:.6f}".format(st["lon"]),
        })
    tables["stops.txt"] = (["stop_id", "stop_name", "stop_lat", "stop_lon"],
                           stop_rows)

    cal_rows = []
    for sid, mask in sorted(service["calendar"].items()):
        row = {"service_id": sid, "start_date": fmt_date(lo), "end_date": fmt_date(hi)}
        for day, flag in zip(DAYS, mask):
            row[day] = flag
        cal_rows.append(row)
    tables["calendar.txt"] = (["service_id"] + list(DAYS) +
                              ["start_date", "end_date"], cal_rows)

    trip_rows, stop_time_rows, freq_rows, shape_rows = [], [], [], []
    speed_ms = float(service["runSpeedKmh"]) * 1000.0 / 3600.0
    dwell = int(service["dwellSeconds"])
    first = parse_hms(service["firstDeparture"])
    run_times = {}

    for suffix, _ in BRANCHES:
        west = line.patterns()[suffix]
        for direction, ids in (("W", west), ("E", list(reversed(west)))):
            shape_id = "T_L3_{}_{}_Shape".format(direction, suffix)
            for seq, sid in enumerate(ids, start=1):
                st = line.stations[sid]
                shape_rows.append({
                    "shape_id": shape_id,
                    "shape_pt_sequence": str(seq),
                    "shape_pt_lat": "{:.6f}".format(st["lat"]),
                    "shape_pt_lon": "{:.6f}".format(st["lon"]),
                })

            for service_id in sorted(service["calendar"]):
                trip_id = "T_L3_{}_{}_{}".format(direction, suffix, service_id)
                trip_rows.append({
                    "route_id": ROUTE_ID,
                    "service_id": service_id,
                    "trip_id": trip_id,
                    "trip_headsign": line.stations[ids[-1]]["name"],
                    "direction_id": "0" if direction == "W" else "1",
                    "shape_id": shape_id,
                })

                t = first
                for seq, sid in enumerate(ids, start=1):
                    arrival = t
                    departure = arrival + (0 if seq == len(ids) else dwell)
                    stop_time_rows.append({
                        "trip_id": trip_id,
                        "arrival_time": hms(arrival),
                        "departure_time": hms(departure),
                        "stop_id": sid,
                        "stop_sequence": str(seq),
                        "timepoint": "0",
                    })
                    if seq < len(ids):
                        metres = line.segment_metres(sid, ids[seq])
                        t = departure + round(metres / speed_ms)
                run_times[trip_id] = t - first

                for start, end, headway in service["headways"][service_id]:
                    freq_rows.append({
                        "trip_id": trip_id,
                        "start_time": start,
                        "end_time": end,
                        "headway_secs": str(int(headway)),
                    })

    tables["trips.txt"] = (["route_id", "service_id", "trip_id", "trip_headsign",
                            "direction_id", "shape_id"], trip_rows)
    tables["stop_times.txt"] = (["trip_id", "arrival_time", "departure_time",
                                 "stop_id", "stop_sequence", "timepoint"],
                                stop_time_rows)
    tables["frequencies.txt"] = (["trip_id", "start_time", "end_time",
                                  "headway_secs"], freq_rows)
    tables["shapes.txt"] = (["shape_id", "shape_pt_sequence", "shape_pt_lat",
                             "shape_pt_lon"], shape_rows)

    # translations.txt in the field_value form - the form the road feed uses,
    # and therefore the one proven against this OTP build.
    tr_rows = [{
        "table_name": "routes",
        "field_name": "route_long_name",
        "language": "ar",
        "field_value": "Metro Line 3",
        "translation": line.long_name_ar,
    }]
    for sid in line.stations:
        st = line.stations[sid]
        tr_rows.append({
            "table_name": "stops",
            "field_name": "stop_name",
            "language": "ar",
            "field_value": st["name"],
            "translation": st["name_ar"],
        })
    for terminus in sorted(set(termini.values()) | {origin}):
        tr_rows.append({
            "table_name": "trips",
            "field_name": "trip_headsign",
            "language": "ar",
            "field_value": terminus,
            "translation": next(s["name_ar"] for s in line.stations.values()
                                if s["name"] == terminus),
        })
    tables["translations.txt"] = (["table_name", "field_name", "language",
                                   "field_value", "translation"], tr_rows)

    tables["feed_info.txt"] = ([
        "feed_id", "feed_publisher_name", "feed_publisher_url", "feed_lang",
        "feed_start_date", "feed_end_date", "feed_version",
    ], [{
        # feed_id is an OTP extension, not standard GTFS. If this OTP build
        # ignores it the feed just gets an auto-numbered prefix instead.
        "feed_id": FEED_ID,
        "feed_publisher_name": "Egypt Transportation Planner",
        "feed_publisher_url": "https://github.com/WafikSleim/egypt-transportation-planner",
        "feed_lang": "en",
        "feed_start_date": fmt_date(lo),
        "feed_end_date": fmt_date(hi),
        "feed_version": "l3-{}".format(fmt_date(lo)),
    }])

    return tables, run_times


def check_run_times(line, service, run_times):
    """Refuse a timetable that a bad speed or a bad coordinate has skewed."""
    bands = service["runTimeBandsMinutes"]
    ok = True

    trunk_ids = line.trunk
    trunk_m = sum(line.segment_metres(a, b) for a, b in zip(trunk_ids, trunk_ids[1:]))
    speed_ms = float(service["runSpeedKmh"]) * 1000.0 / 3600.0
    trunk_min = (trunk_m / speed_ms + int(service["dwellSeconds"]) *
                 (len(trunk_ids) - 2)) / 60.0
    lo, hi = bands["trunk"]
    print("  {:<34} {:5.1f} min  (band {}-{})".format(
        "Adly Mansour - Kit Kat", trunk_min, lo, hi))
    if not lo <= trunk_min <= hi:
        print("  ERROR: trunk run time outside its band")
        ok = False

    lo, hi = bands["branch"]
    for trip_id, secs in sorted(run_times.items()):
        if not trip_id.startswith("T_L3_W_"):
            continue
        minutes = secs / 60.0
        print("  {:<34} {:5.1f} min  (band {}-{})".format(
            trip_id.rsplit("_", 2)[0], minutes, lo, hi))
        if not lo <= minutes <= hi:
            print("  ERROR: {} run time outside its band".format(trip_id))
            ok = False
    return ok


def check_metro_window(lo, hi):
    """Warn if the TfC metro feed's window does not cover ours.

    A mismatch shows up as "no M3 service on the date you asked for", which is
    the same silent walk-only failure the calendar fix exists to prevent.
    """
    if not METRO_FEED.is_file():
        return
    with zipfile.ZipFile(METRO_FEED) as zf:
        _, rows = read_table(zf, "feed_info.txt")
    if not rows:
        return
    start, end = rows[0].get("feed_start_date"), rows[0].get("feed_end_date")
    if not (start and end):
        return
    if parse_date(start) > lo or parse_date(end) < hi:
        print("  WARNING: {} covers {}-{}, which does not cover this feed's "
              "{}-{}.\n           Dates outside the overlap will find M1/M2 or "
              "M3 but not both.".format(METRO_FEED.name, start, end,
                                        fmt_date(lo), fmt_date(hi)))


# --------------------------------------------------------------------------
# Write
# --------------------------------------------------------------------------

def write_feed(out, tables):
    """Atomic, and byte-identical for identical input: no timestamps."""
    fd, tmp = tempfile.mkstemp(dir=str(out.parent), suffix=".zip")
    os.close(fd)
    try:
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
            for name in sorted(tables):
                fields, rows = tables[name]
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                zout.writestr(info, render_table(fields, rows))
        os.replace(tmp, out)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def build(out, lo, hi, dry_run):
    line_path = DATA / "line3.json"
    coord_path = DATA / "coordinates.csv"
    service_path = DATA / "service.json"
    missing = [p for p in (line_path, coord_path, service_path) if not p.is_file()]
    if missing:
        raise SystemExit("not found: " + ", ".join(str(p) for p in missing))

    line = Line(json.loads(line_path.read_text(encoding="utf-8")),
                load_coordinates(coord_path))
    service = json.loads(service_path.read_text(encoding="utf-8"))

    print("\n{}".format(out.name))
    print("-" * max(len(out.name), 62))
    print("  stations               : {}".format(len(line.stations)))
    print("  trunk / branches       : {} + {} + {}".format(
        len(line.trunk),
        len(line.branch_tails["rod_el_farag_branch"]),
        len(line.branch_tails["cairo_university_branch"])))
    print("  straight-line length   : {:.2f} km, scaled x{:.3f} to the "
          "published {:.1f} km".format(line.straight_km, line.route_factor,
                                       line.total_km))
    print("  timetable              : MODELLED - {} km/h, {} s dwell"
          .format(service["runSpeedKmh"], service["dwellSeconds"]))

    tables, run_times = build_tables(line, service, lo, hi)
    if not check_run_times(line, service, run_times):
        return False
    check_metro_window(lo, hi)

    counts = ", ".join("{} {}".format(len(rows), name.replace(".txt", ""))
                       for name, (_, rows) in sorted(tables.items()))
    print("  rows                   : {}".format(counts))

    if dry_run:
        print("  --dry-run: nothing written")
        return True

    out.parent.mkdir(parents=True, exist_ok=True)
    write_feed(out, tables)
    print("  written                : {}".format(out))
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Build the Cairo Metro Line 3 GTFS feed from "
                    "data/metro-l3/. The timetable is modelled, not published.")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT,
                    help="output feed (default {})".format(DEFAULT_OUT))
    ap.add_argument("--start", default=DEFAULT_START,
                    help="service start date, YYYYMMDD (default {})".format(DEFAULT_START))
    ap.add_argument("--end", default=DEFAULT_END,
                    help="service end date, YYYYMMDD (default {})".format(DEFAULT_END))
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would be built, write nothing")
    args = ap.parse_args(argv)

    lo, hi = parse_date(args.start), parse_date(args.end)
    if lo > hi:
        raise SystemExit("--start must not be after --end")
    if "gtfs" not in args.out.name.lower():
        raise SystemExit(
            "the output filename must contain 'gtfs' ({} does not): OTP only "
            "recognises a file as GTFS if the filename matches (?i)gtfs, and "
            "ignores it silently otherwise.".format(args.out.name))
    if not (lo <= dt.date.today() <= hi):
        print("WARNING: today ({}) is outside {} - {}; OTP will find no M3 "
              "service.".format(fmt_date(dt.date.today()), args.start, args.end))

    if not build(args.out, lo, hi, args.dry_run):
        return 1
    if not args.dry_run:
        print("\nDone. Delete graph.obj before rebuilding, or OTP loads the "
              "stale graph\nand none of this takes effect.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
