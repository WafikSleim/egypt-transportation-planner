# Flutter client

The passenger app. Arabic-first, RTL, light and dark, talking only to the
project's own API in [`api/`](../api) — never to OpenTripPlanner directly.

## Running it

The API and OTP have to be up first (see [`../api/README.md`](../api/README.md)).

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` is the Android emulator's alias for the host machine and is the
**default** — inside the emulator `localhost` is the emulated device itself.
On a physical phone, pass your machine's LAN address instead.

```bash
flutter test      # 144 tests, no device, no network, a few seconds
flutter analyze
```

## Architecture — MVVM with Bloc

Settled 2026-09-21. Treat it as decided.

| MVVM role | Here | Where |
| --- | --- | --- |
| Model | Wire models + repository | `data/models`, `data/repositories`, `domain/` |
| ViewModel | A **Cubit** per screen | `features/*/view_model/` |
| View | Widgets, and nothing else | `features/*/view/`, `features/*/widgets/` |

```
lib/
├── core/
│   ├── config/         base URL, coverage box
│   ├── location/       one-off fixes, on demand only
│   ├── map/            tile source, style builder, the map widget
│   ├── network/        ApiClient, failure classification
│   ├── presentation/   TripPresenter + the view models it emits  ← read this first
│   ├── settings/       language and theme (the only two settings passengers get)
│   ├── storage/        KeyValueStore - the seam over shared_preferences
│   ├── text/           bidi isolation, Western-digit formatting
│   ├── theme/          tokens, both palettes, mode colours
│   └── widgets/        ModeBadge, HonestyPanel, AttributionNote, AppErrorView
├── data/               models + repository implementation
├── domain/             entities + the repository interface
├── features/<screen>/  view · view_model · widgets
└── l10n/               app_ar.arb (template) · app_en.arb
```

A Cubit is chosen over a Bloc everywhere: these screens have no event streams
worth modelling, just a handful of methods. Add a Bloc when a screen genuinely
has concurrent, ordered events — not by default.

### The one thing to understand before changing anything

**Presentation rules live in `core/presentation/trip_presenter.dart`, not in
widgets.** Four of the rules in [`docs/design-system.md`](../docs/design-system.md)
are decisions derived from data fields:

- a route-number badge may only be drawn when the route has a number
- a walk-only itinerary is not a result
- the metro is a circular line badge, everything else is a pill
- mode colour comes from `agency_id`, never `route_type`

Each of those fails *plausibly*. A microbus showing a number badge, a two-hour
walk offered as a trip, a metro line drawn as a tomnaya-coloured pill — none of
them look like bugs on screen. They look like answers.

So the presenter decides them once and emits `LegVm` / `ItineraryVm` / `PlanVm`,
and no widget ever sees `has_line_number` or `is_walk_only`. If you find
yourself reading a wire model inside a `build()`, that is the bug.

The presenter **maps, it does not derive**. The server already resolved the
mode from `agency_id` and already set `is_walk_only`; the client must not
second-guess either.

## Why some things look the way they do

**`lang` is added by `ApiClient`, not by call sites.** Stop names, route display
names and the origin/destination labels are localised server-side. A request
that forgets `lang` gives you a fully Arabic screen with Latin stop names —
which reads as a working app, not as a bug. There is no way to make a request
without it, and `test/api_client_test.dart` holds that.

**Metro stop names are in English, and that is the data, not a bug.** The metro
feed ships no `translations.txt`; its 108 stops have no Arabic names yet. The
UI says so rather than hiding the name or transliterating it — a wrong Arabic
name is worse than an honest English one. Every name from the data is wrapped
in `bidiIsolate` so a Latin run cannot reorder the Arabic around it.

**Western digits everywhere**, formatted by hand rather than through `intl`,
which renders Arabic-Indic digits under an `ar` locale. `8:15` is what Egyptian
phones and road signs use.

**The empty-results screen is written in Arabic, not relayed from the server.**
`/plan` returns both `note` (English diagnostic prose, with a bounding box in
decimal degrees) and `note_code` (`out_of_coverage`, `outside_service_hours`,
`no_route`). The client switches on the code and writes its own copy, falling
back to `note` only for a code this build does not recognise. That screen is
the most common thing a passenger outside the covered area will see; relaying
the server's sentence would make it the one place the app stops speaking
Arabic.

**No fare, anywhere.** Not omitted for space — the source fares are from 2018
and the API does not even request the fields.

**Storage is `shared_preferences` behind an interface, not `drift`.** The
three things this app keeps on a phone — language and theme, recent
endpoints, a few saved trips — are read whole and shown in order, never
queried. `core/storage/key_value_store.dart` records the reasoning and what
would justify revisiting it. Nothing above that interface knows what is
underneath, so the swap is one class if it ever comes.

**Bad stored data cannot stop the app starting.** Text that is not JSON, a
language from a newer build, a value of the wrong type — each falls back to
the phone's own locale. Those are phones that would otherwise fail to launch
over data the user can neither see nor clear without reinstalling.

**Location is read on demand and never in the background.** There is no
`ACCESS_BACKGROUND_LOCATION` in the manifest. Following a trip is a separate
feature with its own consent and its own persistent notification, and it must
not arrive by accident through the "my location" button. A coarse fix is
flagged to the user rather than quietly used, and a fix outside the covered
box is caught before a request is spent on it.

**A saved trip is a pair of places, not a saved itinerary.** The itinerary is
worked out again every time it is opened. Storing the one that was on screen
when it was saved would mean showing someone departure times from last
Tuesday — see `SavedTrip` in `data/repositories/trip_history.dart`.

**The map's style is built in Dart, not vendored.** `core/map/map_style.dart`
emits a MapLibre style document from `MapPalette`, the way `TripPresenter`
emits view models — one place decides, the widget is handed something
finished, and the whole thing is testable without a GPU. Protomaps' own light
and dark themes were the quicker route and are somebody else's colours; a map
in another palette inside these screens reads as a second app bolted on. Dark
is written out rather than inverted, because an inverted basemap puts water
lighter than land and the Nile glows.

**The basemap never uses a mode colour.** The licence-plate system only works
while nothing else competes with it, and a basemap is thousands of shapes — a
road casing in microbus orange would be the loudest orange on screen, by area.
`test/map_style_test.dart` holds that.

**The map has its own attribution widget, and that is not duplication.**
`AttributionNote` carries the transit data's credit (TfC, CC BY-NC, fetched
from `/attribution`); `core/map/map_attribution.dart` carries the basemap's
(OpenStreetMap, ODbL, known at build time). Different works, different
licences, and ODbL wants its credit on the map rather than on an About screen.

**Fonts are bundled, not fetched.** `google_fonts` would mean a first run on a
weak connection falling back to a system face with worse Arabic shaping.

**Sizing goes through `flutter_screenutil`.** The design frame is 390×844,
declared once in `app.dart`; `Insets` and `Radii` are scaled getters, so no
screen can opt out. They are therefore not compile-time constants — that is why
widgets using them are not `const`.

## Release builds, and the size budget

Measured on 2026-09-23, Flutter 3.44.6, AGP 9.0.1, from a clean
`flutter build apk --release --split-per-abi`:

| Artifact | Bytes | | Budget |
| --- | ---: | ---: | ---: |
| `app-armeabi-v7a-release.apk` | 26,235,782 | 25.0 MiB | **28 MiB** |
| `app-arm64-v8a-release.apk` | 31,523,614 | 30.1 MiB | **33 MiB** |
| `app-x86_64-release.apk` | 33,358,978 | 31.8 MiB | **35 MiB** |
| `app-debug.apk` (all three ABIs in one file) | 189,936,842 | 181.1 MiB | — |
| `app-release.aab` | 66,119,896 | 63.1 MiB | *not a download size* |

The budget is deliberately about 10% above what is there now. It is a
tripwire, not a target: anything that crosses it is a change big enough that
somebody should have to say out loud why. The number that matters is
**`armeabi-v7a`** — 32-bit ARM is the low-end fleet this app is built for, on
phones where storage is the thing that runs out — and `arm64-v8a` is what
almost everyone actually installs.

**The `.aab` is not a size.** Play splits a bundle per device and ships each
phone one ABI, one density and one language, so 63 MiB is what the upload
weighs, not what anyone downloads. The real download is close to the matching
per-ABI APK above, minus the densities and translations that phone does not
need. `bundletool get-size total` measures it properly; `bundletool` is not
installed here, so that number has never been taken. Do not quote the `.aab`
figure as an install size.

### Where the weight actually is

For `arm64-v8a`, compressed, out of 30.1 MiB:

| | |
| --- | ---: |
| `libflutter.so` — the engine | 11.0 MiB |
| `libmaplibre.so` — the map renderer (#19) | 10.4 MiB |
| `libapp.so` — all of our Dart, AOT-compiled | 6.2 MiB |
| everything else — dex, fonts, resources, assets | 2.5 MiB |

Which is the fact to keep hold of before optimising anything: **92% of this
app is three native libraries, two of which are somebody else's.** Every
lever available on the Dart and Java side is working inside the remaining
8%. If the budget ever needs to come down by a lot rather than a little,
the honest answer is a smaller map renderer, not a smaller anything else.

### R8 and resource shrinking

On, in `android/app/build.gradle.kts`. Measured both ways on the same commit:

| | armeabi-v7a | arm64-v8a | x86_64 |
| --- | ---: | ---: | ---: |
| without | 28.9 MiB | 34.0 MiB | 35.7 MiB |
| with | 25.0 MiB | 30.1 MiB | 31.8 MiB |

The saving is 4,083,574 bytes — 3.9 MiB, and *identical* on all three, which
is the clearest possible demonstration of what R8 does here. It never sees a
native library; it shrinks the JVM half only, and the JVM half is the same
bytes whatever the CPU. Most of that 3.9 MiB is `play-services-base` and
`play-services-location`, which arrive transitively through `maplibre_gl` and
which nothing in this app calls. The dex ends up at 0.78 MiB.

**R8 correctness is not verified and cannot be verified here.** A build with a
class stripped that something reaches by name succeeds exactly like a correct
one; the failure is at runtime, and for the map that means the first time the
coverage map on the About screen opens. `android/app/proguard-rules.pro`
records which plugins ship their own consumer rules — all three do — and what
to try if the map is what breaks. That check is part of the on-hardware review
of #31, along with everything else in this project that has never run on a
phone.

### Fonts: measured, and not subsetted

The four IBM Plex Sans Arabic weights, the two IBM Plex Mono weights and the
variable Readex Pro come to 1,523,972 bytes on disk — but TTF compresses, and
what they weigh **in the APK** is 674 KiB:

| File | On disk | In the APK |
| --- | ---: | ---: |
| `ReadexPro-Variable.ttf` | 272.0 KiB | 149 KiB |
| `IBMPlexSansArabic-SemiBold.ttf` | 238.9 KiB | 105 KiB |
| `IBMPlexSansArabic-Medium.ttf` | 236.4 KiB | 105 KiB |
| `IBMPlexSansArabic-Bold.ttf` | 241.2 KiB | 102 KiB |
| `IBMPlexSansArabic-Regular.ttf` | 230.4 KiB | 100 KiB |
| `IBMPlexMono-SemiBold.ttf` | 136.9 KiB | 58 KiB |
| `IBMPlexMono-Regular.ttf` | 132.4 KiB | 55 KiB |

That is **2.2% of the release APK**, which is the first thing to know before
spending any effort here. The issue that asked for this review assumed ~1.5 MB;
1.5 MB is the on-disk figure and it never ships.

**The Arabic faces are not subsetted, and should not be.** Subsetting means
deciding in advance which glyphs the app will ever draw, and this app draws
names it has never seen — 2,997 road stops, 105,984 places in the OSM index,
and whatever a passenger types. Arabic is worse than Latin for this in two
further ways: shaping needs all four positional forms of every letter plus the
`GSUB`/`GPOS` tables that join and kern them, so a subsetter that keeps
codepoints and drops lookups produces text that renders as disconnected
letters rather than as words; and the required lam-alef ligatures are glyphs
no codepoint-driven subsetter will find. The failure is also silent and
late — a missing glyph is a box in one stop name on one screen, not a build
error. Set against 100 KiB a face, that is not a trade worth making. Readex
Pro is the display face specifically for its low-literacy legibility
([`docs/design-system.md`](../docs/design-system.md)), which is product value
here, not decoration.

Two things that *are* worth knowing:

- **IBM Plex Mono earns its 113 KiB.** It is not decorative — it sets route
  numbers in `ModeBadge` and the licence lines in `AttributionNote` and the
  map attribution. Removing it would change what a route number looks like.
- **Upstream ships a variable IBM Plex Sans Arabic.** Four static weights
  become one file, which would save roughly 250–300 KiB in the APK with *no*
  glyph or ligature coverage lost — the opposite trade from subsetting. It is
  not done because a variable face has to be looked at on a real screen at
  each of the four weights before anyone can say it is the same design, and
  nothing here has been on a real screen yet. Recorded so the next person does
  not have to rediscover it. Readex Pro is already variable.

`--tree-shake-icons` is on by default in release and does apply to
`MaterialIcons-Regular.otf`: 1,645,184 bytes down to 5,700. It does **not**
apply to text fonts — those ship whole, always.

### Re-measuring

```bash
cd app
flutter build apk --release --split-per-abi
ls -l build/app/outputs/flutter-apk/*-release.apk
```

Compare the bytes against the table above. `flutter build appbundle --release`
gives the upload artifact. If a number has moved and it is not obvious why,
the breakdown that produced the table above is just the zip directory:

```bash
python -c "import zipfile,collections; z=zipfile.ZipFile('build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'); a=collections.Counter(); [a.update({'/'.join(i.filename.split('/')[:2]): i.compress_size}) for i in z.infolist()]; [print('%-40s %8.2f MiB' % (k, v/1048576)) for k, v in a.most_common(10)]"
```

### Signing

There is no keystore in this repository and there never will be. Release
signing reads `android/key.properties`, which is untracked; `*.jks` and
`*.keystore` are ignored repository-wide.
[`android/key.properties.example`](android/key.properties.example) shows the
four keys.

**With no `key.properties` present the release build falls back to the debug
signing key.** That is on purpose — `flutter build apk --release` has to keep
working for a fresh clone and for CI, neither of which should hold a signing
key. What it produces runs, and cannot be uploaded to Play. The failure is
therefore visible at exactly the moment it matters and invisible the rest of
the time.

Creating the keystore is the maintainer's job, and is done once. Play will not
let the signing key be replaced after the first upload, so a lost keystore
means the app can never be updated under this listing again — back it up
somewhere that is not this machine:

```bash
keytool -genkey -v \
  -keystore ~/keys/masar-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

No `-storetype`: `keytool` on JDK 9 and later defaults to PKCS12, and asking
for the older JKS gets a migration warning on every use. The `.jks` extension
is kept anyway because that is what the `.gitignore` rules and every piece of
Flutter documentation expect to see; the extension is not the format.

Then copy `android/key.properties.example` to `android/key.properties`, fill
in the two passwords, the alias and the absolute path to the keystore, and
check that `git status` still shows nothing.

`storeFile` is resolved by Gradle against `android/app/`, so a relative path
there is relative to the module, not to the file it is written in. An absolute
path avoids the question. None of this has been run — no `key.properties` has
ever existed on this machine, so the `release` signing config has never been
evaluated by Gradle. Expect the first real signed build to be the thing that
proves it.

## Identity and versions

The icon, the adaptive foreground and both splash marks are **generated**:

```bash
python ../scripts/build_app_icon.py      # assets/icon/*.svg + *.png
dart run flutter_launcher_icons          # the platform icon sets
dart run flutter_native_splash:create    # the platform splash
```

Both the SVG and the PNG for each asset come out of that one script, so they
cannot drift. Do not hand-edit anything under `android/app/src/main/res/` or
`ios/Runner/Assets.xcassets/` — those are output and the next run overwrites
them.

The mark is one idea: a trip. A small node where you are, a route that turns
twice, a larger node where you are going. No vehicle, no map, no lettering —
all three turn to mush at 48dp, which is the size that decides whether an
icon works. It runs **right to left**, because every screen in this app is
RTL. It is drawn in the **accent**, which is chosen in the design system
precisely because it is neither a licence-plate colour nor a metro line
colour — spending one of those on branding would make the launcher icon
claim a mode.

**Launcher label:** `مواصلات` on an Arabic phone, `Mowasalat` everywhere else,
via `values-ar/strings.xml`.

**Version scheme** — `MAJOR.MINOR.PATCH+BUILD`, currently `0.1.0+1`:

| Part | Bumps when |
| --- | --- |
| `MAJOR` | stays `0` until v1 ships — the 20 Phase 2 and Phase 3 `must` stories |
| `MINOR` | a user-visible capability lands |
| `PATCH` | fixes only |
| `BUILD` | every upload, monotonic, never reused — Play rejects a repeat |

## Tests

`test/fixtures/` holds **real captured responses** from the live API. The models
are hand-written rather than generated from `/openapi.json`, and these fixtures
are what keeps them honest: a change in the server's shape fails a test here
instead of a screen on someone's phone.

Recapture one with:

```bash
curl "http://localhost:8000/plan?from=29.8490,31.3340&to=30.1220,31.2450&date=2026-09-21&time=08:00&lang=ar" -o test/fixtures/plan_metro_ar.json
```

`test/mode_catalog_test.dart` reads `../api/modes.py` directly and fails if a
mode exists there without a label here — `ModeCatalog` duplicates a server-side
table, and duplicated tables drift.

## Not built yet

Designed in [`design/app-prototype.html`](../design/app-prototype.html) and
backlogged in [`docs/user-stories.md`](../docs/user-stories.md), but not wired:

- **Places and map picking** (P-18, P-19) — blocked on the `places` table
- **Notifications** (P-16) and **background tracking** (P-17)
- Map tiles on results and itinerary screens. The renderer exists — see
  `core/map/` and the coverage map reached from About — but `/plan` returns
  each leg's endpoints and no geometry, so an itinerary map would be drawing
  straight lines between stops and claiming they are routes
