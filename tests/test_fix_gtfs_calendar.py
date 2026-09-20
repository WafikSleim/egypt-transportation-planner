"""Behaviour of scripts/fix_gtfs_calendar.py.

Two of these guard bugs that actually happened. The script once read its input
from the feed while copying untouched entries from the backup, so a second run
consumed its own output and refused to write. And the original plan for it was
to flatten every service to "runs daily", which silently quadruples metro
service because the metro's four services partition the year.

Feeds are built here rather than copied from OTP/, so the suite needs no data
files on disk.
"""

from __future__ import annotations

import csv
import datetime as dt
import importlib.util
import io
import zipfile
from pathlib import Path

import pytest

DAYS = ("monday", "tuesday", "wednesday", "thursday",
        "friday", "saturday", "sunday")

_spec = importlib.util.spec_from_file_location(
    "fix_gtfs_calendar",
    Path(__file__).resolve().parents[1] / "scripts" / "fix_gtfs_calendar.py",
)
fixcal = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fixcal)


# --------------------------------------------------------------------------
# Synthetic feeds
# --------------------------------------------------------------------------

def _csv(rows: list[dict]) -> str:
    buf = io.StringIO(newline="")
    w = csv.DictWriter(buf, fieldnames=list(rows[0].keys()), lineterminator="\n")
    w.writeheader()
    for r in rows:
        w.writerow(r)
    return buf.getvalue()


def _write_feed(path: Path, calendar_rows: list[dict], service_ids: list[str]):
    """Minimal but valid GTFS. service_id is the last column in calendar.txt,
    matching the real TfC feeds -- code assuming column order would break."""
    trips = [{"route_id": "r1", "service_id": s, "trip_id": f"t{i}"}
             for i, s in enumerate(service_ids)]
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("agency.txt", _csv([{
            "agency_id": "A", "agency_name": "Test",
            "agency_url": "http://x", "agency_timezone": "Africa/Cairo"}]))
        z.writestr("routes.txt", _csv([{
            "route_id": "r1", "agency_id": "A", "route_short_name": "1",
            "route_long_name": "Test", "route_type": "3"}]))
        z.writestr("trips.txt", _csv(trips))
        z.writestr("calendar.txt", _csv(calendar_rows))
        z.writestr("feed_info.txt", _csv([{
            "feed_publisher_name": "Test", "feed_publisher_url": "http://x",
            "feed_lang": "en", "feed_start_date": "20250101",
            "feed_end_date": "20251231", "feed_version": "1.0"}]))


def _cal_row(service_id, dow: str, start, end):
    row = {d: dow[i] for i, d in enumerate(DAYS)}
    row.update(start_date=start, end_date=end, service_id=service_id)
    return row


@pytest.fixture
def road_feed(tmp_path) -> Path:
    """Year-round, and the two services deliberately overlap -- different
    routes use each, so that overlap is correct and must survive."""
    p = tmp_path / "gtfs-road.zip"
    _write_feed(p, [
        _cal_row("Ground_Daily", "1111111", "20250101", "20251231"),
        _cal_row("Ground_Weekdays", "1111001", "20250101", "20251231"),
    ], ["Ground_Daily", "Ground_Weekdays"])
    return p


@pytest.fixture
def metro_feed(tmp_path) -> Path:
    """The real metro shape: std/vac split by day of week, winter/summer split
    by date. Exactly one is ever active."""
    p = tmp_path / "gtfs-metro.zip"
    _write_feed(p, [
        _cal_row("winter_vac", "0000110", "20241028", "20250425"),
        _cal_row("summer_vac", "0000110", "20250426", "20251027"),
        _cal_row("winter_std", "1111001", "20241028", "20250425"),
        _cal_row("summer_std", "1111001", "20250426", "20251027"),
    ], ["winter_vac", "summer_vac", "winter_std", "summer_std"])
    return p


# --------------------------------------------------------------------------
# Reading the result back
# --------------------------------------------------------------------------

def _read(path: Path, name: str) -> list[dict]:
    with zipfile.ZipFile(path) as z:
        try:
            raw = z.read(name)
        except KeyError:
            return []
    return list(csv.DictReader(io.StringIO(raw.decode("utf-8-sig"))))


def _active_days(path: Path) -> dict[dt.date, set[str]]:
    """Rebuild the active-service set straight from the written files, rather
    than trusting the script's own model of what it did."""
    removed: dict[str, set[dt.date]] = {}
    for r in _read(path, "calendar_dates.txt"):
        if r["exception_type"] == "2":
            removed.setdefault(r["service_id"], set()).add(
                dt.datetime.strptime(r["date"], "%Y%m%d").date())
    out: dict[dt.date, set[str]] = {}
    for r in _read(path, "calendar.txt"):
        sid = r["service_id"]
        d = dt.datetime.strptime(r["start_date"], "%Y%m%d").date()
        end = dt.datetime.strptime(r["end_date"], "%Y%m%d").date()
        while d <= end:
            if r[DAYS[d.weekday()]] == "1" and d not in removed.get(sid, ()):
                out.setdefault(d, set()).add(sid)
            d += dt.timedelta(days=1)
    return out


# --------------------------------------------------------------------------
# Tests
# --------------------------------------------------------------------------

def test_window_is_shifted_and_backup_kept(road_feed):
    assert fixcal.main([str(road_feed)]) == 0

    cal = _read(road_feed, "calendar.txt")
    assert {r["start_date"] for r in cal} == {"20260101"}
    assert {r["end_date"] for r in cal} == {"20271231"}
    assert road_feed.with_suffix(".zip.bak").exists()


def test_weekly_pattern_survives(road_feed):
    """Ground_Weekdays is Mon-Thu + Sun: the Egyptian working week, with
    Friday and Saturday off. Flattening that loses real information."""
    fixcal.main([str(road_feed)])

    row = next(r for r in _read(road_feed, "calendar.txt")
               if r["service_id"] == "Ground_Weekdays")
    assert "".join(row[d] for d in DAYS) == "1111001"


def test_existing_overlap_is_preserved(road_feed):
    """These two services do share days, and should keep doing so."""
    fixcal.main([str(road_feed)])
    active = _active_days(road_feed)
    assert any(s == {"Ground_Daily", "Ground_Weekdays"} for s in active.values())


def test_metro_seasons_never_collide(metro_feed):
    """The heart of it. winter_std and summer_std are both Mon-Thu+Sun and
    never collide only because their date ranges partition the year. Put them
    on one shared window and every weekday gets both."""
    assert fixcal.main([str(metro_feed)]) == 0

    active = _active_days(metro_feed)
    worst = max(len(s) for s in active.values())
    assert worst == 1, f"{worst} services active on one day; service is doubled"


def test_every_day_in_the_window_has_service(metro_feed):
    fixcal.main([str(metro_feed)])
    active = _active_days(metro_feed)
    span = [dt.date(2026, 1, 1) + dt.timedelta(days=i) for i in range(730)]
    assert [d for d in span if not active.get(d)] == []


def test_daily_flag_is_refused_on_seasonal_feed(metro_feed):
    """--daily is what the original plan called for. It must fail loudly
    rather than quietly quadrupling metro service."""
    before = metro_feed.read_bytes()
    assert fixcal.main([str(metro_feed), "--daily"]) == 1
    assert metro_feed.read_bytes() == before, "refused, but wrote anyway"


def test_daily_flag_is_allowed_where_it_changes_nothing(road_feed):
    """Both road services are already year-round, so --daily breaks no
    partition. The guard must not be a blanket ban."""
    assert fixcal.main([str(road_feed), "--daily"]) == 0


def test_rerunning_is_idempotent(metro_feed):
    """The bug that shipped: input was read from the feed but untouched
    entries copied from the backup, so a second run read its own output, saw
    a 730-day window, concluded every service was year-round, and refused."""
    assert fixcal.main([str(metro_feed)]) == 0
    first = _active_days(metro_feed)

    assert fixcal.main([str(metro_feed)]) == 0, "second run refused to write"
    assert _active_days(metro_feed) == first

    version = _read(metro_feed, "feed_info.txt")[0]["feed_version"]
    assert version.count("-cal") == 1, f"feed_version compounded: {version}"


def test_rerunning_with_a_new_window_starts_from_the_original(metro_feed):
    """The realistic reason to run it twice: the calendars expire again."""
    fixcal.main([str(metro_feed)])
    assert fixcal.main([str(metro_feed), "--start", "20280101",
                        "--end", "20291231"]) == 0

    cal = _read(metro_feed, "calendar.txt")
    assert {r["start_date"] for r in cal} == {"20280101"}
    active = _active_days(metro_feed)
    assert max(len(s) for s in active.values()) == 1, "seasons lost on re-run"


def test_dry_run_writes_nothing(road_feed):
    before = road_feed.read_bytes()
    assert fixcal.main([str(road_feed), "--dry-run"]) == 0
    assert road_feed.read_bytes() == before
    assert not road_feed.with_suffix(".zip.bak").exists()


def test_service_id_column_order_is_preserved(road_feed):
    """service_id is the last column in the real TfC feeds."""
    fixcal.main([str(road_feed)])
    with zipfile.ZipFile(road_feed) as z:
        header = z.read("calendar.txt").decode("utf-8-sig").splitlines()[0]
    assert header.endswith("service_id")
