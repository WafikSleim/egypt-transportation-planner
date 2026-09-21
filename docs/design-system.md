# Design system

The single source for both builds — the Flutter client and the web dashboard.
Take tokens from here, not by reading colours out of the prototypes.

**Prototypes:** [`design/app-prototype.html`](../design/app-prototype.html) ·
[`design/dashboard-prototype.html`](../design/dashboard-prototype.html)

---

## The one idea

**Colour carries meaning, so the interface stays quiet.**

Every mode colour in this product is a real Egyptian licence-plate colour. The
road feed names its own operators that way — *Paratransit 14 Seater Microbus
(**Orange** Licenseplates)*, *8 Seater (**Blue** Licenseplates)*, *Cooperative
29 Seater (**Grey** Licenseplates)* — because that is how people identify a
vehicle at the kerb, before reading anything written on it.

That is a colour system users already know. It only works if nothing else
competes for attention, which is why the base palette is near-neutral and there
is exactly one accent.

---

## Colour

### Neutrals — warm, not grey

Warm-biased because a pure grey reads as unconsidered, and because the accent is
cool; the tension is deliberate.

| Token | Light | Dark |
| --- | --- | --- |
| `bg` | `#FBFAF7` | `#121210` |
| `surface` | `#FFFFFF` | `#1C1B18` |
| `raise` | `#F4F2EC` | `#24231F` |
| `ink` | `#14130F` | `#F3F1EA` |
| `ink-2` | `#67635A` | `#A6A197` |
| `ink-3` | `#96918A` | `#7C776D` |
| `line` | `#E6E2D9` | `#2E2D28` |

Dashboard uses the same ramp with `bg` `#F6F5F1` / `#121210` — slightly cooler,
because a working surface sits on screen for hours.

### Accent — one, and it stays out of the way

| Token | Light | Dark |
| --- | --- | --- |
| `accent` | `#4A3FA0` | `#9A90F0` |
| `accent-soft` | `#EFEDFB` | `#232041` |
| `accent-ink` | `#FFFFFF` | `#15122B` |

Deep indigo, chosen **because it is not a plate colour and not a metro line
colour**. It cannot be mistaken for a mode. Never use it to mean a mode.

### Modes — the plate colours

| Mode | `agency_id` | Light | Dark | Why |
| --- | --- | --- | --- | --- |
| Microbus | `P_O_14` | `#D2620B` | `#FF9F51` | Orange plates |
| Tomnaya | `P_B_8` | `#1C6FB8` | `#5FAAE8` | Blue plates |
| Cooperative | `COOP` | `#6E6A61` | `#A8A399` | Grey plates |
| CTA bus / minibus | `CTA`, `CTA_M` | `#146A60` | `#3FB5A5` | Distinct from all plates |
| Walk | — | `#96918A` | `#7C776D` | Neutral, dashed |

**Mode comes from `agency_id`, never `route_type`.** The road feed types all
1,011 routes as `3`, microbuses included, because GTFS has no code for a
14-seater. See [`api/modes.py`](../api/modes.py).

### Metro — a different form, not just a different colour

| Line | Light | Dark |
| --- | --- | --- |
| M1 | `#1F6FB2` | `#5BA3DE` |
| M2 | `#C1272D` | `#F0605F` |
| M3 | `#0E8A4F` | `#3FBE7C` |

M1's blue is close to tomnaya's blue. They are never confused because **metro
uses a circular line badge and everything else uses a pill chip** — form
separates the register, colour separates the member within it. Keep that
distinction; do not render a metro line as a pill.

> **Unverified:** these line hues are placeholders. Confirm against the
> operator's own wayfinding before the Flutter build. M3 does not exist in the
> feed yet.

### Semantic — separate from the accent

| | Light | Dark |
| --- | --- | --- |
| ok | `#1E7A4C` | `#4FC98A` |
| warn | `#9A6E06` | `#E0B341` |
| critical | `#B3261E` | `#F27168` |

Never carried by colour alone. Pair with a severity stripe, a pill, or a label.

---

## Type

| Role | Face | Notes |
| --- | --- | --- |
| Display | **Readex Pro** 400–600 | Designed for Arabic/Latin harmony and low-literacy legibility — the right reasoning for a civic tool with a broad audience |
| UI / body | **IBM Plex Sans Arabic** 400–700 | Workhorse. Excellent Arabic, coherent Latin |
| Data / code | **IBM Plex Mono** 400–600 | Times, counts, IDs, log terms |

Anything in columns gets `font-variant-numeric: tabular-nums`. Headings get
`text-wrap: balance`. Uppercase labels get `.1em`–`.14em` tracking.

**Western digits everywhere** — `8:15`, `102 دقيقة`. What Egyptian phones and
road signs use.

---

## Language

**Egyptian colloquial, written in Arabic first.** English is the port, never the
source. MSA reads as officious in a tool about catching a microbus.

| Context | Copy |
| --- | --- |
| Search | `رايح فين النهاردة؟` |
| Board a microbus | `اركب ميكروباص لحد المنيب` |
| Alight | `انزل هنا` |
| No coverage | `لسه مامعندناش بيانات عن المنطقة دي` |
| No service | `مفيش مواصلات دلوقتي` |
| Start tracking | `تابع الرحلة` |
| Post-trip | `وصلت بالسلامة؟` |
| Unsure | `مش متأكدين` |

RTL throughout. Use logical properties (`padding-inline-start`,
`margin-inline-end`) — never `left`/`right`.

**Dashboard keeps English for technical terms** — `graph.obj`, walk-only rate,
`feed_end_date`, OTP. A figure on screen should be traceable to a command in a
runbook, and translating breaks that link.

---

## Rules that are not style

These come from the data, not from taste. Breaking one makes the product lie.

1. **No route-number badge when `has_line_number` is false.** Hundreds of
   microbus routes are named literally "Microbus". Show origin → destination
   from `route.display_name`.
2. **Never show a fare.** 2018 data. The API does not even request the fields.
3. **A walk-only itinerary is not a result.** When every itinerary has
   `is_walk_only`, show the API's `note` instead of the list.
4. **Never imply real-time vehicle position.** No such source exists in Egypt.
   Estimates derive from the user's own GPS against a recorded route — say so.
5. **Attribution verbatim, in English, on any screen showing data.** Licence
   requirement. Fetch from `/attribution`.
6. **One unsolicited prompt per trip.** Enforce in code, not judgement.
7. **Both themes are designed.** Dark is not inverted light — it has its own
   surface elevations and desaturated mode colours, or the plate hues vibrate.

---

## Components

**Mode chip** — pill, `13%` tint of the mode colour as background, mode colour
as text, 6px square glyph. **Metro badge** — 25px circle, solid line colour,
white mono label.

**Card** — `surface`, 1px `line`, 17px radius. Reserve borders and shadow for
things that are genuinely separate objects; not every block is a card.

**Honesty panel** — the pattern carrying rules 3–4. Neutral by default, `warn`
tint when stating a limitation. Always says what we do not know, in plain words.

**Severity stripe** — 4px inline-start bar on a tile whose metric is out of
range. Makes state readable as form, so it survives greyscale and colour-blind
viewing.
