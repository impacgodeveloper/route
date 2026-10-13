# Executive Fleet Mobility

## Complete Flutter Frontend Implementation Specification for Claude

**Purpose:** Build four connected Flutter frontend applications with
local persistence, realistic seed data, end-to-end workflows, and no
production backend in this phase.\
**Source:** MoMs dated 11 October 2026 and 12 October 2026, plus agreed
passenger and driver requirements.\
**Prototype target:** 19 October 2026.

# 0. Instructions to Claude --- Read First

Act as a principal Flutter engineer, product architect, UX designer, and
QA lead. Implement actual working code in the current repository, not
merely a plan or static mockups.

Build four user-facing interfaces sharing the same domain models, design
system, local data layer, and business rules:

1.  **Employee / Passenger App** --- mobile-first.
2.  **Driver App** --- mobile-first and safety-focused.
3.  **Employer Admin Console** --- responsive desktop/tablet web.
4.  **Fleet Manager Admin Console** --- responsive desktop/tablet web.

For this frontend-only prototype, keep them in one Flutter repository
with a polished role/workspace launcher. Share one local database and
repository layer so changes in one workspace immediately appear in the
others. Structure the code so interfaces can later be built/deployed
separately.

**Every primary button, form, tab, filter, row action, and main journey
must work.** Do not deliver inert buttons or disconnected hardcoded
screens. Do not stop at a starter shell.

Before coding: 1. Inspect the repository and existing Flutter/Dart
versions. 2. Preserve useful existing code; avoid overwriting unrelated
work. 3. If no project exists, create a stable Flutter project with null
safety. 4. Check package compatibility for the actual environment; do
not guess APIs. 5. Create/update `README.md`, `IMPLEMENTATION_PLAN.md`,
and this specification. 6. Build and verify in stages. Run formatter,
analyzer, and tests; fix errors. 7. At completion, report implemented
features, run instructions, test results, and simulated integrations. 8.
If a requirement is ambiguous, use the conservative behavior specified
here, document the assumption, and do not invent a real-world result.

**No production backend in this phase.** All editable data is local.
Mark simulated integrations clearly. Never claim a real booking, GPS
fix, QR verification, dispatch message, payment, or emergency
notification happened if it was only simulated.

# 1. Requirements From the Two MoMs

## 1.1 MoM --- 11 October 2026

-   Corporate fleet management for a prospective client with
    approximately 100 cars and plans to add another 100.
-   Reduce reliance on third-party fleet platforms and improve
    operational efficiency and margins.
-   Support corporate clients and future integration with existing fleet
    hardware.
-   Pool employees from multiple companies into shared cabs when
    feasible.
-   Consider pickup locations, arrival deadlines, route efficiency,
    vehicle capacity, and service requirements.
-   Choose EV versus internal-combustion vehicles based on operating
    cost and requirements.
-   Compare routes, including ring roads and internal roads, with
    traffic and travel-time estimates in a future integration.
-   Configure cost-minimization versus on-time-arrival priorities.
-   Apply applicable regulatory and safety constraints.
-   Account for security guard requirements when configured for a trip,
    including seat/capacity reduction.
-   Explore shared corporate shuttle operations.
-   Candidate technologies: Google OR-Tools for routing/scheduling,
    PostgreSQL for future persistence, Google Maps for mapping/traffic,
    and pretrained Hugging Face models for predictive scheduling.
-   Explore historical pickup/arrival patterns, recurring delays, and
    schedule improvement.
-   Formal wireframe review/sign-off before software development.
-   Roadmatic is a visual reference, not something to copy.
-   Prototype target: 19 October 2026.
-   Project leads: Tata Manisha and Gonthina Bhushan. Technical
    documentation: Srinath Pentapati.

## 1.2 MoM --- 12 October 2026

-   Initial employer: Company **C1**.
-   Employees **E1--E100**.
-   Vehicles **C1--C3** and drivers **DR1--DR3**.
-   Shared, non-dedicated fleet pool.
-   Employer uploads employee roster and defines maximum permitted
    arrival time.
-   Billing is calculated after trip completion and linked to trip
    distance.
-   Employer is the parent entity; employees, trips, drivers, and
    vehicles are associated with the appropriate employer/operational
    context.
-   Do **not** use nearest-path routing as the primary optimization
    strategy.
-   Build configurable mathematical weights/constraints; plan for a
    catalog of at least 100 optimization parameters. The prototype must
    not pretend all 100 are connected to live data.
-   Core route example connects employee pickups E1--E4 and destinations
    G1--G4.
-   Support dynamic scheduling and customer-specific requirements.
-   Employee UI shows assigned driver, vehicle, and location
    information; optional password-based login only if configured.
-   Driver schedule starts at 6:00 AM where applicable, with vehicle
    allocation, employee roster, route map, and pickup count.
-   Fleet Manager configures vehicle allocation, vehicle type, luxury
    preference, cost constraints, driver details, availability, and EV
    percentages.
-   Example customer policy: 50% EV allocation.
-   Two distinct admin consoles: Employer Admin and Fleet Manager Admin.
-   Future scale concepts include parking locations P1--P10, companies
    C1--C10, and employees E1--E10.
-   Focus on automation, configurability, accurate distance-based
    billing, efficient utilization, and scalability.

## 1.3 Four required interfaces

**Employee:** login/demo identity, profile, roster, assigned
driver/vehicle, pickup/destination, booking request where allowed, trip
details, shuttle schedule, tracking demo, notifications, e-pass/T-PIN
demo, boarding status, support, trip history, preferences, safety
assistance.

**Driver:** login, shift attendance, vehicle assignment, inspection,
schedule, assigned trips, route/navigation demo, stop arrival, passenger
manifest, QR/T-PIN demo verification, boarding/deboarding, trip
completion, delay/route issue, breakdown, incident, SOS, shift summary,
activity, support.

**Employer Admin:** overview, roster import, employee management,
arrival-time policies, pickup locations, transport preferences,
assignment visibility, completed-trip billing, distance-rate
configuration, reports, customer-specific policies.

**Fleet Manager Admin:** fleet overview, vehicle/driver management,
availability, assignment to employers/trips, vehicle types/luxury/EV
mix/capacity, driver schedule, employee pooling, route planning,
optimization configuration and explanation, parking/stops, monitoring,
incidents, utilization, operational reports.

## 1.4 Explicitly out of scope

No real backend, production SSO, cloud database, real-time telemetry,
live dispatch, SMS/push delivery, payment processing, real OR-Tools
execution, live Google Maps traffic, or Hugging Face inference unless
working infrastructure already exists and is approved. Use clean
interfaces and honest local simulations.

# 2. Architecture and Repository

Use one shared Flutter project unless the existing repository requires a
compatible adaptation.

Suggested structure (adapt to actual code; do not create empty files
just to match a tree):

``` text
lib/
  main.dart
  app/ (bootstrap, router, launcher, configuration)
  core/
    theme/ (colors, typography, spacing, radii, theme)
    widgets/ (buttons, badges, dialogs, empty/error/loading states, fields, tables)
    persistence/ (database, seed manager, migrations)
    demo/ (demo banner, fake integrations, demo clock)
    utils/ (formatters, validators, result types)
  domain/
    models/
    enums/
    rules/
    services/
  data/
    repositories/
    local/
  features/
    launcher/
    employee/ (auth, home, trips, booking, roster, tracking, pass, notifications, support, profile, safety)
    driver/ (auth, home, attendance, vehicle check, trips, navigation, stops, passengers, incidents, emergency, shift summary, support, profile)
    employer_admin/ (dashboard, employees, roster import, policies, locations, assignments, billing, reports, settings)
    fleet_admin/ (dashboard, vehicles, drivers, assignments, pooling, routes, optimization, parking, monitoring, incidents, reports, settings)
test/
  unit/
  widget/
  integration/
```

Architecture rules: - Separate UI, application/state logic, domain
rules, and persistence. - Use repository interfaces. - Widgets must not
write directly to the database. - Use typed models, enums, and stable
IDs. - Prefer Riverpod if compatible; otherwise use the existing state
management consistently. - Use declarative routing such as GoRouter if
compatible. - Avoid giant screens, global mutable state, duplicated
models, and copied business logic. - Use shared repositories for all
four workspaces. - Centralize date/time/currency formatting. - Use
Indian Rupees (₹) and Indian date/time conventions for demo unless a
setting overrides them.

## Local persistence

Use a local relational database because entities are related and
cross-app changes must be consistent. Prefer SQLite with a maintained
Flutter-compatible adapter (e.g., sqflite on supported mobile platforms,
or Drift if compatible). If web is required, verify web support and
provide a compatible persistence adapter behind the same repository
interfaces. Do not assume mobile SQLite works unchanged on web.

Requirements: - Mutable records persist through navigation and
restart. - One shared repository/database instance when the four
interfaces run in the shared prototype. - Seed only on first run or
explicit reset. - Never silently overwrite user edits with seed data. -
Schema versioning and migration scaffolding. - Transactions for
assignment and trip completion/billing. - Repository tests. - Persist
selected role and preferences appropriately. - No secrets or real
personal data in demo storage.

Potential packages, after checking compatibility: `flutter_riverpod`,
`go_router`, `sqflite` or `drift`, `shared_preferences` for simple
preferences only, `intl`, `uuid`, `file_picker`, `csv`, optional image
picker, optional QR scanner, optional map library, and optional
chart/export packages. Add only what is used. Never hardcode API keys.

# 3. Launcher, Navigation, and Visual Design

## 3.1 Launcher

Show a polished "Choose a workspace" screen with four cards: - Employee
/ Passenger - Driver - Employer Admin - Fleet Manager Admin

Each card explains its role and opens the correct workspace. Provide
"Reset demo data" in a demo/developer menu with confirmation and a
warning that local edits will be removed. Display a subtle "DEMO DATA"
indicator. The launcher is not production authorization.

## 3.2 Navigation

Employee bottom tabs: Home, My Trips, Book, Activity, Profile.

Driver bottom tabs: Home, Trips, Activity, Profile. During an active
trip, make Active Trip easy to reopen. Keep SOS accessible during a
trip.

Employer Admin sidebar: Overview, Employees, Rosters & Policies, Pickup
Locations, Fleet Assignments, Billing, Reports, Settings.

Fleet Manager sidebar: Overview, Trips & Dispatch, Route Optimization,
Employee Pooling, Vehicles, Drivers, Parking & Stops, Monitoring &
Incidents, Reports, Settings.

Web consoles must adapt to desktop, tablet, and narrow widths. Use
collapsible sidebar on desktop and drawer/stacked cards on narrow
screens. Avoid overflow; data tables should reflow or scroll
intentionally.

## 3.3 Premium design system

White-first, polished, restrained enterprise UI. Avoid repetitive cards,
random icon styles, excessive gradients, giant empty hero sections, fake
charts, decorative metrics, and generic AI-looking layouts.

Palette: - Midnight Navy `#10243A` - Deep Navy `#172F4D` - Primary Blue
`#2457E6` - Pressed Blue `#1C46C7` - Soft Blue `#EDF3FF` - Teal
`#0D9488` - Soft Teal `#E7F7F4` - App Background `#F4F7FB` - White
`#FFFFFF` - Secondary Surface `#F8FAFD` - Primary Text `#172B4D` -
Secondary Text `#526579` - Muted Text `#718096` - Border `#DFE6EF` -
Divider `#E8EDF3` - Success `#16835D` / background `#E9F7EF` - Warning
`#A66A00` / background `#FFF5DF` - Danger `#C0393A` / background
`#FDEEEE` - Info `#2457E6` / background `#EDF3FF`

Use Material 3 as the base, customized consistently. Use an 8-point
spacing scale; mobile gutters 20--24 px; card padding 16--20 px; section
spacing 24--32 px; buttons 52--56 px; touch targets at least 48×48 dp;
card radius 12--16 px; fields 52--56 px. Use Inter or comparable legible
sans-serif and one consistent outline icon family. Use shadows
sparingly. No emoji as core icons. Support larger text, contrast, screen
readers, keyboard navigation in web, logical focus, and safe-area
layouts. Driver UI must discourage detailed interaction while the
vehicle is moving.

# 4. Shared Domain Model

Implement typed models/enums, repository operations, and foreign-key
relationships.

## Employer

`id, code, name, status, currency, maximumArrivalTime, defaultDistanceRate, preferredEvPercentage, vehicleTypePreferences, luxuryPreference, costPriority, punctualityPriority, securityGuardPolicyEnabled, createdAt, updatedAt`.

## Employee

`id, employeeCode, employerId, name, fictionalEmail, fictionalPhone, pickupLocationId, destinationId, requiredArrivalTime, shiftLabel, transportPreference, status, optionalDemoPasswordEnabled`.
Do not infer sensitive attributes from names. Only include explicitly
configured synthetic policy flags if needed for a demo.

## Driver

`id, driverCode, name, fictionalContact, status (available/assigned/onTrip/offDuty/unavailable), assignedVehicleId, shiftStart, shiftEnd, attendanceStatus, completedTripCount, safetyChecklistStatus`.

## Vehicle

`id, vehicleCode, fictionalRegistration, type, propulsion (EV/ICE/hybrid), totalSeats, operationalPassengerCapacity, luxuryClass, status (available/assigned/onTrip/maintenance/unavailable), odometerKm, optional battery/fuel level, assignedDriverId, assignedEmployerId, requiresSecurityGuard, securityGuardAssigned, notes, lastInspectionAt`.

Choose one seat convention and apply it consistently. Prefer total seats
includes driver; calculate passenger capacity as
`totalSeats - driverSeat - requiredGuardSeats`. Guard seat requirements
must reduce employee capacity.

## Location / Stop / Parking

`id, code, name, type (pickup/destination/office/parking/depot/intermediateStop), address, optional fictional demo coordinates, optional geofence radius, employerId nullable, active, notes`.
Never present fictional coordinates as real.

## Trip

`id, tripCode, employerId, assignedDriverId nullable, assignedVehicleId nullable, routeId nullable, serviceDate, scheduledStart, actualStart nullable, scheduledArrival nullable, actualArrival nullable, originLocationId, destinationLocationId, employeeIds, orderedStopIds, expectedPassengerCount, boardedPassengerIds, alightedPassengerIds, distanceKm nullable, estimatedDurationMinutes nullable, actualDurationMinutes nullable, status (draft/planned/assigned/driverAccepted/ready/inProgress/delayed/completed/cancelled/needsAttention), optimizationRunId nullable, delayReason nullable, completionNotes nullable, billableStatus, createdAt, updatedAt`.

## Route / Route Stop

Route:
`id, routeCode, name, employerId nullable, ordered stop IDs, estimatedDistanceKm, estimatedDurationMinutes, status, optimizationRunId`.
RouteStop:
`id, routeId, locationId, sequence, plannedArrival, actualArrival nullable, expectedBoardingCount, expectedAlightingCount, status (upcoming/arrived/completed/skipped/issue), skipReason nullable`.

## Booking

`id, employeeId, tripId nullable, requestedPickupLocationId, requestedDestinationId, requestedDate, requestedArrivalTime, status (requested/approved/assigned/waitlisted/rejected/cancelled/completed), notes, createdAt`.
A request is not a confirmed assignment until explicitly
approved/assigned.

## Passenger verification event

`id, tripId, employeeId, stopId, eventType (boarded/alighted/noShow/manualOverride), verificationMethod (qrDemo/tpinDemo/manualAuthorized), verificationStatus, eventTime, note`.
All credentials are demo-only.

## Attendance / Shift

`id, driverId, shiftDate, scheduledStart, scheduledEnd, actualCheckIn nullable, actualCheckOut nullable, status (scheduled/checkedIn/late/regularizationPending/completed), regularizationStatus nullable, notes`.

## Vehicle inspection

`id, vehicleId, driverId, tripId nullable, date, checklist items with pass/fail/notApplicable, notes, optional local photo path, overallStatus (passed/failed/needsReview), submittedAt`.
Critical failures can block trip start.

## Incident / Breakdown / Emergency

`id, reference, type (delay/routeDeviation/breakdown/passengerIssue/safety/emergency/other), tripId nullable, driverId nullable, vehicleId nullable, locationId nullable, description, severity, status (draft/submittedDemo/acknowledgedDemo/resolvedDemo/failedDemo), createdAt, updatedAt, resolutionNotes nullable`.
Display that demo events were not sent to a real control room.

## Billing

`id, employerId, tripId, tripCode, completedAt, billableDistanceKm, ratePerKm, additionalCharges, adjustment, totalAmount, status (draft/generated/reviewed/paidDemo/disputed), calculationNotes`.
Formula:
`totalAmount = distanceKm × employer.distanceRate + additionalCharges + adjustment`.
Generate only once after trip completion and valid distance. Missing
distance blocks automatic billing.

## Optimization configuration/run

Configuration:
`id, employerId nullable, name, enabled, costWeight, punctualityWeight, distanceWeight, travelTimeWeight, utilizationWeight, EVPreferenceWeight, customerPreferenceWeight, safetyWeight, guardRequirementWeight, maximumArrivalTime, minimumBufferMinutes, allowedVehicleTypes, minimumEvPercentage, additionalParameters, timestamps`.
Run:
`id, configurationId, createdAt, status (demoCalculated/noFeasibleSolution/failedDemo), inputSummary, outputSummary, totalDistanceKm, estimatedMinutes, estimatedCost, onTimeScore, vehicleUtilization, EVAllocationPercentage, warnings, explanation, isSimulation`.

Build an extensible catalog of 100+ named parameter definitions grouped
by cost, time, distance, traffic, capacity, safety, preferences,
availability, EV/emissions, geography, reliability, and customer policy.
Each definition needs description, units, default/bounds, category, and
active/inactive state. Only a subset must be editable/active in this
demo; never claim 100 live data inputs are connected.

## Notifications, support, audit

Notification:
`id, recipientRole, recipientId nullable, title, body, category, createdAt, readAt nullable, relatedEntityType, relatedEntityId, demoOnly`.
Support ticket:
`id, reference, createdByRole, createdById, category, subject, description, relatedTripId nullable, status, timestamps`.
Audit event:
`id, actorRole, actorId, action, entityType, entityId, timestamp, summary`.

# 5. Seed Data --- Required and Shared

Insert deterministic data once. All four workspaces must use the same
records.

-   Employer `C1` --- "C1 Corporate Services" (fictional demo).
-   Employees `E1` through `E100`, all linked to C1.
-   Vehicles/fleet IDs `C1`, `C2`, `C3` (display clearly as vehicle IDs
    to distinguish from employer C1).
-   Drivers `DR1`, `DR2`, `DR3`.
-   Parking locations `P1`--`P10`.
-   Destinations/offices `G1`--`G4`.
-   At least 10 pickup locations.
-   At least 3 routes with ordered stops.
-   At least 6 trips in planned, assigned, in-progress demo, completed,
    delayed, and cancelled states.
-   At least 10 bookings with different statuses.
-   At least 8 notifications.
-   At least 3 incidents with different statuses.
-   At least 3 completed billable trips with distance/rate.
-   At least 3 inspections with different outcomes.
-   At least 3 shift records.
-   At least 1 optimization configuration and 2 saved demo optimization
    runs.

First four employees must be recognizable in route demo: - E1 --- Asha
Rao - E2 --- Kiran Mehta - E3 --- Neha Iyer - E4 --- Arjun Das

Generate fictional names for E5--E100, with unique IDs and sensible
varied pickup locations, destinations G1--G4, and arrival requirements.
Use sample morning commute times; keep maximum arrival time
configurable.

Example fleet: - Vehicle C1: EV sedan, 4 total seats including driver. -
Vehicle C2: ICE van, 7 total seats including driver. - Vehicle C3: EV
MPV, 6 total seats including driver.

Example drivers: - DR1 Ravi Kumar - DR2 Priya Sharma - DR3 Arif Khan

All contacts, registrations, locations, and map points are fictional.
Shared pool is default: a vehicle is assigned to a trip/time window, not
permanently to one employer unless policy says so. Prevent overlapping
vehicle/driver assignments.

Seed only once; add "Reset demo data" with confirmation. Reset must
restore the baseline data. Never silently reseed over edits.

# 6. App A --- Employee / Passenger App

1.  **Demo login:** Choose E1/E2/E3/E4; optional password behavior only
    if configured; no real auth.
2.  **Home:** Greeting, notifications, next trip,
    pickup/destination/time, assigned driver/vehicle, contextual primary
    action, upcoming trips, service alerts, useful empty state. No fake
    analytics.
3.  **My Trips:** Upcoming/completed/cancelled; details and status;
    useful search/filter.
4.  **Booking request:** Date, pickup, destination, arrival-by time,
    preferences; validation; review; submit local request. It appears in
    Fleet Manager queue and Employer view. Assignment later updates the
    passenger view. Show no availability honestly and preserve form
    input.
5.  **Roster/schedule:** Agenda-first, day/week where useful, shuttle,
    stop, pickup time, destination, changes and holiday notices.
6.  **Trip detail/tracking:** Stops, schedule/actual times,
    driver/vehicle if assigned, schematic route if no map API. Clearly
    label simulated location and last update. Handle stale/unavailable
    GPS, delays, cancellation.
7.  **E-pass/T-PIN:** Demo credential clearly labeled non-production;
    only relevant trip data; boarding status updated by driver events;
    never expose real secrets.
8.  **Notifications:** Trip assignment, booking update, pickup reminder,
    delay, route change, service notice; read/unread persists; tap opens
    related record.
9.  **Activity/support:** Booking and trip history; create support
    ticket with category, subject, description, optional trip.
10. **Profile/preferences/safety:** Editable permitted pickup
    preference, privacy/settings, safety assistance during trip. SOS
    demo outcome must say no real emergency service was contacted.

# 7. App B --- Driver App

Driver interface must be simpler than passenger interface: one primary
action at a time, large touch controls, readable daylight UI, and no
detailed interactions while moving.

1.  **Demo login:** Select DR1/DR2/DR3.
2.  **Stateful Home:**
    -   Before shift: shift details and Start Shift.
    -   Shift active, no trip: next assigned trip.
    -   Trip active: next stop and Open Active Trip.
    -   All work complete: summary and End Shift if permitted.
3.  **Attendance:** Shift start/end, check-in, actual time, early/late,
    prevent duplicate check-in, regularization request if configured.
4.  **Vehicle assignment/inspection:** Vehicle info; tyres, lights,
    brakes, mirrors, seat belts, doors, emergency exits, safety kit,
    cleanliness, visible damage. Pass/fail/not applicable; notes and
    optional photo. Critical failure blocks trip start and allows
    defect/replacement report.
5.  **Schedule/trips:** Schedule from 6:00 AM where applicable;
    upcoming/active/completed; route, stops, passenger count, arrival
    deadline, vehicle and instructions. Cancelled/unassigned trips
    cannot start.
6.  **Active trip/navigation:** Current/next stop, remaining stops,
    status, expected/boarded count, schematic route, demo navigation.
    Warn against interacting while driving. No real GPS/traffic claims.
7.  **Passenger manifest:** Only passengers relevant to the trip/stop;
    search; demo QR/T-PIN; success/invalid/expired/duplicate cases;
    authorized manual override with reason; boarded/alighted/no-show
    states; counts persist and reflect in passenger app.
8.  **Stop management:** Arrival time/status, boarding/alighting counts,
    missed stop handling, reason/authorization for skip, discrepancy
    warnings.
9.  **Trip completion:** Actual times, stops, passenger counts,
    incidents, distance/odometer if configured; validate requirements;
    completed trip updates all apps and triggers billing if distance
    valid.
10. **Delay/route deviation/breakdown:** Category, context, description,
    demo location, local submit, Fleet Manager alert, vehicle
    availability/replacement request when applicable. Failed submission
    retains form values.
11. **SOS:** Confirmation, pending state, explicit demo-only message,
    failure/offline alternatives. Never claim real dispatch.
12. **Shift summary:** Times, trips, passenger counts, open incidents,
    vehicle handover; block shift end on mandatory unresolved tasks
    unless authorized exception.
13. **Activity/support:** Attendance, trip, inspection, incident, ticket
    history; local support ticket and simulated control-room contact.

# 8. App C --- Employer Admin Console

1.  **Overview:** Employee count, trips today, upcoming/completed trips,
    charges, requests needing review, service alerts. Metrics must be
    calculated from local records.
2.  **Employee management:** Search/filter/sort E1--E100;
    view/edit/deactivate; pickup, destination, arrival time, shift,
    preferences and assignment. Unique IDs; deactivation preserves trip
    history.
3.  **Roster CSV import:** Column mapping, preview, row-level errors,
    duplicates, invalid times, unknown pickup. Commit only after
    confirmation. Never overwrite silently. Provide sample template or
    paste-import fallback if platform file picker is unavailable.
4.  **Arrival-time and transport policies:** Employer maximum arrival
    time, per-employee requirement, pickup/destination, allowed vehicle
    types, preferences, EV target, luxury class, cost/punctuality
    priorities, explicit guard policy. Never infer sensitive attributes
    from names.
5.  **Fleet assignments:** View driver, vehicle, route, stops, EV/ICE,
    passenger count, distance estimate and status. Employer does not
    override fleet-manager-only operations by default.
6.  **Billing:** Completed trips eligible for billing; rate; distance;
    line total; trip/time/status/calculation breakdown; charges by
    period. Formula
    `distanceKm × ratePerKm + additionalCharges + adjustment`. Missing
    distance visibly blocks automatic billing. Generate once; allow
    review/dispute and demo "paid" status but no payment processing.
    Cancelled/incomplete trips excluded. CSV export if supported.
7.  **Reports:** Trip volume/completion, recorded distance, charges,
    on-time performance only where timestamps exist, allocation
    visibility; calculated local data only.
8.  **Settings/audit:** Company settings, billing rate, policies, audit
    trail, confirmation for consequential edits, demo label.

# 9. App D --- Fleet Manager Admin Console

1.  **Overview:** Available/assigned/on-trip/maintenance vehicles;
    drivers by duty status; planned/in-progress/delayed/completed trips;
    unassigned requests; incidents; EV target vs actual. All computed
    from records.
2.  **Vehicle management:** Search/filter/add/edit; type, propulsion,
    total seats, calculated passenger capacity, luxury class, status,
    odometer, guard requirement. Block assignment when unavailable, in
    maintenance, over capacity, or conflicting.
3.  **Driver management:** Search/filter/add/edit; shift, duty status,
    vehicle, assigned trips, inspection; prevent overlapping
    assignments; off-duty/unavailable cannot be assigned without
    explicit permitted override.
4.  **Dispatch/trip assignment:** Queue requests, select
    employer/date/route/driver/vehicle/employees/stops; validate
    capacity, availability, time windows, policy; save assignment;
    update all four workspaces; audit event; reassignment reason and
    notifications.
5.  **Shared pooling:** Pool employees across employers only when
    feasible. Consider pickup/destination, arrival time, capacity, time
    windows, customer policy, safety, vehicle availability. Explain why
    employees can/cannot be pooled. Never force infeasible pooling.
6.  **Route planning/optimization:** Ordered stops; compare route
    alternatives; configurable weights for cost, punctuality, distance,
    travel time, utilization, EV, customer preference, safety, guard
    requirements. Hard safety/legal/capacity constraints cannot be
    traded away. Do not use nearest-path as primary strategy. Implement
    a deterministic local heuristic/scoring service with transparent
    calculations. Label it **local demo optimizer**, not OR-Tools or
    production AI. Show score, distance, estimated duration/cost,
    capacity, arrival feasibility, EV percentage, warnings and
    explanation. Save/compare runs. Display "No feasible assignment" if
    hard constraints fail.
7.  **100+ parameter catalog:** Extensible named definitions with
    description, unit, defaults/bounds, category and active state.
    Groups include time windows, distance, travel time, demo traffic,
    capacity, passenger compatibility, driver/vehicle availability,
    operating cost, EV/emissions, luxury preference, pickup proximity,
    destination compatibility, detour, service/boarding buffers, guard
    seat, safety, customer policies, utilization, deadheading,
    historical delay (demo), reliability (demo), shift constraints,
    parking/depot distance, road restrictions (demo), max
    stops/duration/delay and manual priority. Only a subset is
    active/live in prototype.
8.  **EV/customer rules:** Configure EV target e.g. 50%; calculate
    target vs actual; warn if infeasible; do not violate hard
    constraints to meet a preference.
9.  **Guard/capacity:** Explicit policy; deduct required guard seats
    before employee capacity; show total seats, driver seat, guard
    seats, employee capacity. Never infer guard requirement from names.
10. **Parking/locations:** P1--P10, pickup stops, G1--G4; list and
    schematic map; fictional coordinates labeled demo.
11. **Monitoring/incidents:** Trip status, delays, route deviation,
    breakdown, unavailable vehicle, incident queue, demo SOS records;
    reassign with validation and audit.
12. **Reports:** Utilization, distance, vehicle availability, driver
    duty/completion, EV %, delays/incidents, unassigned requests,
    optimization comparison. Calculated records only.

# 10. Cross-App End-to-End Flows --- Mandatory

Implement these using shared local persistence:

**A. Roster:** Employer imports/seed E1--E100 → Fleet Manager sees
eligible employees → Employee workspace can select demo identity.

**B. Booking:** E1 requests pickup/destination/date/arrival-by → request
appears in Fleet Manager and Employer → Fleet Manager assigns a feasible
trip/driver/vehicle → Employee sees assignment → Driver sees assigned
trip.

**C. Trip assignment:** Fleet Manager assigns C1, E1--E4, route, DR1,
and vehicle C1 → validation runs → assignment appears in Driver,
Employee and Employer views.

**D. Driver preparation:** DR1 checks in → inspects vehicle C1 →
critical failed item blocks trip start and creates defect report → Fleet
Manager sees defect/unavailability. If inspection passes, driver can
start an eligible trip.

**E. Boarding:** Driver arrives at stop → verifies demo QR/T-PIN →
boarding event persists → Driver manifest and Employee view update →
counts remain consistent.

**F. Completion:** Driver completes stops and deboarding → passenger
discrepancy flagged if counts do not reconcile → resolve or record
authorized exception → trip completed everywhere.

**G. Billing:** Completed trip with valid distance → billing generated
once using employer rate → Employer sees line and total. Missing
distance blocks automatic billing.

**H. Optimization:** Fleet Manager selects E1--E4 and available vehicles
→ adjusts weights/policies → runs local demo optimizer → sees proposal,
feasibility, score and assumptions → applies only after confirmation →
other workspaces update.

**I. EV target:** Employer sets 50% EV target → Fleet Manager sees
target versus actual → infeasible target explains why.

**J. Incident/SOS:** Driver submits delay/breakdown/SOS demo → Fleet
Manager sees incident → vehicle/trip status updates appropriately →
employee receives local notification → all emergency status is
explicitly demo-only.

**K. Reassignment:** Fleet Manager reassigns with reason → old
assignment invalidated → new driver/vehicle sees assignment →
employee/employer updated → local notification and audit event.

**L. End shift:** Driver finishes trips → completes handover/required
tasks or authorized exception → ends shift → attendance/history update →
Home reflects shift complete.

# 11. Business Rules

Implement in domain services and unit tests, not just widgets.

1.  No overlapping driver or vehicle assignments in conflicting time
    windows.
2.  Vehicle must be available and not in maintenance.
3.  Employee count cannot exceed operational passenger capacity.
4.  Deduct driver seat and required guard seats consistently.
5.  Safety, legal, eligibility, and capacity are hard constraints.
6.  Cannot start cancelled, unassigned, or inspection-blocked trip.
7.  Validate trip status transitions.
8.  No duplicate boarding without explicit correction/override.
9.  Failed QR/T-PIN cannot mark a passenger verified.
10. Follow configured deboarding/reconciliation rules.
11. Trip completion requires mandatory stops/checks or recorded
    authorized exception.
12. Billing generated once only for completed trip with valid
    nonnegative distance.
13. Missing distance prevents automatic billing.
14. Booking is not assignment until approved/assigned.
15. Reassignment preserves history and creates audit event.
16. Cancelled trip cannot remain active for driver.
17. EV preference never overrides hard constraints.
18. SOS is demo-only without real integration.
19. Notifications link to the correct entity.
20. Reset requires confirmation.
21. Validation errors preserve user input.
22. Seed IDs stable and no duplicate seed insertion.
23. Deactivation preserves historical trips.
24. Billing inputs and calculations are transparent.

# 12. Demo Integration Interfaces

Create injectable interfaces so future APIs replace demo adapters
without rewriting UI: - `AuthRepository` --- local demo identity. -
`TripRepository` --- local trip CRUD/state transitions. -
`AssignmentService` --- assignment validation. - `OptimizationService`
--- deterministic local heuristic. - `MapService` --- schematic demo
route/future map adapter. - `LocationService` --- simulated position
only. - `NotificationService` --- local notifications. -
`VerificationService` --- demo QR/T-PIN validation. - `BillingService`
--- distance-based billing. - `IncidentService` --- local incidents/SOS
records. - `RosterImportService` --- CSV parsing and validation. -
`ExportService` --- CSV export where supported. - `AuditService` ---
local audit trail.

Label all fake adapters. Do not make real network calls in this phase.

# 13. UX and Error States

Every major feature must include appropriate loading, empty, success,
error, disabled, validation, confirmation, and retry states.

Specific examples: - No trips: explain and offer the next useful
action. - No vehicles available: explain constraints. - No feasible
route: list hard constraints; do not fabricate a route. - Missing
distance: flag billing as incomplete. - Stale GPS: show last demo update
and warn it may be outdated. - CSV import errors: show row and reason. -
Passenger mismatch: show expected versus actual count. - SOS: clearly
say demo-only and provide available alternative guidance. - No search
results: allow clearing filters. - Failed local submission: preserve
user-entered data.

Use inline feedback for minor issues and dialogs for consequential
actions. Important outcomes must not rely only on a transient toast.

# 14. Privacy and Safety

-   Fictional data only.
-   No secrets or real credentials.
-   Role launcher is not real authorization.
-   Drivers see only passenger data required for transport.
-   Do not log QR/T-PIN secrets.
-   Confirm destructive actions.
-   Preserve completed trip history.
-   Document that production auth, authorization, encryption, retention,
    and backend validation are not supplied by this frontend prototype.
-   Do not encourage phone interaction while driving.
-   Do not claim a control room or emergency service was contacted
    unless a real integration actually confirms it.

# 15. Required Tests

## Unit tests

-   Seed manager inserts once and preserves edits.
-   Unique IDs.
-   Seat capacity with driver/guard.
-   Overlapping assignment prevention.
-   Trip status transitions.
-   Inspection failure blocks trip.
-   QR/T-PIN success/failure/duplicate/expired.
-   Passenger counts and reconciliation.
-   Completion requirements.
-   Billing formula and no duplicate billing.
-   Missing distance blocks billing.
-   EV percentage calculation.
-   Hard constraint failure produces no feasible route.
-   CSV row validation.
-   Notification entity references.

## Widget tests

-   Launcher opens all four workspaces.
-   Main navigation works.
-   Forms validate.
-   Create/edit actions persist.
-   Dialog cancellation works.
-   Loading/empty/error states render.
-   Driver Home changes by duty state.
-   Employee sees assignment updates.
-   Billing totals match records.
-   Responsive web layouts do not overflow.

## Integration tests

1.  Booking → assignment → Employee and Driver update.
2.  Shift → inspection → trip start.
3.  Boarding → passenger status update.
4.  Trip completion → Employer billing.
5.  Vehicle defect → Fleet Manager alert and assignment block.
6.  EV target and optimization proposal.
7.  Reassignment updates all relevant views.
8.  Reset restores baseline seed data.

Manual QA: restart persistence, small mobile width, large text,
desktop/tablet widths, all main buttons, empty/error states, consistent
IDs/status, and explicit demo-only labels.

# 16. Implementation Sequence --- Do Not Skip

**Stage 1 --- Foundation:** inspect repo; confirm environment; implement
theme, router, launcher, persistence, seed manager, and four shells.
Gate: analyzer passes; all workspaces open.

**Stage 2 --- Models and persistence:** implement models, enums,
repositories, seed data, migrations, and domain rules. Gate: seed once,
persist, reset, shared data.

**Stage 3 --- Admin vertical slice:** Employer employee list and Fleet
Manager vehicle/driver/trip assignment. Gate: assignment appears across
all four apps.

**Stage 4 --- Driver workflow:** attendance, inspection, trip, stops,
boarding, completion, incident/SOS. Gate: complete a demo trip with
correct counts.

**Stage 5 --- Employee workflow:** home, booking, trips, tracking, pass,
notifications, profile/support. Gate: booking request and assigned trip
visibility.

**Stage 6 --- Employer policies/billing:** roster import, arrival time,
preferences, billing and reports. Gate: correct one-time distance
billing.

**Stage 7 --- Optimization:** weights, hard constraints, pooling, EV
target, explanation, parameter catalog, saved runs. Gate: deterministic
and explainable output; infeasible constraints are explicit.

**Stage 8 --- Remaining modules and polish:** locations, reports,
incident queue, settings, audit, export, empty/error states, responsive
UI/accessibility. Gate: all main interactions work.

**Stage 9 --- Final verification:** run `dart format .`,
`flutter analyze`, `flutter test`, available integration tests, and
builds for supported targets. Fix failures; do not claim unrun tests
passed.

# 17. Definition of Done

-   [ ] Four distinct role workspaces in launcher.
-   [ ] All four use shared domain records and repositories.
-   [ ] Local persistence survives navigation and restart.
-   [ ] Seed data includes C1, E1--E100, vehicles C1--C3, DR1--DR3,
    P1--P10, G1--G4, coherent trips/routes.
-   [ ] Reset demo data works and warns about local edits.
-   [ ] Employee can request transport.
-   [ ] Fleet Manager validates and assigns trips.
-   [ ] Assignments update Employee, Driver, and Employer.
-   [ ] Driver can check in, inspect vehicle, and start eligible trip.
-   [ ] Critical defect blocks trip start.
-   [ ] Passenger boarding/deboarding and demo verification work.
-   [ ] Trip completion validates required steps.
-   [ ] Completed trip generates distance billing exactly once.
-   [ ] Employer manages employees, policies, assignments, trips, and
    billing.
-   [ ] Fleet Manager manages vehicles, drivers, availability,
    assignment, pooling, stops, and incidents.
-   [ ] Optimizer has configurable weights, hard constraints, 100+
    parameter catalog, transparent demo output.
-   [ ] EV target versus actual is calculated.
-   [ ] Guard policy changes passenger capacity.
-   [ ] Incident, breakdown, route changes, and SOS have honest demo
    states.
-   [ ] Notifications/audit events link to records.
-   [ ] Loading/empty/error/offline states included.
-   [ ] Responsive web layouts do not overflow.
-   [ ] No simulated external result is presented as real.
-   [ ] Formatting, analysis and tests are run and results reported.
-   [ ] README includes run commands, demo identities, reset,
    architecture, limitations and future integration points.

# 18. Final Instructions to Claude

Work in the repository and implement actual Flutter code, local
persistence, deterministic seed data, navigation, business rules, and
cross-app flows. Do not return only architecture, pseudocode,
screenshots, or a checklist. Do not leave important buttons inert. Do
not duplicate data inside widgets. Do not add a backend in this phase.

At each stage: implement → format → analyze → test → fix → update
progress documentation.

At completion, report: - Modules implemented. - How to run. - Demo
account/role switching. - How to reset seed data. - Test/build
results. - Features simulated locally. - Features requiring future
backend/API work.

The target is a coherent, review-ready frontend prototype for the 19
October 2026 demo. Prioritize complete, shared workflows over a large
number of static screens.
