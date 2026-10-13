import '../../core/utils/csv.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/result.dart';
import '../models/models.dart';
import 'service_context.dart';

/// Target fields of a roster import, with header aliases for auto-mapping.
enum RosterField {
  employeeCode('Employee ID', [
    'employee_code',
    'employee id',
    'emp_id',
    'id',
    'code',
  ], true),
  name('Name', ['name', 'full_name', 'employee_name'], true),
  email('Email (fictional)', ['email', 'mail'], false),
  phone('Phone (fictional)', ['phone', 'mobile', 'contact'], false),
  pickupCode('Pickup code', ['pickup_code', 'pickup', 'pickup_location'], true),
  destinationCode('Destination code', [
    'destination_code',
    'destination',
    'office',
  ], true),
  arrivalTime('Arrival time', [
    'arrival_time',
    'arrival',
    'arrive_by',
    'required_arrival',
  ], true),
  shift('Shift label', ['shift', 'shift_label'], false),
  preference('Transport preference', [
    'transport_preference',
    'preference',
  ], false);

  const RosterField(this.label, this.aliases, this.required);
  final String label;
  final List<String> aliases;
  final bool required;
}

enum RowAction { create, update, skip }

class RosterRow {
  RosterRow({
    required this.lineNumber,
    required this.values,
    required this.errors,
    required this.warnings,
    required this.action,
    this.employee,
  });
  final int lineNumber;
  final Map<RosterField, String> values;
  final List<String> errors;
  final List<String> warnings;
  final RowAction action;
  final Employee? employee;
  bool get valid => errors.isEmpty;
}

class RosterPreview {
  RosterPreview({
    required this.headers,
    required this.mapping,
    required this.rows,
    required this.fileErrors,
  });
  final List<String> headers;
  final Map<RosterField, int?> mapping;
  final List<RosterRow> rows;
  final List<String> fileErrors;

  int get creates =>
      rows.where((r) => r.valid && r.action == RowAction.create).length;
  int get updates =>
      rows.where((r) => r.valid && r.action == RowAction.update).length;
  int get invalid => rows.where((r) => !r.valid).length;
  bool get canCommit => fileErrors.isEmpty && (creates + updates) > 0;
}

/// CSV roster parsing, column mapping, row validation and confirmed commit.
class RosterImportService {
  RosterImportService(this.ctx);
  final ServiceContext ctx;

  static const template =
      'employee_code,name,email,phone,pickup_code,destination_code,arrival_time,shift,transport_preference\r\n'
      'E101,Demo Person One,e101@c1-demo.example,+91 90000 10101,PK01,G1,09:00,Morning 9:15 AM,noPreference\r\n'
      'E102,Demo Person Two,e102@c1-demo.example,+91 90000 10102,PK06,G4,08:30,Morning 8:45 AM,evPreferred\r\n';

  List<List<String>> parse(String text) => Csv.parse(text);

  Map<RosterField, int?> autoMap(List<String> headers) {
    final norm = headers
        .map((h) => h.trim().toLowerCase().replaceAll(' ', '_'))
        .toList();
    return {
      for (final f in RosterField.values)
        f: () {
          for (var i = 0; i < norm.length; i++) {
            if (f.aliases
                .map((a) => a.replaceAll(' ', '_'))
                .contains(norm[i])) {
              return i;
            }
          }
          return null;
        }(),
    };
  }

  RosterPreview preview(
    String text, {
    required String employerId,
    Map<RosterField, int?>? mapping,
    bool allowUpdates = false,
  }) {
    final rows = parse(text);
    if (rows.isEmpty) {
      return RosterPreview(
        headers: const [],
        mapping: const {},
        rows: const [],
        fileErrors: ['The file is empty.'],
      );
    }
    final headers = rows.first;
    final map = mapping ?? autoMap(headers);
    final fileErrors = <String>[
      for (final f in RosterField.values.where((f) => f.required))
        if (map[f] == null) 'Map a column to "${f.label}".',
    ];
    if (rows.length < 2) fileErrors.add('No data rows found below the header.');
    final db = ctx.db;
    final employer = db.employers[employerId];
    final seen = <String, int>{};
    final out = <RosterRow>[];
    for (var r = 1; r < rows.length; r++) {
      final cells = rows[r];
      String cell(RosterField f) {
        final i = map[f];
        return (i == null || i >= cells.length) ? '' : cells[i].trim();
      }

      final values = {for (final f in RosterField.values) f: cell(f)};
      final errors = <String>[];
      final warnings = <String>[];
      final code = values[RosterField.employeeCode]!;
      if (code.isEmpty) {
        errors.add('Employee ID missing.');
      } else if (!RegExp(r'^[A-Za-z0-9-]{1,12}$').hasMatch(code)) {
        errors.add('Employee ID "$code" has invalid characters.');
      }
      if (seen.containsKey(code.toLowerCase()) && code.isNotEmpty) {
        errors.add(
          'Duplicate of row ${seen[code.toLowerCase()]} in this file.',
        );
      } else if (code.isNotEmpty) {
        seen[code.toLowerCase()] = r + 1;
      }
      if (values[RosterField.name]!.length < 2) errors.add('Name missing.');
      final pickup = db.locations
          .where(
            (l) =>
                l.code.toLowerCase() ==
                values[RosterField.pickupCode]!.toLowerCase(),
          )
          .firstOrNull;
      if (pickup == null) {
        errors.add('Unknown pickup "${values[RosterField.pickupCode]}".');
      } else if (pickup.type != LocationType.pickup &&
          pickup.type != LocationType.intermediateStop) {
        errors.add('${pickup.code} is not a pickup point.');
      }
      final dest = db.locations
          .where(
            (l) =>
                l.code.toLowerCase() ==
                values[RosterField.destinationCode]!.toLowerCase(),
          )
          .firstOrNull;
      if (dest == null) {
        errors.add(
          'Unknown destination "${values[RosterField.destinationCode]}".',
        );
      } else if (dest.type != LocationType.office &&
          dest.type != LocationType.destination) {
        errors.add('${dest.code} is not a destination/office.');
      }
      final arrival = Fmt.parseTime(values[RosterField.arrivalTime]!);
      if (arrival == null) {
        errors.add(
          'Invalid time "${values[RosterField.arrivalTime]}" (use HH:MM).',
        );
      } else if (employer != null && arrival > employer.maximumArrivalMinutes) {
        errors.add(
          'Arrival ${Fmt.minutesOfDay(arrival)} is after the company maximum ${Fmt.minutesOfDay(employer.maximumArrivalMinutes)}.',
        );
      }
      final email = values[RosterField.email]!;
      if (email.isNotEmpty && !email.contains('@')) {
        warnings.add('Email looks invalid; it will be stored as entered.');
      }
      final prefText = values[RosterField.preference]!;
      final pref = TransportPreference.values
          .where(
            (p) =>
                p.name.toLowerCase() == prefText.toLowerCase() ||
                p.label.toLowerCase() == prefText.toLowerCase(),
          )
          .firstOrNull;
      if (prefText.isNotEmpty && pref == null) {
        warnings.add(
          'Unknown preference "$prefText"; "No preference" will be used.',
        );
      }

      final existing = db.employees
          .where((e) => e.employeeCode.toLowerCase() == code.toLowerCase())
          .firstOrNull;
      var action = RowAction.create;
      if (existing != null) {
        if (allowUpdates) {
          action = RowAction.update;
          warnings.add(
            'Will UPDATE existing ${existing.employeeCode} (${existing.name}).',
          );
        } else {
          errors.add(
            '${existing.employeeCode} already exists. Enable "Allow updates" to overwrite explicitly.',
          );
          action = RowAction.skip;
        }
      }
      Employee? emp;
      if (errors.isEmpty) {
        emp = Employee(
          id: existing?.id ?? code,
          employeeCode: existing?.employeeCode ?? code,
          employerId: employerId,
          name: values[RosterField.name]!,
          fictionalEmail: email,
          fictionalPhone: values[RosterField.phone]!,
          pickupLocationId: pickup!.id,
          destinationId: dest!.id,
          requiredArrivalMinutes: arrival!,
          shiftLabel: values[RosterField.shift]!.isEmpty
              ? 'Morning ${Fmt.minutesOfDay(arrival + 15)}'
              : values[RosterField.shift]!,
          transportPreference: pref ?? TransportPreference.noPreference,
          status: existing?.status ?? RecordStatus.active,
          optionalDemoPasswordEnabled:
              existing?.optionalDemoPasswordEnabled ?? false,
          guardEscortRequired: existing?.guardEscortRequired ?? false,
          notes: existing?.notes ?? '',
        );
      }
      out.add(
        RosterRow(
          lineNumber: r + 1,
          values: values,
          errors: errors,
          warnings: warnings,
          action: action,
          employee: emp,
        ),
      );
    }
    return RosterPreview(
      headers: headers,
      mapping: map,
      rows: out,
      fileErrors: fileErrors,
    );
  }

  /// Commits only valid rows. Call only after the user confirms.
  Future<Result<int>> commit(
    RosterPreview p, {
    Actor actor = Actor.employerAdmin,
  }) {
    if (!p.canCommit) {
      return Future.value(
        Err(p.fileErrors.isEmpty ? ['No valid rows to import.'] : p.fileErrors),
      );
    }
    return ctx.run((tx) {
      var n = 0;
      for (final row in p.rows.where((r) => r.valid && r.employee != null)) {
        if (row.action == RowAction.create) {
          tx.insert(ctx.db.employees, row.employee!);
        } else if (row.action == RowAction.update) {
          tx.put(ctx.db.employees, row.employee!);
        }
        n++;
      }
      ctx.notify(
        tx,
        role: UserRole.fleetManager,
        title: 'Roster updated',
        body: '${p.creates} added, ${p.updates} updated via CSV import.',
        category: NotificationCategory.system,
        entityType: 'employer',
        entityId: p.rows.firstOrNull?.employee?.employerId,
      );
      ctx.audit(
        tx,
        actor,
        'roster.import',
        'employer',
        p.rows.firstOrNull?.employee?.employerId ?? '-',
        'CSV roster import: ${p.creates} created, ${p.updates} updated, ${p.invalid} rejected.',
      );
      return n;
    }, info: 'Roster imported');
  }
}
