import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';

/// Local support ticket form (Employee + Driver). Keeps input on failure.
class SupportTicketForm extends ConsumerStatefulWidget {
  const SupportTicketForm({
    super.key,
    required this.actor,
    required this.tripOptions,
    this.initialTripId,
    this.onSubmitted,
  });

  final Actor actor;
  final List<Trip> tripOptions;
  final String? initialTripId;
  final void Function(SupportTicket ticket)? onSubmitted;

  @override
  ConsumerState<SupportTicketForm> createState() => _SupportTicketFormState();
}

class _SupportTicketFormState extends ConsumerState<SupportTicketForm> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  TicketCategory _category = TicketCategory.trip;
  late String? _tripId = widget.initialTripId;
  List<String> _errors = const [];
  bool _busy = false;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final r = await ref
        .read(servicesProvider)
        .support
        .createTicket(
          actor: widget.actor,
          category: _category,
          subject: _subject.text,
          description: _description.text,
          relatedTripId: _tripId,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = r.errors;
    });
    if (r.isOk) {
      showToast(context, 'Ticket ${r.valueOrNull!.reference} created');
      widget.onSubmitted?.call(r.valueOrNull!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errors.isNotEmpty) ...[
            InlineBanner(
              tone: StatusTone.danger,
              title: 'Ticket not created',
              messages: _errors,
            ),
            const SizedBox(height: AppSpace.md),
          ],
          DropdownButtonFormField<TicketCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in TicketCategory.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: AppSpace.sm),
          DropdownButtonFormField<String?>(
            initialValue: _tripId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Related trip (optional)',
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('None')),
              for (final t in widget.tripOptions)
                DropdownMenuItem<String?>(
                  value: t.id,
                  child: Text(
                    '${t.tripCode} · ${Fmt.dateShort(t.serviceDate)} · ${t.status.label}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _tripId = v),
          ),
          const SizedBox(height: AppSpace.sm),
          TextFormField(
            controller: _subject,
            decoration: const InputDecoration(labelText: 'Subject'),
            textInputAction: TextInputAction.next,
            validator: (v) => Validators.minLength(v, 4, 'Subject'),
          ),
          const SizedBox(height: AppSpace.sm),
          TextFormField(
            controller: _description,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Describe the issue',
              alignLabelWithHint: true,
            ),
            validator: (v) => Validators.minLength(v, 10, 'Description'),
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit ticket'),
          ),
          const SizedBox(height: AppSpace.sm),
          const SimulatedNote(
            'Tickets are stored locally for this prototype. No support agent is notified outside the app.',
          ),
        ],
      ),
    );
  }
}
