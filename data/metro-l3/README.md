# Cairo Metro Line 3 — source data

Line 3 is missing from Transport for Cairo's metro feed, which covers M1 and M2
only. It is one of the busiest lines in the city, so this directory supplies it.
`scripts/build_metro_l3.py` turns these three files into
`OTP/gtfs-metro-l3.zip`, a standalone GTFS feed that OTP loads alongside the TfC
feeds:

```bash
python scripts/build_metro_l3.py
```

Then delete `OTP/graph.obj` and rebuild, or OTP loads the stale graph and nothing
takes effect.

The generated feed is not tracked in git (`OTP/*.zip` is ignored) because
everything needed to rebuild it is here.

## The files

| File | What it is | Provenance |
|---|---|---|
| `line3.json` | Topology: 34 stations in order, the Kit Kat branch point, both western branches, the six interchanges, English and Arabic names. | The operator's published station list. Authoritative — do not hand-edit for convenience. |
| `coordinates.csv` | One `lat,lon` per station, with the Wikidata Q-id it came from. | Wikidata (`P625`), **CC0**. Cross-checked against OpenStreetMap `station=subway` nodes for gross errors; no OSM values were copied. |
| `service.json` | Run speed, dwell, and the headway windows. | **Modelled.** See below. |

## The timetable is modelled, not published

No published Line 3 timetable was used. Running times come from the rule the TfC
feed itself follows — measured off its own M1 and M2 trips, which run at a
uniform **40.4 km/h** between stops with a **30 s dwell** everywhere — so Line 3
is consistent with the rest of the graph rather than with an invented constant.
Straight-line station distances sum to 37.19 km, so every segment is scaled
×1.108 to match the published route length of 41.2 km.

That yields 53 min Adly Mansour → Kit Kat, 66 min to Rod El Farag Axis and 65 min
to Cairo University. The builder refuses to write if any of those leaves the band
in `runTimeBandsMinutes`, so a bad speed or a bad coordinate cannot pass quietly.

Headways are modelled on M2's window shape. **Every headway in `service.json` is
per branch**: trains alternate at Kit Kat, so an 8-minute branch headway is
4 minutes on the trunk between Adly Mansour and Kit Kat.

Treat these numbers the way the project treats the 2018 fares — usable for
routing, never presentable as operator times. Replacing them with published
figures is a one-command update: edit `service.json` and rebuild.

## Licensing

The coordinates are CC0 and the topology is published operator information, so
this feed carries neither the TfC feed's non-commercial restriction nor OSM's
share-alike. That is the point of keeping it separate: mixing it into
`gtfs-metro.zip` would make one derived database out of sources the project is
required to keep apart.

Wikidata asks for no attribution. Credited here regardless: station coordinates
from [Wikidata](https://www.wikidata.org/), CC0 1.1.

## Two traps

- **`sequence` in `line3.json` is not a stop order.** It numbers all 34 stations
  1–34 in a single chain, so Kit Kat (23) is followed by *both* Sudan (24) and
  El Tawfikia (30). Split on `branch`.
- **Line 3's western terminus is `Rod El Farag Axis`.** The TfC feed already has
  a `Rod El Farag` — the Line 2 station, 2.4 km away. The rename lives in
  `STATION_NAME_OVERRIDES` in the builder, not in `line3.json`.

## Not included

Fares. Real track geometry — `shapes.txt` is straight lines between stations. The
unbuilt Sheraton, Airport, Military Academy, Ahmed Galal and Al-Hegaz stations,
which have no coordinates in Wikidata because they do not exist yet.
