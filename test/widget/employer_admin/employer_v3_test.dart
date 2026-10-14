import 'package:executive_fleet/core/utils/formatters.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:executive_fleet/domain/services/app_services.dart';
import 'package:executive_fleet/features/employer_admin/analytics_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employer_harness.dart';

String _tileValue(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
    )
    .elementAt(1)
    .data!;

void main() {
  testWidgets(
    'analytics KPIs equal service values for 7 days; disclaimer; ranges; CSV',
    (tester) async {
      String? clip;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (c) async {
          if (c.method == 'Clipboard.setData') {
            clip = (c.arguments as Map)['text'] as String?;
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

      await pumpEmployer(tester, location: '/employer/overview');
      await tapIt(tester, find.text('Analytics & Carbon').first);
      expect(currentPath(tester), '/employer/analytics');
      final data = dataOf(tester);
      final s = servicesOf(tester).analytics.summary(
        data.primaryEmployer.id,
        DateRange.lastDays(data.today, 7),
      );
      expect(s.trips, isNotEmpty);
      expect(_tileValue(tester, 'kpi-co2'), fmtKg(s.co2SavedKg));
      expect(
        _tileValue(tester, 'kpi-time'),
        '${(s.minutesSaved / 60).toStringAsFixed(1)} vehicle-h',
      );
      expect(_tileValue(tester, 'kpi-cost'), Fmt.inr0(s.costSaved));
      expect(_tileValue(tester, 'kpi-riders'), '${s.riders}');
      expect(_tileValue(tester, 'kpi-km'), Fmt.km(s.vehicleKm));
      expect(
        find.text('${s.creditTonnes.toStringAsFixed(3)} tCO₂e'),
        findsOneWidget,
      );
      expect(
        find.text('Indicative value ${Fmt.inr(s.indicativeCreditValue)}'),
        findsOneWidget,
      );
      expect(find.text(carbonCreditDisclaimer), findsOneWidget);
      expect(find.text('Methodology'), findsOneWidget);
      expect(find.text('TR-0991'), findsWidgets);
      // TR-0994 has no recorded distance → flagged as estimated.
      expect(find.text('Distance estimated'), findsWidgets);

      // Ranges.
      await tapIt(tester, find.text('30 days'));
      final s30 = servicesOf(tester).analytics.summary(
        data.primaryEmployer.id,
        DateRange.lastDays(data.today, 30),
      );
      expect(_tileValue(tester, 'kpi-riders'), '${s30.riders}');
      await tapIt(tester, find.text('90 days'));
      await tapIt(tester, find.text('Custom'));
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // CSV export (falls back to clipboard or saves in tests).
      await tapIt(tester, find.text('Export CSV'));
      for (
        var i = 0;
        i < 30 &&
            clip == null &&
            find.textContaining('Saved').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        clip != null || find.textContaining('Saved').evaluate().isNotEmpty,
        isTrue,
      );
      if (clip != null) expect(clip, startsWith('Trip,Date,Riders'));
    },
  );

  testWidgets(
    'SOS card shows escalation chain; employer admin acknowledges; notification opens SOS',
    (tester) async {
      await pumpEmployer(tester, location: '/employer/overview');
      expect(find.text('All clear'), findsOneWidget);
      final r = await servicesOf(
        tester,
      ).incidents.raiseSos(actor: Actor.employee('E1'), tripId: 'TR-1001');
      expect(r.isOk, isTrue, reason: r.message);
      await tester.pumpAndSettle();
      final inc = r.valueOrNull!;
      expect(find.text('1 open'), findsOneWidget);
      expect(find.textContaining(inc.reference), findsWidgets);
      final chain = dataOf(tester).sosDispatchesOf(inc.id);
      expect(chain, isNotEmpty);
      for (final d in chain) {
        expect(find.text(d.recipient.label), findsWidgets);
      }
      final admin = chain.firstWhere(
        (d) => d.recipient == SosRecipient.companyAdmin,
      );
      await tapIt(tester, find.byKey(Key('ack-${admin.id}')));
      expect(find.text('Acknowledge SOS escalation?'), findsOneWidget);
      await tapIt(tester, find.widgetWithText(TextButton, 'Cancel'));
      expect(
        dataOf(
          tester,
        ).sosDispatchesOf(inc.id).firstWhere((d) => d.id == admin.id).status,
        SosDispatchStatus.alertedInApp,
      );
      await tapIt(tester, find.byKey(Key('ack-${admin.id}')));
      await tapIt(
        tester,
        find.widgetWithText(FilledButton, 'Acknowledge').last,
      );
      expect(
        dataOf(
          tester,
        ).sosDispatchesOf(inc.id).firstWhere((d) => d.id == admin.id).status,
        SosDispatchStatus.acknowledged,
      );

      // Notification → SOS detail.
      await tapIt(tester, find.byTooltip('Notifications'));
      await tapIt(tester, find.textContaining('SOS raised by').first);
      expect(currentPath(tester), '/employer/sos/${inc.id}');
      expect(find.text('Escalation chain'), findsOneWidget);
    },
  );

  testWidgets('absence shows as Not travelling and in utilization', (
    tester,
  ) async {
    await pumpEmployer(tester, location: '/employer/overview');
    final r = await servicesOf(
      tester,
    ).matching.reportAbsence('TR-1001', 'E2', 'WFH');
    expect(r.isOk, isTrue, reason: r.message);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('util-released')),
        matching: find.text('1 released'),
      ),
      findsOneWidget,
    );
    await goTo(tester, '/employer/assignments');
    expect(find.textContaining('1 not travelling'), findsOneWidget);
    await tapIt(tester, find.text('TR-1001'));
    expect(find.byKey(const Key('absent-E2')), findsOneWidget);
    expect(find.text('Not travelling'), findsOneWidget);
  });

  for (final size in [phoneSize, tabletSize, desktopSize]) {
    testWidgets('v3 screens without overflow at ${size.width.toInt()}px', (
      tester,
    ) async {
      await pumpEmployer(tester, location: '/employer/overview', size: size);
      final inc = (await servicesOf(tester).incidents.raiseSos(
        actor: Actor.employee('E1'),
        tripId: 'TR-1001',
      )).valueOrNull!;
      await servicesOf(tester).matching.reportAbsence('TR-1001', 'E2', 'WFH');
      for (final p in [
        '/employer/overview',
        '/employer/analytics',
        '/employer/sos/${inc.id}',
        '/employer/assignments/TR-1001',
      ]) {
        await goTo(tester, p);
        expect(tester.takeException(), isNull, reason: p);
      }
    });
  }

  testWidgets('employer can require a personal demo password for an employee', (
    tester,
  ) async {
    await pumpEmployer(
      tester,
      location: '/employer/employees/E1',
      size: const Size(1440, 1400),
    );
    final sw = find.widgetWithText(
      SwitchListTile,
      'Require personal demo password',
    );
    await tester.ensureVisible(sw);
    await tester.pumpAndSettle();
    await tester.tap(sw);
    await tester.pumpAndSettle();
    final save = find.text('Save changes');
    await tester.ensureVisible(save.first);
    await tester.tap(save.first);
    await tester.pumpAndSettle();
    final s = servicesOf(tester);
    expect(dataOf(tester).employee('E1')!.optionalDemoPasswordEnabled, isTrue);
    expect((await s.session.signInEmployee('E1')).isOk, isFalse);
    expect(
      (await s.session.signInEmployee('E1', password: 'demo1234')).isOk,
      isTrue,
    );
  });
}
