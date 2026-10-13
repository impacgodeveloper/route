import 'package:executive_fleet/core/persistence/local_database.dart';
import 'package:executive_fleet/core/persistence/storage_adapter.dart';
import 'package:executive_fleet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

void main() {
  group('Seed manager', () {
    test('seeds the required baseline exactly once', () async {
      final h = await Harness.create();
      final v = h.view;
      expect(v.employer('C1')!.name, 'C1 Corporate Services');
      expect(v.employees.length, 100);
      expect(v.employees.map((e) => e.id), containsAll(['E1', 'E50', 'E100']));
      expect(v.employee('E1')!.name, 'Asha Rao');
      expect(v.employee('E2')!.name, 'Kiran Mehta');
      expect(v.employee('E3')!.name, 'Neha Iyer');
      expect(v.employee('E4')!.name, 'Arjun Das');
      expect(v.vehicles.map((x) => x.id), ['C1', 'C2', 'C3']);
      expect(v.drivers.map((d) => d.name), [
        'Ravi Kumar',
        'Priya Sharma',
        'Arif Khan',
      ]);
      for (var i = 1; i <= 10; i++) {
        expect(v.location('P$i'), isNotNull, reason: 'P$i');
      }
      for (var i = 1; i <= 4; i++) {
        expect(v.location('G$i'), isNotNull, reason: 'G$i');
      }
      expect(v.pickupLocations.length, greaterThanOrEqualTo(10));
      expect(h.db.routes.length, greaterThanOrEqualTo(3));
      final statuses = v.trips.all().map((t) => t.status).toSet();
      expect(
        statuses,
        containsAll([
          TripStatus.planned,
          TripStatus.assigned,
          TripStatus.inProgress,
          TripStatus.completed,
          TripStatus.delayed,
          TripStatus.cancelled,
        ]),
      );
      expect(v.bookings.length, greaterThanOrEqualTo(10));
      expect(
        v.bookings.map((b) => b.status).toSet().length,
        greaterThanOrEqualTo(5),
      );
      expect(h.db.notifications.length, greaterThanOrEqualTo(8));
      expect(
        v.incidents.map((i) => i.status).toSet().length,
        greaterThanOrEqualTo(3),
      );
      expect(v.billingOf('C1').length, greaterThanOrEqualTo(3));
      expect(v.inspections.map((i) => i.overallStatus).toSet().length, 3);
      expect(h.db.shifts.length, greaterThanOrEqualTo(3));
      expect(v.optimizationConfigs.length, greaterThanOrEqualTo(1));
      expect(v.optimizationRuns.length, greaterThanOrEqualTo(2));

      // Second call is a no-op.
      expect(await h.services.seed.ensureSeeded(), isFalse);
      expect(h.view.employees.length, 100);
    });

    test(
      'preserves user edits across restart (never silently reseeds)',
      () async {
        final h = await Harness.create();
        final e1 = h.view.employee('E1')!;
        final r = await h.services.employees.save(
          e1.copyWith(name: 'Asha R. (edited)'),
        );
        expect(r.isOk, isTrue, reason: r.message);
        final h2 = await h.restart();
        expect(await h2.services.seed.ensureSeeded(), isFalse);
        expect(h2.view.employee('E1')!.name, 'Asha R. (edited)');
      },
    );

    test('reset restores baseline seed data', () async {
      final h = await Harness.create();
      await h.services.employees.save(
        h.view.employee('E1')!.copyWith(name: 'Changed'),
      );
      await h.services.employees.setActive('E2', false);
      await h.services.seed.reset();
      expect(h.view.employee('E1')!.name, 'Asha Rao');
      expect(h.view.employee('E2')!.isActive, isTrue);
      expect(h.view.employees.length, 100);
      expect(h.db.seededAt, isNotNull);
    });

    test(
      'recovers without duplicating if rows exist but meta is missing',
      () async {
        final h = await Harness.create();
        await h.db.flush();
        final raw = Map.of(h.storage.snapshot)..remove('meta');
        final db = LocalDatabase(MemoryStorageAdapter(raw));
        await db.open();
        expect(db.seededAt, isNull);
        final h2 = await Harness.create(storage: MemoryStorageAdapter(raw));
        expect(h2.view.employees.length, 100);
      },
    );
  });

  group('IDs and transactions', () {
    test('all seeded IDs are unique per table', () async {
      final h = await Harness.create();
      for (final table in h.db.tables) {
        final ids = table.values.map((e) => (e).id).toList();
        expect(ids.toSet().length, ids.length, reason: table.name);
      }
    });

    test(
      'generated IDs never collide and duplicate inserts are rejected',
      () async {
        final h = await Harness.create();
        final ids = <String>{};
        await h.db.transaction((tx) {
          for (var i = 0; i < 50; i++) {
            ids.add(tx.newId(h.db.trips, 'TR-'));
          }
        });
        expect(ids.length, 50);
        expect(ids.any(h.db.trips.contains), isFalse);
        expect(
          () => h.db.transaction(
            (tx) => tx.insert(h.db.employees, h.view.employee('E1')!),
          ),
          throwsA(isA<TxnAbort>()),
        );
      },
    );

    test('failed transactions roll back every change', () async {
      final h = await Harness.create();
      final before = h.view.employee('E5')!.name;
      await expectLater(
        h.db.transaction((tx) {
          tx.put(h.db.employees, h.view.employee('E5')!.copyWith(name: 'Temp'));
          throw TxnAbort('boom');
        }),
        throwsA(isA<TxnAbort>()),
      );
      expect(h.view.employee('E5')!.name, before);
    });
  });

  group('Notifications', () {
    test('every notification references an existing entity', () async {
      final h = await Harness.create();
      final v = h.view;
      for (final n in h.db.notifications.values) {
        if (n.relatedEntityType == null) continue;
        final exists = switch (n.relatedEntityType) {
          'trip' => v.trips.byId(n.relatedEntityId) != null,
          'booking' => v.booking(n.relatedEntityId) != null,
          'incident' => v.incident(n.relatedEntityId) != null,
          'billing' => v.billingRecord(n.relatedEntityId) != null,
          'vehicle' => v.vehicle(n.relatedEntityId) != null,
          'shift' => h.db.shifts.contains(n.relatedEntityId),
          'ticket' => h.db.tickets.contains(n.relatedEntityId),
          'employer' => v.employer(n.relatedEntityId) != null,
          'employee' => v.employee(n.relatedEntityId) != null,
          _ => false,
        };
        expect(
          exists,
          isTrue,
          reason: '${n.id} → ${n.relatedEntityType}:${n.relatedEntityId}',
        );
      }
    });

    test(
      'mark read persists and broadcast/recipient filtering works',
      () async {
        final h = await Harness.create();
        final mine = h.view.notificationsFor(UserRole.employee, 'E1');
        expect(mine, isNotEmpty);
        expect(
          mine.every((n) => n.recipientId == null || n.recipientId == 'E1'),
          isTrue,
        );
        final unread = h.view.unreadCount(UserRole.employee, 'E1');
        await h.services.notifications.markRead(
          mine.firstWhere((n) => !n.isRead).id,
        );
        final h2 = await h.restart();
        expect(h2.view.unreadCount(UserRole.employee, 'E1'), unread - 1);
      },
    );
  });

  test('fictional employee names are unique', () async {
    final h = await Harness.create();
    final names = h.view.employees.map((e) => e.name).toList();
    expect(names.toSet().length, names.length);
  });
}
