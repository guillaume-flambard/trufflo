# AGENTS.md — Trufflo

Native iPhone app: Swift, SwiftUI, SwiftData, Core Location, MapKit.
The Xcode project exists. Do not recreate it.

## Layout

| Path | Content |
|---|---|
| `trufflo/` | App sources: `Data/`, `Domain/`, `Features/` |
| `truffloTests/` | Swift Testing, unit + integration |
| `truffloUITests/` | XCTest UI journeys |
| `TruffloFast.xctestplan` | Unit target only (default plan) |
| `TruffloFull.xctestplan` | Unit + UI targets |
| `PRD.md` | Product requirements, source of truth for scope |

Layering: `UI -> Feature/Domain -> services -> SwiftData / CoreLocation`.
Domain and DTO files never import SwiftUI or SwiftData.

## Test execution policy

Do not run the complete Xcode test suite after every change.
Use the smallest relevant test scope.

A change of 10 lines must never trigger 5 minutes of tests.

### FAST LOOP: after a local implementation change

1. Run only the directly affected tests.
2. Build the affected target if needed.
3. Do not run UI tests unless the change affects a critical user journey.

Target duration: seconds, not minutes.

Measured 2026-10-04 on Xcode 27 / iPhone 17e / iOS 27.0:

| Command | Wall clock | Test execution |
|---|---|---|
| `build-for-testing` (TruffloFast) | 17 s | — |
| `test-without-building` (TruffloFast), simulator cold | 61 s | 2.6 s |
| `test-without-building` (TruffloFast), simulator warm | 16 s | 1.9 s |
| `test` (TruffloFull) | 90 s | 1.5 s unit + 76 s UI |

The tests are not slow; the invocation is. 65 unit tests run in under 2 s, while
the three UI tests alone cost 76 s because each one boots and installs the app
on its own. Measured individually from a cold simulator: the lightest journey is
69 s, the profile-edit plus walk-delete journey is 94 s, so a journey costs about
25 s of interaction on top of the launch. Leave the simulator booted and reuse
the build, otherwise every loop pays 45-60 s of boot and install overhead.

Onboarding is gated by the same `--uitesting` launch argument the app already
uses to pick an in-memory store. Without that gate the first-run full screen
cover hides the app and all three journeys fail on a clean simulator.

Build once per edit session, then reuse the result:

```bash
xcodebuild build-for-testing \
  -scheme trufflo -testPlan TruffloFast \
  -destination 'platform=iOS Simulator,name=iPhone 17e'
```

```bash
xcodebuild test-without-building \
  -scheme trufflo -testPlan TruffloFast \
  -destination 'platform=iOS Simulator,name=iPhone 17e'
```

### FEATURE CHECK: when a complete feature is finished

- Run all tests of the affected feature.
- Build the application.
- Run only the UI tests related to that feature.

### FULL SUITE: run only when

- a milestone ends, before declaring it DONE;
- before a merge or a release;
- shared infrastructure changed: schema, migration, persistence, scheme,
  test plan, app entry point.

```bash
xcodebuild test \
  -scheme trufflo -testPlan TruffloFull \
  -destination 'platform=iOS Simulator,name=iPhone 17e'
```

#### Five journeys need host setup, not two

`TruffloFast` is the unit gate and runs anywhere. Of the eight UI journeys,
only three touch no location at all and need nothing but a booted
simulator: `testCreateDogAndRecordManualWalk`,
`testEmptyJournalStateAndGlobalErasure` and
`testEditDogProfileAndDeleteSingleWalk`.

The other five start a real GPS session, so they need host-side state: the
location permission granted, and a simulated position on the simulator.
Both are set with `simctl`, which does not exist inside the simulator.
A bare `xcodebuild test -testPlan TruffloFull` therefore leaves five
journeys red, and that failure is a missing precondition, not a product
defect. Do not "fix" it by weakening an assertion or skipping a test.

```bash
tools/sim/gps-journeys.sh            # the five GPS journeys, each isolated
tools/sim/gps-journeys.sh manual     # the three without location
tools/sim/gps-journeys.sh all        # everything
tools/sim/gps-journeys.sh background # one named journey
```

Each journey runs in its own `xcodebuild` invocation. That matters because
the revocation journey revokes location for the whole simulator and
starves whatever runs after it, so they must never share an invocation.

The script boots a simulator if none is running, which is the state of a
CI runner, and reads each verdict from the journal because `xcodebuild`
both exits 0 when it ran nothing and sometimes never returns after a UI
journey.

A milestone is not verified until `TruffloFast` and this script have both
been run.

### Rules

- Never repeatedly launch the full simulator/UI suite during implementation.
- If tests are slow, investigate the cause instead of accepting the time.
- Never delete a failing test, skip it, or weaken an assertion to get green.
- Do not weaken a requirement to make a suite pass.

## Test suites

| Target | Framework | Files | Cost |
|---|---|---|---|
| `truffloTests` | Swift Testing | WalkDomainTests, TrackWriterTests, StorageTests, MigrationTests, TrackAccumulatorResumeTests | low |
| `truffloUITests` | XCTest UI | StarterUITests | high: simulator boot, app relaunch, UI automation |

### Narrowing a run

The `@Test` functions are declared at file scope, so they carry no suite name
and a suite selector does not match:

```bash
# WRONG: runs 0 tests, yet still reports ** TEST EXECUTE SUCCEEDED **
xcodebuild test-without-building -scheme trufflo -testPlan TruffloFast \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -only-testing:truffloTests/WalkDomainTests
```

Selecting by function name does match:

```bash
# RIGHT: runs exactly 1 test
xcodebuild test-without-building -scheme trufflo -testPlan TruffloFast \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -only-testing:'truffloTests/recordingAccruesConfirmedTime()'
```

A wrong selector is silent: xcodebuild exits 0 and prints `Executed 0 tests`.
Read the `Test run with N tests` line, never the exit code.

Until the tests are grouped inside `@Suite struct` there is no per-file scope.
Grouping them is worth doing when a per-file scope is actually needed; do not do
it as a speculative refactor.

### UI tests: keep to these journeys

- create dog, record a manual walk, walk appears in the journal;
- empty journal state, global erasure;
- edit a dog profile, delete a single walk, journal is left consistent;
- start a GPS walk, pause, resume, finish, the walk appears in the journal;
- kill the app mid-walk, relaunch, the walk is interrupted with its three exits;
- send the app to the background for two minutes mid-walk, the timer and the
  track keep advancing;
- revoke location mid-walk, the walk interrupts without inventing distance.

Do not add a UI test for every button. Screens are covered by Swift Testing,
domain tests, previews and a manual simulator check.

## Core Location seam

Never drive real Core Location from unit tests. Put it behind a protocol:

```swift
protocol LocationProviding: Sendable {
    func start() async
    func stop() async
}
```

Production uses a Core Location adapter. Tests use a fake that emits fixes:

```swift
let location = FakeLocationProvider()
location.emit(latitude: 48.8566, longitude: 2.3522)
```

The pipeline GPS point -> distance -> walk state -> persistence must be testable
in milliseconds. Real Core Location belongs to a few integration tests plus
verification on a physical device, including with the screen locked.

## Definition of done

A feature is DONE when its acceptance criteria are demonstrated, not when it
renders. Each completed feature carries: domain behaviour, SwiftUI state,
persistence behaviour, error and empty states, accessibility, and the relevant
tests.
