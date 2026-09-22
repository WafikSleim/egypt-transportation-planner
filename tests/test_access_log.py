"""The access log must not become a record of where people travelled.

These tests deliberately do not call `install_access_log_redaction()`. They
import `api.main` and then log through the real `uvicorn.access` logger, so
deleting the install call from `api/main.py` fails them -- which is the actual
regression to guard against. A test that installed the filter itself would stay
green while the deployed app leaked.

The record is built and formatted with uvicorn's own code (`AccessFormatter`,
`get_path_with_query_string`), so the string under assertion is the one uvicorn
would really write, and a filter that broke the five-argument shape the
formatter unpacks would raise here rather than in production.
"""

from __future__ import annotations

import logging

import httpx
import pytest
from uvicorn.config import LOGGING_CONFIG
from uvicorn.logging import AccessFormatter
from uvicorn.protocols.utils import get_path_with_query_string

# Importing the app is what installs the filter. Not a stray import.
from api.main import app

from .conftest import microbus_itinerary

# Real Cairo coordinates: Tahrir to Shubra El-Kheima.
FROM = "30.0444,31.2357"
TO = "30.1220,31.2450"


class _Capture(logging.Handler):
    def __init__(self):
        super().__init__()
        self.lines: list[str] = []
        # uvicorn's own access format, so the assertions are about the line a
        # deployment actually writes. Colours off: they would wrap the status
        # code in escapes and make a substring check meaningless.
        self.setFormatter(
            AccessFormatter(
                fmt=LOGGING_CONFIG["formatters"]["access"]["fmt"],
                use_colors=False,
            )
        )

    def emit(self, record: logging.LogRecord) -> None:
        self.lines.append(self.format(record))


@pytest.fixture
def access_log():
    """Capture what `uvicorn.access` emits, with the app's filter in place.

    The handler goes on the same logger the filter is attached to: logger
    filters run in `Logger.handle` before `callHandlers`, so the handler only
    ever sees an already-redacted record.
    """
    logger = logging.getLogger("uvicorn.access")
    handler = _Capture()
    previous_level, previous_propagate = logger.level, logger.propagate
    logger.setLevel(logging.INFO)
    logger.propagate = False
    logger.addHandler(handler)
    try:
        yield handler.lines
    finally:
        logger.removeHandler(handler)
        logger.setLevel(previous_level)
        logger.propagate = previous_propagate


class _Recorder:
    """An ASGI client over the real app that keeps each request's scope.

    The scope is what uvicorn builds its access line from, so capturing it here
    means the line under test comes from a request the app actually served
    rather than from a URL typed into the test.

    This wraps the app rather than the conftest `client` fixture because
    `httpx` invokes the app through `type(app).__call__`; an instance-level
    patch would never be reached.
    """

    def __init__(self):
        self.scopes: list[dict] = []
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=self._app),
            base_url="http://test",
        )

    async def _app(self, scope, receive, send):
        if scope["type"] == "http":
            self.scopes.append(scope)
        await app(scope, receive, send)

    async def get(self, url: str) -> httpx.Response:
        # Not `async with`: that would close the client on the way out, and a
        # test making two requests would fail on the second for a reason that
        # has nothing to do with logging. The fixture closes it instead.
        return await self.client.get(url)


@pytest.fixture
async def recorder():
    recorder = _Recorder()
    try:
        yield recorder
    finally:
        await recorder.client.aclose()


def _log_as_uvicorn(scope: dict, status: int = 200) -> None:
    """Emit the access line exactly as uvicorn's HTTP protocol does."""
    logging.getLogger("uvicorn.access").info(
        '%s - "%s %s HTTP/%s" %d',
        "127.0.0.1:52104",
        scope["method"],
        get_path_with_query_string(scope),
        scope.get("http_version", "1.1"),
        status,
    )


async def test_plan_coordinates_never_reach_the_access_log(
    fake_otp, recorder, access_log
):
    fake_otp.itineraries = [microbus_itinerary()]
    response = await recorder.get(
        f"/plan?from={FROM}&to={TO}&date=2026-09-22&time=08:00&lang=ar"
    )
    assert response.status_code == 200

    scope = recorder.scopes[0]
    # The leak is real before redaction: uvicorn's own helper puts both
    # coordinate pairs into the string it hands the logger. If this ever stops
    # holding, the rest of the test is checking nothing.
    unredacted = get_path_with_query_string(scope)
    assert FROM in unredacted and TO in unredacted

    _log_as_uvicorn(scope)
    line = access_log[0]

    assert FROM not in line
    assert TO not in line
    # No fragment of a coordinate either -- a partial redaction that left
    # "30.0444" behind would still be a location.
    for fragment in ("30.0444", "31.2357", "30.1220", "31.2450"):
        assert fragment not in line
    # ...and the timestamp that would turn two points into a journey.
    assert "2026-09-22" not in line and "08:00" not in line

    # What the log is for is still there: which endpoint, and how it went.
    assert "/plan" in line
    assert "GET" in line
    assert "200" in line
    # Proof the filter ran, rather than the coordinates happening to be absent.
    assert "?<redacted>" in line


async def test_stop_search_queries_are_redacted_too(
    fake_otp, recorder, access_log
):
    """Not a `/plan`-only rule. A stop search is a weaker signal than a trip,
    but it is still a place someone typed."""
    fake_otp.stops = []
    await recorder.get("/stops?q=%D8%A7%D9%84%D9%85%D9%86%D9%8A%D8%A8&lang=ar")

    _log_as_uvicorn(recorder.scopes[0])
    line = access_log[0]

    assert "q=" not in line
    assert "/stops?<redacted>" in line


async def test_a_request_with_no_query_is_not_marked_redacted(
    fake_otp, recorder, access_log
):
    """The marker has to mean something. A path with nothing to hide is logged
    plainly, so `?<redacted>` in a line always indicates a query string that
    was actually dropped."""
    await recorder.get("/health")

    _log_as_uvicorn(recorder.scopes[0])
    line = access_log[0]

    assert "/health" in line
    assert "<redacted>" not in line


async def test_rejected_coordinates_are_redacted_as_well(
    fake_otp, recorder, access_log
):
    """A rejected request is logged too, and its coordinates are in the request
    target whether or not the app accepted them. Paris: outside Egypt, so
    `_coords` raises before any routing happens."""
    response = await recorder.get(f"/plan?from=48.8566,2.3522&to={TO}")
    assert response.status_code == 422

    _log_as_uvicorn(recorder.scopes[0], status=response.status_code)
    line = access_log[0]

    assert "48.8566" not in line and "2.3522" not in line
    assert "/plan?<redacted>" in line
    assert "422" in line
