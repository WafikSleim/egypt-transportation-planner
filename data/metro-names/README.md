# Metro stop names in Arabic — lines 1 and 2

Transport for Cairo's metro feed ships no `translations.txt`, so its stops render
as `Ain Helwan` and `Al-Shohadaa` inside an otherwise Arabic itinerary. The road
feed needs nothing — all 2,997 of its stops already carry Arabic — so the metro
is the one place an Arabic itinerary switches to Latin. This directory supplies
the missing Arabic for lines 1 and 2.

Line 3 is not here. It is our own feed and already ships Arabic for all 34 of its
stations — see [`data/metro-l3/`](../metro-l3/).

`stations.csv` is **source data, not an applied change.** Nothing in this
directory has been written into `OTP/gtfs-metro.zip`, and nothing should be: see
[Applying this](#applying-this).

Checked **2026-09-22**. Every URL below was reachable on that date.

## The file

`stations.csv`, one row per station-on-a-line, 55 rows:

| Column | What it is |
|---|---|
| `line` | `M1` or `M2`. |
| `sequence` | Position along the line, 1 at the southern terminus. M1 runs Helwan (1) → New El-Marg (35); M2 runs El-Mounib (1) → Shubra El-Kheima (20). |
| `station_id` | Local key, snake_case, in the style of `data/metro-l3/`. **Local to this file** — see the note under [Collisions](#collisions). |
| `name_en` | The Latin name, as the TfC feed is expected to spell it. **Not yet reconciled against the real feed** — see below. |
| `name_en_source` | `feed` where the spelling is attested from a real API response in `app/test/fixtures/`; `wikidata` where it is the Wikidata English label used as a stand-in; `unverified` for the one blank row. |
| `name_ar` | The Arabic name. Blank where no confident name was found. |
| `source` | Where the **chosen Arabic string** came from: `wikidata`, `arwiki` or `operator`. |
| `source_ref` | The Wikidata Q-id. This identifies the **station**, not the string — for rows where `source` is not `wikidata`, the Q-id is the station's identity and the Arabic came from elsewhere. |
| `wikidata_label_ar` | The raw Wikidata Arabic label, preserved verbatim. Differs from `name_ar` wherever a label was stripped or a disagreement was resolved against Wikidata. |

55 rows, 53 distinct stations: Sadat and Al-Shohadaa are M1/M2 interchanges and
appear once per line with the same `station_id`, Q-id and Arabic name.

**Coverage: 54 of 55 rows filled, one deliberately blank.** See
[The one blank](#the-one-blank-helwan-university).

## Where the names came from

Three sources, in the order they were trusted:

1. **[Wikidata](https://www.wikidata.org/)**, `rdfs:label@ar` on the station item,
   reached by `wdt:P81` (connecting line) from `Q5017774` (Line 1) and
   `Q5017773` (Line 2). The preferred source, and the reason this project already
   used Wikidata for the Line 3 coordinates. 35 + 20 items, matching the
   operator's published station counts exactly.
2. **Arabic Wikipedia**, [`مترو القاهرة`](https://ar.wikipedia.org/wiki/مترو_القاهرة).
   The per-line articles are redirects; the station lists live in that one
   article, under `محطات الخط الأول` and `محطات الخط الثاني`. Used to adjudicate
   spelling and to confirm order.
3. **The operator**, the Egyptian Company for Metro Management and Operation, at
   [`cairometro.gov.eg/ar/operations/1`](https://www.cairometro.gov.eg/ar/operations/1)
   and `/2`. Used only where 1 and 2 disagreed.

**Signage was not independently verified from photographs.** No usable signage
imagery was found. The operator's own published prose is treated as the signage
proxy throughout, which is what settles the disagreements below. That is a weaker
bar than the task asked for and is recorded here rather than glossed.

### Two editorial acts, both recorded rather than silent

**Stripping.** Five Wikidata labels carry a `محطة` ("station") or `مترو`
("metro") qualifier that is not part of the station name: Helwan, Ain Helwan,
El-Maasara, Dar El-Salam and Shubra El-Kheima. The qualifier was stripped; the
raw label is preserved in `wikidata_label_ar` and the stripped form matches the
Arabic Wikipedia station list in all five cases.

**Order.** `sequence` was taken from the operator's and Arabic Wikipedia's
published station lists, then checked independently: sorting each line by
descending latitude from the Wikidata `P625` coordinates reproduces the published
order exactly, strictly monotonic, 35/35 on M1 and 20/20 on M2. No row was
hand-numbered from memory. Arabic Wikipedia's M1 list also contains
`الشيخ منصور`, approved in 2025 and still under construction; it is excluded, and
excluding it is what makes the count 35.

## Where sources disagreed

Seven disagreements. None was resolved silently.

### Short label vs. official form — Sadat, Nasser, Orabi

One cause, three stations. Wikidata carries the short colloquial label; the
operator and Arabic Wikipedia both publish the full official name.

| Station | Wikidata | Operator / arwiki | Taken |
|---|---|---|---|
| Sadat | `السادات` | `أنور السادات` | `أنور السادات` |
| Nasser | `جمال عبد الناصر` | `جمال عبد الناصر` | `جمال عبد الناصر` |
| Orabi | `عرابي` | `أحمد عرابي` | `أحمد عرابي` |

The tiebreak is signage, and the operator's form is the signage proxy. Note the
operator's page writes `جمال عبدالناصر` unspaced; that is a CMS artifact, and the
spaced `جمال عبد الناصر` used here is what both Wikidata and Arabic Wikipedia
carry.

**Nasser conflicts with our own Line 3 feed.** `data/metro-l3/line3.json` ships
`nameAr: "ناصر"` for the same physical station — the M1/M3 interchange, 26 m
apart per `CLAUDE.md`. Three independent sources agree against that one string,
so `ناصر` is treated here as a defect in our feed rather than as a competing
name. **Fixing it is a prerequisite, not a caveat** — see
[Applying this](#applying-this).

### Spelling variants

| Station | Wikidata | arwiki | Operator | Taken | Why |
|---|---|---|---|---|---|
| Kozzika | `كوتسيكا` | `كوتسكا` | `كوتسيكا` | `كوتسيكا` | Wikidata and the operator agree; arwiki is the outlier. |
| Saray El-Qobba | `ساراي القبة` | `سراي القبة` | — | `سراي القبة` | arwiki plus standard orthography. **Two sources only — the operator does not name this station**, so this is not operator-confirmed. |
| St. Teresa | `سانتا تريزا` | `سانت تريزا` | — | `سانت تريزا` | As above. **Two sources only, not operator-confirmed.** |

### The one blank: Helwan University

`M1` sequence 3, `Q10276202`, left blank on purpose. Three live renderings and no
way to choose between them:

- `جامعة حلوان` — Wikidata's Arabic label, and the operator's own page. **Both
  are stale**: the operator page still describes the 2002 opening under that name.
- `جامعة العاصمة` — Arabic Wikipedia, following the university's renaming to
  Capital University.
- `العاصمة` — [Masrawy, 31 August 2026](https://www.masrawy.com/news/news_egypt/details/2026/8/31/3041377/),
  quoting an unnamed metro source that the **station** signage was changed to
  `محطة مترو العاصمة` around 26 August 2026 — about four weeks before this was
  checked.

So the station was renamed very recently, the operator's own site has not caught
up, and the two post-rename sources disagree on whether the station is
`جامعة العاصمة` or `العاصمة`. Wikidata's English label is already
`Capital University metro station` while its Arabic label is still
`جامعة حلوان`, which is the same staleness from the other side.

`docs/design-system.md`: *a wrong Arabic name is worse than an honest English
one*. One documented blank is a better deliverable than 55 rows with a coin-flip
in one of them, and the app already renders an un-translated metro stop honestly.

**To close it:** a photograph of the station's current signage, or the operator's
page once it is updated. Then fill `name_ar`, set `source`, and note that the
TfC feed's Latin is expected to be the pre-rename `Helwan University`.

## Collisions

**`station_id` is local to this file. It is not a join key with
`data/metro-l3/`.** That file's `rod_el_farag` is the Line 3 *Axis* station; this
file's `rod_el_farag` is the Line 2 station, 2.4 km away. They are different
places that happen to share a local key. The three ids that **do** denote the
same physical station in both files are `attaba`, `nasser` and `cairo_university`.

**Rod El Farag — found, already handled.** Line 3's terminus is published as
`محور روض الفرج` / `Rod El Farag Axis` and is already renamed in
`STATION_NAME_OVERRIDES` in `scripts/build_metro_l3.py`, precisely so it does not
collide with this Line 2 station. Nothing new is needed; recorded because the
collision is real and the mitigation is easy to remove by accident.

**Sadat and Al-Shohadaa are not collisions.** Each is one station serving two
lines, one Wikidata item, one Arabic name. Under `field_value` matching a single
translation row correctly serves every stop that carries the name.

**No two distinct stations in this file share an Arabic name**, and no Latin name
maps to two different Arabic strings. Both were checked over the finished file;
the second is the property `field_value` matching actually depends on, and
whatever applies these names should assert it again against the real feed.

**Expected, benign, and worth knowing about:** applying these names makes several
metro stops share an Arabic name with *road* feed stops that already carry it —
`المنيب`, `العتبة`, `الجيزة`, `الدقي` and others. At least 16 road-feed stops
already match `المنيب` (`CLAUDE.md`; `app/test/fixtures/stops_ar.json` shows the
first five of sixteen), and `CLAUDE.md` records 2,997 road stops across only
1,572 distinct names, so
duplicate names are the normal condition of place search, not a new fault. This
is the same place reached by different modes — unlike Rod El Farag, which was two
different places.

## Licensing

The Line 3 directory chose CC0 specifically to avoid dragging share-alike across.
This directory uses three sources, and only one of them is CC0, so the argument
has to be made rather than assumed:

- **Wikidata** is **CC0**. No attribution required, no share-alike. Credited
  anyway, as `data/metro-l3/README.md` does.
- **Arabic Wikipedia** is **CC BY-SA 4.0**.
- **cairometro.gov.eg** is the operator's site, all rights reserved.

**A station's proper name is a fact, not creative expression.** No copyright
attaches to the string `سراي القبة`, so neither Wikipedia's share-alike nor the
operator's terms follow it into this dataset. Wikipedia and the operator were
used to *verify* names and to *adjudicate* spelling; **no prose, table, list
structure or other expressive content was copied from either**. Where this README
cites them it does so in short, attributed fragments.

This directory therefore carries no share-alike obligation and no
non-commercial restriction, exactly like `data/metro-l3/`.

**It must still be kept out of the TfC feed's licence envelope in the other
direction.** These names describe TfC's stops but are not TfC's data. Merging
them into `gtfs-metro.zip` is wrong for the reasons in the next section, and the
`source`/`confidence` labels in `api/config.py` `FEED_PROVENANCE` are what stop
the app from crediting TfC with names they did not produce.

## Applying this

Not done here, and deliberately not scripted. What a future change has to do:

**1. Reconcile `name_en` against the real feed first.** The TfC metro feed is not
in the repository — it is CC BY-NC, so it is gitignored — and these Latin
spellings have **not** been checked against its `stops.txt`. Three are attested
from real captured API responses in `app/test/fixtures/`: `Ain Helwan`,
`Al-Shohadaa`, `Shubra El-Kheima`. All three match the Wikidata English label
character for character, which is why the Wikidata label was used as the
stand-in for the other 50 — but it is a stand-in, and two rows are known to be
suspect: `Road El-Farag` (likely `Rod El Farag` in the feed) and
`Helwan University` (Wikidata's English label is
`Capital University metro station`, with a disambiguator that is certainly not a
feed spelling). Match by position on the line and by line membership, never by
fuzzy string matching on the Latin name.

**2. Enumerate the feed's distinct `stop_name` values — there may be more than
53.** The feed has 108 stops for 53 stations, roughly two per station, one per
direction. `field_value` matching keys on the **string**, so this works only if
both directional stops carry the *same* `stop_name`. The metro fixture shows
Al-Shohadaa as two stop ids 40 m apart (`1:trusts.imperious.tarnished`,
`1:fidelity.asking.cheek`) both named `Al-Shohadaa`, so at least there it holds.
It must be confirmed for all 108. If any station spells its two stops
differently, that station needs a row per spelling — the reconciliation step is
not "check spellings", it is "enumerate the distinct values".

**3. Do not forget `trip_headsign`.** Headsigns are a separate `field_name` and
the feed spells them differently from stop names. The fixtures show headsigns
`Shobra El Kheima` (stop name: `Shubra El-Kheima`), `Moneeb` (stop name:
`El-Mounib`) and `El Marg` (stop name: `El-Marg`). A translation row keyed on the
stop-name spelling will not match the headsign, and the headsign is what the
itinerary shows as the direction of travel. `scripts/build_metro_l3.py` already
writes `trips`/`trip_headsign` rows alongside its `stops`/`stop_name` rows; the
same is needed here, keyed on the headsign strings as the feed spells them.

**4. Fix Line 3's `nasser` in the same commit.** Set `nameAr` for `nasser` in
`data/metro-l3/line3.json` to `جمال عبد الناصر` and regenerate
`OTP/gtfs-metro-l3.zip` with `python scripts/build_metro_l3.py`. Otherwise place
search shows one station under two Arabic names — the failure the
`Rod El Farag Axis` rename exists to prevent. The builder's duplicate guard keys
on the Latin `name`, so changing `nameAr` alone trips nothing.

**5. Never write into `OTP/gtfs-metro.zip`.** `scripts/fix_gtfs_calendar.py`
reads `gtfs-metro.zip.bak` as its input on **every** run, so anything added to
the zip is silently deleted the next time the calendar is fixed. This is the same
trap recorded in `CLAUDE.md` under "Line 3 is our own feed". Whatever applies
these names has to be a build step that re-derives the feed, ordered after the
calendar rewrite — or the names have to live outside the feed entirely and be
applied in `api/`, next to the `_stop_names()` workaround in `api/main.py`.

**6. Rebuild the graph.** Delete `OTP/graph.obj` first, or OTP loads the stale
graph and nothing takes effect.

The rows are in the `field_value` form the road feed uses and that
`build_metro_l3.py` is already proven against:

```
table_name,field_name,language,field_value,translation
stops,stop_name,ar,Ain Helwan,عين حلوان
```

## Credits

Station names and identities from [Wikidata](https://www.wikidata.org/), CC0 1.0.
Spelling and station order cross-checked against
[Arabic Wikipedia](https://ar.wikipedia.org/wiki/مترو_القاهرة), CC BY-SA 4.0, and
against the Egyptian Company for Metro Management and Operation at
[cairometro.gov.eg](https://www.cairometro.gov.eg/).

The stops these names describe are Transport for Cairo's, under CC BY-NC 4.0. The
attribution TfC's licence requires verbatim is served from `api/config.py`.
