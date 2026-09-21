"""Thin async client for OTP's GTFS GraphQL endpoint.

Everything that knows GraphQL lives here. The rest of the API deals in plain
dicts, so replacing or upgrading OTP does not ripple outwards.
"""

from __future__ import annotations

from typing import Any

import httpx

from . import config


# Injection point for tests. Left None in production, so the client behaves
# exactly as it otherwise would; a test sets it to an httpx.MockTransport and
# gets the real query() path -- headers, status handling, GraphQL error
# unwrapping -- instead of a stubbed-out query() that skips all of it.
TRANSPORT: httpx.BaseTransport | None = None


class OTPUnavailable(RuntimeError):
    """OTP could not be reached, or did not answer in time."""


class OTPError(RuntimeError):
    """OTP answered, but with GraphQL errors."""


# Asking only for what we return. Fare fields are deliberately absent: the
# feeds carry 2018 prices that are worthless today, and a field that is never
# fetched cannot leak into a response by accident.
PLAN_QUERY = """
query Plan($from: InputCoordinates!, $to: InputCoordinates!, $date: String!,
           $time: String!, $arriveBy: Boolean!, $num: Int!) {
  plan(from: $from, to: $to, date: $date, time: $time, arriveBy: $arriveBy,
       numItineraries: $num,
       transportModes: [{mode: TRANSIT}, {mode: WALK}]) {
    itineraries {
      startTime
      endTime
      duration
      walkDistance
      legs {
        mode
        startTime
        endTime
        duration
        distance
        transitLeg
        headsign
        from { name lat lon stop { gtfsId } }
        to   { name lat lon stop { gtfsId } }
        intermediatePlaces { name }
        route {
          gtfsId
          shortName
          longName
          mode
          agency { gtfsId name }
        }
        trip { gtfsId tripHeadsign }
      }
    }
  }
}
"""

# Deliberately without route lists. OTP's stops(name:) has no limit argument
# and matches on prefix, so a broad query like "Al" returns 757 stops; asking
# for each one's routes as well turns a 68 kB response into 2 MB. Stop search
# is a typeahead, so that cost lands on every keystroke.
STOPS_QUERY = """
query Stops($name: String!) {
  stops(name: $name) {
    gtfsId
    name
    lat
    lon
  }
}
"""

# Localised stop names by id.
#
# Needed because OTP applies translations.txt inconsistently: with
# Accept-Language: ar the top-level stop(id:) resolver returns the Arabic name,
# but the same stop reached through plan { legs { from { stop { name } } } }
# comes back in Latin -- verified in a single request against 2.11.0-SNAPSHOT
# on 2026-09-21. Itineraries would otherwise be English-only, which is fatal
# for an Arabic-first app. This resolver does translate, so names are fetched
# separately and merged in.
STOP_NAMES_QUERY = """
query StopNames($ids: [String]) {
  stops(ids: $ids) {
    gtfsId
    name
  }
}
"""

# Second hop: routes for the handful of stops actually being returned.
STOP_ROUTES_QUERY = """
query StopRoutes($ids: [String]) {
  stops(ids: $ids) {
    gtfsId
    routes { gtfsId agency { gtfsId } }
  }
}
"""

HEALTH_QUERY = """
query Health {
  feeds { feedId agencies { gtfsId name } }
  routes { gtfsId }
  stops { gtfsId }
}
"""


async def query(
    graphql: str,
    variables: dict[str, Any] | None = None,
    lang: str = "en",
) -> dict[str, Any]:
    """Run one GraphQL query against OTP and return its `data`.

    `lang` becomes Accept-Language, which is how OTP applies the feed's
    translations.txt -- the road feed ships Arabic names for every stop, so
    this is the whole of our Arabic support. Nothing is translated here.
    """
    payload = {"query": graphql, "variables": variables or {}}
    headers = {"Content-Type": "application/json", "Accept-Language": lang}
    try:
        async with httpx.AsyncClient(
            timeout=config.OTP_TIMEOUT, transport=TRANSPORT
        ) as client:
            response = await client.post(
                config.OTP_URL, json=payload, headers=headers
            )
    except httpx.TimeoutException as exc:
        raise OTPUnavailable(
            f"OTP did not respond within {config.OTP_TIMEOUT:g}s. It may still "
            "be loading the graph."
        ) from exc
    except httpx.HTTPError as exc:
        raise OTPUnavailable(f"Could not reach OTP at {config.OTP_URL}") from exc

    if response.status_code != 200:
        raise OTPUnavailable(
            f"OTP returned HTTP {response.status_code} from {config.OTP_URL}"
        )

    body = response.json()
    if body.get("errors"):
        messages = "; ".join(
            e.get("message", "unknown") for e in body["errors"]
        )
        raise OTPError(messages)
    return body.get("data") or {}
