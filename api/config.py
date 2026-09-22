"""Configuration, read from the environment.

Nothing here is secret, so there is no .env loading and no secret store. The
only setting that genuinely varies is where OTP lives.
"""

from __future__ import annotations

import os

# OTP's GTFS GraphQL endpoint. Not pinned to localhost: in deployment OTP sits
# on another host, and the container is easy to restart on a different port.
OTP_URL = os.environ.get("OTP_URL", "http://localhost:8080/otp/gtfs/v1")

# Seconds. A cold OTP takes a while to answer its first query while the graph
# finishes loading, so this is deliberately not aggressive.
OTP_TIMEOUT = float(os.environ.get("OTP_TIMEOUT", "30"))

# Everything in the feeds is Cairo. When a caller gives a date and time with no
# zone, this is what it means, and it is what departure times are rendered in.
TIMEZONE = os.environ.get("TIMEZONE", "Africa/Cairo")

# CORS. The Flutter client is served from somewhere else, so it needs this.
# Comma-separated, or "*" while developing.
CORS_ORIGINS = [
    o.strip() for o in os.environ.get("CORS_ORIGINS", "*").split(",") if o.strip()
]

# Which feed a route came out of decides its provenance, because the graph is
# not all one dataset. The key is OTP's feed id, which is the part of a gtfsId
# before the colon: "1:M1" is the TfC metro feed, "metro-l3:L3" is ours.
#
# A route with no entry here falls back to the first value, because the TfC
# feeds are the ones whose ids OTP assigns by load order and can therefore
# change; ours is pinned in feed_info.txt precisely so it cannot.
#
# `metro-l3` is not TfC data and must not be labelled as such: its topology is
# the operator's published station list and its coordinates are Wikidata (CC0).
# Its confidence is "reported" rather than "confirmed" because its timetable is
# modelled — see data/metro-l3/README.md.
FEED_PROVENANCE = {
    None: ("tfc", "confirmed"),
    "metro-l3": ("project", "reported"),
}

# Required verbatim by the CC BY-NC 4.0 terms the TfC data is published under.
# Served rather than hardcoded in the client: the client is meant to be thin,
# and an attribution that lives in one place cannot drift out of date.
TFC_ATTRIBUTION = (
    "This data was created by Transport for Cairo 'TfC' with DigitalMatatus "
    "and Takween for Integrated Community Development, under the Digital Cairo "
    "Project supported by ExpoLive 2020."
)

# The transit feeds' own extent: Greater Cairo, and nothing else in Egypt.
# Read by `main.COVERAGE`, by every /places query, and by the OSM ingest in
# scripts/build_places.py, which clips the extract to exactly this box. One
# copy, because a place index covering more ground than the transit data would
# offer people destinations no itinerary can reach.
COVERAGE = {"min_lat": 29.745, "max_lat": 30.352,
            "min_lon": 30.846, "max_lon": 31.775}

# --------------------------------------------------------------------------
# The place index
# --------------------------------------------------------------------------
#
# Named for the one dataset it is allowed to hold, not `DATABASE_URL`. OSM is
# ODbL and the TfC transit data is CC BY-NC; merged into a single derived
# database the two licences contradict each other, so they are kept as
# separate databases. A connection string called `DATABASE_URL` invites
# someone to point this at the transit data and join; one called
# `PLACES_DATABASE_URL` does not.
#
# The default matches docker-compose.yml, which stands this up locally. The
# credentials in it are a local development convenience and must be replaced
# before anything is exposed.
#
# `127.0.0.1`, not `localhost`. docker-compose binds the port to the IPv4
# loopback, while `localhost` resolves to `::1` first on Windows and on many
# Linux distributions — so every connection pays the IPv6 attempt's timeout
# before falling back. Measured here as a five-second first query against a
# database that answers in three milliseconds once connected.
PLACES_DATABASE_URL = os.environ.get(
    "PLACES_DATABASE_URL",
    "postgresql://masar:masar@127.0.0.1:5432/masar_places",
)

# Seconds to wait for the connection. Place search is a typeahead: a slow
# answer is a wrong answer, and failing fast lets the client fall back to stop
# search, which needs no database at all.
PLACES_TIMEOUT = float(os.environ.get("PLACES_TIMEOUT", "5"))

# ODbL's attribution requirement. Deliberately a second attribution object
# rather than an addition to the TfC text: the two datasets are under
# different licences and the UI has to be able to credit whichever one a given
# screen is showing. See docs/design-system.md rule 4.
OSM_ATTRIBUTION = "© OpenStreetMap contributors"
