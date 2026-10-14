# Implementation Plan & Progress — Executive Fleet Mobility

Source of truth: `Executive_Fleet_Mobility_Four_Flutter_Apps_Claude_Implementation_Spec.md`.
Prototype target: **19 October 2026**.

## Environment (verified)

| Item | Version |
| --- | --- |
| Flutter | 3.41.6 (stable) |
| Dart | 3.11.4 |
| State management | flutter_riverpod 2.6.1 (3.x not compatible with the resolved set) |
| Routing | go_router 17.5.0 |
| Other | intl 0.20, path_provider 2.1, web 1.1, qr_flutter 4.1, file_picker 13.1 |

No repository existed; a fresh null-safe Flutter project (`executive_fleet`) was created for
Android, iOS, Web and Windows.

## Key decisions & assumptions

1. **One repository, four workspaces** behind a launcher (`/`), each with its own route subtree
   (`/employee`, `/driver`, `/employer`, `/fleet`) so they can later be split into separate builds.
2. **Persistence.** A local relational store (`LocalDatabase`): typed tables, stable IDs,
   all-or-nothing transactions, schema versioning + migration scaffold. Tables are serialized
   through a `StorageAdapter`:
   * native → JSON table files in the app-support directory (atomic temp-file rename),
   * web → browser `localStorage`,
   * tests → in-memory.
   SQLite (sqflite/drift) was not used because the web consoles need a verified web adapter and
   drift/sqflite-web require extra worker/wasm assets; the adapter interface allows swapping to
   SQLite or a backend later without UI changes. *(Documented assumption.)*
3. **Shared reactive data.** `databaseProvider` (ChangeNotifier) → `dataProvider` (read model,
   rebuilt on every commit) → every workspace updates instantly. Widgets never write to the DB;
   all writes go through domain services (`servicesProvider`).
4. **Seat convention.** `totalSeats` includes the driver. Employee capacity =
   `totalSeats − 1 driver − guard seats`. Vehicle C1 (4-seat EV sedan) therefore carries 3
   employees — assigning E1–E4 to C1 is rejected by validation and C3/C2 are suggested.
5. **Demo day anchor.** Seed data is anchored to the date of first run (or last reset) so
   "today" scenarios stay coherent; events are never dated after the seeding moment.
6. **Arrival deadlines.** Employee required arrival is capped at the employer maximum arrival
   time; routes are planned backwards from the tightest deadline minus a buffer.
7. **Optimizer.** Deterministic local heuristic: cluster-first/route-second with exhaustive
   assignment search for small selections (greedy regret insertion for larger ones), scored
   pickup permutations, earliest-deadline drop ordering, ring-road vs internal-road comparison.
   Hard constraints are filters, never traded for score. Labelled "local demo optimizer".
8. **Pooling defaults.** Max pickup detour 12 km and destination gap 10 km (catalog params) so
   the E1–E4 core example is poolable while genuinely distant pairs (e.g. E3/E4) are not.
9. **Booking ≠ assignment.** Requests are requested/waitlisted until a Fleet Manager approves
   and assigns them.
10. **Billing** is generated once per completed trip with a valid non-negative distance
    (odometer end − start). Missing distance sets `billableStatus = missingDistance` and must
    be recorded explicitly (with a note) before billing.

## Stages

| Stage | Scope | Status |
| --- | --- | --- |
| 1 Foundation | project, theme/design system, router, launcher, persistence, seed, shells | ✅ |
| 2 Models & persistence | 20 entities, enums, repositories, seed, migrations, rules | ✅ unit tested |
| 3 Admin vertical slice | employer employees, FM vehicles/drivers/assignment | ✅ |
| 4 Driver workflow | attendance, inspection, trip, stops, boarding, completion, incident/SOS | ✅ |
| 5 Employee workflow | home, booking, trips, tracking, pass, notifications, profile/support | ✅ |
| 6 Employer policies/billing | roster import, arrival policy, preferences, billing, reports | ✅ |
| 7 Optimization | weights, hard constraints, pooling, EV target, catalog (116 params), runs | ✅ |
| 8 Remaining modules & polish | locations, reports, incident queue, settings, audit, export, states | ✅ |
| 9 Verification | format, analyze, unit/widget/integration tests, web build | see README |

## Business rule coverage (spec §11) → implementation

| # | Rule | Where |
| --- | --- | --- |
| 1 | No overlapping driver/vehicle windows | `AssignmentService.validate`, `OptimizationEngine` |
| 2 | Vehicle available / not maintenance | `AssignmentService`, `vehicleEligibility` |
| 3–4 | Capacity incl. driver + guard seats | `CapacityRules` |
| 5 | Hard constraints | engine filters + validation errors |
| 6 | Cannot start cancelled/unassigned/inspection-blocked | `DriverOpsService.startBlockers` |
| 7 | Trip status transitions | `TripStateMachine` |
| 8–9 | No duplicate boarding; failed QR/T-PIN never verifies | `VerificationService`, `verifyAndBoard` |
| 10–11 | Deboarding reconciliation; completion requirements / authorized exception | `departStop`, `completionReport`, `completeTrip` |
| 12–13 | Billing once; missing distance blocks | `BillingService` |
| 14 | Booking ≠ assignment | `BookingService` |
| 15 | Reassignment history + audit | `AssignmentService.commitInTx` |
| 16 | Cancelled trip not active for driver | `cancelTrip`, `startBlockers` |
| 17 | EV preference never overrides hard constraints | engine scoring after filtering |
| 18 | SOS demo-only | `IncidentService.raiseSos`, `DemoLabels.sosDemo` |
| 19 | Notifications link to entities | `relatedEntityType/Id` + unit test |
| 20 | Reset requires confirmation | launcher Demo tools |
| 21 | Validation preserves input | `Result`/`Err` + inline banners |
| 22 | Stable IDs, no duplicate seeding | `SeedManager`, `Txn.insert` |
| 23 | Deactivation preserves history | `EmployeeService.setActive` |
| 24 | Transparent billing inputs | `BillingCalculation.explanation` |

---

# v2 — Client-architecture increment

Source: `RouteMatic_Incremental_Client_Architecture_Claude_Prompt.md` (the three handwritten
images were not attached; requirements are taken from the prompt's description of them).
Gap analysis and conflict resolutions: `GAP_ANALYSIS_V2.md`. Domain API: `V2_DOMAIN_API.md`.

| Stage | Scope | Status |
| --- | --- | --- |
| 1 Audit | gap analysis vs v1 code | ✅ `GAP_ANALYSIS_V2.md` |
| 2 Domain & migration | models, enums, schema v2 migration (fills only missing data), fixtures shared by seed + migration | ✅ unit tested (v1→v2 migration test) |
| 3 Employee fields & preferences | shift start/end (overnight), ±tolerance (company default 7, per-employee override), self-declared gender (unused by logic), travel preferences scored by optimizer | ✅ domain · UI in Employee/Employer apps |
| 4 Company, contract, fleet mapping | company register/deactivate + derived counts, contracts (validity, hard/soft car limit), fleet-company allocations (overlap detection), vehicle inventory, driver records (no Aadhaar/age), parking lat/lng + occupancy | ✅ domain · UI in Fleet console |
| 5 Mapping & assignment | car-to-employee mapping = validated view over Trips; guard is a hard rule; contract + allocation enforced in assignment AND optimizer | ✅ |
| 6 Traffic movement | `TrafficProvider` (simulated only), board, scenario → `RouteRevision` proposals, dedup alerts, apply never touches completed stops | ✅ |
| 7 Billing cycle | weekly (Mon–Sun) / monthly periods on local dates, preview with exclusion reasons, idempotent invoice generation (+ supplementary), invoice status flow | ✅ |
| 8 Audit trail | outcome/changes/reason/related/simulated; rejected operations audited; demo reset audited; shared filterable view | ✅ |
| 9 Verification | format, analyze, unit + workflow + widget tests, web build | see README |

New hard constraints (never overridden by weights or preferences): guard availability, driver
licence validity, vehicle/driver/company active, contract coverage and hard car limit,
fleet-company allocation windows, deadline = min(required arrival, shift start, employer max).

# v3 — Client MoM increment

| Stage | Scope | Status |
| --- | --- | --- |
| 1 Domain & migration | fleet policy, alcohol tests, geofences, vehicle events/telematics, parking planner, SOS escalation, analytics & carbon, dynamic matching; schema v3 migration + fixtures | ✅ `test/unit/v3_domain_test.dart` |
| 2 Alcohol & parking | driver breathalyzer step + start blockers; FM safety page; parking optimizer | ✅ |
| 3 Telematics | live speed/GPS banners, events, geofence CRUD + map, diagnostics | ✅ |
| 4 SOS chain | in-app escalation, auto support ticket, acknowledgement | ✅ |
| 5 Analytics & carbon | employer analytics page, CSV, disclaimer | ✅ |
| 6 Dynamic booking | absences, ad-hoc instant match, released seats | ✅ |
| 7 Per-employee demo password | employer toggle on employee detail | ✅ |
| 8 Verification | analyze, 356+ tests, screenshots (all four apps), web build, Android build | see README |

Rules: failed alcohol test → incident + trips "needs attention"; latest test of the day must pass; SOS police/phone/SMS never contacted automatically; carbon credits indicative only.
