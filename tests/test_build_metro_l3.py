"""Behaviour of scripts/build_metro_l3.py.

Three of these guard traps specific to this data. The station "sequence" in
line3.json runs 1-34 across both branches, so using it as a stop order silently
produces a line that runs Kit Kat -> Sudan -> ... -> Rod El Farag -> El Tawfikia
-> Cairo University as one impossible trip. "Rod El Farag" collides with a Line 2
station 2.4 km away in the TfC feed. And translations.txt matches on the field
value rather than a record id, so two stations sharing a name would make their
Arabic ambiguous.

Unlike test_fix_gtfs_calendar.py these run against the real tracked source data
in data/metro-l3/ - it is small, checked in, and the point of most of these
assertions is that the real 34 stations come out right. The feed is written to
tmp_path, never to OTP/.
"""

from __future__ import annotations

import csv
import importlib.util
import io
import json
import zipfile
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]

_spec = importlib.util.spec_from_file_location(
    "build_metro_l3", REPO / "scripts" / "build_metro_l3.py")
build = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(build)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

def _read(path: Path, name: str) -> list[dict]:
    with zipfile.ZipFile(path) as z:
        try:
            raw = z.read(name)
        except KeyError:
            return []
    return list(csv.DictReader(io.StringIO(raw.decode("utf-8-sig"))))


def _secs(text: str) -> int:
    h, m, s = (int(x) for x in text.split(":"))
    return h * 3600 + m * 60 + s


def _pattern(path: Path, trip_id: str) -> list[str]:
    rows = [r for r in _read(path, "stop_times.txt") if r["trip_id"] == trip_id]
    rows.sort(key=lambda r: int(r["stop_sequence"]))
    return [r["stop_id"] for r in rows]


@pytest.fixture
def feed(tmp_path):
    out = tmp_path / "gtfs-metro-l3.zip"
    assert build.main(["--out", str(out)]) == 0
    return out


@pytest.fixture
def source(tmp_path, monkeypatch):
    """A writable copy of data/metro-l3/, for the refusal cases."""
    dst = tmp_path / "metro-l3"
    dst.mkdir()
    for name in ("line3.json", "coordinates.csv", "service.json"):
        (dst / name).write_bytes((build.DATA / name).read_bytes())
    monkeypatch.setattr(build, "DATA", dst)
    return dst


# --------------------------------------------------------------------------
# Shape of the feed
# --------------------------------------------------------------------------

def test_all_34_stations_become_stops(feed):
    stops = _read(feed, "stops.txt")
    assert len(stops) == 34
    assert len({s["stop_id"] for s in stops}) == 34
    # Every stop inside the API's Greater Cairo coverage box.
    for s in stops:
        assert 29.745 <= float(s["stop_lat"]) <= 30.352
        assert 30.846 <= float(s["stop_lon"]) <= 31.775


def test_one_route_typed_as_subway(feed):
    routes = _read(feed, "routes.txt")
    assert len(routes) == 1
    assert routes[0]["route_short_name"] == "M3"
    # route_type 1, not 3: the metro is rail and OTP must report it as SUBWAY.
    assert routes[0]["route_type"] == "1"
    # Mode comes from agency_id, and this one has to match the TfC metro feed
    # or api/modes.py will not resolve it to the metro mode.
    assert routes[0]["agency_id"] == "NAT"
    assert _read(feed, "agency.txt")[0]["agency_id"] == "NAT"


def test_four_patterns_two_services_eight_trips(feed):
    trips = _read(feed, "trips.txt")
    assert len(trips) == 8
    assert {t["trip_id"] for t in trips} == {
        "T_L3_{}_{}_{}".format(d, b, s)
        for d in ("W", "E") for b in ("RF", "CU") for s in ("l3_std", "l3_vac")}
    assert {t["route_id"] for t in trips} == {"L3"}


# --------------------------------------------------------------------------
# The branch split - the trap in this data
# --------------------------------------------------------------------------

def test_branches_split_at_kit_kat_and_do_not_run_through(feed):
    rf = _pattern(feed, "T_L3_W_RF_l3_std")
    cu = _pattern(feed, "T_L3_W_CU_l3_std")

    assert rf[0] == cu[0] == "adly_mansour"
    assert rf[-1] == "rod_el_farag"
    assert cu[-1] == "cairo_university"

    # Kit Kat is the last station the two patterns share, and the trunk before
    # it is identical.
    shared = [a for a, b in zip(rf, cu) if a == b]
    assert shared[-1] == "kit_kat"
    assert len(shared) == 23

    # Neither branch may contain the other's stations: sequence 23 (Kit Kat) is
    # followed by both 24 (Sudan) and 30 (El Tawfikia) in line3.json, and
    # treating that as one chain would splice both tails into one trip.
    assert not set(rf) & {"el_tawfikia", "wadi_el_nil", "cairo_university"}
    assert not set(cu) & {"sudan", "imbaba", "rod_el_farag"}
    assert len(rf) == 29 and len(cu) == 28


def test_eastbound_is_the_reverse_of_westbound(feed):
    for branch in ("RF", "CU"):
        west = _pattern(feed, "T_L3_W_{}_l3_std".format(branch))
        east = _pattern(feed, "T_L3_E_{}_l3_std".format(branch))
        assert east == list(reversed(west))
    directions = {t["trip_id"]: t["direction_id"] for t in _read(feed, "trips.txt")}
    assert directions["T_L3_W_RF_l3_std"] == "0"
    assert directions["T_L3_E_RF_l3_std"] == "1"


def test_headsign_is_the_terminus(feed):
    signs = {t["trip_id"]: t["trip_headsign"] for t in _read(feed, "trips.txt")}
    assert signs["T_L3_W_RF_l3_std"] == "Rod El Farag Axis"
    assert signs["T_L3_W_CU_l3_std"] == "Cairo University"
    assert signs["T_L3_E_CU_l3_std"] == "Adly Mansour"


# --------------------------------------------------------------------------
# Naming
# --------------------------------------------------------------------------

def test_line_3_terminus_is_named_rod_el_farag_axis(feed):
    """The TfC metro feed already has a "Rod El Farag" - the Line 2 station,
    2.4 km from this one. Two stops with one name in different parts of the city
    make place search useless."""
    names = {s["stop_id"]: s["stop_name"] for s in _read(feed, "stops.txt")}
    assert names["rod_el_farag"] == "Rod El Farag Axis"


def test_no_two_stations_share_a_name(feed):
    """translations.txt here matches on the field value, not a record id."""
    names = [s["stop_name"] for s in _read(feed, "stops.txt")]
    assert len(set(names)) == len(names)


def test_every_stop_has_an_arabic_name(feed):
    tr = _read(feed, "translations.txt")
    stop_tr = {r["field_value"]: r["translation"] for r in tr
               if r["table_name"] == "stops"}
    names = {s["stop_name"] for s in _read(feed, "stops.txt")}
    assert names <= set(stop_tr)
    assert stop_tr["Kit Kat"] == "الكيت كات"
    assert all(r["language"] == "ar" for r in tr)


# --------------------------------------------------------------------------
# Timetable
# --------------------------------------------------------------------------

def test_stop_times_increase_and_dwell_everywhere(feed):
    rows = _read(feed, "stop_times.txt")
    by_trip: dict[str, list[dict]] = {}
    for r in rows:
        by_trip.setdefault(r["trip_id"], []).append(r)
    assert len(by_trip) == 8

    for trip_id, trip_rows in by_trip.items():
        trip_rows.sort(key=lambda r: int(r["stop_sequence"]))
        assert [int(r["stop_sequence"]) for r in trip_rows] == \
            list(range(1, len(trip_rows) + 1))
        previous = -1
        for i, r in enumerate(trip_rows):
            arrival, departure = _secs(r["arrival_time"]), _secs(r["departure_time"])
            assert arrival > previous, trip_id
            # 30 s dwell at every stop but the last, matching the TfC feed.
            assert departure - arrival == (0 if i == len(trip_rows) - 1 else 30)
            previous = departure


def test_run_times_land_in_their_bands(feed):
    """The distance calibration and the 40.4 km/h speed are both modelled; this
    is the assertion that a wrong one cannot pass silently."""
    for trip_id, lo, hi in (("T_L3_W_RF_l3_std", 55, 75),
                            ("T_L3_W_CU_l3_std", 55, 75)):
        rows = [r for r in _read(feed, "stop_times.txt") if r["trip_id"] == trip_id]
        rows.sort(key=lambda r: int(r["stop_sequence"]))
        minutes = (_secs(rows[-1]["arrival_time"]) -
                   _secs(rows[0]["arrival_time"])) / 60
        assert lo <= minutes <= hi, "{} runs {:.1f} min".format(trip_id, minutes)


def test_builder_refuses_a_run_time_outside_its_band(source, tmp_path):
    service = json.loads((source / "service.json").read_text(encoding="utf-8"))
    service["runSpeedKmh"] = 12.0
    (source / "service.json").write_text(json.dumps(service), encoding="utf-8")
    out = tmp_path / "gtfs-bad.zip"
    assert build.main(["--out", str(out)]) == 1
    assert not out.exists()


def test_every_trip_has_frequencies_and_no_exact_times(feed):
    freqs = _read(feed, "frequencies.txt")
    trips = {t["trip_id"] for t in _read(feed, "trips.txt")}
    assert {f["trip_id"] for f in freqs} == trips
    assert all("exact_times" not in f for f in freqs)
    for f in freqs:
        assert _secs(f["end_time"]) > _secs(f["start_time"])
        assert int(f["headway_secs"]) > 0
    # Per-branch headways: trains alternate at Kit Kat, so a 480 s branch
    # headway is 240 s on the trunk. Nothing may be quicker than the trunk's
    # real minimum.
    assert min(int(f["headway_secs"]) for f in freqs) >= 300


def test_frequency_windows_do_not_overlap_within_a_trip(feed):
    by_trip: dict[str, list[tuple[int, int]]] = {}
    for f in _read(feed, "frequencies.txt"):
        by_trip.setdefault(f["trip_id"], []).append(
            (_secs(f["start_time"]), _secs(f["end_time"])))
    for trip_id, windows in by_trip.items():
        windows.sort()
        for (_, end), (start, _) in zip(windows, windows[1:]):
            assert start >= end, trip_id


# --------------------------------------------------------------------------
# Calendar, shapes, feed_info
# --------------------------------------------------------------------------

def test_services_exist_and_never_share_a_day(feed):
    cal = {r["service_id"]: r for r in _read(feed, "calendar.txt")}
    assert set(cal) == {"l3_std", "l3_vac"}
    assert {t["service_id"] for t in _read(feed, "trips.txt")} <= set(cal)
    days = ("monday", "tuesday", "wednesday", "thursday",
            "friday", "saturday", "sunday")
    # std is Mon-Thu + Sun and vac is Fri/Sat, matching the TfC feed's split.
    # No day may activate both, or a frequency-based line doubles its service.
    for day in days:
        assert not (cal["l3_std"][day] == "1" and cal["l3_vac"][day] == "1"), day
    assert cal["l3_std"]["sunday"] == "1" and cal["l3_std"]["friday"] == "0"
    assert cal["l3_vac"]["friday"] == "1" and cal["l3_vac"]["saturday"] == "1"
    # No calendar_dates.txt: nothing here is seasonal, so there is nothing to
    # remove. fix_gtfs_calendar.py must never be run on this feed.
    assert _read(feed, "calendar_dates.txt") == []


def test_calendar_window_is_the_requested_one(tmp_path):
    out = tmp_path / "gtfs-window.zip"
    assert build.main(["--out", str(out),
                       "--start", "20260401", "--end", "20261231"]) == 0
    for row in _read(out, "calendar.txt"):
        assert row["start_date"] == "20260401"
        assert row["end_date"] == "20261231"
    info = _read(out, "feed_info.txt")[0]
    assert info["feed_start_date"] == "20260401"


def test_every_trip_has_a_shape_matching_its_stops(feed):
    shapes: dict[str, list[tuple[int, float, float]]] = {}
    for r in _read(feed, "shapes.txt"):
        shapes.setdefault(r["shape_id"], []).append(
            (int(r["shape_pt_sequence"]), float(r["shape_pt_lat"]),
             float(r["shape_pt_lon"])))
    stops = {s["stop_id"]: (float(s["stop_lat"]), float(s["stop_lon"]))
             for s in _read(feed, "stops.txt")}

    for trip in _read(feed, "trips.txt"):
        shape = sorted(shapes[trip["shape_id"]])
        assert [n for n, _, _ in shape] == list(range(1, len(shape) + 1))
        pattern = _pattern(feed, trip["trip_id"])
        assert len(shape) == len(pattern)
        for (_, lat, lon), stop_id in zip(shape, pattern):
            assert (lat, lon) == stops[stop_id]


def test_feed_info_declares_the_feed_id(feed):
    info = _read(feed, "feed_info.txt")
    assert len(info) == 1
    assert info[0]["feed_id"] == "metro-l3"
    assert info[0]["feed_lang"] == "en"


def test_no_fares_are_published(feed):
    """2018-era fares are worthless and a wrong fare is worse than none."""
    with zipfile.ZipFile(feed) as z:
        names = set(z.namelist())
    assert not {"fare_attributes.txt", "fare_rules.txt"} & names


# --------------------------------------------------------------------------
# Running it twice, and refusing bad input
# --------------------------------------------------------------------------

def test_rebuilding_is_byte_identical(tmp_path):
    first = tmp_path / "gtfs-a.zip"
    second = tmp_path / "gtfs-b.zip"
    assert build.main(["--out", str(first)]) == 0
    assert build.main(["--out", str(second)]) == 0
    assert first.read_bytes() == second.read_bytes()


def test_dry_run_writes_nothing(tmp_path):
    out = tmp_path / "gtfs-dry.zip"
    assert build.main(["--out", str(out), "--dry-run"]) == 0
    assert not out.exists()


def test_dry_run_leaves_an_existing_feed_untouched(feed):
    before = feed.read_bytes()
    assert build.main(["--out", str(feed), "--dry-run"]) == 0
    assert feed.read_bytes() == before


def test_output_filename_must_contain_gtfs(tmp_path):
    """OTP only recognises a feed if the filename matches (?i)gtfs. This is the
    fault that made every search return walk-only for days."""
    with pytest.raises(SystemExit):
        build.main(["--out", str(tmp_path / "metro-l3.zip")])


def test_refuses_a_station_with_no_coordinates(source, tmp_path):
    lines = (source / "coordinates.csv").read_text(encoding="utf-8").splitlines()
    kept = [ln for ln in lines if not ln.startswith("kit_kat,")]
    assert len(kept) == len(lines) - 1
    (source / "coordinates.csv").write_text("\n".join(kept), encoding="utf-8")
    with pytest.raises(SystemExit) as excinfo:
        build.main(["--out", str(tmp_path / "gtfs-x.zip")])
    assert "kit_kat" in str(excinfo.value)


def test_refuses_a_coordinate_outside_greater_cairo(source, tmp_path):
    text = (source / "coordinates.csv").read_text(encoding="utf-8")
    text = text.replace("kit_kat,30.066790000,31.212990000",
                        "kit_kat,31.200000000,29.900000000")  # Alexandria
    (source / "coordinates.csv").write_text(text, encoding="utf-8")
    with pytest.raises(SystemExit) as excinfo:
        build.main(["--out", str(tmp_path / "gtfs-x.zip")])
    assert "Greater Cairo" in str(excinfo.value)


def test_refuses_a_duplicate_station_name(source, tmp_path):
    line = json.loads((source / "line3.json").read_text(encoding="utf-8"))
    for station in line["stations"]:
        if station["id"] == "sudan":
            station["name"] = "Imbaba"
    (source / "line3.json").write_text(json.dumps(line), encoding="utf-8")
    with pytest.raises(SystemExit) as excinfo:
        build.main(["--out", str(tmp_path / "gtfs-x.zip")])
    assert "Imbaba" in str(excinfo.value)


def test_refuses_when_json_and_coordinates_disagree(source, tmp_path):
    with (source / "coordinates.csv").open("a", encoding="utf-8") as fh:
        fh.write("sheraton,30.100000,31.400000,wikidata,Q138496371\n")
    with pytest.raises(SystemExit) as excinfo:
        build.main(["--out", str(tmp_path / "gtfs-x.zip")])
    assert "sheraton" in str(excinfo.value)
