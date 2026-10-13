import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';

/// True when [a] concerns company [companyId] (Employer Admin scope).
bool auditConcernsCompany(DataView d, AuditEvent a, String companyId) {
  if (a.related['company'] == companyId) return true;
  return switch (a.entityType) {
    'employer' => a.entityId == companyId,
    'employee' => d.employee(a.entityId)?.employerId == companyId,
    'trip' => d.trips.byId(a.entityId)?.employerId == companyId,
    'booking' =>
      d.employee(d.booking(a.entityId)?.employeeId)?.employerId == companyId,
    'billing' => d.billingRecord(a.entityId)?.employerId == companyId,
    'invoice' =>
      d.invoice(a.entityId)?.employerId == companyId ||
          a.entityId.startsWith('$companyId:'),
    'contract' => d.contract(a.entityId)?.employerId == companyId,
    'location' => d.location(a.entityId)?.employerId == companyId,
    _ => false,
  };
}

enum _Range { all, today, week, month }

/// Searchable, filterable audit history (newest first). Read-only: audit
/// events cannot be edited or deleted from the UI.
class AuditTrailView extends ConsumerStatefulWidget {
  const AuditTrailView({
    super.key,
    this.companyId,
    this.onOpenEntity,
    this.initialEntityType,
  });

  /// Restrict to one company's events (Employer Admin).
  final String? companyId;

  /// Navigate to the related record, if the workspace supports it.
  final void Function(String entityType, String entityId)? onOpenEntity;
  final String? initialEntityType;

  @override
  ConsumerState<AuditTrailView> createState() => _AuditTrailViewState();
}

class _AuditTrailViewState extends ConsumerState<AuditTrailView> {
  String _query = '';
  _Range _range = _Range.all;
  UserRole? _role;
  String? _action;
  late String? _entity = widget.initialEntityType;
  AuditOutcome? _outcome;
  int _limit = 60;
  int _searchGeneration = 0;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final now = data.now;
    var events = data.auditTrail;
    if (widget.companyId != null) {
      events = events
          .where((a) => auditConcernsCompany(data, a, widget.companyId!))
          .toList();
    }
    final actions = events.map((a) => a.action).toSet().toList()..sort();
    final entities = events.map((a) => a.entityType).toSet().toList()..sort();
    final q = _query.trim().toLowerCase();
    final filtered = events.where((a) {
      if (_role != null && a.actorRole != _role) return false;
      if (_action != null && a.action != _action) return false;
      if (_entity != null && a.entityType != _entity) return false;
      if (_outcome != null && a.outcome != _outcome) return false;
      switch (_range) {
        case _Range.today:
          if (!sameDay(a.timestamp, now)) return false;
        case _Range.week:
          if (now.difference(a.timestamp).inDays > 7) return false;
        case _Range.month:
          if (now.difference(a.timestamp).inDays > 31) return false;
        case _Range.all:
          break;
      }
      if (q.isEmpty) return true;
      return a.id.toLowerCase().contains(q) ||
          a.entityId.toLowerCase().contains(q) ||
          a.summary.toLowerCase().contains(q) ||
          a.actorId.toLowerCase().contains(q) ||
          a.related.values.any((v) => v.toLowerCase().contains(q));
    }).toList();
    final shown = filtered.take(_limit).toList();
    final t = Theme.of(context).textTheme;
    final filtersActive =
        q.isNotEmpty ||
        _role != null ||
        _action != null ||
        _entity != null ||
        _outcome != null ||
        _range != _Range.all;

    Widget dropdown<T>(
      String label,
      T? value,
      List<T> options,
      String Function(T) text,
      ValueChanged<T?> onChanged,
    ) => SizedBox(
      width: 200,
      child: DropdownButtonFormField<T?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          DropdownMenuItem<T?>(
            value: null,
            child: Text('All', style: t.bodyMedium),
          ),
          for (final o in options)
            DropdownMenuItem<T?>(
              value: o,
              child: Text(text(o), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          key: ValueKey('audit-search-$_searchGeneration'),
          hint: 'Search by audit ID, record ID, actor or text',
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: AppSpace.sm),
        FilterChipBar<_Range>(
          options: _Range.values,
          selected: _range,
          onSelected: (r) => setState(() => _range = r),
          labelOf: (r) => switch (r) {
            _Range.all => 'All time',
            _Range.today => 'Today',
            _Range.week => 'Last 7 days',
            _Range.month => 'Last 31 days',
          },
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            dropdown<UserRole>(
              'Actor role',
              _role,
              UserRole.values,
              (r) => r.label,
              (v) => setState(() => _role = v),
            ),
            dropdown<String>(
              'Action',
              _action,
              actions,
              (a) => a,
              (v) => setState(() => _action = v),
            ),
            dropdown<String>(
              'Record type',
              _entity,
              entities,
              (e) => e,
              (v) => setState(() => _entity = v),
            ),
            dropdown<AuditOutcome>(
              'Result',
              _outcome,
              AuditOutcome.values,
              (o) => o.label,
              (v) => setState(() => _outcome = v),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                '${filtered.length} of ${events.length} events · newest first',
                style: AppText.muted(context),
              ),
            ),
            if (filtersActive)
              TextButton(
                onPressed: () => setState(() {
                  _query = '';
                  _searchGeneration++;
                  _range = _Range.all;
                  _role = null;
                  _action = null;
                  _entity = null;
                  _outcome = null;
                }),
                child: const Text('Clear filters'),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        if (shown.isEmpty)
          const EmptyState(
            icon: Icons.history_rounded,
            title: 'No audit events',
            message: 'No events match these filters.',
            compact: true,
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _row(context, shown[i], now),
                ],
              ],
            ),
          ),
        if (filtered.length > shown.length) ...[
          const SizedBox(height: AppSpace.sm),
          Center(
            child: OutlinedButton(
              onPressed: () => setState(() => _limit += 60),
              child: Text('Show more (${filtered.length - shown.length})'),
            ),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        const SimulatedNote(
          DemoLabels.auditNotTamperProof,
          icon: Icons.verified_user_outlined,
        ),
      ],
    );
  }

  StatusTone _tone(AuditOutcome o) => switch (o) {
    AuditOutcome.success => StatusTone.success,
    AuditOutcome.rejected => StatusTone.warning,
    AuditOutcome.failure => StatusTone.danger,
  };

  Widget _row(BuildContext context, AuditEvent a, DateTime now) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => _detail(context, a),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Fmt.dateShort(a.timestamp), style: t.labelMedium),
                  Text(Fmt.time(a.timestamp), style: AppText.muted(context)),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.summary, style: t.bodyMedium),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusBadge(
                        a.outcome.label,
                        tone: _tone(a.outcome),
                        dense: true,
                      ),
                      Text(
                        '${a.action} · ${a.entityType} ${a.entityId}',
                        style: AppText.muted(context),
                      ),
                      Text(
                        'by ${a.actorRole.label}${a.actorId.isNotEmpty ? ' ${a.actorId}' : ''}',
                        style: AppText.muted(context),
                      ),
                      if (a.simulated)
                        const StatusBadge(
                          'Simulated',
                          tone: StatusTone.neutral,
                          dense: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  void _detail(BuildContext context, AuditEvent a) {
    showAppSheet<void>(
      context,
      title: 'Audit event ${a.id}',
      builder: (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueRow(label: 'Time', value: Fmt.dateTime(a.timestamp)),
          KeyValueRow(
            label: 'Actor',
            value: '${a.actorRole.label} ${a.actorId}',
          ),
          KeyValueRow(label: 'Action', value: a.action),
          KeyValueRow(
            label: 'Record',
            value: '${a.entityType} · ${a.entityId}',
          ),
          KeyValueRow(
            label: 'Result',
            valueWidget: StatusBadge(a.outcome.label, tone: _tone(a.outcome)),
          ),
          if (a.simulated)
            const KeyValueRow(
              label: 'Simulation',
              value: 'Concerns simulated behaviour',
            ),
          const SizedBox(height: AppSpace.sm),
          Text('Summary', style: Theme.of(c).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(a.summary),
          if (a.changes.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              'Changes (before → after)',
              style: Theme.of(c).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            for (final part in a.changes.split('; '))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $part'),
              ),
          ],
          if (a.reason != null && a.reason!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text('Reason / details', style: Theme.of(c).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(a.reason!),
          ],
          if (a.related.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text('Related records', style: Theme.of(c).textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in a.related.entries)
                  Chip(label: Text('${e.key}: ${e.value}')),
              ],
            ),
          ],
          if (widget.onOpenEntity != null) ...[
            const SizedBox(height: AppSpace.lg),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(c).pop();
                widget.onOpenEntity!(a.entityType, a.entityId);
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open record'),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          const SimulatedNote(
            DemoLabels.auditNotTamperProof,
            icon: Icons.verified_user_outlined,
          ),
        ],
      ),
    );
  }
}
