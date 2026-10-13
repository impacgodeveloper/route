import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import 'employer_common.dart';

/// CSV roster import: source → column mapping → preview → confirmed commit.
class RosterImportPage extends ConsumerStatefulWidget {
  const RosterImportPage({super.key});

  @override
  ConsumerState<RosterImportPage> createState() => _RosterImportPageState();
}

class _RosterImportPageState extends ConsumerState<RosterImportPage> {
  final _paste = TextEditingController();
  String? _sourceLabel;
  Map<RosterField, int?>? _mapping;
  bool _allowUpdates = false;
  RosterPreview? _preview;
  String? _sourceError;
  String? _success;
  bool _busy = false;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  void _parse({bool resetMapping = false}) {
    final text = _paste.text;
    if (text.trim().isEmpty) {
      setState(() {
        _sourceError = 'Paste CSV text or choose a file first.';
        _preview = null;
      });
      return;
    }
    final svc = ref.read(servicesProvider).roster;
    final employerId = ref.read(dataProvider).primaryEmployer.id;
    final p = svc.preview(
      text,
      employerId: employerId,
      mapping: resetMapping ? null : _mapping,
      allowUpdates: _allowUpdates,
    );
    setState(() {
      _sourceError = null;
      _success = null;
      _preview = p;
      _mapping = Map.of(p.mapping);
    });
  }

  Future<void> _pickFile() async {
    try {
      final f = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (f == null) return;
      final text = await f.xFile.readAsString();
      _paste.text = text;
      _sourceLabel = f.name;
      _parse(resetMapping: true);
    } catch (e) {
      setState(
        () => _sourceError =
            'File picker is unavailable on this platform ($e). Paste the CSV text instead.',
      );
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      final where = await ref
          .read(servicesProvider)
          .export
          .saveCsv('roster_template.csv', RosterImportService.template);
      if (mounted) showToast(context, where);
    } catch (_) {
      await Clipboard.setData(
        const ClipboardData(text: RosterImportService.template),
      );
      if (mounted) {
        showToast(
          context,
          'Download unavailable — template copied to clipboard',
        );
      }
    }
  }

  Future<void> _commit() async {
    final p = _preview!;
    final ok = await showConfirmDialog(
      context,
      title: 'Import ${p.creates + p.updates} employees?',
      message:
          '${p.creates} new employee${p.creates == 1 ? '' : 's'} will be added'
          '${p.updates > 0 ? ' and ${p.updates} existing record${p.updates == 1 ? '' : 's'} will be OVERWRITTEN' : ''}. '
          '${p.invalid} row${p.invalid == 1 ? '' : 's'} with errors will be skipped.',
      confirmLabel: 'Import',
      destructive: p.updates > 0,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await ref.read(servicesProvider).roster.commit(p);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.isOk) {
      setState(() {
        _success =
            '${p.creates} added, ${p.updates} updated, ${p.invalid} skipped.';
        _preview = null;
        _paste.clear();
        _sourceLabel = null;
        _mapping = null;
      });
    } else {
      await showResult(context, r, failureTitle: 'Import failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = _preview;
    return AdminPage(
      title: 'Import roster (CSV)',
      subtitle:
          'Nothing is saved until you review the preview and confirm. Existing employees are never overwritten silently.',
      actions: [
        TextButton.icon(
          onPressed: () => context.go(EmployerPaths.policies),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Rosters & Policies'),
        ),
      ],
      children: [
        if (_success != null) ...[
          InlineBanner(
            tone: StatusTone.success,
            title: 'Roster imported',
            message: _success,
            actions: [
              TextButton(
                onPressed: () => context.go(EmployerPaths.employees),
                child: const Text('View employees'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
        ],
        PanelCard(
          title: '1 · Source',
          subtitle:
              'Columns: employee_code, name, email, phone, pickup_code, destination_code, arrival_time (HH:MM), shift, transport_preference',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  FilledButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Choose CSV file'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        const ClipboardData(text: RosterImportService.template),
                      );
                      if (context.mounted) {
                        showToast(context, 'Template copied');
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy template'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _downloadTemplate,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Download template'),
                  ),
                  TextButton(
                    onPressed: () {
                      _paste.text = RosterImportService.template;
                      _sourceLabel = 'Sample template';
                      _parse(resetMapping: true);
                    },
                    child: const Text('Use sample'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                key: const Key('roster-paste'),
                controller: _paste,
                minLines: 5,
                maxLines: 10,
                style: t.bodySmall!.copyWith(fontFeatures: AppText.tabular),
                decoration: InputDecoration(
                  labelText: _sourceLabel == null
                      ? 'Or paste CSV text'
                      : 'CSV text · $_sourceLabel',
                  alignLabelWithHint: true,
                  errorText: _sourceError,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _parse(resetMapping: true),
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('Preview import'),
                ),
              ),
            ],
          ),
        ),
        if (p != null) ...[
          const SizedBox(height: AppSpace.md),
          PanelCard(
            title: '2 · Column mapping',
            subtitle:
                'Auto-detected from the header row. Adjust if your file uses different names.',
            child: Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final f in RosterField.values)
                  SizedBox(
                    width: 230,
                    child: DropdownButtonFormField<int?>(
                      key: ValueKey('map-${f.name}-${_mapping?[f]}'),
                      initialValue: _mapping?[f],
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: '${f.label}${f.required ? ' *' : ''}',
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('— Not mapped —'),
                        ),
                        for (var i = 0; i < p.headers.length; i++)
                          DropdownMenuItem<int?>(
                            value: i,
                            child: Text(
                              p.headers[i],
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        _mapping![f] = v;
                        _parse();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          PanelCard(
            title: '3 · Preview',
            subtitle:
                '${p.rows.length} data row${p.rows.length == 1 ? '' : 's'}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (p.fileErrors.isNotEmpty) ...[
                  InlineBanner(
                    tone: StatusTone.danger,
                    title: 'Fix the file or mapping',
                    messages: p.fileErrors,
                  ),
                  const SizedBox(height: AppSpace.sm),
                ],
                Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  children: [
                    StatusBadge(
                      '${p.creates} to create',
                      tone: StatusTone.success,
                    ),
                    StatusBadge(
                      '${p.updates} to update',
                      tone: p.updates > 0
                          ? StatusTone.warning
                          : StatusTone.neutral,
                    ),
                    StatusBadge(
                      '${p.invalid} rejected',
                      tone: p.invalid > 0
                          ? StatusTone.danger
                          : StatusTone.neutral,
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allowUpdates,
                  onChanged: (v) {
                    _allowUpdates = v;
                    _parse();
                  },
                  title: const Text('Allow updates to existing employees'),
                  subtitle: const Text(
                    'Off: rows with existing IDs are rejected. On: they overwrite the existing record (shown as "Update").',
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                AdaptiveTable<RosterRow>(
                  rows: p.rows,
                  columns: [
                    TableCol('Row', (r) => Text('${r.lineNumber}')),
                    TableCol(
                      'ID',
                      (r) => Text(
                        r.values[RosterField.employeeCode]!.isEmpty
                            ? '—'
                            : r.values[RosterField.employeeCode]!,
                      ),
                    ),
                    TableCol(
                      'Name',
                      (r) => Text(
                        r.values[RosterField.name]!,
                        overflow: TextOverflow.ellipsis,
                      ),
                      flex: 2,
                    ),
                    TableCol(
                      'Pickup → Dest',
                      (r) => Text(
                        '${r.values[RosterField.pickupCode]} → ${r.values[RosterField.destinationCode]}',
                      ),
                      flex: 2,
                    ),
                    TableCol(
                      'Arrive',
                      (r) => Text(r.values[RosterField.arrivalTime]!),
                    ),
                    TableCol('Result', (r) => _actionBadge(r)),
                    TableCol('Issues', (r) => _issues(context, r), flex: 4),
                  ],
                  mobileCard: (r) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Row ${r.lineNumber} · ${r.values[RosterField.employeeCode]} ${r.values[RosterField.name]}',
                              style: t.titleSmall,
                            ),
                          ),
                          _actionBadge(r),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _issues(context, r),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _preview = null;
                        _paste.clear();
                        _sourceLabel = null;
                      }),
                      child: const Text('Start over'),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    FilledButton.icon(
                      onPressed: p.canCommit && !_busy ? _commit : null,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(
                        'Import ${p.creates + p.updates} valid row${p.creates + p.updates == 1 ? '' : 's'}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _actionBadge(RosterRow r) {
    if (!r.valid) {
      return const StatusBadge(
        'Rejected',
        tone: StatusTone.danger,
        dense: true,
      );
    }
    return r.action == RowAction.update
        ? const StatusBadge('Update', tone: StatusTone.warning, dense: true)
        : const StatusBadge('Create', tone: StatusTone.success, dense: true);
  }

  Widget _issues(BuildContext context, RosterRow r) {
    final t = Theme.of(context).textTheme;
    if (r.errors.isEmpty && r.warnings.isEmpty) {
      return Text('OK', style: t.bodySmall!.copyWith(color: AppColors.success));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in r.errors)
          Text(e, style: t.bodySmall!.copyWith(color: AppColors.danger)),
        for (final w in r.warnings)
          Text(w, style: t.bodySmall!.copyWith(color: AppColors.warning)),
      ],
    );
  }
}
