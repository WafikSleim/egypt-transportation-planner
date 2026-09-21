# User stories

The backlog for Egypt Transportation Planner, written after the routing core
was proven working on 2026-09-21. Extended the same day with the design round
(P-15 to P-17, C-06), which added saved trips, notifications and honest
background tracking to the v1 scope.

These are deliberately specific to *this* product. A generic trip-planner
backlog would not mention that hundreds of routes share the name "Microbus", or
that a walking itinerary is a failure rather than an answer, and those are the
things that will make or break whether anyone in Cairo actually uses this.

**How to read a story.** Acceptance criteria are written to be checkable, and
reference real fields in the API contract (`api/models.py`) where one exists.
Phase numbers match the project plan. Sizes are S (hours), M (a day or two),
L (a week or more).

**Priority is scoped to the story's own phase**, not to v1 — otherwise every
Phase 4 story would read as deferrable and the dashboard would never get built
properly. `must` = that phase is not finished without it. `should` = the phase
is notably worse without it. `later` = genuinely deferrable.

**The v1 release gate is therefore the Phase 2 and Phase 3 `must` stories**, and
nothing else: eighteen stories, listed at the end.

---

## Actors

| | Who they are |
| --- | --- |
| **Passenger** | Someone in Greater Cairo trying to get somewhere. Arabic speaker, low-end Android, patchy data, no account. The overwhelming majority of users. |
| **Contributor** | A passenger who noticed the data is wrong and is willing to say so, standing at the stop, in under a minute. |
| **Moderator** | Trusted volunteer judging submissions. Small group, web dashboard, authenticated. |
| **Maintainer** | You. Keeps feeds fresh, calendars valid, the graph rebuilt and the service up. |

---

## Passenger

### Core journey

**P-01 — Plan a trip between two points** · must · Phase 3 · M

> As a passenger, I want to enter where I am and where I'm going and see how to
> get there by public transport, so that I don't have to already know which
> microbus to take.

- Origin and destination can each be set by map pin, current location, or stop search
- Results show departure time, arrival time, total duration, and number of transfers
- At least 3 itineraries where they exist
- Calls `GET /plan`; no routing logic in the client

**P-02 — See each leg of the journey** · must · Phase 3 · M

> As a passenger, I want to see each stage of the trip in order, so that I know
> where to get off and what to get on next.

- Every leg shows mode, start and end stop, departure time, duration
- Walking legs show distance and are visually distinct from transit legs
- Interchange between two legs at the same stop reads as a transfer, not a mystery
- Leg list is the primary view, not hidden behind a tap

**P-03 — Identify a microbus with no route number** · must · Phase 3 · S

> As a passenger, I want to know *which* microbus to board when it has no
> number painted on it, so that the itinerary is actually followable.

Grounding: 511 microbus routes share the short name "Microbus". Real microbuses
in Cairo carry no route number; they are identified by shouted destination.

- When `has_line_number` is `false`, **no route-number badge is rendered**
- The leg is labelled by origin → destination, from `route.display_name`
- When `has_line_number` is `true` (CTA bus, metro), the number *is* shown prominently
- A designer viewing the microbus case must not be able to mistake it for a missing value

**P-04 — Read everything in Arabic** · must · Phase 3 · M

> As an Egyptian passenger, I want the whole app in Arabic with Arabic stop
> names, because I do not read Latin transliterations of my own city.

- App defaults to Arabic; RTL layout throughout
- Requests pass `lang=ar`; stop names come back Arabic (all 2,997 road stops)
- Mode labels use `mode.label_ar` — ميكروباص, تمنايا, مترو الأنفاق
- **A stop with no Arabic name renders its Latin name**, never blank — the
  metro feed's 108 stops have no translations
- Mixed Arabic/Latin in one itinerary must not break the layout
- English remains available

**P-05 — See the trip on a map** · should · Phase 3 · M

> As a passenger, I want to see the route drawn on a map, so that I can tell
> whether it's going the way I expect.

- Legs drawn in mode colours; stops marked
- Self-hosted Protomaps tiles, not Google — per-request billing would sink a free app
- Map is supplementary; the itinerary must be fully usable without it loading

### Being told the truth

These stories exist because the failure modes here are silent, and a silent
wrong answer is worse than a refusal.

**P-06 — Be told when there's no data for my city** · must · Phase 3 · S

> As someone in Alexandria, I want to be told this app doesn't cover my city,
> rather than being handed a two-hour walk.

Grounding: the OSM extract covers all of Egypt while transit data covers
Greater Cairo only, so OTP will cheerfully return a long walk for Aswan.

- When every itinerary has `is_walk_only: true`, **none are shown as results**
- The `note` from the API is displayed instead
- Coverage is stated plainly: Greater Cairo only
- This must not read as an error or a crash — it is a known limit

**P-07 — Be told when nothing is running** · must · Phase 3 · S

> As a passenger searching at midnight, I want to know service has stopped, not
> that my search failed.

- Empty result shows the API's `note`
- Offers to re-search for the next morning
- Distinguishable in the UI from "no data for this area"

**P-08 — Never be shown a wrong fare** · must · Phase 3 · S

> As a passenger, I want to not be told a price that is years out of date,
> because I'll budget around it and be wrong at the turnstile.

Grounding: fares in the feed are from 2018. The API never requests fare fields.

- No fare appears anywhere in the UI
- If a fare is mentioned at all, it says unavailable and why
- `fare.available` is `false` on every itinerary; the client must not invent one

**P-09 — Understand how fresh and trustworthy the data is** · should · Phase 4 · S

> As a passenger, I want to know whether a route is confirmed or just reported,
> so that I can decide whether to trust it.

- Legs expose `confidence`; anything below `confirmed` is visibly marked
- `source` is available in detail (TfC, community)
- Confirmed data carries no badge — absence of warning is the signal

### Practicalities

**P-10 — Search for a stop by name** · must · Phase 3 · S

> As a passenger, I want to type part of a stop name and pick it, so I don't
> have to find it on a map.

- Typeahead against `GET /stops`
- **Search is prefix-based** (OTP behaviour): المنيب matches, منيب does not —
  the UI must not imply substring search
- `truncated: true` prompts for a longer query rather than implying the first
  20 are all of them
- Each result shows the modes served

**P-11 — Plan for a later time** · should · Phase 3 · S

> As a passenger, I want to plan a trip for tomorrow morning, so I know when to
> leave.

- Date and time pickers, defaulting to now in Africa/Cairo
- "Arrive by" as well as "depart at" (`arrive_by`)

**P-13 — Use the app on a cheap phone and a bad connection** · must · Phase 3 · M

> As a passenger on a low-end Android with intermittent data, I want the app to
> work anyway.

- Usable on 2GB-RAM Android, API 24+
- Requests time out gracefully with a retry, never an indefinite spinner
- Last result readable while offline
- APK small enough to install over mobile data

**P-14 — See who made this data** · must · Phase 3 · S

> As a passenger, I want to know where the data comes from.

Grounding: this is a licence obligation, not a nicety.

- TfC attribution shown verbatim, fetched from `GET /attribution`
- Reachable from any screen showing transit data
- Port Said credited separately when that feed lands

### Keeping and repeating trips

**P-15 — Get back to trips I take often** · must · Phase 3 · M

> As a commuter, I want my recent and saved trips one tap away, because I make
> the same journey twice a day and re-entering it every time is absurd.

- Recent searches kept automatically; any trip can be starred and named
  (`الشغل`, `البيت`)
- A saved trip re-runs **for today** in one tap — it stores the endpoints, not
  a stale itinerary
- **Entirely on-device.** No account, no server-side history, and the UI says so
- Clearable; uninstalling removes it

Supersedes P-12, which covered only recents.

### Notifications and tracking

**P-16 — Be reminded, and asked once** · must · Phase 3 · L

> As a passenger, I want the app to tell me when to leave and when to get off,
> and to ask my opinion once without nagging.

Three kinds, and no others:

1. **Departure reminder** — fires with walking time accounted for
   (`رحلتك بتبدأ بعد 20 دقيقة`). Snooze and cancel inline
2. **Next-stop alert** — only while tracking is active (P-17)
3. **One post-trip question** — kind, skippable, framed as helping other
   passengers rather than rating us

- **At most one unsolicited prompt per trip.** If ignored, never asked again for
  that trip. Enforced in code and covered by a test, not left to judgement
- Notifications are disableable from the notification itself
- **No growth, re-engagement or marketing pushes.** Ever

**P-17 — Be told the truth while my trip is tracked** · must · Phase 3 · L

> As a passenger, I want to know exactly what the app is doing in the
> background, what it costs me, and what it genuinely cannot know.

Grounding: **there is no real-time vehicle data for Cairo paratransit, and none
exists to buy or scrape.** The app cannot know where your microbus is. Most of
what a tracking feature normally promises would therefore be a lie.

- Tracking is **explicit and per-trip** (`تابع الرحلة`), never automatic
- Before consent, the UI states: it uses GPS and **costs battery**; location is
  computed **on the device and sent nowhere**; and we do **not** know where the
  vehicle is
- A persistent notification runs for the whole session; one tap stops it; it
  stops itself on arrival
- **Never display a vehicle arrival countdown.** Estimates are framed as derived
  from the user's own position against a recorded route
- When the user drifts off the recorded route, show a **low-confidence state**
  (`مش متأكدين إنك في السكة الصح`) offering a re-search and a report — never a guess

---

## Contributor

**C-01 — Report that something is wrong** · must · Phase 4 · M

> As a passenger who just found out a route changed, I want to report it in
> under a minute while I'm standing there.

- Reachable from a leg, a stop, and a failed search
- Categories: route no longer runs / stop moved / route goes elsewhere now / new route / other
- Free text optional, Arabic
- **No account required** — device identifier only
- Submission works on a bad connection; queued if offline

**C-02 — Report a missing route** · should · Phase 4 · M

> As a passenger who knows a microbus the app doesn't, I want to add it.

- Draw or trace the path; mark endpoints and known stops
- Operator type from the real list (microbus, tomnaya, minibus…)
- Saved to `submissions`, **never** written directly to live data

**C-03 — See that my report went somewhere** · should · Phase 4 · S

> As a contributor, I want to see my reports and their status, so I know it
> wasn't a black hole.

- List of own submissions with status: pending / confirmed / rejected
- Rejections carry a reason
- Local to the device, consistent with no accounts

**C-04 — Confirm someone else's report** · should · Phase 4 · M

> As a passenger who sees a pending correction for a route I use, I want to
> confirm it, so that accurate data gets published faster.

- Pending submissions relevant to a viewed route/stop are surfaced
- One tap to confirm or dispute
- **Two independent confirmations promote a submission to confirmed**
- A contributor cannot confirm their own submission

**C-06 — Confirm accuracy from the post-trip prompt** · should · Phase 4 · M

> As a passenger who just finished a trip, I want to answer one question about
> whether it was accurate, because that is the least effort anyone could spend
> on improving the data.

This is the contribution pipeline with the friction removed — the same
mechanism as C-01, reached by answering a notification instead of filling a form.

- A yes/no answer becomes a **low-weight submission** in the same `submissions`
  table, counting toward the two-confirmation threshold
- **"مش متأكد" is offered as a real answer** and recorded as such. Forcing a
  guess would poison the data this feeds
- A "something changed" answer routes into the full C-01 flow
- Weighted below a deliberate report, since it is answered in passing

**C-05 — Build up standing** · later · Phase 4 · M

> As a frequent contributor, I want my accepted reports to count for something,
> so that my future reports are trusted sooner.

- `trust_score` per contributor
- High trust can lower the confirmation threshold
- Not shown competitively — this is not a leaderboard

---

## Moderator

**M-01 — Sign in** · must · Phase 4 · S

> As a moderator, I want an authenticated dashboard, because I can change what
> everyone sees.

- Auth on the dashboard only; passengers still need no account
- Scoped roles: moderator vs admin

**M-02 — Work a submission queue** · must · Phase 4 · M

> As a moderator, I want a queue of pending submissions with enough context to
> judge them.

- Sortable by age, confirmations, contributor trust
- Each shows the claim, the existing data, and a map of both
- Approve / reject / request-more-info, with a reason on rejection

**M-03 — See a submission against current data** · must · Phase 4 · M

> As a moderator, I want to see the proposed change beside what's live, so I can
> judge it in seconds rather than minutes.

- Side-by-side map, existing in one colour and proposed in another
- Affected routes and stops listed
- Nearby recent submissions shown — they often corroborate

**M-04 — Promote a confirmed change into the live data** · must · Phase 4 · L

> As a moderator, I want an approved submission to reach passengers.

- Writes to the main tables with `source: community`, `confidence` set
- **Never** modifies the TfC feed files themselves — provenance stays separable
- Triggers the graph rebuild
- Reversible: every promotion is auditable and can be rolled back

**M-05 — Manage contributors** · should · Phase 4 · M

> As a moderator, I want to adjust trust and block bad actors.

- Per-contributor history and accept/reject ratio
- Adjust `trust_score`; block a device identifier
- Blocking does not retroactively delete already-confirmed contributions

**M-06 — Browse the network** · should · Phase 4 · M

> As a moderator, I want to search routes and stops and see coverage on a map,
> so I can spot gaps without waiting for a report.

- Search by name, operator, mode
- Map overlay of coverage; visible holes
- Stop detail: routes serving it, Arabic name present or missing

---

## Maintainer

These exist because every bug in this project so far has been invisible by
default. Both faults found on 2026-09-20 produced *plausible* output.

**O-01 — Know when the graph has no transit in it** · must · Phase 2 · S

> As a maintainer, I want an alarm when OTP is serving a graph with no transit,
> because that failure looks exactly like normal operation.

Grounding: OTP silently ignored both feeds for days because their filenames did
not match `(?i)gtfs`. Every search returned a walk. Nothing errored.

- `/health` already reports `degraded` with zero routes or stops — alert on it
- Dashboard shows route and stop counts against expected
- **Walk-only rate is tracked and alerted on** — a sudden jump means the feeds
  stopped loading

**O-02 — Know before the calendars expire** · must · Phase 2 · S

> As a maintainer, I want warning before service dates lapse, because when they
> do every search silently returns walking.

Grounding: both feeds shipped expired calendars. Current window ends 2027-12-31.

- Countdown to `feed_end_date` on the dashboard
- Warning at 90 days, alert at 30
- Runbook points at `scripts/fix_gtfs_calendar.py`, which is idempotent

**O-03 — Know when the source feed changes** · should · Phase 5 · M

> As a maintainer, I want to know when TfC publishes new data, so we aren't a
> year behind without noticing.

- Periodic check of the GeoNode documents
- Diff summary: routes and stops added, removed, changed
- Never auto-applied — a feed change needs a rebuild and a look

**O-04 — Rebuild and deploy safely** · must · Phase 2 · M

> As a maintainer, I want to rebuild the graph without taking the service down
> or breaking it.

- Build off the live path, verify, then swap
- **Verification asserts transit is present** before promotion — not just that
  a file was written
- Previous `graph.obj` retained for rollback
- Runbook documents the whole thing

**O-05 — Restore after losing the host** · must · Phase 2 · M

> As a maintainer, I want to rebuild the service from nothing in about an hour.

Grounding: Oracle can reclaim idle Always-Free instances.

- Feeds and graph backed up to object storage
- Documented restore, tested at least once
- Infrastructure reproducible from the repo

**O-06 — See that the service is up** · must · Phase 2 · S

> As a maintainer, I want to know it's down before a user tells me.

- External uptime check on `/health`
- Alert on `degraded` as well as unreachable
- Latency tracked — a cold OTP is slow while the graph loads

---

## Deliberately not stories

| Not doing | Why |
| --- | --- |
| Passenger accounts, login, profiles | Ruled out by the brief. Recents live on the device |
| Ads, subscriptions, paid tiers | **Breaks the CC BY-NC licence.** Not a product decision |
| Live vehicle positions | No source exists for Cairo paratransit |
| Turn-by-turn navigation | Different product |
| Ride-hailing, payments | Out of scope, and payments imply revenue |
| Multi-city at v1 | Only Greater Cairo has data. Port Said in Phase 5 |

---

## What gets built first

v1 is **Cairo-only, shipped early**, so the `must` column is the release gate.

**The release gate — 18 stories:**

1. **Phase 2 — operability (5).** O-01, O-02, O-04, O-05, O-06. Unglamorous,
   and the reason the last two bugs cost days rather than minutes. Ship nothing
   publicly without them.
2. **Phase 3 — the app (13).** P-01 to P-04, P-06 to P-08, P-10, P-13 to P-17.
   **P-03** (microbus without a number) and **P-06** (no data for your city) are
   the two that most separate this from a generic trip planner; both are easy to
   skip and each makes the app quietly wrong if skipped.

**After v1:**

3. **Phase 4 — contributions and dashboard.** C-01 and C-04 first, then M-01 to
   M-04. Note C-04 (a second person confirming) is what makes the pipeline work
   without your constant attention.
4. **Phase 5 — data quality.** Metro line 3, Arabic for metro stops, a
   maintained fares table, Port Said.

### Known data holes v1 ships with

Stated here so the UI can be honest about them rather than pretending:

- **Metro line 3 is missing** — one of the busiest lines. Itineraries through it
  will route oddly or not at all.
- **Metro stops have no Arabic names** — 108 of them.
- **No fares at all**, by design.
- **Greater Cairo only.**
- **No service late at night** in the data, whatever reality is.
