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
flutter test      # 59 tests, no device, no network, a few seconds
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
│   ├── network/        ApiClient, failure classification
│   ├── presentation/   TripPresenter + the view models it emits  ← read this first
│   ├── settings/       language and theme (the only two settings passengers get)
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

**No fare, anywhere.** Not omitted for space — the source fares are from 2018
and the API does not even request the fields.

**Fonts are bundled, not fetched.** `google_fonts` would mean a first run on a
weak connection falling back to a system face with worse Arabic shaping.

**Sizing goes through `flutter_screenutil`.** The design frame is 390×844,
declared once in `app.dart`; `Insets` and `Radii` are scaled getters, so no
screen can opt out. They are therefore not compile-time constants — that is why
widgets using them are not `const`.

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
- **Recents and saved trips** (P-15) — needs on-device storage
- **Notifications** (P-16) and **background tracking** (P-17)
- Map tiles on results and itinerary screens
- Persisting the language and theme choice
