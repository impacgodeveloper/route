# Gap Analysis — Incremental Client-Architecture Requirements (v2)

Source: `RouteMatic_Incremental_Client_Architecture_Claude_Prompt.md`.
The three handwritten images were **not attached**; their content is taken from the
textual description in that prompt. Baseline: `Executive_Fleet_Mobility_Four_Flutter_Apps_Claude_Implementation_Spec.md`.

| # | Requirement | Existing (v1) | Gap → v2 decision |
|---|---|---|---|
| 3.1 | Employee name, phone, ID, company ID | ✅ `Employee` | — |
| 3.1 | Source/pickup + coordinates | Pickup `Location` with fictional plane km (`demoX/Y`) | Add fictional **lat/lng** to `Location` (derived for seed; editable, validated). Employee keeps reusable pickup reference. |
| 3.1 | Shift start / end | Only `shiftLabel` + required arrival | Add `shiftStartMinutes`, `shiftEndMinutes` (overnight = end < start). Arrival deadline = min(required arrival, shift start, employer max). |
| 3.1 | ±7 min pickup/drop tolerance | Param `pickup_wait_tolerance_min` (= vehicle **waiting** time, 5 min) | New, separate **pickup/drop tolerance**: employer default 7 min, optional per-employee override (0–30). Waiting time param untouched. |
| 3.1 | Gender/sex | — | Optional, **self-declared**, defaults "Not specified"; never used by any algorithm or inferred from names. |
| 3.2 | Time/distance preferences | Only `TransportPreference` (vehicle type/EV) | Add per-employee importance levels (0–3) for travel time, distance, detour, arrival reliability; *pickup proximity* shown as configurable but has no effect while pickups are always at the registered source point. |
| 3.3 | Weights: time, distance, detour, proximity, reliability, utilization, cost, EV, customer pref | 9 weights (no detour/proximity/employee-pref) | Add `detourWeight`, `pickupProximityWeight`, `employeePreferenceWeight`; "punctuality" relabelled *Arrival reliability*. Runs persist preference summary, start parking, deadhead, guard source and remedies. |
| 4 | Weekly/monthly billing cycle, automatic raise | Per-trip billing line at completion | Keep per-trip lines; add `Invoice` grouping per period (Mon–Sun weeks, calendar months, local dates), idempotent **Run billing cycle (demo)**, app-open due-cycle banner, history & audit. |
| 5 | Real-time traffic movement | Static peak factors | `TrafficProvider` interface + persisted **simulated** scenario; traffic board (Fleet full, Employer read-only); scenario change → `RouteRevision` proposals, deduplicated notifications, apply workflow that never touches completed stops. |
| 6 | Car-to-employee mapping (vehicle, company, employee list, guard Y/N) | `Trip` already = vehicle + employer + employees + driver + guard + route for a time window | **Reuse Trip** (no duplicate table). Mapping table is a validated view over trips with seat maths and actions. Guard requirement now a **hard** rule (guard reference or vehicle guard required). |
| 7 | Operator assignment workflow | Dispatch wizard + optimizer | Queue → "Optimize selected" → proposal (mapping preview, remedies when infeasible) → confirm → atomic apply. |
| 8 | Registered companies + derived counts | `Employer` = company (C1 only) | Reuse `Employer`; add company shift windows, register/deactivate, derived employee/shift/location counts. |
| 9 | Fleet-company mapping + shift windows | — | New normalized `FleetAllocation` (company × vehicle/driver × time window); overlap detection across companies; enforced by assignment + optimizer. |
| 10 | Contracts (doc ref, validity, car count, cost per car, contact) | — | New `Contract`; effective status by local date; hard/soft vehicle limit enforced in assignment + optimizer; history preserved. |
| 11 | Vehicle inventory (reg, RC, engine no., colour, fuel type, seats) | reg, seats, propulsion | Add RC no., engine no., colour, fuel type, `active`; uniqueness validation. |
| 12 | Driver dictionary (licence, Aadhaar, phone, email, address, sex, age) | contact only | Add licence no. + expiry (expired → cannot assign), email, address, optional self-declared gender, `active`. **Aadhaar and age deliberately omitted** (not needed for any workflow; sensitive). |
| 13 | Parking spots: ID, location, coordinates, capacity | P1–P10 with capacity, plane coords | Add lat/lng; occupancy derived from vehicles' home parking; capacity validation; parking selectable as optimizer start point. |
| 14 | Audit trail of every transaction | `AuditEvent` (summary only) | Add before/after change summary, outcome (success/rejected/failure), reason, related IDs, simulated flag; audit rejected assignments/billing; demo reset audited; shared audit view with filters. |
| 16 | Migration | Schema v1 | **Schema v2** migration backfills new fields and inserts new fixtures without touching existing records/IDs. |

Conflicts & resolutions
* ±7 min tolerance vs existing 5-min *waiting* parameter → different concepts; both kept.
* Handwritten mapping example (vehicle C1, company 123, [E1, E3, E4, E9]) is illustrative only; baseline IDs kept.
* Vehicle C1 seats 3 employees (4 incl. driver) — the example list of four employees would be rejected by the capacity rule; validator explains this.
