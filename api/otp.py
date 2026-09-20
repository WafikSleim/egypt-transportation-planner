"""Thin async client for OTP's GTFS GraphQL endpoint.

Everything that knows GraphQL lives here. The rest of the API deals in plain
dicts, so replacing or upgrading OTP does not ripple outwards.
"""

from __future__ import annotations

from typing import Any

import httpx

from . import config


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

STOPS_QUERY = """
query Stops($name: String!) {
  stops(name: $name) {
    gtfsId
    name
    lat
    lon
    routes { gtfsId shortName longName agency { gtfsId name } }
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
        async with httpx.AsyncClient(timeout=config.OTP_TIMEOUT) as client:
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
