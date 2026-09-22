# The Masar board

Where work on the Flutter client is tracked:
**[github.com/users/WafikSleim/projects/2](https://github.com/users/WafikSleim/projects/2)**

Issues live in this repository; the board is a view over them. Nothing is
tracked only on the board — if it matters, it is an issue.

---

## Status — the only column that carries a rule

| Status | Means | Who moves it |
| --- | --- | --- |
| **Backlog** | Waiting on another issue, named in the body as *Blocked by #n* | Whoever closes the blocker |
| **Ready** | Nothing is stopping this. Pick it up today | — |
| **In progress** | Someone is on it | Whoever picked it up |
| **In review** | Shipped, but "done" is a claim the maintainer has to check | Maintainer, to Done |
| **Done** | Shipped, and verified | — |

### Backlog means blocked, not "later"

This is the one place the board's vocabulary is used differently from the
template's default. **Backlog here is not a holding pen for someday work** —
everything in it is blocked by a specific named issue, and "later" is
expressed with the `After v1` milestone instead.

The consequence is useful: `Ready` is an honest answer to "what can I start
right now", and an empty Backlog would mean nothing is waiting on anything.

### In review means *you* have to look

Not "a pull request is open". An item sits here when the work is finished and
pushed, but whether it is **right** rests on judgement that cannot be
automated or delegated. Two kinds:

1. **Native Egyptian Arabic.** Every Arabic string in the app was written by
   Claude. The test is not grammar — it is whether a Cairene would say it.
   Only the maintainer can apply that test.
2. **Behaviour on real hardware.** Nothing in this project has ever run on a
   phone. `flutter analyze` is clean, 63 Dart tests pass and a debug APK
   builds, but no device or emulator has been attached. Widget tests cannot
   see a plate colour vibrating on a dark ground, an Arabic IME, or a
   clipped attribution line.

Every issue in this column carries a **comment with a concrete checklist**.
Working through it and moving the item to Done is the whole job. Anything
that fails goes back as a comment rather than being patched around.

A closed issue is never in this column — if it needs review, it is open.

---

## Fields

| Field | Values | Set by | Meaning |
| --- | --- | --- | --- |
| `Status` | above | script + people | The rule above |
| `Area` | nine streams | script | Which part of the app |
| `Priority` | `P0` `P1` `P2` | script | See below |
| `Size` | `XS`–`XL` | script | From the user-story estimates where they exist |
| `Milestone` | `v1 - Cairo`, `After v1` | the issue | Native GitHub field |
| `Labels` | `app` `tech` `design` `blocked` | the issue | Native GitHub field |

### Priority

- **`P0` — the critical path.** In the v1 gate *and* blocking other issues.
  There are four, and every one of the ten Backlog items waits on one of
  them.
- **`P1`** — everything else in `v1 - Cairo`.
- **`P2`** — `After v1`. Wanted; not holding the release.

Shipped issues carry no Priority or Size. Estimating finished work would be
inventing numbers.

### Area

`Foundation` · `Journey` · `Storage & history` · `Places & search` · `Map` ·
`Notifications & tracking` · `Quality` · `Build & release` · `Design & data`

The one field added to the template. Nine streams over 34 items, so the board
reads as work rather than a list.

### Fields deliberately left empty

**`Start date` and `Target date`**, which is why the Roadmap view is bare.
Filling them would be inventing a schedule for a non-profit project with no
deadline and one maintainer. Fill them when a real date exists.

**`Estimate`** — `Size` already carries this, in a unit that does not pretend
to be hours.

---

## The critical path

Four issues, each in the v1 gate and each holding up others:

| | Unblocks |
| --- | --- |
| **#11** On-device storage | recents, saved trips, reminder scheduling |
| **#14** `places` table + `/places` | place search, map picking, the unified picker |
| **#19** Map rendering | the itinerary map, map picking |
| **#21** Notification infrastructure | reminders, post-trip prompt, background tracking |

**#14 was the largest single blocker** — three v1 `must` stories waited on it,
and it was backend work rather than app work. The backend half shipped on
2026-09-22: `GET /places`, `GET /places/reverse`, an `osm.places` table built
from the OSM extract by `scripts/build_places.py`, and a `docker-compose.yml`
that stands the database up. It sits in **In review** rather than Done for two
reasons — the category labels are Arabic copy shown to every user, and whether
searching «المعادي» ranks the district above the streets named after it is a
judgement about the city. The client half of P-10, P-18 and P-19 is still to
build, but it is no longer waiting on anything.

---

## Conventions for a new issue

- **Milestone is required.** `v1 - Cairo` or `After v1`. The milestone is how
  "later" is expressed, never the Backlog column.
- **Label `blocked` and write `Blocked by #n` in the body**, if it is. Both,
  so it is visible from the board and from the issue. Label a *blocker*
  `blocked` and the thing you should start first looks like the thing you
  cannot — that mistake has already been made once here.
- **State acceptance criteria, not a description.** Several issues in this
  repo exist to force a decision rather than to write code — `#11` picks a
  storage library, `#32` decides whether crash reporting is compatible with
  an app that promises to collect nothing. Say what "done" means.
- **Reference the user story** where one exists, by id (`P-15`).

---

## Re-syncing

[`scripts/project_board.py`](../scripts/project_board.py) sets Status, Area,
Priority and Size for every issue, adds any that are missing, and creates the
`Area` field if it has gone.

```bash
gh auth refresh -s project     # once; the default token lacks it
python scripts/project_board.py            # dry run
python scripts/project_board.py --apply
```

It reads the board first and writes only what differs, so running it after
filing new issues tops the board up rather than rebuilding it.

**It is the source of truth for the mapping, not for progress.** The sets at
the top of that file — `DONE`, `REVIEW`, `BLOCKED`, `P0` — are what it
enforces, so a status changed by hand on the board is reverted on the next
run. Move an issue for good by editing those sets in the same commit as the
work.

---

## The constraints behind the wording

Several issues are phrased oddly until you know these. They come from the
data licence and from what the data can honestly support, and they are why a
well-meaning change can make the product lie.

- **No revenue, ever.** No ads, no subscriptions, no paid tier. The Transport
  for Cairo data is CC BY-NC 4.0, so this is a licence condition rather than
  a preference — and the reason hosting is Oracle Always Free.
- **Never show a fare.** The source fares are from 2018. The API does not
  even request the fields.
- **Never imply a real-time vehicle position.** No such source exists in
  Egypt. Times come from recorded schedules, and the UI has to say so.
- **Mode colour comes from `agency_id`, never `route_type`.** The road feed
  types all 1,011 of its routes as `3`, microbuses included.
- **No route-number badge for paratransit.** Hundreds of microbus routes are
  named literally "Microbus", because real microbuses carry no number.
- **A walk-only itinerary is not a result.** The street network covers all of
  Egypt while the transit feeds cover Greater Cairo, so a walk looks exactly
  like an answer.
- **OSM (ODbL) and TfC (CC BY-NC) must never be merged** into one derived
  database.

The middle four are enforced in
[`app/lib/core/presentation/trip_presenter.dart`](../app/lib/core/presentation/trip_presenter.dart)
and covered by tests, because each fails *plausibly* — none of them looks
like a bug on screen. See [design-system.md](design-system.md).
