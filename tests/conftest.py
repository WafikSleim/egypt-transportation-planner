"""Test fixtures: a stub OTP that answers GraphQL without Docker.

The suite runs with nothing else on the machine — no OTP container, no graph,
no network. That matters because the checks here guard behaviour that was only
ever verified by hand against a live server, and a suite you can only run with
a 529 MB graph loaded is a suite nobody runs.

Requests go through the real `api.otp.query`, driven by an injected
`httpx.MockTransport`. Stubbing `query` itself would skip the header handling,
status handling and GraphQL error unwrapping — the parts most likely to break.
"""

from __future__ import annotations

import json

import httpx
import pytest

from api import otp

# --------------------------------------------------------------------------
# Canned OTP payloads, shaped exactly as OTP 2.11 returns them.
# Times are epoch milliseconds, as OTP reports them.
# --------------------------------------------------------------------------

# 2026-09-21 08:00 Africa/Cairo == 1790053200000
T0 = 1790053200000
MINUTE = 60_000


def _place(name, lat, lon, stop_id=None):
    return {"name": name, "lat": lat, "lon": lon,
            "stop": {"gtfsId": stop_id} if stop_id else None}


def _walk_leg(start, minutes, frm, to, distance=500):
    return {
        "mode": "WALK", "startTime": start, "endTime": start + minutes * MINUTE,
        "duration": minutes * 60, "distance": distance, "transitLeg": False,
        "headsign": None, "from": frm, "to": to,
        "intermediatePlaces": [], "route": None, "trip": None,
    }


def _transit_leg(start, minutes, frm, to, mode, route, distance=10000, stops=4):
    return {
        "mode": mode, "startTime": start, "endTime": start + minutes * MINUTE,
        "duration": minutes * 60, "distance": distance, "transitLeg": True,
        "headsign": route.get("_headsign"), "from": frm, "to": to,
        "intermediatePlaces": [{"name": f"stop {i}"} for i in range(stops)],
        "route": {k: v for k, v in route.items() if not k.startswith("_")},
        "trip": {"gtfsId": "2:t1", "tripHeadsign": route.get("_headsign")},
    }


METRO_ROUTE = {
    "gtfsId": "1:M1", "shortName": "M1", "longName": "Helwan - New El-Marg",
    "mode": "SUBWAY", "agency": {"gtfsId": "1:NAT", "name": "Cairo Metro"},
    "_headsign": "New El-Marg",
}

# Metro line 3 is not in the TfC feed. We build it ourselves, in a feed whose id
# is pinned to "metro-l3", and its provenance has to differ because of that.
L3_ROUTE = {
    "gtfsId": "metro-l3:L3", "shortName": "M3", "longName": "Metro Line 3",
    "mode": "SUBWAY", "agency": {"gtfsId": "metro-l3:NAT", "name": "Cairo Metro"},
    "_headsign": "Cairo University",
}

# The trap: shortName is literally "Microbus" on hundreds of routes, because
# real microbuses in Cairo carry no number.
MICROBUS_ROUTE = {
    "gtfsId": "2:r511", "shortName": "Microbus", "longName": "Microbus",
    "mode": "BUS",
    "agency": {"gtfsId": "2:P_O_14",
               "name": "Paratransit 14 Seater Microbus (Orange Licenseplates)"},
    "_headsign": None,
}

CTA_ROUTE = {
    "gtfsId": "2:r100", "shortName": "381", "longName": "Ramsis - Maadi",
    "mode": "BUS",
    "agency": {"gtfsId": "2:CTA", "name": "Cairo Transport Authority"},
    "_headsign": "Maadi",
}

HELWAN = _place("Ain Helwan", 29.8490, 31.3340, "1:s1")
SHOHADAA = _place("Al-Shohadaa", 30.0620, 31.2460, "1:s2")
SHUBRA = _place("Shubra El-Kheima", 30.1220, 31.2450, "1:s3")
MONEEB = _place("Moneeb", 29.9810, 31.2100, "2:1145")
FESTIVAL = _place("Cairo Festival City", 30.0280, 31.4070, "2:2001")
ORIGIN = _place("Origin", 29.8480, 31.3330)
DEST = _place("Destination", 30.1230, 31.2460)


def metro_itinerary():
    return {
        "startTime": T0, "endTime": T0 + 101 * MINUTE, "duration": 101 * 60,
        "walkDistance": 1976.0,
        "legs": [
            _walk_leg(T0, 24, ORIGIN, HELWAN, 1834),
            _transit_leg(T0 + 24 * MINUTE, 46, HELWAN, SHOHADAA, "SUBWAY",
                         METRO_ROUTE, 25502),
            _walk_leg(T0 + 70 * MINUTE, 4, SHOHADAA, SHOHADAA, 30),
            _transit_leg(T0 + 74 * MINUTE, 13, SHOHADAA, SHUBRA, "SUBWAY",
                         METRO_ROUTE, 7109),
            _walk_leg(T0 + 87 * MINUTE, 3, SHUBRA, DEST, 110),
        ],
    }


def metro_l3_itinerary():
    """One M3 leg, straight through - line 3 needs no interchange to be itself."""
    return {
        "startTime": T0, "endTime": T0 + 47 * MINUTE, "duration": 47 * 60,
        "walkDistance": 140.0,
        "legs": [
            _walk_leg(T0, 2, ORIGIN, HELWAN, 110),
            _transit_leg(T0 + 2 * MINUTE, 44, HELWAN, SHUBRA, "SUBWAY",
                         L3_ROUTE, 21363),
            _walk_leg(T0 + 46 * MINUTE, 1, SHUBRA, DEST, 30),
        ],
    }


def microbus_itinerary():
    return {
        "startTime": T0, "endTime": T0 + 60 * MINUTE, "duration": 60 * 60,
        "walkDistance": 704.0,
        "legs": [
            _walk_leg(T0, 9, ORIGIN, MONEEB, 704),
            _transit_leg(T0 + 9 * MINUTE, 30, MONEEB, FESTIVAL, "BUS",
                         MICROBUS_ROUTE, 21283),
        ],
    }


def cta_itinerary():
    """A route whose operator does number its lines -- the other branch."""
    return {
        "startTime": T0, "endTime": T0 + 40 * MINUTE, "duration": 40 * 60,
        "walkDistance": 300.0,
        "legs": [
            _transit_leg(T0, 40, MONEEB, FESTIVAL, "BUS", CTA_ROUTE, 12000),
        ],
    }


def walk_only_itinerary():
    """What OTP returns for a trip in a city with no transit data at all. The
    OSM extract covers the whole country; the feeds do not."""
    return {
        "startTime": T0, "endTime": T0 + 45 * MINUTE, "duration": 45 * 60,
        "walkDistance": 3400.0,
        "legs": [_walk_leg(T0, 45, ORIGIN, DEST, 3400)],
    }


HEALTH_DATA = {
    "feeds": [
        {"feedId": "1", "agencies": [{"gtfsId": "1:NAT", "name": "Cairo Metro"}]},
        {"feedId": "2", "agencies": [
            {"gtfsId": "2:CTA", "name": "Cairo Transport Authority"}]},
    ],
    "routes": [{"gtfsId": f"2:r{i}"} for i in range(1012)],
    "stops": [{"gtfsId": f"2:s{i}"} for i in range(3105)],
}


# --------------------------------------------------------------------------
# The stub transport
# --------------------------------------------------------------------------

class FakeOTP:
    """Answers GraphQL by looking at which query was sent.

    `requests` records every call so tests can assert on what was *not* asked
    for -- fare fields, for instance.
    """

    def __init__(self):
        self.itineraries: list[dict] = []
        self.stops: list[dict] = []
        self.stop_routes: dict[str, list[dict]] = {}
        # Localised names by stop id, as OTP's stops(ids:) resolver returns
        # them. OTP will not supply these inside a plan response.
        self.stop_names: dict[str, str] = {}
        self.health = HEALTH_DATA
        self.status_code = 200
        self.graphql_errors: list[dict] | None = None
        self.fail_with: Exception | None = None
        self.requests: list[dict] = []

    def handler(self, request: httpx.Request) -> httpx.Response:
        if self.fail_with:
            raise self.fail_with
        body = json.loads(request.content)
        self.requests.append({
            "query": body["query"],
            "variables": body.get("variables") or {},
            "lang": request.headers.get("Accept-Language"),
        })
        if self.status_code != 200:
            return httpx.Response(self.status_code, json={})
        if self.graphql_errors is not None:
            return httpx.Response(200, json={"errors": self.graphql_errors})

        q = body["query"]
        if "plan(" in q:
            data = {"plan": {"itineraries": self.itineraries}}
        elif "StopRoutes" in q:
            ids = body["variables"].get("ids") or []
            data = {"stops": [
                {"gtfsId": i, "routes": self.stop_routes.get(i, [])}
                for i in ids
            ]}
        elif "StopNames" in q:
            ids = body["variables"].get("ids") or []
            data = {"stops": [
                {"gtfsId": i, "name": self.stop_names[i]}
                for i in ids if i in self.stop_names
            ]}
        elif "stops(name:" in q or "Stops(" in q:
            data = {"stops": self.stops}
        else:
            data = self.health
        return httpx.Response(200, json={"data": data})

    @property
    def transport(self) -> httpx.MockTransport:
        return httpx.MockTransport(self.handler)


@pytest.fixture
def fake_otp(monkeypatch):
    stub = FakeOTP()
    monkeypatch.setattr(otp, "TRANSPORT", stub.transport)
    return stub


@pytest.fixture
def client():
    """ASGI client -- no network, no uvicorn."""
    from api.main import app
    return httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    )
