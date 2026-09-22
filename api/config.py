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
