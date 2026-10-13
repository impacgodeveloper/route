import 'package:executive_fleet/core/demo/clock.dart';
import 'package:executive_fleet/core/utils/formatters.dart';
import 'package:executive_fleet/core/widgets/form_fields.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/services/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employer_harness.dart';

/// Captures Clipboard.setData calls made by the UI.
String? _clipboard;
void _mockClipboard(WidgetTester tester) {
  _clipboard = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        _clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

Future<void> _pickDropdown(
  WidgetTester tester,
  Finder field,
  String item,
) async {
  await tapIt(tester, field);
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

/// Lets platform-channel futures (path_provider) finish, then settles.
Future<void> _realSettle(WidgetTester tester) async {
  for (var i = 0; i < 50; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (_clipboard != null ||
        find.textContaining('Saved').evaluate().isNotEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

String _resultsText(int n) => '$n result${n == 1 ? '' : 's'}';

void main() {
  group('Employees', () {
    testWidgets('filters, search, sort, paging, clear, row action', (
      tester,
    ) async {
      await pumpEmployer(tester, location: '/employer/employees');
      final data = dataOf(tester);
      expect(find.text(_resultsText(100)), findsOneWidget);
      expect(find.text('Show more (75 remaining)'), findsOneWidget);
      await tapIt(tester, find.text('Show more (75 remaining)'));
      expect(find.text('Show more (50 remaining)'), findsOneWidget);

      // Status filter.
      await _pickDropdown(tester, find.text('All statuses'), 'Inactive');
      expect(find.text(_resultsText(2)), findsOneWidget);
      expect(find.text('E99'), findsOneWidget);
      await tapIt(tester, find.text('Clear filters'));
      expect(find.text(_resultsText(100)), findsOneWidget);

      // Destination filter.
      final g1 = data.employees.where((e) => e.destinationId == 'G1').length;
      await _pickDropdown(
        tester,
        find.text('All destinations'),
        'G1 · Tech Park Tower A',
      );
      expect(find.text(_resultsText(g1)), findsOneWidget);

      // + pickup filter (combined).
      final g1pk01 = data.employees
          .where((e) => e.destinationId == 'G1' && e.pickupLocationId == 'PK01')
          .length;
      await _pickDropdown(
        tester,
        find.text('All pickups'),
        'PK01 · Cedar Park Gate',
      );
      expect(find.text(_resultsText(g1pk01)), findsOneWidget);
      await tapIt(tester, find.text('Clear filters'));

      // Arrival filter.
      final at830 = data.employees
          .where((e) => e.requiredArrivalMinutes == 510)
          .length;
      await _pickDropdown(tester, find.text('Any time'), '8:30 AM');
      expect(find.text(_resultsText(at830)), findsOneWidget);
      await tapIt(tester, find.text('Clear filters'));

      // Sort by name.
      final first = ([
        ...data.employees,
      ]..sort((a, b) => a.name.compareTo(b.name))).first;
      await _pickDropdown(tester, find.text('Employee ID'), 'Name');
      expect(find.text(first.name), findsWidgets);

      // Search (by code) and no-results state with clear.
      await tester.enterText(find.byType(TextField).first, 'E42');
      await tester.pumpAndSettle();
      expect(find.text(_resultsText(1)), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('No employees match'), findsOneWidget);
      await tapIt(tester, find.widgetWithText(OutlinedButton, 'Clear filters'));
      expect(find.text(_resultsText(100)), findsOneWidget);

      // Row action opens detail.
      await tester.enterText(find.byType(TextField).first, 'Kiran');
      await tester.pumpAndSettle();
      await tapIt(tester, find.text('Kiran Mehta'));
      expect(currentPath(tester), '/employer/employees/E2');
      expect(find.text('E2 · Kiran Mehta'), findsOneWidget);
    });

    testWidgets(
      'add with duplicate ID error, then create, edit, deactivate, reactivate',
      (tester) async {
        await pumpEmployer(tester, location: '/employer/employees');
        await tapIt(tester, find.text('Add employee'));
        expect(currentPath(tester), '/employer/employees/new');
        // Empty submit → field validation.
        await tapIt(tester, find.text('Create employee'));
        expect(find.text('Employee ID is required'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Employee ID'),
          'E1',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Full name'),
          'Audit Person',
        );
        await tapIt(tester, find.text('Create employee'));
        expect(find.text('Not saved'), findsOneWidget);
        expect(find.text('Employee ID E1 already exists.'), findsOneWidget);
        // Input preserved; fix ID and create.
        expect(find.text('Audit Person'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Employee ID'),
          'E150',
        );
        await tapIt(tester, find.text('Create employee'));
        expect(currentPath(tester), '/employer/employees/E150');
        expect(dataOf(tester).employee('E150')!.name, 'Audit Person');

        // Edit.
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Shift label'),
          'Morning 9:00 AM',
        );
        await tapIt(tester, find.text('Save changes'));
        expect(dataOf(tester).employee('E150')!.shiftLabel, 'Morning 9:00 AM');

        // Deactivate: cancel, then confirm with a too-short reason, then valid.
        await tapIt(tester, find.text('Deactivate'));
        await tapIt(tester, find.widgetWithText(TextButton, 'Cancel').last);
        expect(dataOf(tester).employee('E150')!.isActive, isTrue);
        await tapIt(tester, find.text('Deactivate'));
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Reason for deactivation'),
          'no',
        );
        await tapIt(tester, find.widgetWithText(FilledButton, 'Deactivate'));
        expect(find.text('Enter at least 5 characters'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Reason for deactivation'),
          'Audit deactivation',
        );
        await tapIt(tester, find.widgetWithText(FilledButton, 'Deactivate'));
        expect(dataOf(tester).employee('E150')!.isActive, isFalse);
        expect(find.text('Inactive employee'), findsOneWidget);

        // Reactivate: cancel, then confirm.
        await tapIt(tester, find.text('Reactivate'));
        await tapIt(tester, find.widgetWithText(TextButton, 'Cancel').last);
        expect(dataOf(tester).employee('E150')!.isActive, isFalse);
        await tapIt(tester, find.text('Reactivate').first);
        await tapIt(tester, find.widgetWithText(FilledButton, 'Reactivate'));
        expect(dataOf(tester).employee('E150')!.isActive, isTrue);
      },
    );
  });

  testWidgets(
    'CSV import: mapping change, allow-updates, cancel commit, commit',
    (tester) async {
      await pumpEmployer(tester, location: '/employer/policies/import');
      // Preview without input.
      await tapIt(tester, find.text('Preview import'));
      expect(
        find.text('Paste CSV text or choose a file first.'),
        findsOneWidget,
      );
      const csv =
          'employee_code,name,pickup_code,destination_code,arrival_time\n'
          'E201,Demo Person,PK01,G1,09:00\n'
          'E1,Existing Person,PK01,G1,09:00\n'
          'E201,Duplicate Row,PK01,G1,09:00\n';
      await tester.enterText(find.byKey(const Key('roster-paste')), csv);
      await tapIt(tester, find.text('Preview import'));
      expect(find.textContaining('Duplicate of row 2'), findsOneWidget);
      expect(find.text('Import 1 valid row'), findsOneWidget);

      // Unmap arrival time → file error, import disabled.
      await _pickDropdown(
        tester,
        find.byKey(const ValueKey('map-arrivalTime-4')),
        '— Not mapped —',
      );
      expect(find.text('Map a column to "Arrival time".'), findsOneWidget);
      final disabled = tester.widget<ButtonStyleButton>(
        find
            .ancestor(
              of: find.textContaining('valid row'),
              matching: find.bySubtype<ButtonStyleButton>(),
            )
            .first,
      );
      expect(disabled.onPressed, isNull);
      await _pickDropdown(
        tester,
        find.byKey(const ValueKey('map-arrivalTime-null')),
        'arrival_time',
      );
      expect(find.text('Map a column to "Arrival time".'), findsNothing);

      // Allow updates → E1 becomes an update.
      await tapIt(tester, find.text('Allow updates to existing employees'));
      expect(find.text('Import 2 valid rows'), findsOneWidget);
      expect(find.textContaining('Will UPDATE existing E1'), findsOneWidget);

      // Cancel commit → nothing saved.
      await tapIt(tester, find.text('Import 2 valid rows'));
      expect(find.text('Import 2 employees?'), findsOneWidget);
      await tapIt(tester, find.widgetWithText(TextButton, 'Cancel'));
      expect(dataOf(tester).employee('E201'), isNull);
      expect(dataOf(tester).employee('E1')!.name, 'Asha Rao');

      // Commit.
      await tapIt(tester, find.text('Import 2 valid rows'));
      await tapIt(tester, find.widgetWithText(FilledButton, 'Import'));
      expect(dataOf(tester).employee('E201')!.name, 'Demo Person');
      expect(dataOf(tester).employee('E1')!.name, 'Existing Person');
      expect(find.text('Roster imported'), findsOneWidget);
      await tapIt(tester, find.text('View employees'));
      expect(currentPath(tester), '/employer/employees');
    },
  );

  testWidgets('CSV import: sample template path', (tester) async {
    _mockClipboard(tester);
    await pumpEmployer(tester, location: '/employer/policies/import');
    await tapIt(tester, find.text('Copy template'));
    expect(_clipboard, RosterImportService.template);
    await tapIt(tester, find.text('Use sample'));
    expect(find.text('Import 2 valid rows'), findsOneWidget);
    await tapIt(tester, find.text('Start over'));
    expect(find.text('Import 2 valid rows'), findsNothing);
  });

  group('Policies', () {
    testWidgets(
      'rate needs confirmation (cancel + apply); guard needs confirmation',
      (tester) async {
        await pumpEmployer(tester, location: '/employer/policies');
        final save = find.widgetWithText(FilledButton, 'Save policies');
        expect(
          tester.widget<FilledButton>(save).onPressed,
          isNull,
          reason: 'disabled until changed',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Distance rate'),
          '20',
        );
        await tapIt(tester, save);
        expect(find.text('Apply policy changes?'), findsOneWidget);
        await tapIt(tester, find.widgetWithText(TextButton, 'Cancel'));
        expect(dataOf(tester).primaryEmployer.defaultDistanceRate, 18);
        await tapIt(tester, save);
        await tapIt(tester, find.text('Apply changes'));
        expect(dataOf(tester).primaryEmployer.defaultDistanceRate, 20);

        await tapIt(tester, find.text('Security guard policy'));
        await tapIt(tester, save);
        expect(find.textContaining('Security guard policy ON'), findsOneWidget);
        await tapIt(tester, find.text('Apply changes'));
        expect(
          dataOf(tester).primaryEmployer.securityGuardPolicyEnabled,
          isTrue,
        );

        // Discard reverts unsaved edits.
        await tapIt(tester, find.text('Allow shared pooling'));
        await tapIt(tester, find.text('Discard'));
        expect(dataOf(tester).primaryEmployer.allowSharedPooling, isTrue);
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
      },
    );

    testWidgets('max arrival change needs confirmation', (tester) async {
      await pumpEmployer(tester, location: '/employer/policies');
      await tapIt(tester, find.text('9:30 AM'));
      await tapIt(tester, find.byIcon(Icons.keyboard_outlined));
      final fields = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), '10');
      await tester.enterText(fields.at(1), '00');
      await tapIt(tester, find.text('OK'));
      expect(find.text('10:00 AM'), findsOneWidget);
      await tapIt(tester, find.widgetWithText(FilledButton, 'Save policies'));
      expect(
        find.textContaining('Maximum arrival 9:30 AM → 10:00 AM'),
        findsOneWidget,
      );
      await tapIt(tester, find.text('Apply changes'));
      expect(dataOf(tester).primaryEmployer.maximumArrivalMinutes, 600);
    });

    testWidgets(
      'EV target change is reflected on Overview; vehicle type & luxury persist',
      (tester) async {
        await pumpEmployer(tester, location: '/employer/policies');
        final evSlider = find.descendant(
          of: find.ancestor(
            of: find.text('EV allocation target (%)'),
            matching: find.byType(WeightSlider),
          ),
          matching: find.byType(Slider),
        );
        await tester.ensureVisible(evSlider);
        await tester.pumpAndSettle();
        await tester.drag(evSlider, const Offset(800, 0));
        await tester.pumpAndSettle();
        await tapIt(tester, find.widgetWithText(FilterChip, 'Mini bus'));
        await tapIt(tester, find.text('Premium'));
        await tapIt(tester, find.widgetWithText(FilledButton, 'Save policies'));
        final e = dataOf(tester).primaryEmployer;
        expect(e.preferredEvPercentage, 100);
        expect(e.vehicleTypePreferences, contains(VehicleType.minibus));
        expect(e.luxuryPreference, LuxuryClass.premium);
        await tapIt(tester, find.text('Overview').first);
        expect(find.textContaining('/ 100% target'), findsOneWidget);
      },
    );
  });

  testWidgets(
    'Pickup locations: add with validation, edit, deactivation blocked while in use',
    (tester) async {
      await pumpEmployer(tester, location: '/employer/locations');
      await tapIt(tester, find.text('Add pickup point'));
      await tapIt(tester, find.widgetWithText(FilledButton, 'Add'));
      expect(find.text('Code is required'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Code'),
        'PK13',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Audit Gate',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Demo X (km)'),
        '50',
      );
      await tapIt(tester, find.widgetWithText(FilledButton, 'Add'));
      expect(find.text('0–40'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Demo X (km)'),
        '12',
      );
      await tapIt(tester, find.widgetWithText(FilledButton, 'Add'));
      expect(dataOf(tester).location('PK13')!.name, 'Audit Gate');

      // Edit.
      await tapIt(tester, find.byTooltip('Edit PK13'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Audit Gate North',
      );
      await tapIt(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(dataOf(tester).location('PK13')!.name, 'Audit Gate North');

      // Cancel edit leaves data.
      await tapIt(tester, find.byTooltip('Edit PK13'));
      await tapIt(tester, find.widgetWithText(TextButton, 'Cancel'));

      // Deactivation of an in-use point is blocked with a visible reason.
      await tapIt(tester, find.byTooltip('Edit PK01'));
      await tapIt(tester, find.widgetWithText(SwitchListTile, 'Active'));
      await tapIt(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(find.textContaining('use PK01'), findsOneWidget);
      expect(dataOf(tester).location('PK01')!.active, isTrue);
      await tapIt(tester, find.widgetWithText(TextButton, 'Cancel'));

      // Row selection highlights the point.
      await tapIt(tester, find.text('Orchid Enclave'));
    },
  );

  testWidgets('Assignments: date switch, filters, trip detail and back', (
    tester,
  ) async {
    await pumpEmployer(tester, location: '/employer/assignments');
    expect(find.text('TR-1001'), findsOneWidget);
    await tapIt(tester, find.byTooltip('Next day'));
    expect(find.text('TR-1004'), findsOneWidget);
    expect(find.text('TR-1001'), findsNothing);
    await tapIt(tester, find.textContaining('Completed ·'));
    expect(find.text('No trips match this filter.'), findsOneWidget);
    await tapIt(tester, find.text('Show all'));
    expect(find.text('TR-1004'), findsOneWidget);
    await tapIt(tester, find.text('TR-1004'));
    expect(currentPath(tester), '/employer/assignments/TR-1004');
    expect(find.text('Not assigned'), findsWidgets);
    await tapIt(tester, find.text('Assignments').last);
    await tapIt(tester, find.byTooltip('Previous day'));
    await tapIt(tester, find.byTooltip('Previous day'));
    expect(find.text('TR-0991'), findsOneWidget);
    await tapIt(tester, find.text('Today'));
    expect(find.text('TR-1001'), findsOneWidget);
    await tapIt(tester, find.text('TR-1002'));
    expect(find.text('Trip TR-1002'), findsOneWidget);
    expect(find.textContaining('Simulated location'), findsOneWidget);
    await tapIt(
      tester,
      find.text('Kiran Mehta').evaluate().isEmpty
          ? find.textContaining('E5 ·')
          : find.text('Kiran Mehta'),
    );
    expect(currentPath(tester), '/employer/employees/E5');
  });

  group('Billing', () {
    testWidgets(
      'review → paid(demo); dispute with reason (cancel first) → resolve',
      (tester) async {
        await pumpEmployer(tester, location: '/employer/billing?tab=lines');
        await tapIt(tester, find.text('TR-0993'));
        expect(currentPath(tester), '/employer/billing/BL-1003');
        expect(find.textContaining('34.9 km × ₹18.00/km'), findsWidgets);
        await tapIt(tester, find.text('Mark reviewed'));
        expect(
          dataOf(tester).billingRecord('BL-1003')!.status,
          BillingStatus.reviewed,
        );
        await tapIt(tester, find.text('Mark paid (demo)'));
        expect(find.text('Mark as paid (demo)?'), findsOneWidget);
        await tapIt(tester, find.widgetWithText(TextButton, 'Cancel'));
        expect(
          dataOf(tester).billingRecord('BL-1003')!.status,
          BillingStatus.reviewed,
        );
        await tapIt(tester, find.text('Mark paid (demo)'));
        await tapIt(
          tester,
          find.widgetWithText(FilledButton, 'Mark paid (demo)').last,
        );
        expect(
          dataOf(tester).billingRecord('BL-1003')!.status,
          BillingStatus.paidDemo,
        );
        expect(
          find.text('Paid (demo) is final in this prototype.'),
          findsOneWidget,
        );

        await goTo(tester, '/employer/billing?tab=lines');
        await tapIt(tester, find.text('TR-0992'));
        await tapIt(tester, find.text('Dispute'));
        await tapIt(tester, find.widgetWithText(TextButton, 'Cancel'));
        expect(
          dataOf(tester).billingRecord('BL-1002')!.status,
          BillingStatus.reviewed,
        );
        await tapIt(tester, find.text('Dispute'));
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Dispute reason'),
          'Toll was not used on this trip',
        );
        await tapIt(tester, find.widgetWithText(FilledButton, 'Dispute'));
        final b = dataOf(tester).billingRecord('BL-1002')!;
        expect(b.status, BillingStatus.disputed);
        expect(b.disputeReason, 'Toll was not used on this trip');
        expect(find.text('Dispute reason'), findsOneWidget);
        await tapIt(tester, find.text('Resolve & mark reviewed'));
        expect(
          dataOf(tester).billingRecord('BL-1002')!.status,
          BillingStatus.reviewed,
        );
      },
    );

    testWidgets(
      'filters, totals, record distance for TR-0994, CSV copy/export',
      (tester) async {
        _mockClipboard(tester);
        await pumpEmployer(tester, location: '/employer/billing?tab=lines');
        String total() => (tester.widget<Text>(
          find
              .descendant(
                of: find.byKey(const Key('billing-total')),
                matching: find.textContaining('₹'),
              )
              .first,
        )).data!;
        double sum(bool Function(BillingRecord) f) => dataOf(
          tester,
        ).billingOf('C1').where(f).fold(0.0, (s, b) => s + b.totalAmount);
        expect(total(), Fmt.inr(sum((_) => true)));

        // Status filter.
        await tapIt(tester, find.text('Paid (demo) · 1'));
        expect(
          total(),
          Fmt.inr(sum((b) => b.status == BillingStatus.paidDemo)),
        );
        expect(find.text('TR-0992'), findsNothing);
        await tapIt(tester, find.text('Disputed · 0'));
        expect(find.text('No billing lines'), findsOneWidget);
        await tapIt(tester, find.widgetWithText(OutlinedButton, 'Show all'));
        expect(total(), Fmt.inr(sum((_) => true)));

        // Period filters.
        await tapIt(tester, find.text('Last 7 days'));
        expect(total(), Fmt.inr(sum((_) => true)));
        await tapIt(tester, find.text('Custom'));
        expect(find.byType(DateRangePickerDialog), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        await tapIt(tester, find.text('All time'));

        // Record distance & bill: validation, then success; billed once.
        await tapIt(tester, find.text('Record distance & bill'));
        await tapIt(tester, find.text('Record & bill'));
        expect(find.text('Distance is required'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('distance-km')), '-3');
        await tester.enterText(
          find.byKey(const Key('distance-note')),
          'Odometer photo',
        );
        await tapIt(tester, find.text('Record & bill'));
        expect(find.text('Distance cannot be negative'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('distance-km')), '20');
        await tester.pumpAndSettle();
        expect(find.textContaining('20.0 km × ₹18.00/km'), findsOneWidget);
        await tapIt(tester, find.text('Record & bill'));
        expect(dataOf(tester).billingForTrip('TR-0994')!.totalAmount, 360);
        expect(find.text('Record distance & bill'), findsNothing);
        expect(total(), Fmt.inr(sum((_) => true)));

        // CSV copy and export (export falls back to clipboard in tests).
        await tapIt(tester, find.text('Copy CSV'));
        expect(_clipboard, contains('TR-0994'));
        expect(_clipboard!.split('\r\n').first, startsWith('Billing ID,Trip'));
        _clipboard = null;
        await tapIt(tester, find.text('Export CSV'));
        await _realSettle(tester);
        expect(
          _clipboard != null ||
              find.textContaining('Saved').evaluate().isNotEmpty,
          isTrue,
        );
        expect(_clipboard ?? 'TR-0994', contains('TR-0994'));
      },
    );
  });

  testWidgets('Reports ranges and export', (tester) async {
    _mockClipboard(tester);
    await pumpEmployer(tester, location: '/employer/reports');
    expect(find.textContaining('13 Oct 2026'), findsOneWidget);
    await tapIt(tester, find.text('14 days'));
    expect(find.textContaining('6 Oct 2026'), findsOneWidget);
    await tapIt(tester, find.text('30 days'));
    expect(
      find.textContaining('20 Sept 2026').evaluate().isNotEmpty ||
          find.textContaining('20 Sep 2026').evaluate().isNotEmpty,
      isTrue,
    );
    expect(find.text('Trip volume per day'), findsOneWidget);
    await tapIt(tester, find.text('Export CSV'));
    await _realSettle(tester);
    expect(
      _clipboard != null || find.textContaining('Saved').evaluate().isNotEmpty,
      isTrue,
    );
  });

  testWidgets('Settings save with confirmation and audit filter', (
    tester,
  ) async {
    await pumpEmployer(tester, location: '/employer/settings');
    await tester.enterText(
      find.widgetWithText(TextField, 'Billing rate'),
      '19',
    );
    await tapIt(tester, find.text('Save settings'));
    expect(find.text('Save company settings?'), findsOneWidget);
    await tapIt(tester, find.widgetWithText(TextButton, 'Cancel'));
    expect(dataOf(tester).primaryEmployer.defaultDistanceRate, 18);
    await tester.enterText(
      find.widgetWithText(TextField, 'Company name'),
      'C1 Corporate Services Ltd',
    );
    await tapIt(tester, find.text('Save settings'));
    await tapIt(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(dataOf(tester).primaryEmployer.defaultDistanceRate, 19);
    expect(dataOf(tester).primaryEmployer.name, 'C1 Corporate Services Ltd');
    expect(
      find.text('C1 Corporate Services Ltd'),
      findsWidgets,
    ); // sidebar org label updates

    // Shared audit view: the change is recorded; search and record-type filter.
    final search = find.widgetWithText(
      TextField,
      'Search by audit ID, record ID, actor or text',
    );
    await tester.enterText(search, 'TR-1005');
    await tester.pumpAndSettle();
    expect(find.textContaining('Cancelled TR-1005'), findsOneWidget);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    await pickAuditFilter(tester, 'Record type', 'billing');
    expect(
      find.textContaining('Billing generated for TR-0993'),
      findsOneWidget,
    );
    expect(find.textContaining('Cancelled TR-1005'), findsNothing);
    await tapIt(tester, find.text('Back to sign-in'));
    expect(currentPath(tester), '/');
  });

  testWidgets('Notifications panel opens the right records', (tester) async {
    await pumpEmployer(tester, location: '/employer/overview');
    await tapIt(tester, find.byTooltip('Notifications'));
    expect(currentPath(tester), '/employer/notifications');
    await tapIt(tester, find.text('Billing generated: TR-0993'));
    expect(currentPath(tester), '/employer/billing/BL-1003');
    await tapIt(tester, find.byTooltip('Notifications'));
    await tapIt(tester, find.text('Booking request BK-1004'));
    expect(currentPath(tester), '/employer/employees/E4');
    await tapIt(tester, find.byTooltip('Notifications'));
    await tapIt(tester, find.text('Unread · 0'));
    expect(find.text('You\'re all caught up'), findsOneWidget);
  });

  testWidgets(
    'Cross-app: driver completion bills on screen; employee booking appears',
    (tester) async {
      await pumpEmployer(tester, location: '/employer/billing?tab=lines');
      final before = dataOf(tester).billingOf('C1').length;
      final trip = dataOf(tester).trips.byId('TR-1002')!;
      final r = await servicesOf(tester).driverOps.completeTrip(
        tripId: 'TR-1002',
        driverId: 'DR2',
        endOdometerKm: trip.startOdometerKm! + 40,
        exceptionReason: 'Audit test closes remaining stops',
        exceptionAuthorizedBy: 'Fleet Manager (demo)',
      );
      expect(r.isOk, isTrue, reason: r.message);
      await tester.pumpAndSettle();
      final records = dataOf(tester).billingOf('C1');
      expect(records.length, before + 1);
      expect(find.text('TR-1002'), findsOneWidget);
      final sum = records.fold<double>(0, (s, b) => s + b.totalAmount);
      expect(
        find.descendant(
          of: find.byKey(const Key('billing-total')),
          matching: find.text(Fmt.inr(sum)),
        ),
        findsOneWidget,
      );

      // Employee booking request → Overview requests list.
      final e = dataOf(tester).employee('E40')!;
      final b = await servicesOf(tester).bookings.submit(
        BookingDraft(
          employeeId: 'E40',
          pickupLocationId: e.pickupLocationId,
          destinationId: e.destinationId,
          date: dateOnly(dataOf(tester).now).add(const Duration(days: 1)),
          arrivalMinutes: e.requiredArrivalMinutes,
        ),
      );
      expect(b.isOk, isTrue, reason: b.message);
      await tapIt(tester, find.text('Overview').first);
      expect(
        find.textContaining('${b.valueOrNull!.reference} · E40'),
        findsOneWidget,
      );
      expect(find.text('7'), findsWidgets); // requests KPI now 7
    },
  );

  const paths = [
    '/employer/overview',
    '/employer/employees',
    '/employer/employees/E1',
    '/employer/employees/new',
    '/employer/policies',
    '/employer/policies/import',
    '/employer/locations',
    '/employer/assignments',
    '/employer/assignments/TR-1002',
    '/employer/billing',
    '/employer/billing/BL-1001',
    '/employer/reports',
    '/employer/settings',
    '/employer/notifications',
  ];
  for (final (size, scale) in [
    (phoneSize, 1.0),
    (tabletSize, 1.0),
    (desktopSize, 1.0),
    (desktopSize, 1.3),
  ]) {
    testWidgets(
      'no overflow on all employer screens at ${size.width.toInt()}px ×$scale',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpEmployer(tester, location: '/employer/overview', size: size);
        for (final p in paths) {
          await goTo(tester, p);
          expect(tester.takeException(), isNull, reason: p);
          expect(currentPath(tester), p);
        }
      },
    );
  }
}
