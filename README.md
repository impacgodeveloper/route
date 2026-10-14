# Executive Fleet Mobility — Four Connected Flutter Workspaces (Prototype)

Frontend prototype for corporate fleet mobility: **Employee / Passenger**, **Driver**,
**Employer Admin** and **Fleet Manager Admin** — one Flutter repository, one shared local
database, one set of business rules. A change made in any workspace appears in the others
immediately. Target demo: **19 October 2026**.

> ⚠️ **Prototype / DEMO DATA.** No production backend, authentication, GPS, live traffic,
> OR-Tools, payments, SMS/push or emergency integration. All people, contacts, registrations
> and coordinates are fictional. Simulated features are labelled in the UI.

---

## Run

```bash
flutter pub get
flutter run -d chrome          # web — best for the two admin consoles
flutter run -d <android-device> # mobile — best for the Employee and Driver apps
flutter run -d windows          # requires Visual Studio C++ tools
```

Build: `flutter build web --release` (output in `build/web`).

## Verify

```bash
dart format lib test integration_test
flutter analyze                                   # → No issues found
flutter test --exclude-tags screenshot            # unit + widget + cross-app flow tests
flutter test test/screenshots --update-goldens    # optional: re-render UI screenshots to test/screenshots/out/
flutter test integration_test                     # needs a connected device/emulator
```

## Demo identities & role switching

The launcher (`/`) shows four workspace cards. Choosing one is a **demo convenience, not
authorization**. Use **Switch workspace** (consoles) or **Profile → Back to workspaces** (mobile).

| Workspace | Demo identity |
| --- | --- |
| Employee | E1 Asha Rao, E2 Kiran Mehta, E3 Neha Iyer, E4 Arjun Das (E4 has an optional demo password **`demo1234`**, shown on screen) — or search any active E1–E100 |
| Driver | DR1 Ravi Kumar (Vehicle C1), DR2 Priya Sharma (C2), DR3 Arif Khan (C3) |
| Employer Admin | C1 Corporate Services administrator |
| Fleet Manager | Shared fleet pool operator |

## Reset demo data

Launcher → **Demo tools** (sliders icon, top right) → **Reset demo data** → confirm.
This wipes all local edits in every workspace and restores the baseline. Seeding otherwise
happens **only on first run** — edits are never silently overwritten. Demo tools also show the
storage location / schema version, and a **"Simulate failed submissions"** switch that makes
incident/SOS submissions fail as if offline (to demo retry with preserved input).

## Baseline data (seeded once, anchored to the first-run date)

* Employer **C1** "C1 Corporate Services" — max arrival 9:30 AM, ₹18/km, EV target 50%.
* Employees **E1–E100** (E99, E100 inactive), pickups **PK01–PK12**, offices **G1–G4**,
  parking **P1–P10** (P1 = depot).
* Vehicles (IDs shown as "Vehicle C1…" to avoid confusion with employer C1):
  **C1** EV sedan, 4 seats incl. driver → **3** employee seats; **C2** ICE van 7 → 6; **C3** EV MPV 6 → 5.
* Drivers **DR1–DR3**, shifts from 6:00 AM.
* Trips in every state: TR-1001 (today, assigned, E1–E3 · DR1 · C1), TR-1002 (in progress),
  TR-1003 (delayed), TR-1004 (tomorrow, planned/unassigned), TR-1005 (cancelled),
  TR-1006 (tomorrow, assigned), TR-0991–0993 (completed + billed), TR-0994 (completed,
  **missing distance → billing blocked**).
* 12 bookings, 25+ notifications, 4 incidents, 3 billing lines, 3 inspections
  (passed / needs review / failed), 6 shifts, optimization profile OC-1 and runs
  **OR-1001** (feasible) and **OR-1002** (sedan-only → *No feasible assignment*).

## Suggested demo script (cross-app flows)

1. **Booking (B):** Employee E1 → Book → request for a future date → Fleet Manager → Trips &
   Dispatch → approve → create trip with DR1 + Vehicle C1 → Employee sees the assignment, Driver
   sees the trip, Employer sees it under Fleet Assignments.
2. **Capacity (C):** Fleet Manager → new trip with E1–E4 + Vehicle C1 → "Over capacity (3 seats)"
   → one-click switch to Vehicle C3.
3. **Driver day (D/E/F/G/L):** Driver DR1 → Start shift → Inspect C1 (fail a *critical* item to
   see the trip blocked + defect in Fleet Monitoring, or pass it) → Start TR-1001 → each stop:
   Arrived → Scan QR (demo scenarios) / T-PIN → Complete stop → drops → Complete trip with an end
   odometer → Employer → Billing shows the new line once (`km × ₹18`). Then Review & end shift.
4. **Optimization (H/I):** Fleet Manager → Route Optimization → E1–E4 → adjust weights → Run
   local demo optimizer → score, breakdown, explanation, alternatives → Apply (confirm) → trips
   appear for drivers/employees. Employer → Policies → EV target 100% → Fleet overview explains
   why it is not achievable.
5. **Incident / SOS (J):** Driver → Report issue (delay/breakdown) or SOS → Fleet Manager →
   Monitoring & Incidents → acknowledge/resolve; passengers receive a local notification. Every
   SOS screen states that no real emergency service was contacted.
6. **Reassignment (K):** Fleet Manager → trip detail → Reassign (reason required) → old driver
   loses it, new driver/employees notified, history + audit recorded.

## Architecture

```
lib/
  app/              bootstrap (BootstrapApp), router (GoRouter), Riverpod providers
  core/
    persistence/    LocalDatabase (typed tables, transactions), storage adapters (file / web / memory), migrations
    theme/          colours, tokens (8-pt spacing, radii, breakpoints), Material 3 theme (Inter)
    widgets/        design system: cards, badges, states, dialogs, tables, timeline, schematic map, shells
    demo/           Clock (System/Fixed), honest demo labels
    export/         CSV export (web download / native file)
    utils/          formatters (₹, Indian dates), CSV parser, Result type, validators
  domain/
    models/ enums/  20 typed entities with stable IDs
    rules/          capacity (driver + guard seats), trip state machine, inspection, geo/cost model,
                    116-parameter optimization catalog
    services/       assignment, booking, driver ops, verification (QR/T-PIN demo), incidents/SOS,
                    billing, roster import, optimization engine/pooling/EV target, metrics,
                    notifications, audit, session, support, location (simulated), map (schematic)
  data/
    repositories/   read-side repositories (TripRepository, AuthRepository, DataView)
    seed/           deterministic dataset + SeedManager (seed once / reset)
  features/
    launcher/ employee/ driver/ employer_admin/ fleet_admin/ shared/
test/  unit/ integration/ widget/ screenshots/   integration_test/ (on device)
```

* **Data flow:** widgets `ref.watch(dataProvider)` (a read model rebuilt after every committed
  transaction) and call `ref.read(servicesProvider).<service>`; widgets never write to storage.
* **Persistence:** native = JSON table files in the app-support folder (atomic writes);
  web = `localStorage`; tests = memory. Schema versioned with a migration hook. All
  multi-record changes (assignment, completion + billing, optimizer apply) are transactional.
* **Workspaces are separable:** each owns its route subtree (`/employee`, `/driver`,
  `/employer`, `/fleet`) and only depends on `core/`, `domain/`, `data/`.

## Simulated locally (clearly labelled in the UI)

Demo identity login · QR/T-PIN boarding credentials · vehicle position and "live" tracking
(derived from stop progress, with last-update/stale warnings) · schematic route maps on fictional
coordinates · distance/time/traffic model (ring road vs internal roads) · local demo optimizer
(deterministic heuristic, not OR-Tools/AI) · notifications (in-app only) · incident/SOS and
control-room contact (recorded locally) · "Paid (demo)" billing status · CSV export · camera
photo for inspections (placeholder) · "vehicle moving" safety lock (manual switch).

## Future backend / API work

Real authentication & role authorization, server persistence (e.g. PostgreSQL) and sync,
encryption/retention policies and backend validation, GPS/telematics and fleet hardware
integration, Google Maps routing & live traffic, OR-Tools solver, predictive scheduling models,
SMS/push delivery, payment/invoicing, emergency/control-room integration, real QR scanning with
signed credentials, multi-employer (C1–C10) onboarding. Integration points are the service and
repository interfaces (`LocationService`, `MapService`, `TripRepository`, `AuthRepository`,
`StorageAdapter`, `OptimizationService`, …) so UI code does not need rewriting.

## Known limitations

* Notification preference toggles are stored but do not yet filter the inbox.
* The schedule's holiday notices come from service-notice notifications (no holiday calendar).
* The demo day is anchored to the first-run date; after midnight, "today" scenarios become history
  — use **Reset demo data** to re-anchor.
* Windows desktop builds need Visual Studio C++ tools (not installed in the build environment).

See `IMPLEMENTATION_PLAN.md` for decisions, assumptions, stages and rule-to-code mapping.

---

## v2 — Client-architecture increment

What was added on top of the baseline (details: `GAP_ANALYSIS_V2.md`, `V2_DOMAIN_API.md`):

* **Employee input:** shift start/end (overnight supported), arrival deadline, pickup/drop
  tolerance (company default **±7 min**, per-employee override; separate from vehicle waiting
  time and route buffer), fictional source coordinates, optional self-declared gender (never used
  by any algorithm).
* **Employee travel preferences** (travel time, distance, detour, arrival reliability) scored by
  the local optimizer; run results explain how preferences affected the choice. Hard constraints
  always win.
* **Optimizer v2:** new weights (detour, pickup proximity, employee preferences), start
  parking/depot selection, guard pool, remedies when infeasible, reject/apply with guard names.
* **Car-to-employee mapping table** (vehicle, company, employees, guard Y/N, seat maths) — a
  validated view over trips, not a duplicate table.
* **Registered companies** with derived employee/shift/location counts; **contracts** (validity,
  agreed cars, cost per car, hard/soft limit); **fleet-company allocations** with shift windows.
* **Vehicle inventory** (RC no., engine no., colour, fuel type) and **driver records** (licence
  no. + expiry, email, address). Aadhaar and age are intentionally not collected.
* **Parking** P1–P10 with fictional lat/lng, capacity and derived occupancy.
* **Traffic & movement** (simulated provider only): scenario changes recalculate schedules,
  create reviewable route revisions and deduplicated local notifications.
* **Weekly/monthly billing cycles:** preview, idempotent "Run billing cycle (demo)", invoices
  (generated locally only), review/dispute/paid (demo).
* **Audit trail** of every significant transaction incl. rejected operations, with before/after
  summaries, filters and detail. Local prototype — not tamper-proof.

Migration: existing local data (schema v1) is upgraded to **v2** automatically on launch; new
fields and fixtures are only filled where missing — user edits and IDs are preserved.

v2 tests: `test/unit/v2_domain_test.dart`, `test/integration/v2_workflows_test.dart`
(workflows A–G + end-to-end smoke path).

---

## v3 — Client MoM increment (safety, telematics, analytics, dynamic booking)

| # | Feature | Where |
| --- | --- | --- |
| 1 | **Alcohol monitoring** — simulated breathalyzer + supervisor entry; a failed/inconclusive latest test blocks trip start and raises a safety incident; Fleet Manager clears the block, retest still required. Policy (on/off, threshold, check point) editable. | Driver `/driver/alcohol`, Fleet `/fleet/safety` |
| 1 | **Parking optimisation** — nearest parking to each vehicle's next first pickup within capacity; review and apply, drivers notified, audited. | Fleet `/fleet/parking` |
| 2 | **Speed / GPS / geofence / diagnostics** (simulated from trip progress) — live speed vs limit, "Slow down" / "Off planned route" banners, events (acknowledge / raise incident), geofence CRUD + map, DTC scan, demo simulation panel. | Driver active trip, Fleet `/fleet/telematics` |
| 3 | **SOS escalation chain** — FM, company admin, support (auto safety ticket) and driver alerted in-app; police and personal contacts are shown as "Not contacted — integration required". | Employee/Driver after SOS, Employer overview, Fleet `/fleet/safety?tab=sos` |
| 4 | **Analytics & indicative carbon credits** — KPIs, per-trip table, CSV export, disclaimer (not certified by Verra / Gold Standard). | Employer `/employer/analytics` |
| 5 | **Dynamic booking / roster** — "I'm not travelling", ad-hoc instant match (policy `autoMatchAdhoc`, max detour 25 min), released seats, absent riders greyed in driver manifest. | Employee, Driver, Employer, Fleet dispatch |

Decisions: alcohol monitoring is ON by default (seeded passing tests for DR1–DR3); analytics baseline is a solo ICE direct ride (editable in fleet policy).
**Employee passwords:** employer admins can switch on a *personal demo password* per employee (Employee detail → "Require personal demo password"); those employees must enter it at sign-in. Demo only, not real authentication.

Still simulated / out of scope: breathalyzer hardware, GPS/OBD telematics, police 112 / phone / SMS, certified carbon credits.

Tests: `test/unit/v3_domain_test.dart`, `test/widget/*/*_v3_*test.dart`; golden screenshots via `flutter test --tags screenshot --update-goldens` (images in `test/screenshots/out`).
API reference: `V2_DOMAIN_API.md` (v3 section).
