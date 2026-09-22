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
| M1 | `#00528F` | `#288FDC` |
| M2 | `#C23038` | `#EE636B` |
| M3 | `#00A88F` | `#1FC1A9` |

M1's blue is close to tomnaya's blue. They are never confused because **metro
uses a circular line badge and everything else uses a pill chip** — form
separates the register, colour separates the member within it. Keep that
distinction; do not render a metro line as a pill. The confirmed M3 is a teal
rather than the grass green it was guessed as, which puts it on the same hue as
the CTA bus colour — 171° against 173°. That pair now leans on the same form
rule, so it matters twice over.

**The light values are the operator's own.** They are the three swatches in the
legend of the official Cairo Metro network map, version `V2024.05.09`, published
by RATP Dev Mobility Cairo — the company that operates Line 3 — at
[mobilitycairo.com](https://www.mobilitycairo.com/en/travel-information/maps).
That legend labels its swatches `M1`, `M2`, `M3`, the same keys this table is
keyed by. The values were read out of the PDF's vector colour operators rather
than sampled off a screenshot, so they are exact. Checked 2026-09-22. The
Egyptian Company for Metro Management and Operation's own network map at
[cairometro.gov.eg/Maps](https://www.cairometro.gov.eg/Maps) independently
agrees on which line is which colour.

**The dark values are derived, not the operator's** — the source publishes one
value per line. Each holds its line's hue to within 0.2°, keeps saturation
inside the 0.6–0.8 band the plate colours use, and lifts lightness the way the
plate pairs do. Against `#121210` they measure M1 5.4:1, M2 5.9:1, M3 8.3:1 —
the band the metro darks already sat in, when the placeholders measured
5.8–7.9:1.

M1 is deliberately the deepest of the three. The confirmed M1 is a navy, and
lifting it as far as the others would land it on top of tomnaya's `#5FAAE8`;
keeping it deeper preserves the same ordering the light theme has, where M1 is
the darker blue of the pair.

> **Do not "correct" this table from a secondary source.** Wikipedia and most
> third-party maps print "Line 1 (red), Line 2 (blue)". Both operator maps say
> the opposite: M1 is blue, M2 is red. This was checked against the operators,
> not against those.

> **Open:** white on M3 `#00A88F` measures 3.00:1. That clears AA for the badge
> numeral only because it is large and bold. If the badge ever shrinks, the M3
> numeral needs a darker treatment — the colour is the operator's and is not
> the thing to change.

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
   from `route.display_name`. Metro legs are the exception in the other
   direction — they have numbers, but the circular badge already carries it.

   These rules are derived from data fields, so in the Flutter build they are
   decided once in `app/lib/core/presentation/trip_presenter.dart` and the
   widgets receive view models with no field left to re-interpret. Rules 1, 3
   and 5 are all things that fail *plausibly* on screen; keeping them in four
   different `build()` methods is how one of them eventually gets it wrong.
2. **Never show a fare.** 2018 data. The API does not even request the fields.
3. **A walk-only itinerary is not a result.** When every itinerary has
   `is_walk_only`, show the API's `note` instead of the list.
4. **Place names come from OSM (ODbL), stop names from TfC (CC BY-NC).** Keep
   them in separate tables and label them separately in the UI. They must never
   be merged into one dataset — the licences are incompatible.
5. **Never imply real-time vehicle position.** No such source exists in Egypt.
   Estimates derive from the user's own GPS against a recorded route — say so.
6. **Attribution verbatim, in English, on any screen showing data.** Licence
   requirement. Fetch from `/attribution`.
7. **One unsolicited prompt per trip.** Enforce in code, not judgement.
8. **Both themes are designed.** Dark is not inverted light — it has its own
   surface elevations and desaturated mode colours, or the plate hues vibrate.

---

## Components

**Mode chip** — pill, `13%` tint of the mode colour as background, mode colour
as text, 6px square glyph. **Metro badge** — 25px circle, solid line colour,
white mono label.

The metro badge **is** the line number. Do not also draw a number chip beside
it: the Flutter build did, briefly, and rendered `M1` twice on every metro leg.
Rule 1 below governs the chip; the circle is a different thing wearing the same
text.

**Card** — `surface`, 1px `line`, 17px radius. Reserve borders and shadow for
things that are genuinely separate objects; not every block is a card.

**Honesty panel** — the pattern carrying rules 3 and 5. Neutral by default, `warn`
tint when stating a limitation. Always says what we do not know, in plain words.

**Place picker** — one field over two indexes. Stops and places get different
32px marks (`.pmark.stop` in microbus orange, `.pmark.place` in accent) because
they behave differently: a stop is where a vehicle calls, a place is where
you're going. The differing match behaviour is stated in the UI, since a user
who types منيب and gets nothing will otherwise assume the app is broken.

**Latin fallback** — a place with no `name:ar` renders its Latin name in an
LTR span with a note saying the map has no Arabic name for it. Never hide the
result, and never transliterate automatically — a wrong Arabic name is worse
than an honest English one.

**Severity stripe** — 4px inline-start bar on a tile whose metric is out of
range. Makes state readable as form, so it survives greyscale and colour-blind
viewing.
