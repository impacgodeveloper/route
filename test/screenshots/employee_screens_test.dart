@Tags(['screenshot'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:executive_fleet/app/providers.dart';
import 'package:executive_fleet/app/router.dart';
import 'package:executive_fleet/domain/models/models.dart';

import '../widget/employee/employee_harness.dart';
import 'screenshot_util.dart';

Future<void> _signIn(WidgetTester t, String name) async {
  await pumpEmployeeApp(t);
  await t.tap(find.text(name));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('employee login', (t) async {
    await pumpEmployeeApp(t, location: '/employee/login');
    await snap(t, 'employee_login');
  });

  testWidgets('employee home + tabs', (t) async {
    await _signIn(t, 'Asha Rao');
    await snap(t, 'employee_home');
    for (final (tab, name) in [
      ('My Trips', 'trips'),
      ('Book', 'book'),
      ('Activity', 'activity'),
      ('Profile', 'profile'),
    ]) {
      await t.tap(find.text(tab).last);
      await t.pumpAndSettle();
      await snap(t, 'employee_$name');
    }
  });

  testWidgets('employee trip detail + pass', (t) async {
    await _signIn(t, 'Asha Rao');
    await t.tap(find.text('Details'));
    await t.pumpAndSettle();
    await snap(t, 'employee_trip_detail');
    await t.tap(find.text('Show e-pass'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Reveal T-PIN'));
    await t.pumpAndSettle();
    await snap(t, 'employee_pass');
  });

  testWidgets('employee active trip tracking (E5 on TR-1002)', (t) async {
    await pumpEmployeeApp(t, location: '/employee/login');
    await t.enterText(find.byType(TextField), 'E5');
    await t.pumpAndSettle();
    await t.tap(find.textContaining('E5 ·').first);
    await t.pumpAndSettle();
    await snap(t, 'employee_home_active');
    await t.tap(find.text('Track trip'));
    await t.pumpAndSettle();
    await snap(t, 'employee_tracking');
  });

  testWidgets('employee safety + roster', (t) async {
    await _signIn(t, 'Asha Rao');
    await t.tap(find.text('Safety'));
    await t.pumpAndSettle();
    await snap(t, 'employee_safety');
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Schedule'));
    await t.pumpAndSettle();
    await snap(t, 'employee_roster');
  });

  testWidgets('employee v2: preferences, schedule card, traffic', (t) async {
    await _signIn(t, 'Asha Rao');
    final router = containerOf(t).read(routerProvider);
    router.go('/employee/preferences');
    await t.pumpAndSettle();
    await snap(t, 'employee_preferences');
    router.go('/employee/profile');
    await t.pumpAndSettle();
    await t.drag(find.byType(Scrollable).first, const Offset(0, -520));
    await t.pumpAndSettle();
    await snap(t, 'employee_schedule_card');
    await servicesOf(t).traffic.setScenario(
      internalRoads: TrafficLevel.heavy,
      ringRoad: TrafficLevel.heavy,
    );
    router.go('/employee/trip/TR-1001');
    await t.pumpAndSettle();
    await snap(t, 'employee_trip_window');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -560));
    await t.pumpAndSettle();
    await snap(t, 'employee_trip_traffic');
    final rev = dataOf(t).openRevision('TR-1001');
    if (rev != null) await servicesOf(t).traffic.applyRevision(rev.id);
    router.go('/employee/home');
    await t.pumpAndSettle();
    router.go('/employee/trip/TR-1001');
    await t.pumpAndSettle();
    await snap(t, 'employee_trip_revised');
  });

  testWidgets('employee v3: SOS chain, absence, instant match', (t) async {
    await pumpEmployeeApp(t);
    final s = servicesOf(t);
    await s.policy.save(dataOf(t).policy.copyWith(autoMatchAdhoc: true));
    await s.assignments.commit(
      AssignmentRequest(
        employerId: 'C1',
        serviceDate: dataOf(t).today.add(const Duration(days: 1)),
        employeeIds: const ['E1'],
        driverId: 'DR3',
        vehicleId: 'C3',
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Kiran Mehta'));
    await t.pumpAndSettle();
    await snap(t, 'employee_home_absence_action');
    final router = containerOf(t).read(routerProvider);
    router.go('/employee/safety');
    await t.pumpAndSettle();
    await t.tap(find.text('Raise SOS'));
    await t.pumpAndSettle();
    await t.tap(find.text('Raise SOS').last);
    await t.pumpAndSettle();
    final sos = dataOf(t).incidents.firstWhere((i) => i.isSos);
    final fm = dataOf(t)
        .sosDispatchesOf(sos.id)
        .firstWhere((d) => d.recipient == SosRecipient.fleetManager);
    await s.incidents.acknowledgeSos(fm.id);
    await t.pumpAndSettle();
    await t.drag(find.byType(Scrollable).first, const Offset(0, -380));
    await t.pumpAndSettle();
    await snap(t, 'employee_sos_chain');
    router.go('/employee/home');
    await t.pumpAndSettle();
    await snap(t, 'employee_home_sos');
    router.go('/employee/book');
    await t.pumpAndSettle();
    await t.tap(find.text('Review request'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining(RegExp(r'^Submit')));
    await t.pumpAndSettle();
    await snap(t, 'employee_book_matched');
    await s.matching.reportAbsence('TR-1001', 'E2', 'Working from home');
    router.go('/employee/trip/TR-1001');
    await t.pumpAndSettle();
    await snap(t, 'employee_trip_absent');
  });
}
