# RouteMatic v3 — status & pending work

Snapshot: 2026-10-13. Work paused here to save tokens; resume from the "Pending" list.

## Current health (verified)

| Check | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test --exclude-tags screenshot` | **356 / 356 pass** (unit, integration, widget, route crawler at phone / large-text / tablet / desktop) |
| `dart format lib test integration_test` | Clean |
| `flutter build web --release --no-wasm-dry-run` | Built successfully |

All v1/v2 functionality is unchanged and still covered by the existing tests.

## v3 (client MoM) — what is done

Domain layer (complete, unit-tested in `test/unit/v3_domain_test.dart`): fleet policy, alcohol tests, geofences, vehicle events/telematics, parking planner, SOS escalation, analytics & carbon, dynamic matching. Schema v3 migration + fixtures.

| # | Feature | Employee | Driver | Employer Admin | Fleet Manager |
|---|---|---|---|---|---|
| 1 | Alcohol monitoring | – | Breathalyzer step (`/driver/alcohol`), start blockers, Activity history | – | `/fleet/safety` policy editor + alcohol log + clear block |
| 1 | Parking optimization | – | New home parking shown on shift summary | – | Parking page "Optimize parking placement" → apply |
| 2 | Speed / GPS / geofence / diagnostics | – | Live speed vs limit, "Slow down" / "Off planned route" banners | – | `/fleet/telematics` (live, events ack/incident, simulation, scan, geofence CRUD + map); vehicle diagnostics panel |
| 3 | SOS escalation | Chain status after SOS | Chain status after SOS | Overview "Open SOS alerts" + acknowledge | `/fleet/safety?tab=sos`, chain in Monitoring |
| 4 | Analytics & carbon credits | – | – | `/employer/analytics` (KPIs, credits w/ disclaimer, chart, per-trip table, CSV), Overview card | – |
| 5 | Dynamic booking / roster | "I'm not travelling", ad-hoc instant match | Absent riders greyed in manifest | Absences on assignments, utilization | Dispatch "Find seat in existing trip", released seats, trip-detail absences |

Fixes made in this pass:
- `TelematicsPage` / `SafetyPage`: links to another `?tab=` while already on the page now switch tab (`didUpdateWidget`).
- `fleet_admin_test` sidebar test scrolls the (now longer) sidebar.
- `fleet_v3_telematics_test` assertions corrected (speed shown on card + map; clear the right DTC row).
- v3 routes added to `test/widget/route_crawler_test.dart`.

## Pending (not started / unfinished — do later)

1. **Screenshots for v3**: Driver and Fleet screenshot tests (`test/screenshots/driver_screens_test.dart`, `fleet_screens_test.dart`) do not yet include alcohol, telematics, safety or parking-optimizer screens. Employee/Employer were updated. Run with `flutter test --tags screenshot` and review images in `test/screenshots/out`.
2. **Per-app visual review** of the new v3 screens on a real browser/phone (tests pass, but no human-eye review of layout polish yet).
3. **Docs**: add a v3 section to `README.md` and `IMPLEMENTATION_PLAN.md` (`V2_DOMAIN_API.md` already has the v3 API).
4. **Android build** (`flutter build apk`) and **on-device integration test** (`integration_test/app_test.dart`) not run.
5. **Optional employee individual password policy** — today employees still pick their ID on the role sign-in (E4 has a password). Decide if every employee needs a personal password.
6. **Real integrations (out of scope for the prototype, clearly labelled in UI)**:
   - Breathalyzer device (currently simulated scenarios + supervisor entry).
   - GPS / OBD telematics (simulated from trip progress).
   - Police 112 / phone calls / SMS for SOS (shown as "Not contacted — integration required").
   - Carbon credits are indicative only — require eligibility, verified measurement and certification (Verra / Gold Standard).

## Decisions taken (keep in mind)

- Alcohol monitoring is ON by default; seeded passing tests today for DR1–DR3 so the normal flows still work. Latest test of the day must be a pass; a fail raises a safety incident and puts trips on "needs attention"; FM clear lifts the block but a retest is still needed.
- Auto-match of ad-hoc bookings is policy-controlled (`autoMatchAdhoc`), max added detour 25 min.
- SOS chain: FM, company admin, support (auto safety ticket) and driver alerted in-app; police shown but not contacted.
- Analytics baseline = solo ICE direct ride (editable in the fleet policy).

## How to resume

```
flutter analyze
flutter test --exclude-tags screenshot
flutter run -d chrome --web-port 8080
```
Then work through the Pending list from the top.
