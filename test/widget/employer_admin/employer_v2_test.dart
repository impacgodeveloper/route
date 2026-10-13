import 'package:executive_fleet/core/demo/demo_labels.dart';
import 'package:executive_fleet/core/widgets/form_fields.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employer_harness.dart';

Future<void> _pick(WidgetTester tester, Finder field, String item) async {
  await tapIt(tester, field);
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

/// Sets a TimeOfDayField via the picker's keyboard input mode.
Future<void> _pickTime(
  WidgetTester tester,
  String fieldLabel,
  int hour12,
  int minute, {
  required bool pm,
}) async {
  await tapIt(
    tester,
    find
        .ancestor(
          of: find.text(fieldLabel),
          matching: find.byType(InputDecorator),
        )
        .first,
  );
  await tapIt(tester, find.byIcon(Icons.keyboard_outlined));
  final fields = find.descendant(
    of: find.byType(Dialog).last,
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), '$hour12');
  await tester.enterText(fields.at(1), minute.toString().padLeft(2, '0'));
  await tester.tap(find.text(pm ? 'PM' : 'AM').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK').last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {});

  group('Employee v2 fields', () {
    testWidgets(
      'company shift + tolerance + gender persist; deadline, coordinates and preferences shown',
      (tester) async {
        await pumpEmployer(tester, location: '/employer/employees/E2');
        expect(find.byKey(const Key('source-coordinates')), findsOneWidget);
        expect(find.text(DemoLabels.fictionalCoordinates), findsWidgets);
        expect(
          find.textContaining('Effective office deadline: 9:00 AM'),
          findsOneWidget,
        );
        // Read-only travel preference summary (E2: distance = Important).
        expect(find.text('Shorter travel distance'), findsOneWidget);
        expect(find.text('Important'), findsWidgets);

        await _pick(
          tester,
          find
              .ancestor(
                of: find.text('Use company shift'),
                matching: find.byType(InputDecorator),
              )
              .first,
          'S3 · Late morning · 9:30 AM–6:30 PM',
        );
        await tester.enterText(find.byKey(const Key('tolerance-field')), '10');
        await _pick(
          tester,
          find
              .ancestor(
                of: find.text('Gender (optional, self-declared)'),
                matching: find.byType(InputDecorator),
              )
              .first,
          'Prefer not to say',
        );
        await tapIt(tester, find.text('Save changes'));
        final e = dataOf(tester).employee('E2')!;
        expect(e.shiftStartMinutes, 570);
        expect(e.shiftEndMinutes, 1110);
        expect(e.shiftLabel, 'S3 · Late morning');
        expect(e.pickupToleranceMinutes, 10);
        expect(e.gender, SelfDeclaredGender.preferNotToSay);

        // Blank tolerance = company default.
        await tester.enterText(find.byKey(const Key('tolerance-field')), '');
        await tapIt(tester, find.text('Save changes'));
        expect(dataOf(tester).employee('E2')!.pickupToleranceMinutes, isNull);
        expect(
          dataOf(
            tester,
          ).employee('E2')!.toleranceMinutes(dataOf(tester).primaryEmployer),
          7,
        );
      },
    );

    testWidgets('invalid shift and tolerance show errors and are not saved', (
      tester,
    ) async {
      await pumpEmployer(tester, location: '/employer/employees/E2');
      final before = dataOf(tester).employee('E2')!;
      // S1 starts 8:45 AM but E2 must arrive by 9:00 AM → invalid.
      await _pick(
        tester,
        find
            .ancestor(
              of: find.text('Use company shift'),
              matching: find.byType(InputDecorator),
            )
            .first,
        'S1 · Early · 8:45 AM–5:45 PM',
      );
      expect(find.byKey(const Key('schedule-errors')), findsOneWidget);
      expect(
        find.textContaining(
          'Required office arrival must be at or before the shift start.',
        ),
        findsWidgets,
      );
      await tapIt(tester, find.text('Save changes'));
      expect(find.text('Not saved'), findsOneWidget);
      expect(
        dataOf(tester).employee('E2')!.shiftStartMinutes,
        before.shiftStartMinutes,
      );

      // Out-of-range tolerance → inline error, not saved.
      await _pick(
        tester,
        find
            .ancestor(
              of: find.text('Use company shift'),
              matching: find.byType(InputDecorator),
            )
            .first,
        'S2 · General · 9:15 AM–6:15 PM',
      );
      await tester.enterText(find.byKey(const Key('tolerance-field')), '45');
      await tester.pumpAndSettle();
      expect(
        find.text('Tolerance must be between 0 and 30 minutes.'),
        findsWidgets,
      );
      await tapIt(tester, find.text('Save changes'));
      expect(
        dataOf(tester).employee('E2')!.pickupToleranceMinutes,
        before.pickupToleranceMinutes,
      );
    });

    testWidgets('employees list shift filter and column', (tester) async {
      await pumpEmployer(tester, location: '/employer/employees');
      expect(find.text('SHIFT'), findsOneWidget);
      final data = dataOf(tester);
      final s2 = data.primaryEmployer.shifts.firstWhere((s) => s.id == 'S2');
      final n = data.employees
          .where(
            (e) =>
                e.shiftStartMinutes == s2.startMinutes &&
                e.shiftEndMinutes == s2.endMinutes,
          )
          .length;
      await _pick(tester, find.text('All shifts'), 'S2 · General');
      expect(find.text('$n result${n == 1 ? '' : 's'}'), findsOneWidget);
    });
  });

  testWidgets(
    'company tolerance and shift-window editor save with confirmation',
    (tester) async {
      await pumpEmployer(tester, location: '/employer/policies');
      // Tolerance slider → 0..30; drag fully left.
      final tolSlider = find.descendant(
        of: find.byKey(const Key('company-tolerance')),
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(tolSlider);
      await tester.pumpAndSettle();
      await tester.drag(tolSlider, const Offset(-900, 0));
      await tester.pumpAndSettle();
      expect(find.text('Use ±7 reference'), findsOneWidget);
      await tapIt(tester, find.text('Use ±7 reference'));
      expect(find.text('Client reference'), findsOneWidget);
      await tester.drag(tolSlider, const Offset(40, 0));
      await tester.pumpAndSettle();

      // Add an overnight shift: validation first.
      await tapIt(tester, find.text('Add shift'));
      await tapIt(tester, find.widgetWithText(FilledButton, 'Add'));
      expect(find.text('Enter a label.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('shift-label')),
        'S5 · Night',
      );
      await _pickTime(tester, 'Start', 9, 0, pm: true);
      await _pickTime(tester, 'End', 6, 0, pm: false);
      expect(find.text('Overnight — ends the next day'), findsOneWidget);
      await tapIt(tester, find.widgetWithText(FilledButton, 'Add'));
      expect(find.text('S5 · Night'), findsOneWidget);

      // Remove S4 (cancel first, then confirm).
      await tapIt(tester, find.byTooltip('Remove S4 · Mid'));
      await tapIt(tester, find.widgetWithText(TextButton, 'Cancel'));
      expect(find.text('S4 · Mid'), findsOneWidget);
      await tapIt(tester, find.byTooltip('Remove S4 · Mid'));
      await tapIt(tester, find.widgetWithText(FilledButton, 'Remove'));
      expect(find.text('S4 · Mid'), findsNothing);

      await tapIt(tester, find.widgetWithText(FilledButton, 'Save policies'));
      expect(find.text('Apply policy changes?'), findsOneWidget);
      expect(find.textContaining('Pickup/drop tolerance ±7'), findsOneWidget);
      expect(find.textContaining('Shift S4 · Mid removed'), findsOneWidget);
      await tapIt(tester, find.text('Apply changes'));
      final e = dataOf(tester).primaryEmployer;
      expect(e.pickupToleranceMinutes, isNot(7));
      expect(e.pickupToleranceMinutes, inInclusiveRange(0, 30));
      final night = e.shifts.firstWhere((s) => s.label == 'S5 · Night');
      expect(night.startMinutes, 21 * 60);
      expect(night.endMinutes, 6 * 60);
      expect(night.overnight, isTrue);
      expect(e.shifts.any((s) => s.id == 'S4'), isFalse);
    },
  );

  testWidgets('billing configuration change is saved and shows next boundary', (
    tester,
  ) async {
    await pumpEmployer(tester, location: '/employer/billing?tab=config');
    expect(
      find.textContaining('next boundary Monday, 26 October'),
      findsOneWidget,
    );
    await tapIt(tester, find.text('Monthly'));
    expect(
      find.textContaining('next boundary Sunday, 1 November'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('config-additional')), '50');
    await tapIt(tester, find.text('Save configuration'));
    expect(find.text('Save billing configuration?'), findsOneWidget);
    await tapIt(tester, find.widgetWithText(TextButton, 'Cancel'));
    expect(dataOf(tester).primaryEmployer.billingCycle, BillingCycle.weekly);
    await tapIt(tester, find.text('Save configuration'));
    await tapIt(
      tester,
      find.widgetWithText(FilledButton, 'Save configuration').last,
    );
    final e = dataOf(tester).primaryEmployer;
    expect(e.billingCycle, BillingCycle.monthly);
    expect(e.additionalChargePerTrip, 50);
    // Pause billing → cycles cannot run.
    await tapIt(tester, find.text('Billing active'));
    await tapIt(tester, find.text('Save configuration'));
    await tapIt(
      tester,
      find.widgetWithText(FilledButton, 'Save configuration').last,
    );
    expect(dataOf(tester).primaryEmployer.billingActive, isFalse);
    await tapIt(tester, find.text('Cycles & invoices'));
    expect(find.text('Cannot run this cycle'), findsOneWidget);
  });

  testWidgets(
    'cycle preview → run → no duplicate → invoice flow → rejected audit',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (c) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpEmployer(tester, location: '/employer/billing');
      // Previous week (12–18 Oct) is due.
      expect(find.byKey(const Key('due-cycles')), findsOneWidget);
      await tapIt(tester, find.text('Review due cycle'));
      expect(
        find.descendant(
          of: find.byKey(const Key('cycle-eligible')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Missing actual distance'), findsOneWidget);
      expect(find.text('TR-0994'), findsOneWidget);

      // Run (cancel first).
      await tapIt(tester, find.byKey(const Key('run-cycle')));
      expect(find.text('Run billing cycle (demo)?'), findsOneWidget);
      await tapIt(tester, find.widgetWithText(TextButton, 'Cancel'));
      expect(dataOf(tester).invoicesOf('C1'), isEmpty);
      await tapIt(tester, find.byKey(const Key('run-cycle')));
      await tapIt(tester, find.text('Generate invoice'));
      final invs = dataOf(tester).invoicesOf('C1');
      expect(invs, hasLength(1));
      final inv = invs.single;
      expect(inv.tripIds.toSet(), {'TR-0991', 'TR-0992', 'TR-0993'});
      expect(find.text('Invoice ${inv.reference} generated'), findsOneWidget);
      expect(find.text(DemoLabels.invoiceDemo), findsWidgets);
      await tapIt(tester, find.text('Close'));

      // Run again → no duplicate.
      await tapIt(tester, find.byKey(const Key('run-cycle')));
      expect(find.text('Billing cycle not processed'), findsOneWidget);
      expect(find.textContaining('No duplicate generated'), findsOneWidget);
      await tapIt(tester, find.text('OK'));
      expect(dataOf(tester).invoicesOf('C1'), hasLength(1));

      // Invoice history → detail → status flow.
      await tapIt(tester, find.text(inv.reference).last);
      expect(currentPath(tester), '/employer/billing/invoices/${inv.id}');
      expect(find.text('TR-0991'), findsWidgets);
      await tapIt(tester, find.text('Mark invoice reviewed'));
      expect(dataOf(tester).invoice(inv.id)!.status, InvoiceStatus.reviewed);
      await tapIt(tester, find.text('Dispute invoice'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dispute reason'),
        'Toll line looks wrong',
      );
      await tapIt(tester, find.widgetWithText(FilledButton, 'Dispute'));
      expect(dataOf(tester).invoice(inv.id)!.status, InvoiceStatus.disputed);
      await tapIt(tester, find.text('Resolve & mark reviewed'));
      await tapIt(tester, find.text('Mark invoice paid (demo)'));
      await tapIt(
        tester,
        find.widgetWithText(FilledButton, 'Mark paid (demo)'),
      );
      expect(dataOf(tester).invoice(inv.id)!.status, InvoiceStatus.paidDemo);
      await tapIt(tester, find.text('Export CSV'));

      // Audit: Result = Rejected shows the duplicate attempt.
      await goTo(tester, '/employer/settings');
      await pickAuditFilter(tester, 'Result', 'Rejected');
      expect(find.textContaining('— rejected'), findsWidgets);
      expect(find.textContaining('Processed weekly cycle'), findsNothing);
    },
  );

  testWidgets(
    'traffic page is read-only after a heavy scenario; overview shows summaries',
    (tester) async {
      await pumpEmployer(tester, location: '/employer/overview');
      expect(find.byKey(const Key('overview-cycle-running')), findsOneWidget);
      expect(find.byKey(const Key('overview-traffic-delayed')), findsOneWidget);
      final r = await servicesOf(tester).traffic.setScenario(
        internalRoads: TrafficLevel.heavy,
        ringRoad: TrafficLevel.heavy,
      );
      expect(r.isOk, isTrue, reason: r.message);
      await tester.pumpAndSettle();
      await tapIt(tester, find.text('Traffic & Movement').first);
      expect(currentPath(tester), '/employer/traffic');
      expect(find.text('Read-only for employer admins'), findsOneWidget);
      expect(find.text('Apply scenario & recalculate'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Apply'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Apply'), findsNothing);
      expect(find.textContaining('Simulated'), findsWidgets);
    },
  );

  testWidgets(
    'invoice and traffic notifications route to billing and traffic',
    (tester) async {
      await pumpEmployer(tester, location: '/employer/billing');
      await tapIt(tester, find.text('Review due cycle'));
      await tapIt(tester, find.byKey(const Key('run-cycle')));
      await tapIt(tester, find.text('Generate invoice'));
      await tapIt(tester, find.text('Close'));
      final inv = dataOf(tester).invoicesOf('C1').single;
      await tapIt(tester, find.byTooltip('Notifications'));
      await tapIt(
        tester,
        find.text('Invoice ${inv.reference} generated (demo)'),
      );
      expect(currentPath(tester), '/employer/billing/invoices/${inv.id}');
    },
  );

  for (final size in [phoneSize, tabletSize, desktopSize]) {
    testWidgets('v2 screens without overflow at ${size.width.toInt()}px', (
      tester,
    ) async {
      await pumpEmployer(tester, location: '/employer/overview', size: size);
      for (final p in [
        '/employer/employees/E1',
        '/employer/employees/new',
        '/employer/policies',
        '/employer/billing',
        '/employer/billing?tab=lines',
        '/employer/billing?tab=config',
        '/employer/traffic',
        '/employer/settings',
      ]) {
        await goTo(tester, p);
        expect(tester.takeException(), isNull, reason: p);
      }
    });
  }

  testWidgets('weight slider type used in policies', (tester) async {
    await pumpEmployer(tester, location: '/employer/policies');
    expect(find.byType(WeightSlider), findsWidgets);
  });
}
