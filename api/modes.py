"""Mapping GTFS operators onto modes a passenger in Cairo would recognise.

The road feed types every route as `route_type = 3` (bus), because GTFS has no
code for a 14-seater microbus. What actually distinguishes a microbus from a
CTA bus from a tomnaya is `agency_id`. So the operator, not the route type, is
what this maps on.

(The metro is a separate feed and does type itself correctly as `route_type = 1`
-> OTP mode SUBWAY. An earlier note in CLAUDE.md claimed every route including
the metro was type 3; that was checked on 2026-09-20 and is not the case.)

`vehicle` is the distinction a passenger actually makes at the kerb: what pulls
up, how many seats, whether it has a fixed stop. It is not the GTFS mode.
"""

from __future__ import annotations

from typing import NamedTuple


class Mode(NamedTuple):
    id: str            # stable key for the client to switch on
    en: str            # English label
    ar: str            # Arabic label
    seats: int | None  # nominal capacity, None where it varies
    has_line_number: bool  # whether a route number exists to show the user


# Keyed on agency_id as it appears in the feeds' agency.txt.
BY_AGENCY: dict[str, Mode] = {
    # --- paratransit: the network this project exists to cover ---
    "P_O_14": Mode("microbus", "Microbus", "ميكروباص", 14, False),
    "P_B_8": Mode("tomnaya", "Tomnaya", "تمنايا", 8, False),
    "COOP": Mode("coop_minibus", "Cooperative minibus", "ميني باص تعاوني", 29, False),
    "BOX": Mode("box", "Box", "بوكس", None, False),
    "PGT": Mode("peugeot", "Peugeot", "بيجو", 7, False),
    # --- scheduled bus operators ---
    "CTA": Mode("cta_bus", "CTA bus", "أتوبيس النقل العام", None, True),
    "CTA_M": Mode("cta_minibus", "CTA minibus", "ميني باص النقل العام", None, True),
    "LTRA_M": Mode("ltra_minibus", "Minibus", "ميني باص", None, True),
    "MM": Mode("mwasalat_misr", "Mwasalat Misr", "مواصلات مصر", None, True),
    "GRN": Mode("green_bus", "Green Bus", "الأتوبيس الأخضر", None, True),
    # --- rail ---
    "NAT": Mode("metro", "Cairo Metro", "مترو الأنفاق", None, True),
}

WALK = Mode("walk", "Walk", "سيرًا", None, False)

# Fallback when OTP reports a transit leg whose agency we do not recognise --
# a feed added later, most likely. Better a vague label than a crash.
UNKNOWN_TRANSIT = Mode("transit", "Transit", "مواصلات", None, True)


def resolve(agency_gtfs_id: str | None, otp_mode: str) -> Mode:
    """Pick a mode for a leg.

    `agency_gtfs_id` arrives feed-prefixed, e.g. "2:P_O_14"; the prefix is the
    feed, which we do not care about here.
    """
    if otp_mode == "WALK":
        return WALK
    if agency_gtfs_id:
        bare = agency_gtfs_id.split(":", 1)[-1]
        if bare in BY_AGENCY:
            return BY_AGENCY[bare]
    # Trust OTP's own mode as a last resort, so a correctly typed rail feed
    # added later still reads as rail rather than "transit".
    if otp_mode in ("SUBWAY", "RAIL", "TRAM"):
        return BY_AGENCY["NAT"]
    return UNKNOWN_TRANSIT
