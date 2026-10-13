# v2 Domain API — quick reference for UI work

Requirements: `C:\Users\impac\Downloads\RouteMatic_Incremental_Client_Architecture_Claude_Prompt.md`
Decisions: `GAP_ANALYSIS_V2.md`. Schema is **v2** (migration in `core/persistence/migrations.dart`).
Everything below is already implemented and unit-tested — UI must call these, never write to the DB.

Read model: `ref.watch(dataProvider)` (DataView). Services: `ref.read(servicesProvider)` (AppServices).
Labels: `DemoLabels.trafficSimulated`, `.invoiceDemo`, `.auditNotTamperProof`, `.fictionalCoordinates`.

## Models (lib/domain/models)
* `Employer` (= registered company): new `pickupToleranceMinutes` (default 7), `billingCycle` (`BillingCycle.weekly|monthly`), `billingActive`, `additionalChargePerTrip`, `shifts: List<ShiftWindow>` (id, label, startMinutes, endMinutes, overnight), `contactName`, `contactEmail`, `isActive`.
* `Employee`: `shiftStartMinutes`, `shiftEndMinutes` (nullable; end<start = overnight), `pickupToleranceMinutes` (nullable → employer default via `toleranceMinutes(employer)`), `gender: SelfDeclaredGender` (optional, never used by logic), `travelPreferences: Map<String,int>` keys in `TravelPreferenceKeys` (travelTime, distance, detour, reliability — scored; proximity — shown but not active), levels 0–3 (`TravelPreferenceKeys.levels`, `.label(k)`), `arrivalDeadlineMinutes` (= min(required arrival, shift start); services additionally cap it at the company maximum), `overnightShift`.
* `Location`: `latitude`, `longitude` (FICTIONAL), `fleetOwned`, `isParking`, `capacity` = parking spots. `GeoRules.latLngOf(l)`.
* `Vehicle`: `rcNumber`, `engineNumber`, `color`, `fuelType` (`FuelType`, `effectiveFuelType`), `active`.
* `Driver`: `licenceNumber`, `licenceExpiry`, `email`, `address`, `gender`, `active`, `licenceValidOn(day)`. (Aadhaar & age intentionally NOT stored.)
* `Trip.guardReference` (guard name/ID when guard required).
* `BillingRecord.invoiceId`.
* `AuditEvent`: `outcome` (AuditOutcome.success/rejected/failure), `changes` (before→after text), `reason`, `related` map, `simulated`.
* `OptimizationConfig`: new weights `detourWeight`, `pickupProximityWeight`, `employeePreferenceWeight` (keys 'detour','proximity','employeePreference' in `weights` / `withWeight`).
* `OptimizationRun`: `remedies`, `preferenceSummary`, `candidateVehicleIds`, `candidateDriverIds`, `constraintsEvaluated`, `rejectedAt`, `rejectionReason`, `isRejected`. `VehiclePlan`: `startLocationId`, `deadheadKm`, `guardSource` ('vehicle'|'pool'|null), `totalSeats`.
* New: `Invoice`, `Contract` (`validityOn(day)` → `ContractValidity`, `coversDay`), `FleetAllocation` (company × vehicle/driver × daily window), `RouteRevision` (+`RevisionStop`), `TrafficState` (`label`, `available`, `normal`, `factorFor`).

## DataView additions
`invoicesOf(empId)`, `invoice(id)`, `contracts`, `contractsOf(empId)`, `contract(id)`, `activeContract(empId, day)`, `allocations`, `allocationsOf(empId)`, `allocationsFor(ResourceType, id)`, `routeRevisions`, `revisionsOf(tripId)`, `openRevision(tripId)`, `traffic`, `companyEmployeeCount(id)`, `companyShiftCount(id)`, `companyLocationCount(id)`, `parkedVehicles(parkingId)`, `parkingAvailable(parkingId)`.

## Services
* `employees.save(e)` validates shift/tolerance/company/location; `employees.updateTravelPreferences(id, map)` (employee self-service, audited). Helper `employeeChanges(a,b)`.
* `employers.update(e)` (tolerance, cycle, shifts, billing config — audited with changes), `employers.register(e)` (FM), `employers.setActive(id, bool, reason:)`.
* `contracts.save(c, isNew:)`, `contracts.validate`, `contracts.warnings(c)`, `contracts.setStatus(id, status, reason:)`, `contracts.usage(empId, day)` → (used, allowed, contract).
* `allocations.save(a, isNew:)` (overlap detection across companies), `allocations.remove(id)` (deactivates).
* `fleet.saveVehicle / saveDriver / saveLocation` (uniqueness reg/RC/engine/licence; lat/lng ↔ plane; parking capacity ≥ parked vehicles), `fleet.normalizeCoordinates(l)`.
* `assignments.validate/commit(AssignmentRequest(..., guardReference:))` — new HARD rules: guard required ⇒ `guardReference` or vehicle `securityGuardAssigned`; driver licence present & valid; vehicle/driver active; company active; **contract** (no active contract / hard car limit); **fleet allocation windows**; deadline = min(arrival, shift start, employer max). Rejections are audited (outcome rejected).
* `optimization.buildInput(..., startParkingId:, guardsAvailable:)`, `preview`, `runAndSave`, `applyRun(id, guardReferences: {vehicleId: name})` (pool-guard plans need a name), `rejectRun(id, reason)`.
* `billingCycles`: `BillingPeriod.of(cycle, date)` (`label`, `code`, `previous`, `next`, `nextBoundary`, `contains`), `currentPeriod(employer)`, `preview(empId, period)` → `CyclePreview` (`eligible`, `excluded` with `exclusion` reason, `total`, `distanceKm`, `existingInvoices`, `blockers`, `canRun`), `dueCycles(empId)`, `runCycle(empId, period)` (idempotent; supplementary invoice `-S2` for late lines), `setStatus(invoiceId, InvoiceStatus, reason:)`.
* `traffic`: `board()` → `List<TrafficTripStatus>` (`statusLabel`, `delayMinutes`, `plannedFinal`, `estimatedFinal`, `nextStop`, `proposedTimes`, `affectedStopIds`, `feasible`, `violations`, `recommendation`, `earlierDepartureMinutes`, `outsideToleranceEmployeeIds`, `available`), `statusOf(trip)`, `setScenario(internalRoads:, ringRoad:, source:)`, `applyRevision(id)`, `dismissRevision(id, reason)`. Same scenario twice ⇒ no duplicate revisions/alerts.
* Rules: `ToleranceRules.window/deviation/within/describe(actual, planned, tol)`, `ShiftRules.validate/overlaps/covers`, `CommercialRules.contract/allocation`.

## Shared widgets (lib/features/shared)
* `AuditTrailView(companyId:, onOpenEntity:)` — search + filters (date, role, action, record type, result), detail sheet with before/after.
* `TrafficBoard(readOnly:, companyId:, onOpenTrip:)` — scenario controls (FM), trip traffic cards, proposals apply/dismiss (FM), history.

## Notification entity types (new)
`invoice`, `traffic` (id 'current'), `contract`, plus existing ones.

---

# v3 Domain API — safety, telematics, SOS, analytics, dynamic matching

Client requirements (MoM 13 Oct 2026): alcohol monitoring (configurable) & parking management;
vehicle diagnostics, GPS/speed, geofencing; SOS escalation; employer analytics & carbon credits;
dynamic cab booking & seat matching. Schema **v3** (migration v2→v3 fills only missing data).
All telematics/GPS/breathalyzer/telephony behaviour is SIMULATED and must be labelled.

## Models (lib/domain/models/safety.dart)
* `FleetPolicy` (single row 'fleet'): `alcoholMonitoringEnabled`, `alcoholThresholdMg` (0 = zero tolerance), `alcoholCheckPoint` (`AlcoholCheckPoint.shiftStart|everyTrip`), `speedLimitKmh`, `speedAlertsEnabled`, `geofenceAlertsEnabled`, `routeCorridorKm`, `sosRecipients: List<SosRecipient>`, `autoMatchAdhoc`, `maxAddedDetourMinutes`, `carbonCreditPricePerTonne`, `baselineCo2GramsPerKm`, `baselineSpeedKmh`, `baselineCostPerKm`.
* `AlcoholTest`: driverId, tripId?, testedAt, readingMg, thresholdMg, `result` (`AlcoholResult.pass|fail|inconclusive`), method, note, clearedBy/clearedAt, incidentId, `blocking`.
* `Geofence`: name, `kind` (`GeofenceKind.serviceArea|routeCorridor|restrictedZone`), centerX/centerY/radiusKm (demo plane km), vehicleIds (empty = all), active.
* `VehicleEvent`: vehicleId, tripId?, driverId?, geofenceId?, `type` (`VehicleEventType.speeding|geofenceExit|restrictedEntry|routeDeviation|diagnosticFault|harshBraking`), occurredAt, description, value/limit, x/y, acknowledgedAt (`open`), incidentId, simulated.
* `SosDispatch`: incidentId, `recipient` (`SosRecipient`), `status` (`SosDispatchStatus.alertedInApp|acknowledged|integrationRequired|disabled`), channel, note, acknowledgedAt/By.
* `Trip.absentEmployeeIds`; `Vehicle.diagnosticCodes`.

## DataView
`policy`, `alcoholTests`, `alcoholTestsOf(driverId)`, `blockingAlcoholTest(driverId)`, `passedAlcoholTestToday(driverId, tripId:)`, `geofences`, `geofence(id)`, `vehicleEvents`, `vehicleEventsOf(vehicleId)`, `openVehicleEvents`, `sosDispatchesOf(incidentId)`.

## Services (`ref.read(servicesProvider)`)
* `policy.save(FleetPolicy)` / `policy.validate`.
* `alcohol.record(driverId:, readingMg: double? (null = device error), method: AlcoholService.deviceSimulated|supervisorEntry, tripId:)`, `alcohol.blockers(driverId, trip:)`, `alcohol.clear(testId, note)` (FM). A failed test → safety incident, FM alert, driver's not-started trips today → needsAttention; trip start is blocked (also via `driverOps.startBlockers`). Latest test of the day must be a pass.
* `geofences.save(g, isNew:)`, `geofences.validate`.
* `telematics.fleet()` / `snapshot(vehicle)` → `VehicleTelemetry` (status, speedKmh, x, y, lastUpdate, trip, positionLabel, diagnosticCodes, openEvents); `telematics.simulate(vehicleId, VehicleEventType, value:, code:)`; `telematics.scan()`; `telematics.acknowledge(eventId, note:, raiseIncident:)`; `telematics.clearDiagnostic(vehicleId, code)`; `telematics.corridorDistance(trip, x, y)`.
* `parkingPlanner.recommend()` → `List<ParkingRecommendation>` (vehicle, currentParkingId, recommendedParkingId, targetLabel, currentDeadheadKm, recommendedDeadheadKm, savingKm, changes); `parkingPlanner.apply(vehicleIds)`.
* SOS: `incidents.raiseSos(...)` now also creates the escalation chain (`sosDispatchesOf`); `incidents.acknowledgeSos(dispatchId)`.
* `analytics.summary(employerId, DateRange)` → `AnalyticsSummary` (trips: `TripSavings`, riders, co2SavedKg, baselineCo2Kg, actualCo2Kg, minutesSaved, costSaved, baselineCost, actualCost, vehicleKm, baselineKm, estimatedDistanceTrips, creditTonnes, indicativeCreditValue, co2ReductionPct, co2ByDay()).
* `matching.reportAbsence(tripId, employeeId, reason)`, `matching.suggestions(bookingId)` → `List<SeatMatch>` (trip, feasible, reasons, addedMinutes, addedKm, seatsAfter, capacity), `matching.matchBest(bookingId)`, `matching.submitAdhoc(BookingDraft)` (auto-match if policy allows), `matching.utilization(day)`.

## Routes pre-wired
Fleet sidebar: **Telematics & Geofences** `/fleet/telematics`, **Safety & SOS** `/fleet/safety` (placeholder file `lib/features/fleet_admin/pages/v3/v3_routes.dart`).
