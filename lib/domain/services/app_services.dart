import '../../core/demo/clock.dart';
import '../../core/export/export_service.dart';
import '../../core/persistence/local_database.dart';
import '../../data/seed/seed_manager.dart';
import 'admin_services.dart';
import 'analytics_matching.dart';
import 'assignment_service.dart';
import 'billing_cycle_service.dart';
import 'billing_service.dart';
import 'booking_service.dart';
import 'core_services.dart';
import 'driver_ops_service.dart';
import 'incident_service.dart';
import 'location_service.dart';
import 'optimization_service.dart';
import 'registry_services.dart';
import 'roster_import_service.dart';
import 'safety_services.dart';
import 'service_context.dart';
import 'traffic_service.dart';
import 'verification_service.dart';

export 'admin_services.dart';
export 'analytics_matching.dart';
export 'assignment_service.dart';
export 'billing_cycle_service.dart';
export 'billing_service.dart';
export 'booking_service.dart';
export 'core_services.dart';
export 'driver_ops_service.dart';
export 'incident_service.dart';
export 'location_service.dart';
export 'metrics_service.dart';
export 'optimization_engine.dart';
export 'optimization_service.dart';
export 'registry_services.dart';
export 'roster_import_service.dart';
export 'safety_services.dart';
export '../rules/tolerance_rules.dart';
export 'route_builder.dart';
export 'service_context.dart';
export 'traffic_service.dart';
export 'verification_service.dart';

/// Single entry point to every write-side service. All four workspaces use
/// the same instance, so business rules live in exactly one place.
class AppServices {
  AppServices(this.db, this.clock, {this.export = const ExportService()})
    : ctx = ServiceContext(db, clock) {
    audit = AuditService(ctx);
    notifications = NotificationService(ctx);
    session = SessionService(ctx);
    support = SupportService(ctx);
    settings = SettingsService(ctx);
    assignments = AssignmentService(ctx);
    billing = BillingService(ctx);
    bookings = BookingService(ctx, assignments);
    driverOps = DriverOpsService(ctx, billing, verification: verification);
    incidents = IncidentService(ctx);
    employers = EmployerService(ctx);
    employees = EmployeeService(ctx);
    fleet = FleetService(ctx);
    roster = RosterImportService(ctx);
    optimization = OptimizationService(ctx, assignments);
    seed = SeedManager(db, clock);
    billingCycles = BillingCycleService(ctx, billing);
    contracts = ContractService(ctx);
    allocations = AllocationService(ctx);
    traffic = TrafficService(ctx);
    policy = FleetPolicyService(ctx);
    alcohol = AlcoholService(ctx);
    geofences = GeofenceService(ctx);
    telematics = TelematicsService(ctx);
    parkingPlanner = ParkingPlannerService(ctx);
    analytics = AnalyticsService(ctx);
    matching = MatchingService(ctx, assignments, bookings);
  }

  final LocalDatabase db;
  final Clock clock;
  final ServiceContext ctx;
  final verification = const VerificationService();

  /// Injectable so tests never write real files.
  final ExportService export;
  final map = const SchematicMapService();

  late final AuditService audit;
  late final NotificationService notifications;
  late final SessionService session;
  late final SupportService support;
  late final SettingsService settings;
  late final AssignmentService assignments;
  late final BillingService billing;
  late final BookingService bookings;
  late final DriverOpsService driverOps;
  late final IncidentService incidents;
  late final EmployerService employers;
  late final EmployeeService employees;
  late final FleetService fleet;
  late final RosterImportService roster;
  late final OptimizationService optimization;
  late final SeedManager seed;
  late final BillingCycleService billingCycles;
  late final ContractService contracts;
  late final AllocationService allocations;
  late final TrafficService traffic;
  late final FleetPolicyService policy;
  late final AlcoholService alcohol;
  late final GeofenceService geofences;
  late final TelematicsService telematics;
  late final ParkingPlannerService parkingPlanner;
  late final AnalyticsService analytics;
  late final MatchingService matching;
}
