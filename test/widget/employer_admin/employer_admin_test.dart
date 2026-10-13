import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/core/utils/formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employer_harness.dart';

DataView _data(WidgetTester tester) => dataOf(tester);

AppServices _services(WidgetTester tester) => servicesOf(tester);

Future<void> _tap(WidgetTester tester, Finder f) => tapIt(tester, f);

void main() {
  testWidgets('sidebar navigates across all 9 sections', (tester) async {
    await pumpEmployer(tester, location: '/employer', size: desktopSize);
    expect(find.textContaining('Good day'), findsOneWidget);
    for (final (label, marker) in [
      ('Employees', 'Search by employee ID or name'),
      ('Rosters & Policies', 'Save policies'),
      ('Pickup Locations', 'Add pickup point'),
      ('Fleet Assignments', 'Read-only for employer admins'),
      ('Billing', 'Run billing cycle (demo)'),
      ('Traffic & Movement', 'Read-only for employer admins'),
      ('Reports', 'Trip volume per day'),
      ('Settings', 'Audit trail'),
      ('Overview', 'EV allocation'),
    ]) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(find.text(marker), findsWidgets, reason: label);
    }
  });

  testWidgets('employee search and edit persists', (tester) async {
    await pumpEmployer(
      tester,
      location: '/employer/employees',
      size: desktopSize,
    );
    await tester.enterText(find.byType(TextField).first, 'Asha');
    await tester.pumpAndSettle();
    expect(find.text('Asha Rao'), findsOneWidget);
    expect(find.text('1 result'), findsOneWidget);
    await tester.tap(find.text('Asha Rao'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      'Asha Rao K',
    );
    await _tap(tester, find.text('Save changes'));
    expect(_data(tester).employee('E1')!.name, 'Asha Rao K');
  });

  testWidgets('deactivation needs confirmation and preserves history', (
    tester,
  ) async {
    await pumpEmployer(
      tester,
      location: '/employer/employees/E3',
      size: desktopSize,
    );
    await _tap(tester, find.text('Deactivate'));
    expect(find.text('Deactivate E3?'), findsOneWidget);
    await _tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
    expect(_data(tester).employee('E3')!.isActive, isTrue);
    final tripsBefore = _data(tester).trips.forEmployee('E3').length;
    await _tap(tester, find.text('Deactivate'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason for deactivation'),
      'Left the company (demo)',
    );
    await _tap(tester, find.widgetWithText(FilledButton, 'Deactivate'));
    expect(_data(tester).employee('E3')!.isActive, isFalse);
    expect(_data(tester).trips.forEmployee('E3').length, tripsBefore);
    expect(find.text('Inactive employee'), findsOneWidget);
  });

  testWidgets(
    'CSV paste import shows row errors and commits only after confirm',
    (tester) async {
      await pumpEmployer(
        tester,
        location: '/employer/policies/import',
        size: desktopSize,
      );
      const csv =
          'employee_code,name,pickup_code,destination_code,arrival_time\n'
          'E201,Demo Person,PK01,G1,09:00\n'
          'E202,Bad Pickup,PK99,G1,09:00\n'
          'E1,Existing Person,PK01,G1,09:00\n'
          'E203,Late Person,PK02,G2,25:00\n';
      await tester.enterText(find.byKey(const Key('roster-paste')), csv);
      await _tap(tester, find.text('Preview import'));
      expect(find.text('Unknown pickup "PK99".'), findsOneWidget);
      expect(find.textContaining('already exists'), findsOneWidget);
      expect(find.textContaining('Invalid time'), findsOneWidget);
      expect(find.text('3 rejected'), findsOneWidget);
      expect(_data(tester).employee('E201'), isNull);
      await _tap(tester, find.text('Import 1 valid row'));
      expect(find.text('Import 1 employees?'), findsOneWidget);
      await _tap(tester, find.widgetWithText(FilledButton, 'Import'));
      expect(_data(tester).employee('E201'), isNotNull);
      expect(_data(tester).employee('E1')!.name, 'Asha Rao');
      expect(find.text('Roster imported'), findsOneWidget);
    },
  );

  testWidgets('policy save persists', (tester) async {
    await pumpEmployer(
      tester,
      location: '/employer/policies',
      size: desktopSize,
    );
    expect(_data(tester).primaryEmployer.allowCrossEmployerPooling, isFalse);
    await _tap(tester, find.text('Allow cross-employer pooling'));
    await _tap(tester, find.text('Save policies'));
    expect(_data(tester).primaryEmployer.allowCrossEmployerPooling, isTrue);
  });

  testWidgets('billing totals match records', (tester) async {
    await pumpEmployer(
      tester,
      location: '/employer/billing?tab=lines',
      size: desktopSize,
    );
    await _tap(tester, find.textContaining('All time'));
    final records = _data(tester).billingOf('C1');
    final sum = records.fold<double>(0, (s, b) => s + b.totalAmount);
    expect(records, isNotEmpty);
    expect(
      find.descendant(
        of: find.byKey(const Key('billing-total')),
        matching: find.text(Fmt.inr(sum)),
      ),
      findsOneWidget,
    );
  });

  testWidgets('missing-distance trip TR-0994 bills exactly once', (
    tester,
  ) async {
    await pumpEmployer(
      tester,
      location: '/employer/billing?tab=lines',
      size: desktopSize,
    );
    expect(find.textContaining('TR-0994'), findsWidgets);
    expect(_data(tester).billingForTrip('TR-0994'), isNull);
    await _tap(tester, find.text('Record distance & bill'));
    await tester.enterText(find.byKey(const Key('distance-km')), '21.5');
    await tester.enterText(
      find.byKey(const Key('distance-note')),
      'Odometer photo from driver',
    );
    await _tap(tester, find.text('Record & bill'));
    final bill = _data(tester).billingForTrip('TR-0994');
    expect(bill, isNotNull);
    expect(bill!.totalAmount, closeTo(21.5 * 18, 0.01));
    expect(find.text('Record distance & bill'), findsNothing);
    final again = await _services(
      tester,
    ).billing.recordDistanceAndBill('TR-0994', 30, 'Second attempt');
    expect(again.isOk, isFalse);
    expect(
      _data(tester).billingOf('C1').where((b) => b.tripId == 'TR-0994').length,
      1,
    );
  });

  for (final size in [phoneSize, tabletSize, desktopSize]) {
    for (final path in [
      '/employer/overview',
      '/employer/employees',
      '/employer/billing',
      '/employer/assignments/TR-1002',
      '/employer/policies',
      '/employer/reports',
    ]) {
      testWidgets('$path renders without overflow at ${size.width.toInt()}px', (
        tester,
      ) async {
        await pumpEmployer(tester, location: path, size: size);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
