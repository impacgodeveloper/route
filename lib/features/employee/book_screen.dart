import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'employee_common.dart';

enum _Step { form, review, done }

class EmployeeBookScreen extends ConsumerStatefulWidget {
  const EmployeeBookScreen({super.key});

  @override
  ConsumerState<EmployeeBookScreen> createState() => _EmployeeBookScreenState();
}

class _EmployeeBookScreenState extends ConsumerState<EmployeeBookScreen> {
  int _view = 0; // 0 new request, 1 my requests
  _Step _step = _Step.form;
  DateTime? _date;
  String? _pickup;
  String? _destination;
  int? _arrival;
  TransportPreference _pref = TransportPreference.noPreference;
  final _notes = TextEditingController();
  List<String> _errors = const [];
  AvailabilityCheck? _availability;
  Booking? _submitted;
  bool _busy = false;
  String? _initializedFor;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _initDefaults(Employee e, DataView data) {
    if (_initializedFor == e.id) return;
    _initializedFor = e.id;
    _date = data.today.add(const Duration(days: 1));
    _pickup = e.pickupLocationId;
    _destination = e.destinationId;
    _arrival = e.requiredArrivalMinutes;
    _pref = e.transportPreference;
  }

  BookingDraft? _draft(Employee e) {
    if (_date == null ||
        _pickup == null ||
        _destination == null ||
        _arrival == null) {
      return null;
    }
    return BookingDraft(
      employeeId: e.id,
      pickupLocationId: _pickup!,
      destinationId: _destination!,
      date: _date!,
      arrivalMinutes: _arrival!,
      preference: _pref,
      notes: _notes.text,
    );
  }

  void _review(Employee e) {
    final d = _draft(e);
    if (d == null) {
      setState(() => _errors = ['Complete all required fields.']);
      return;
    }
    final svc = ref.read(servicesProvider).bookings;
    final errors = svc.validate(d);
    setState(() {
      _errors = errors;
      if (errors.isEmpty) {
        _availability = svc.checkAvailability(d);
        _step = _Step.review;
      }
    });
  }

  Future<void> _submit(Employee e) async {
    final d = _draft(e);
    if (d == null) return;
    setState(() => _busy = true);
    final r = await ref.read(servicesProvider).matching.submitAdhoc(d);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.isOk) {
        _submitted = r.valueOrNull;
        _step = _Step.done;
        _errors = const [];
      } else {
        _errors = r.errors;
        _step = _Step.form;
      }
    });
  }

  void _reset(Employee e, DataView data) {
    setState(() {
      _initializedFor = null;
      _initDefaults(e, data);
      _notes.clear();
      _step = _Step.form;
      _submitted = null;
      _errors = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final e = ref.watch(currentEmployeeProvider);
    if (e == null) return const LoadingState();
    _initDefaults(e, data);
    final requests = data.bookingsOf(e.id);
    final open = requests.where((b) => b.status.isOpen).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Book transport')),
      body: MobilePage(
        children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: 0, label: Text('New request')),
              ButtonSegment(
                value: 1,
                label: Text('My requests${open > 0 ? ' · $open' : ''}'),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
          const SizedBox(height: AppSpace.lg),
          if (_view == 1)
            ..._requests(context, data, requests)
          else
            switch (_step) {
              _Step.form => _form(context, data, e),
              _Step.review => _reviewCard(context, data, e),
              _Step.done => _doneCard(context, data, e),
            },
        ],
      ),
    );
  }

  Widget _form(BuildContext context, DataView data, Employee e) {
    final employer = data.employer(e.employerId);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Where and when?', style: t.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Your request goes to the Fleet Manager. It is not a confirmed trip until it is assigned.',
          style: t.bodyMedium!.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpace.lg),
        if (_errors.isNotEmpty) ...[
          InlineBanner(
            tone: StatusTone.danger,
            title: 'Please fix the following',
            messages: _errors,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        DateField(
          label: 'Date',
          value: _date,
          firstDate: data.today,
          lastDate: data.today.add(const Duration(days: 30)),
          onChanged: (d) => setState(() => _date = d),
        ),
        const SizedBox(height: AppSpace.sm),
        DropdownButtonFormField<String>(
          initialValue: _pickup,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Pickup point',
            prefixIcon: Icon(Icons.trip_origin_rounded),
          ),
          items: [
            for (final l in data.pickupLocations)
              DropdownMenuItem(
                value: l.id,
                child: Text(
                  '${l.code} · ${l.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _pickup = v),
        ),
        const SizedBox(height: AppSpace.sm),
        DropdownButtonFormField<String>(
          initialValue: _destination,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Destination',
            prefixIcon: Icon(Icons.apartment_outlined),
          ),
          items: [
            for (final l in data.destinations)
              DropdownMenuItem(
                value: l.id,
                child: Text(
                  '${l.code} · ${l.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _destination = v),
        ),
        const SizedBox(height: AppSpace.sm),
        TimeOfDayField(
          label: 'Arrive by',
          minutes: _arrival,
          helper: employer == null
              ? null
              : 'Latest permitted arrival: ${Fmt.minutesOfDay(employer.maximumArrivalMinutes)}',
          onChanged: (m) => setState(() => _arrival = m),
        ),
        const SizedBox(height: AppSpace.sm),
        DropdownButtonFormField<TransportPreference>(
          initialValue: _pref,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Preference'),
          items: [
            for (final p in TransportPreference.values)
              DropdownMenuItem(value: p, child: Text(p.label)),
          ],
          onChanged: (v) => setState(() => _pref = v ?? _pref),
        ),
        const SizedBox(height: AppSpace.sm),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 4,
          maxLength: 240,
          decoration: const InputDecoration(
            labelText: 'Notes for the Fleet Manager (optional)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        FilledButton(
          onPressed: () => _review(e),
          child: const Text('Review request'),
        ),
      ],
    );
  }

  Widget _reviewCard(BuildContext context, DataView data, Employee e) {
    final t = Theme.of(context).textTheme;
    final a = _availability;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Review your request', style: t.titleLarge),
        const SizedBox(height: AppSpace.md),
        AppCard(
          child: Column(
            children: [
              KeyValueRow(label: 'Date', value: Fmt.weekday(_date)),
              KeyValueRow(label: 'Pickup', value: data.locationLabel(_pickup)),
              KeyValueRow(
                label: 'Destination',
                value: data.locationLabel(_destination),
              ),
              KeyValueRow(
                label: 'Arrive by',
                value: Fmt.minutesOfDay(_arrival!),
              ),
              KeyValueRow(label: 'Preference', value: _pref.label),
              if (_notes.text.trim().isNotEmpty)
                KeyValueRow(label: 'Notes', value: _notes.text.trim()),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (a != null)
          InlineBanner(
            tone: a.available ? StatusTone.info : StatusTone.warning,
            title: a.available
                ? 'Vehicles appear to be free'
                : 'No vehicle free right now',
            message: a.message,
          ),
        const SizedBox(height: AppSpace.lg),
        FilledButton(
          onPressed: _busy ? null : () => _submit(e),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  a?.available == false
                      ? 'Submit (will be waitlisted)'
                      : 'Submit request',
                ),
        ),
        const SizedBox(height: AppSpace.xs),
        OutlinedButton(
          onPressed: _busy ? null : () => setState(() => _step = _Step.form),
          child: const Text('Edit details'),
        ),
      ],
    );
  }

  Widget _doneCard(BuildContext context, DataView data, Employee e) {
    final t = Theme.of(context).textTheme;
    final b = data.booking(_submitted?.id) ?? _submitted!;
    final waitlisted = b.status == BookingStatus.waitlisted;
    final matchedTrip = b.status == BookingStatus.assigned
        ? data.trips.byId(b.tripId)
        : null;
    final matchedPickup = matchedTrip == null
        ? null
        : data.trips.pickupStopFor(matchedTrip, e.id)?.plannedArrival;
    if (matchedTrip != null) {
      return AppCard(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          children: [
            const IconTile(
              icon: Icons.bolt_rounded,
              color: AppColors.success,
              size: 56,
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              'Matched instantly to ${matchedTrip.tripCode}',
              textAlign: TextAlign.center,
              style: t.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Reference ${b.reference}',
              style: t.titleSmall!.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'A free seat on an existing trip fits your request. '
              'Pickup ${Fmt.time(matchedPickup ?? matchedTrip.scheduledStart)} on ${Fmt.weekday(matchedTrip.serviceDate)}.',
              textAlign: TextAlign.center,
              style: t.bodyMedium!.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpace.md),
            StatusBadge(b.status.label, tone: Tones.booking(b.status)),
            const SizedBox(height: AppSpace.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    context.push('/employee/trip/${matchedTrip.id}'),
                child: const Text('View trip'),
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _reset(e, data),
                child: const Text('New request'),
              ),
            ),
          ],
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        children: [
          IconTile(
            icon: waitlisted
                ? Icons.hourglass_top_rounded
                : Icons.check_rounded,
            color: waitlisted ? AppColors.warning : AppColors.success,
            size: 56,
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            waitlisted ? 'Request waitlisted' : 'Request submitted',
            style: t.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Reference ${b.reference}',
            style: t.titleSmall!.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            waitlisted
                ? 'No vehicle was free at submission time. The Fleet Manager can still assign one — you will be notified.'
                : 'The Fleet Manager will review it. You will see the driver and vehicle once it is assigned.',
            textAlign: TextAlign.center,
            style: t.bodyMedium!.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),
          StatusBadge(b.status.label, tone: Tones.booking(b.status)),
          const SizedBox(height: AppSpace.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.push('/employee/booking/${b.id}'),
              child: const Text('View request'),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _reset(e, data),
              child: const Text('New request'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _requests(
    BuildContext context,
    DataView data,
    List<Booking> requests,
  ) {
    if (requests.isEmpty) {
      return [
        EmptyState(
          icon: Icons.event_note_outlined,
          title: 'No requests yet',
          message: 'Requests you submit appear here with their status.',
          actionLabel: 'New request',
          onAction: () => setState(() => _view = 0),
        ),
      ];
    }
    return [
      for (final b in requests)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: BookingTile(booking: b),
        ),
    ];
  }
}

/// Booking request row with cancel action for open requests.
class BookingTile extends ConsumerWidget {
  const BookingTile({super.key, required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final t = Theme.of(context).textTheme;
    final b = booking;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      onTap: () => context.push('/employee/booking/${b.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${b.reference} · ${Fmt.weekday(b.requestedDate)}',
                  style: t.titleSmall,
                ),
              ),
              StatusBadge(
                b.status.label,
                tone: Tones.booking(b.status),
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${data.location(b.requestedPickupLocationId)?.name ?? b.requestedPickupLocationId} → ${data.location(b.requestedDestinationId)?.name ?? b.requestedDestinationId} · arrive by ${Fmt.minutesOfDay(b.requestedArrivalMinutes)}',
            style: t.bodySmall!.copyWith(color: AppColors.textSecondary),
          ),
          if (b.decisionReason != null) ...[
            const SizedBox(height: 4),
            Text(b.decisionReason!, style: AppText.muted(context)),
          ],
        ],
      ),
    );
  }
}

/// Shared cancel action (used by booking detail).
Future<void> cancelBookingFlow(
  BuildContext context,
  WidgetRef ref,
  Booking b,
) async {
  final ok = await showConfirmDialog(
    context,
    title: 'Cancel ${b.reference}?',
    message:
        'The Fleet Manager will be notified. You can submit a new request later.',
    confirmLabel: 'Cancel request',
    cancelLabel: 'Keep',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  final r = await ref
      .read(servicesProvider)
      .bookings
      .cancelByEmployee(b.id, b.employeeId);
  if (context.mounted) {
    await showResult(context, r, successMessage: 'Request cancelled');
  }
}
