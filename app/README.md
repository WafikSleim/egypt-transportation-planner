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
flutter test      # 172 tests, no device, no network, a few seconds
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
│   ├── notifications/  the four kinds that exist, and no way to add a fifth
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

**A notification cannot say anything it likes.** `core/notifications/` is
built so that the fourth kind of notification — the growth one, the
re-engagement one — is not a thing someone could add without noticing.
`NotificationKind` is a closed enum, `NotificationRequest` is sealed and
carries a trip or a stop rather than a title and a body, the words come from
`notification_copy.dart`, and there is no remote-push package in the project
and no `UIBackgroundModes` in `Info.plist`. `NotificationService.post` is the
only entry point and it refuses a kind the passenger switched off; the "turn
these off" action on the notification is handled in the base class, so a
feature cannot forget to implement it. The one kind with no off switch is the
ongoing tracking notice, because silencing it would let GPS run invisibly.
`test/notifications_test.dart` holds all of this against
`test/fake_notification_service.dart`, which overrides only `deliver` and
`retract`.

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
- **The four notifications themselves** (#22–#25). The infrastructure landed
  with #21 — the seam, the in-context permission flow, the switches on the
  About screen — but nothing schedules a notification yet, and none of it has
  run on a phone
- **Background tracking** (P-17, #24)
- Map tiles on results and itinerary screens. The renderer exists — see
  `core/map/` and the coverage map reached from About — but `/plan` returns
  each leg's endpoints and no geometry, so an itinerary map would be drawing
  straight lines between stops and claiming they are routes
