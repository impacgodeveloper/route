import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/features/fleet_admin/fleet_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/widget_harness.dart';

/// Fleet registry (v2): companies, contracts, fleet allocations, vehicle
/// inventory, driver records and parking — driven through the UI.

ProviderContainer _c(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(FleetShell)));
DataView _data(WidgetTester t) => _c(t).read(dataProvider);
AppServices _svc(WidgetTester t) => _c(t).read(servicesProvider);

Future<void> _tap(WidgetTester t, Finder f) async {
  // A focused text field would scroll itself back into view.
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pump();
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> _tapText(WidgetTester t, String text, {bool last = false}) =>
    _tap(t, last ? find.text(text).last : find.text(text).first);

Finder _inDialog(Finder f) =>
    find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> _go(WidgetTester t, String path) async {
  _c(t).read(routerProvider).go(path);
  await t.pumpAndSettle();
}

Future<void> _ok(WidgetTester t) async {
  if (find.text('OK').evaluate().isNotEmpty) {
    await t.tap(find.text('OK').last);
    await t.pumpAndSettle();
  }
}

/// Picks a date in the Material date picker via its text-input mode.
Future<void> _pickDate(
  WidgetTester t,
  String fieldLabel,
  String mmddyyyy,
) async {
  await _tap(
    t,
    find
        .ancestor(
          of: find.text(fieldLabel).last,
          matching: find.byType(InkWell),
        )
        .first,
  );
  await t.tap(find.byIcon(Icons.edit_outlined).last);
  await t.pumpAndSettle();
  final input = find.descendant(
    of: find.byType(DatePickerDialog),
    matching: find.byType(TextField),
  );
  await t.enterText(input, mmddyyyy);
  await t.pumpAndSettle();
  await t.tap(find.text('OK').last);
  await t.pumpAndSettle();
}

String _mdY(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

Future<void> _register(WidgetTester t, String code, String name) async {
  await _go(t, '/fleet/companies/new');
  await t.enterText(find.byKey(const Key('companyCode')), code);
  await t.enterText(find.byKey(const Key('companyName')), name);
  await _tap(t, find.byKey(const Key('registerCompany')));
}

void main() {
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  testWidgets(
    'register company: duplicate ID rejected, then created with derived counts',
    (t) async {
      await pumpApp(t, location: '/fleet/companies', size: desktopSize);
      expect(find.text('Company C1'), findsOneWidget);
      // Derived counts for C1 (98 active employees, 4 shifts, 16 locations).
      final d = _data(t);
      expect(find.text('${d.companyEmployeeCount('C1')}'), findsWidgets);
      expect(d.companyEmployeeCount('C1'), 98);
      expect(find.text('CT-2026-01 · Active'), findsOneWidget);

      await _register(t, 'C1', 'Duplicate Co');
      expect(
        find.textContaining('Company ID C1 already exists'),
        findsOneWidget,
      );
      expect(_data(t).employers.length, 1);

      await t.enterText(find.byKey(const Key('companyCode')), 'C9');
      await _tap(t, find.byKey(const Key('registerCompany')));
      expect(_data(t).employer('C9')!.name, 'Duplicate Co');
      expect(find.text('Company C9 · Duplicate Co'), findsOneWidget);
      expect(find.text('Active employees'), findsOneWidget);
      expect(
        _data(t).auditTrail.any((a) => a.action == 'company.register'),
        isTrue,
      );

      await _go(t, '/fleet/companies');
      await t.enterText(
        find.widgetWithText(TextField, 'Search company ID or name'),
        'dup',
      );
      await t.pumpAndSettle();
      expect(find.text('Company C9'), findsOneWidget);
      expect(find.text('Company C1'), findsNothing);
    },
  );

  testWidgets(
    'contract: invalid dates rejected, create, activate, suspend; expired history shown',
    (t) async {
      await pumpApp(
        t,
        location: '/fleet/companies/C1?tab=contracts',
        size: desktopSize,
      );
      expect(find.text('CT-2025-02'), findsOneWidget);
      expect(find.text('Expired'), findsWidgets);
      expect(
        find.textContaining('of 3 contracted car(s) in use'),
        findsOneWidget,
      );

      await _register(t, 'C9', 'Northwind Demo Co');
      await _go(t, '/fleet/companies/C9?tab=contracts');
      expect(find.text('No contracts'), findsOneWidget);
      await _tapText(t, 'New contract');
      await t.enterText(find.byKey(const Key('contractCode')), 'CT-9-01');
      await t.enterText(find.byKey(const Key('contractDoc')), 'DOC-C9-01');
      final today = _data(t).today;
      await _pickDate(
        t,
        'Valid until',
        _mdY(today.subtract(const Duration(days: 3))),
      );
      await _tap(t, find.byKey(const Key('saveContract')));
      expect(find.textContaining('cannot be earlier'), findsOneWidget);
      expect(_data(t).contract('CT-9-01'), isNull);

      await _pickDate(
        t,
        'Valid until',
        _mdY(today.add(const Duration(days: 200))),
      );
      await _tap(t, find.byKey(const Key('saveContract')));
      await _ok(t);
      final c = _data(t).contract('CT-9-01')!;
      expect(c.status, ContractStatus.draft);
      expect(find.text('Draft'), findsWidgets);

      Future<void> act(String action, String expectBadge) async {
        await _tap(t, find.byTooltip('Actions for CT-9-01'));
        await t.tap(find.text(action).last);
        await t.pumpAndSettle();
        await t.enterText(
          _inDialog(find.widgetWithText(TextFormField, 'Reason')),
          'Demo status change',
        );
        await _tap(t, _inDialog(find.byType(FilledButton)));
        await _ok(t);
        expect(find.text(expectBadge), findsWidgets);
      }

      await act('Activate…', 'Active');
      expect(_data(t).contract('CT-9-01')!.status, ContractStatus.active);
      await act('Suspend…', 'Suspended');
      expect(
        _data(t).contract('CT-9-01')!.validityOn(today),
        ContractValidity.suspended,
      );
      expect(
        _data(t).auditFor('contract', 'CT-9-01').length,
        greaterThanOrEqualTo(3),
      );
    },
  );

  testWidgets('allocations: overlap rejected, add and remove (deactivates)', (
    t,
  ) async {
    await pumpApp(
      t,
      location: '/fleet/companies/C1?tab=allocations',
      size: desktopSize,
    );
    expect(find.textContaining('Morning operations'), findsOneWidget);
    expect(find.text('Car IDs'), findsWidgets);

    await _register(t, 'C9', 'Northwind Demo Co');
    // A fresh vehicle with no allocations (set up via services).
    final base = _data(t).vehicle('C3')!;
    await _svc(t).fleet.saveVehicle(
      Vehicle.fromJson({
        ...base.toJson(),
        'id': 'C7',
        'vehicleCode': 'C7',
        'fictionalRegistration': 'DM-07',
        'rcNumber': 'RC-7',
        'engineNumber': 'EN-7',
        'assignedDriverId': null,
        'status': 'available',
      }),
      isNew: true,
    );
    await _go(t, '/fleet/companies/C9?tab=allocations');
    expect(find.text('No fleet allocations'), findsOneWidget);

    Future<void> add(String vehicleLabel) async {
      await _tapText(t, 'Add allocation');
      await _tap(t, _inDialog(find.byType(DropdownButtonFormField<String>)));
      await t.tap(find.text(vehicleLabel).last);
      await t.pumpAndSettle();
      await _tap(t, find.byKey(const Key('saveAllocation')));
    }

    await add('Vehicle C1 · Sedan');
    expect(find.textContaining('already allocated to C1'), findsOneWidget);
    await _tap(t, _inDialog(find.text('Cancel')));

    await add('Vehicle C7 · MPV');
    final a = _data(t).allocationsFor(ResourceType.vehicle, 'C7').single;
    expect(a.employerId, 'C9');
    expect(find.text('Vehicle C7'), findsOneWidget);

    await t.tap(find.byTooltip('Remove C7'));
    await t.pumpAndSettle();
    await _tap(t, _inDialog(find.text('Remove')));
    expect(
      _data(t).allocations.firstWhere((x) => x.id == a.id).active,
      isFalse,
    );
    expect(find.text('No fleet allocations'), findsOneWidget);
  });

  testWidgets(
    'company deactivation: blocked for C1, allowed for a new company',
    (t) async {
      await pumpApp(t, location: '/fleet/companies/C1', size: desktopSize);
      await _tapText(t, 'Deactivate company');
      await t.enterText(
        _inDialog(find.widgetWithText(TextFormField, 'Reason')),
        'End of demo pilot',
      );
      await _tap(t, _inDialog(find.text('Deactivate')));
      expect(find.textContaining('upcoming trip(s) exist'), findsOneWidget);
      await _ok(t);
      expect(_data(t).employer('C1')!.isActive, isTrue);

      await _register(t, 'C9', 'Northwind Demo Co');
      await _tapText(t, 'Deactivate company');
      await t.enterText(
        _inDialog(find.widgetWithText(TextFormField, 'Reason')),
        'Pilot ended (demo)',
      );
      await _tap(t, _inDialog(find.text('Deactivate')));
      expect(_data(t).employer('C9')!.isActive, isFalse);
      expect(find.text('Reactivate'), findsOneWidget);
    },
  );

  testWidgets('vehicle inventory: registration / RC uniqueness, then saved', (
    t,
  ) async {
    await pumpApp(t, location: '/fleet/vehicles/new', size: desktopSize);
    await t.enterText(find.widgetWithText(TextField, 'Vehicle ID'), 'C5');
    await t.enterText(
      find.widgetWithText(TextField, 'Registration (fictional)'),
      'DM-01-EV-1001',
    );
    await _tap(t, find.widgetWithText(FilledButton, 'Add vehicle'));
    expect(
      find.textContaining('Registration DM-01-EV-1001 is already used'),
      findsOneWidget,
    );

    await t.enterText(
      find.widgetWithText(TextField, 'Registration (fictional)'),
      'DM-05-EV-5005',
    );
    await t.enterText(
      find.widgetWithText(TextField, 'RC number (synthetic)'),
      'DEMO-RC-1001',
    );
    await _tap(t, find.widgetWithText(FilledButton, 'Add vehicle'));
    expect(
      find.textContaining('RC number DEMO-RC-1001 is already used'),
      findsOneWidget,
    );

    await t.enterText(
      find.widgetWithText(TextField, 'RC number (synthetic)'),
      'DEMO-RC-5005',
    );
    await t.enterText(
      find.widgetWithText(TextField, 'Engine number (synthetic)'),
      'EVM-5005-DEMO',
    );
    await t.enterText(find.widgetWithText(TextField, 'Colour'), 'Silver');
    await _tap(t, find.widgetWithText(FilledButton, 'Add vehicle'));
    final v = _data(t).vehicle('C5')!;
    expect(v.rcNumber, 'DEMO-RC-5005');
    expect(v.engineNumber, 'EVM-5005-DEMO');
    expect(v.color, 'Silver');
    expect(find.text('Company allocations'), findsOneWidget);
    expect(find.text('Availability'), findsOneWidget);

    // Seeded C1 shows allocations and RC.
    await _go(t, '/fleet/vehicles/C1');
    expect(find.textContaining('Morning operations'), findsOneWidget);
  });

  testWidgets(
    'driver records: licence required, expiry badge, no Aadhaar/age',
    (t) async {
      await pumpApp(t, location: '/fleet/drivers', size: desktopSize);
      expect(
        find.textContaining('Expires'),
        findsWidgets,
        reason: 'DR3 licence expires within 30 days',
      );
      await _go(t, '/fleet/drivers/new');
      await t.enterText(find.widgetWithText(TextField, 'Driver ID'), 'DR5');
      await t.enterText(
        find.widgetWithText(TextField, 'Name (fictional)'),
        'Kavya Menon',
      );
      await _tap(t, find.widgetWithText(FilledButton, 'Add driver'));
      expect(find.textContaining('Licence number is required'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextField, 'Licence number (fictional, required)'),
        'DL-DEMO-0001',
      );
      await _tap(t, find.widgetWithText(FilledButton, 'Add driver'));
      expect(
        find.textContaining('already used by another driver'),
        findsOneWidget,
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Licence number (fictional, required)'),
        'DL-DEMO-0005',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Email (fictional)'),
        'dr5@fleet-demo.example',
      );
      await _tap(t, find.widgetWithText(FilledButton, 'Add driver'));
      final d = _data(t).driver('DR5')!;
      expect(d.licenceNumber, 'DL-DEMO-0005');
      expect(d.email, 'dr5@fleet-demo.example');
      expect(
        find.textContaining('Aadhaar'),
        findsOneWidget,
        reason: 'privacy note only',
      );
      expect(find.widgetWithText(TextField, 'Aadhaar'), findsNothing);
    },
  );

  testWidgets('parking: capacity and latitude validation, occupancy shown', (
    t,
  ) async {
    await pumpApp(t, location: '/fleet/parking', size: desktopSize);
    expect(find.textContaining('spots used'), findsWidgets);
    expect(find.text('Fleet-owned'), findsWidgets);
    await _tapText(t, 'Add location');
    await t.enterText(_inDialog(find.widgetWithText(TextField, 'Code')), 'P13');
    await t.enterText(
      _inDialog(find.widgetWithText(TextField, 'Name (fictional)')),
      'Lakeside Bay',
    );
    await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Add')));
    expect(find.textContaining('at least 1 spot'), findsOneWidget);
    await t.enterText(
      _inDialog(find.widgetWithText(TextField, 'Parking spots (capacity)')),
      '5',
    );
    await t.enterText(
      _inDialog(find.widgetWithText(TextField, 'Latitude (fictional)')),
      '91.5',
    );
    await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Add')));
    expect(find.textContaining('Latitude must be between'), findsOneWidget);
    await t.enterText(
      _inDialog(find.widgetWithText(TextField, 'Latitude (fictional)')),
      '12.95',
    );
    await _tap(t, _inDialog(find.widgetWithText(FilledButton, 'Add')));
    final p = _data(t).location('P13')!;
    expect(p.capacity, 5);
    expect(p.latitude, closeTo(12.95, 0.0001));
    expect(p.fleetOwned, isTrue);
    expect(_data(t).parkingAvailable('P13'), 5);
  });

  for (final size in [phoneSize, tabletSize, desktopSize]) {
    testWidgets(
      'registry pages render without overflow at ${size.width.toInt()}px',
      (t) async {
        await pumpApp(t, location: '/fleet/companies', size: size);
        final failures = <String>[];
        for (final path in [
          '/fleet/companies',
          '/fleet/companies/new',
          '/fleet/companies/C1',
          '/fleet/companies/C1?tab=contracts',
          '/fleet/companies/C1?tab=allocations',
          '/fleet/companies/C1?tab=audit',
          '/fleet/vehicles',
          '/fleet/vehicles/C1',
          '/fleet/drivers',
          '/fleet/drivers/DR3',
          '/fleet/parking',
        ]) {
          _c(t).read(routerProvider).go(path);
          await t.pump();
          await t.pump(const Duration(milliseconds: 300));
          Object? ex;
          while ((ex = t.takeException()) != null) {
            failures.add('$path → ${ex.toString().split('\n').first}');
          }
        }
        expect(failures, isEmpty, reason: failures.join('\n'));
      },
    );
  }
}
