/// Typed enums shared by all four workspaces.
///
/// Every enum is persisted by its `name`, so renaming a value requires a
/// migration (see `core/persistence/migrations.dart`).
library;

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

String _humanize(String camel) {
  final spaced = camel.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
  return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
}

enum UserRole {
  employee('Employee'),
  driver('Driver'),
  employerAdmin('Employer Admin'),
  fleetManager('Fleet Manager'),
  system('System');

  const UserRole(this.label);
  final String label;
}

enum RecordStatus {
  active('Active'),
  inactive('Inactive');

  const RecordStatus(this.label);
  final String label;
}

enum VehicleType {
  sedan('Sedan'),
  suv('SUV'),
  mpv('MPV'),
  van('Van'),
  minibus('Mini bus');

  const VehicleType(this.label);
  final String label;
}

enum Propulsion {
  ev('EV'),
  ice('ICE'),
  hybrid('Hybrid');

  const Propulsion(this.label);
  final String label;
}

enum LuxuryClass {
  standard('Standard'),
  premium('Premium'),
  luxury('Luxury');

  const LuxuryClass(this.label);
  final String label;
}

enum VehicleStatus {
  available,
  assigned,
  onTrip,
  maintenance,
  unavailable;

  String get label => _humanize(name);
}

enum DriverStatus {
  available,
  assigned,
  onTrip,
  offDuty,
  unavailable;

  String get label => _humanize(name);
}

enum AttendanceStatus {
  notCheckedIn,
  checkedIn,
  late,
  checkedOut;

  String get label => _humanize(name);
}

enum SafetyChecklistStatus {
  pending,
  passed,
  failed,
  needsReview;

  String get label => _humanize(name);
}

enum LocationType {
  pickup,
  destination,
  office,
  parking,
  depot,
  intermediateStop;

  String get label => _humanize(name);
}

enum TripStatus {
  draft,
  planned,
  assigned,
  driverAccepted,
  ready,
  inProgress,
  delayed,
  completed,
  cancelled,
  needsAttention;

  String get label => _humanize(name);

  bool get isActive =>
      this == inProgress || this == delayed || this == needsAttention;
  bool get isUpcoming =>
      this == draft ||
      this == planned ||
      this == assigned ||
      this == driverAccepted ||
      this == ready;
  bool get isTerminal => this == completed || this == cancelled;
}

enum BillableStatus {
  notYetBillable,
  missingDistance,
  billed,
  excluded;

  String get label => _humanize(name);
}

enum RouteStatus {
  draft,
  planned,
  active,
  completed,
  cancelled;

  String get label => _humanize(name);
}

enum StopStatus {
  upcoming,
  arrived,
  completed,
  skipped,
  issue;

  String get label => _humanize(name);
}

enum StopKind {
  pickup,
  drop;

  String get label => _humanize(name);
}

enum BookingStatus {
  requested,
  approved,
  assigned,
  waitlisted,
  rejected,
  cancelled,
  completed;

  String get label => _humanize(name);
  bool get isOpen =>
      this == requested || this == approved || this == waitlisted;
}

enum PassengerEventType {
  boarded,
  alighted,
  noShow,
  manualOverride;

  String get label => _humanize(name);
}

enum VerificationMethod {
  qrDemo('QR (demo)'),
  tpinDemo('T-PIN (demo)'),
  manualAuthorized('Manual (authorized)');

  const VerificationMethod(this.label);
  final String label;
}

enum VerificationStatus {
  verified,
  invalid,
  expired,
  duplicate,
  wrongTrip,
  overridden;

  String get label => _humanize(name);
}

/// Per-trip passenger state derived from verification events.
enum PassengerState {
  awaiting,
  boarded,
  alighted,
  noShow;

  String get label => _humanize(name);
}

enum ShiftStatus {
  scheduled,
  checkedIn,
  late,
  regularizationPending,
  completed;

  String get label => _humanize(name);
}

enum RegularizationStatus {
  pending,
  approved,
  rejected;

  String get label => _humanize(name);
}

enum CheckResult {
  pass('Pass'),
  fail('Fail'),
  notApplicable('N/A');

  const CheckResult(this.label);
  final String label;
}

enum InspectionOutcome {
  passed,
  failed,
  needsReview;

  String get label => _humanize(name);
}

enum IncidentType {
  delay,
  routeDeviation,
  breakdown,
  vehicleDefect,
  passengerIssue,
  safety,
  emergency,
  other;

  String get label => _humanize(name);
}

enum IncidentSeverity {
  low,
  medium,
  high,
  critical;

  String get label => _humanize(name);
}

enum IncidentStatus {
  draft('Draft'),
  submittedDemo('Submitted (demo)'),
  acknowledgedDemo('Acknowledged (demo)'),
  resolvedDemo('Resolved (demo)'),
  failedDemo('Failed (demo)');

  const IncidentStatus(this.label);
  final String label;
  bool get isOpen => this == submittedDemo || this == acknowledgedDemo;
}

enum BillingStatus {
  draft('Draft'),
  generated('Generated'),
  reviewed('Reviewed'),
  paidDemo('Paid (demo)'),
  disputed('Disputed');

  const BillingStatus(this.label);
  final String label;
}

enum OptimizationRunStatus {
  demoCalculated('Calculated (demo)'),
  noFeasibleSolution('No feasible solution'),
  failedDemo('Failed (demo)');

  const OptimizationRunStatus(this.label);
  final String label;
}

enum NotificationCategory {
  tripAssignment,
  bookingUpdate,
  pickupReminder,
  delay,
  routeChange,
  serviceNotice,
  incident,
  billing,
  shift,
  system;

  String get label => _humanize(name);
}

enum TicketCategory {
  trip,
  booking,
  driver,
  vehicle,
  app,
  billing,
  safety,
  other;

  String get label => _humanize(name);
}

enum TicketStatus {
  open,
  inProgress,
  resolved,
  closed;

  String get label => _humanize(name);
}

enum TransportPreference {
  noPreference('No preference'),
  evPreferred('EV preferred'),
  sedanPreferred('Sedan preferred'),
  shuttlePreferred('Shared shuttle preferred');

  const TransportPreference(this.label);
  final String label;
}

enum RouteVariant {
  ringRoad('Ring road'),
  internalRoads('Internal roads');

  const RouteVariant(this.label);
  final String label;
}

// ---------------- v2 (client-architecture increment) ----------------

enum BillingCycle {
  weekly('Weekly (Mon–Sun)'),
  monthly('Monthly (calendar month)');

  const BillingCycle(this.label);
  final String label;
}

enum InvoiceStatus {
  generated('Generated'),
  reviewed('Reviewed'),
  paidDemo('Paid (demo)'),
  disputed('Disputed');

  const InvoiceStatus(this.label);
  final String label;
}

/// Optional, self-declared. Never inferred and never used by any algorithm.
enum SelfDeclaredGender {
  notSpecified('Not specified'),
  female('Female'),
  male('Male'),
  nonBinary('Non-binary'),
  preferNotToSay('Prefer not to say');

  const SelfDeclaredGender(this.label);
  final String label;
}

enum FuelType {
  electric('Electric'),
  petrol('Petrol'),
  diesel('Diesel'),
  cng('CNG'),
  hybrid('Hybrid');

  const FuelType(this.label);
  final String label;
}

enum ContractStatus {
  draft('Draft'),
  active('Active'),
  suspended('Suspended'),
  terminated('Terminated');

  const ContractStatus(this.label);
  final String label;
}

/// Effective validity of a contract on a given local date.
enum ContractValidity {
  draft('Draft'),
  notYetValid('Not yet valid'),
  active('Active'),
  expired('Expired'),
  suspended('Suspended'),
  terminated('Terminated');

  const ContractValidity(this.label);
  final String label;
}

enum ResourceType {
  vehicle('Vehicle'),
  driver('Driver');

  const ResourceType(this.label);
  final String label;
}

enum AuditOutcome {
  success('Success'),
  rejected('Rejected'),
  failure('Failure');

  const AuditOutcome(this.label);
  final String label;
}

enum RevisionStatus {
  proposed('Proposed'),
  applied('Applied'),
  dismissed('Dismissed'),
  superseded('Superseded');

  const RevisionStatus(this.label);
  final String label;
}

/// Simulated traffic level per road class.
enum TrafficLevel {
  free('Free flowing', 1.0),
  moderate('Moderate', 1.25),
  heavy('Heavy', 1.6),
  severe('Severe', 2.1);

  const TrafficLevel(this.label, this.factor);
  final String label;
  final double factor;
}

/// Where traffic data comes from (never fabricate "live").
enum TrafficSource {
  simulated('Simulated demo traffic'),
  unavailable('Traffic data unavailable');

  const TrafficSource(this.label);
  final String label;
}

// ---------------- v3 (safety, telematics, analytics, dynamic matching) ----------------

/// When a breathalyzer test is required (if alcohol monitoring is enabled).
enum AlcoholCheckPoint {
  shiftStart('Before each shift'),
  everyTrip('Before every trip');

  const AlcoholCheckPoint(this.label);
  final String label;
}

enum AlcoholResult {
  pass('Pass'),
  fail('Fail'),
  inconclusive('Inconclusive / device error');

  const AlcoholResult(this.label);
  final String label;
}

enum GeofenceKind {
  serviceArea('Service area (circle)'),
  routeCorridor('Route corridor (all trips)'),
  restrictedZone('Restricted zone (must not enter)');

  const GeofenceKind(this.label);
  final String label;
}

enum VehicleEventType {
  speeding('Speeding'),
  geofenceExit('Left geofence'),
  restrictedEntry('Entered restricted zone'),
  routeDeviation('Route deviation'),
  diagnosticFault('Diagnostic fault'),
  harshBraking('Harsh braking');

  const VehicleEventType(this.label);
  final String label;
}

enum SosRecipient {
  fleetManager('Fleet Manager'),
  companyAdmin('Company administrator'),
  supportTeam('Support team'),
  police('Police (112)'),
  driver('Assigned driver'),
  emergencyContact('Personal emergency contact');

  const SosRecipient(this.label);
  final String label;
}

enum SosDispatchStatus {
  alertedInApp('Alerted in app (local)'),
  acknowledged('Acknowledged'),
  integrationRequired('Not contacted — integration required'),
  disabled('Not configured');

  const SosDispatchStatus(this.label);
  final String label;
}
