#!/usr/bin/env python3
"""Rewrite a GTFS feed's service calendar onto a current date range.

The TfC feeds ship expired calendars: the road feed runs 20250101-20251231 and
the metro feed 20241028-20251027. OTP honours calendar.txt literally, finds no
service running on today's date, and silently returns walk-only itineraries
rather than reporting an error. Shifting the calendar forward is what makes
transit appear.

What this deliberately does NOT do is flatten every service to "runs daily".
That looks like a harmless simplification and is not one. The metro feed's four
services partition the year:

    winter_std  Mon-Thu,Sun   Oct 28 - Apr 25
    summer_std  Mon-Thu,Sun   Apr 26 - Oct 27
    winter_vac  Fri,Sat       Oct 28 - Apr 25
    summer_vac  Fri,Sat       Apr 26 - Oct 27

The std/vac pair is split by day of week, the winter/summer pair by date.
Exactly one is ever active on a given day. Put them all on one shared window and
every weekday gets both winter_std and summer_std - 8 trips where there should
be 4 - and since the metro is frequency-based, that shows up as roughly halved
headways. Plausible-looking, and wrong.

So each service keeps its day-of-week pattern and its seasonal window. The
season is re-expressed as a recurring month/day range over the new date range,
with out-of-season days removed via calendar_dates.txt. A service that already
ran year-round (both road services) needs no exceptions at all.

The rewrite is then verified rather than assumed: for every pair of service_ids,
whether they ever share a day must be the same before and after. That is the
invariant that catches the doubling described above. Note that it permits
overlap where overlap already existed - the road feed's Ground_Daily and
Ground_Weekdays do overlap, and that is correct, since different routes use each.

Usage:
    python fix_gtfs_calendar.py ../OTP/road.zip ../OTP/metro.zip
    python fix_gtfs_calendar.py ../OTP/road.zip --dry-run
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import io
import os
import sys
import tempfile
import zipfile
from pathlib import Path

DAYS = ("monday", "tuesday", "wednesday", "thursday",
        "friday", "saturday", "sunday")

DEFAULT_START = "20260101"
DEFAULT_END = "20271231"


# --------------------------------------------------------------------------
# GTFS I/O helpers
# --------------------------------------------------------------------------

def parse_date(s):
    return dt.datetime.strptime(s.strip(), "%Y%m%d").date()


def fmt_date(d):
    return d.strftime("%Y%m%d")


def read_table(zf, name):
    """Return (fieldnames, rows). ([], []) if the file is not in the feed."""
    try:
        raw = zf.read(name)
    except KeyError:
        return [], []
    # utf-8-sig strips a BOM if present; we never write one back.
    reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
    return list(reader.fieldnames or []), list(reader)


def render_table(fieldnames, rows):
    buf = io.StringIO(newline="")
    writer = csv.DictWriter(buf, fieldnames=fieldnames,
                            lineterminator="\n", extrasaction="ignore")
    writer.writeheader()
    for row in rows:
        writer.writerow(row)
    return buf.getvalue().encode("utf-8")


def daterange(lo, hi):
    d = lo
    step = dt.timedelta(days=1)
    while d <= hi:
        yield d
        d += step


# --------------------------------------------------------------------------
# Service model
# --------------------------------------------------------------------------

class Service:
    """One service_id: a day-of-week mask plus a seasonal month/day window."""

    def __init__(self, service_id, dow, start, end, row=None):
        self.id = service_id
        self.dow = dow                      # 7 bools, Monday first
        self.start = start
        self.end = end
        self.row = row or {}
        span = (end - start).days + 1
        # 365 days or more means the window is not seasonal, it is the whole
        # year, so there is nothing to preserve and no exceptions to emit.
        self.year_round = span >= 365
        self.season_start = (start.month, start.day)
        self.season_end = (end.month, end.day)

    def in_season(self, d):
        if self.year_round:
            return True
        md = (d.month, d.day)
        if self.season_start <= self.season_end:
            return self.season_start <= md <= self.season_end
        # Window wraps the new year, e.g. Oct 28 -> Apr 25.
        return md >= self.season_start or md <= self.season_end

    def original_dates(self, exceptions):
        out = {d for d in daterange(self.start, self.end) if self.dow[d.weekday()]}
        for date, kind in exceptions.get(self.id, ()):
            if kind == 1:
                out.add(date)
            elif kind == 2:
                out.discard(date)
        return out

    def projected_dates(self, lo, hi):
        return {d for d in daterange(lo, hi)
                if self.dow[d.weekday()] and self.in_season(d)}


def load_services(cal_rows, cal_date_rows, trip_service_ids):
    """Build Service objects from calendar.txt, synthesising any that exist
    only in calendar_dates.txt (legal GTFS, and how some feeds express
    irregular service)."""
    services = {}
    for row in cal_rows:
        sid = row["service_id"].strip()
        services[sid] = Service(
            sid,
            tuple(row[d].strip() == "1" for d in DAYS),
            parse_date(row["start_date"]),
            parse_date(row["end_date"]),
            row,
        )

    added = {}
    for row in cal_date_rows:
        sid = row["service_id"].strip()
        if int(row["exception_type"]) == 1:
            added.setdefault(sid, []).append(parse_date(row["date"]))

    for sid in sorted(trip_service_ids - set(services)):
        dates = sorted(added.get(sid, []))
        if not dates:
            raise SystemExit(
                "  ERROR: service_id {!r} is referenced by trips.txt but "
                "defined in neither calendar.txt nor calendar_dates.txt. The "
                "feed is internally inconsistent; fix it before "
                "rewriting.".format(sid))
        # Infer a weekly pattern from the days it actually ran.
        weekdays = {d.weekday() for d in dates}
        services[sid] = Service(
            sid,
            tuple(i in weekdays for i in range(7)),
            dates[0], dates[-1],
        )
        print("  note: {!r} had no calendar.txt row; inferred a {}-day-a-week "
              "pattern from calendar_dates.txt".format(sid, len(weekdays)))
    return services


def coincidence(date_sets):
    """For every pair of services, do they ever share a day? This is the
    structure the rewrite has to preserve."""
    ids = sorted(date_sets)
    return {(a, b): bool(date_sets[a] & date_sets[b])
            for i, a in enumerate(ids) for b in ids[i + 1:]}


# --------------------------------------------------------------------------
# The rewrite
# --------------------------------------------------------------------------

def fix_feed(path, lo, hi, daily, force, dry_run):
    print("\n{}".format(path.name))
    print("-" * max(len(path.name), 62))

    with zipfile.ZipFile(path) as zf:
        names = set(zf.namelist())
        if "calendar.txt" not in names and "calendar_dates.txt" not in names:
            print("  ERROR: feed has neither calendar.txt nor calendar_dates.txt")
            return False
        # A feed whose .txt files are nested in a folder will not load into OTP.
        if "routes.txt" not in names:
            nested = sorted(n for n in names if n.endswith("routes.txt"))
            if nested:
                print("  ERROR: GTFS files are nested inside a folder ({}). "
                      "They must sit at the root of the zip.".format(nested[0]))
            else:
                print("  ERROR: no routes.txt in this zip; is it really a GTFS feed?")
            return False

        cal_fields, cal_rows = read_table(zf, "calendar.txt")
        cd_fields, cd_rows = read_table(zf, "calendar_dates.txt")
        _, trip_rows = read_table(zf, "trips.txt")
        info_fields, info_rows = read_table(zf, "feed_info.txt")

    trip_sids = {r["service_id"].strip() for r in trip_rows}
    exceptions = {}
    for row in cd_rows:
        exceptions.setdefault(row["service_id"].strip(), []).append(
            (parse_date(row["date"]), int(row["exception_type"])))

    services = load_services(cal_rows, cd_rows, trip_sids)

    # Report the current state before touching anything.
    originals = {s.id: s.original_dates(exceptions) for s in services.values()}
    spans = [(min(v), max(v)) for v in originals.values() if v]
    today = dt.date.today()
    if spans:
        covers = any(a <= today <= b for a, b in spans)
        print("  current window         : {} - {}".format(
            fmt_date(min(a for a, _ in spans)), fmt_date(max(b for _, b in spans))))
        print("  covers today ({})  : {}".format(
            fmt_date(today),
            "yes" if covers else "NO - this is why OTP returns walk-only"))
    print("  services               : {} ({} used by {} trips)".format(
        len(services), len(trip_sids), len(trip_rows)))

    unused = set(services) - trip_sids
    if unused:
        print("  note: {} service_id(s) not used by any trip: {}".format(
            len(unused), ", ".join(sorted(unused))))

    if daily:
        for s in services.values():
            s.dow = (True,) * 7
            s.year_round = True
        print("  --daily: every service forced to run seven days a week")

    # Project each service onto the new range.
    projected = {s.id: s.projected_dates(lo, hi) for s in services.values()}

    empty = [sid for sid, d in projected.items() if sid in trip_sids and not d]
    if empty:
        print("  ERROR: {} would have no active days in {} - {}".format(
            ", ".join(sorted(empty)), fmt_date(lo), fmt_date(hi)))
        return False

    # The check that matters: pairwise overlap must be unchanged.
    before, after = coincidence(originals), coincidence(projected)
    broken = [pair for pair in before if before[pair] != after[pair]]
    if broken:
        print("  ERROR: the rewrite would change which services share days:")
        for a, b in broken:
            print("    {} / {}: {}, {}".format(
                a, b,
                "overlapped" if before[(a, b)] else "never overlapped",
                "now overlap" if after[(a, b)] else "now never overlap"))
        if not force:
            print("  Refusing to write. This doubles or drops service on the "
                  "affected days.\n  Re-run with --force only if you know the "
                  "overlap change is what you want.")
            return False
        print("  --force given; writing anyway")

    # Build calendar.txt, preserving the feed's own column order.
    out_fields = cal_fields or (list(DAYS) + ["start_date", "end_date", "service_id"])
    new_cal = []
    for sid in sorted(services):
        svc = services[sid]
        row = dict(svc.row)
        row["service_id"] = sid
        for i, day in enumerate(DAYS):
            row[day] = "1" if svc.dow[i] else "0"
        row["start_date"], row["end_date"] = fmt_date(lo), fmt_date(hi)
        new_cal.append(row)

    # Build calendar_dates.txt: remove the out-of-season days that the plain
    # day-of-week mask would otherwise let through.
    new_cd = []
    for sid in sorted(services):
        svc = services[sid]
        if svc.year_round:
            continue
        for d in daterange(lo, hi):
            if svc.dow[d.weekday()] and not svc.in_season(d):
                new_cd.append({"service_id": sid, "date": fmt_date(d),
                               "exception_type": "2"})

    seasonal = sorted(s.id for s in services.values() if not s.year_round)
    if seasonal:
        print("  seasonal services      : {}".format(", ".join(seasonal)))
        print("  calendar_dates.txt     : {} out-of-season removals".format(len(new_cd)))
    else:
        print("  calendar_dates.txt     : not needed (no seasonal services)")

    active_days = len(set().union(*projected.values()))
    print("  new window             : {} - {} ({} days with service)".format(
        fmt_date(lo), fmt_date(hi), active_days))

    replacements = {
        "calendar.txt": render_table(out_fields, new_cal),
        "calendar_dates.txt": (
            render_table(["service_id", "date", "exception_type"], new_cd)
            if new_cd else None),
    }

    # feed_info.txt: keep it consistent with the calendar we just wrote.
    if info_rows:
        info = dict(info_rows[0])
        if "feed_start_date" in info:
            info["feed_start_date"] = fmt_date(lo)
        if "feed_end_date" in info:
            info["feed_end_date"] = fmt_date(hi)
        if "feed_version" in info:
            info["feed_version"] = "{}-cal{}".format(
                info["feed_version"], fmt_date(lo))
        replacements["feed_info.txt"] = render_table(info_fields, [info])

    if dry_run:
        print("  --dry-run: nothing written")
        return True

    backup = path.with_suffix(path.suffix + ".bak")
    if not backup.exists():
        backup.write_bytes(path.read_bytes())
        print("  backed up to           : {}".format(backup.name))

    # Write to a temp file in the same directory, then swap, so an interrupted
    # run cannot leave a half-written feed where the real one was. The backup
    # is the read source, so re-running is idempotent rather than compounding.
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), suffix=".zip")
    os.close(fd)
    try:
        with zipfile.ZipFile(backup) as zin, \
                zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                if item.filename in replacements:
                    continue
                zout.writestr(item, zin.read(item.filename))
            for name, data in replacements.items():
                if data is not None:
                    zout.writestr(name, data)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise

    print("  written                : {}".format(path.name))
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Shift a GTFS feed's calendar onto a current date range, "
                    "preserving each service's weekly and seasonal pattern.")
    ap.add_argument("feeds", nargs="+", type=Path,
                    help="GTFS .zip files to rewrite in place")
    ap.add_argument("--start", default=DEFAULT_START,
                    help="new start date, YYYYMMDD (default {})".format(DEFAULT_START))
    ap.add_argument("--end", default=DEFAULT_END,
                    help="new end date, YYYYMMDD (default {})".format(DEFAULT_END))
    ap.add_argument("--daily", action="store_true",
                    help="force every service to run seven days a week. Loses "
                         "the Friday/Saturday weekend distinction and will fail "
                         "the overlap check on seasonal feeds like the metro.")
    ap.add_argument("--force", action="store_true",
                    help="write even if the overlap check fails")
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would change, write nothing")
    args = ap.parse_args(argv)

    lo, hi = parse_date(args.start), parse_date(args.end)
    if lo > hi:
        raise SystemExit("--start must not be after --end")
    if not (lo <= dt.date.today() <= hi):
        print("WARNING: today ({}) is outside {} - {}; OTP will still find no "
              "service.\n".format(fmt_date(dt.date.today()), args.start, args.end))

    missing = [f for f in args.feeds if not f.is_file()]
    if missing:
        raise SystemExit("not found: " + ", ".join(str(f) for f in missing))

    results = [fix_feed(f, lo, hi, args.daily, args.force, args.dry_run)
               for f in args.feeds]

    if all(results) and not args.dry_run:
        print("\nDone. Delete graph.obj before rebuilding, or OTP loads the "
              "stale graph\nand none of this takes effect.")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
