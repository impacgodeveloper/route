import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';

IconData notificationIcon(NotificationCategory c) => switch (c) {
  NotificationCategory.tripAssignment => Icons.directions_car_outlined,
  NotificationCategory.bookingUpdate => Icons.event_note_outlined,
  NotificationCategory.pickupReminder => Icons.alarm_outlined,
  NotificationCategory.delay => Icons.schedule_outlined,
  NotificationCategory.routeChange => Icons.alt_route_outlined,
  NotificationCategory.serviceNotice => Icons.campaign_outlined,
  NotificationCategory.incident => Icons.report_gmailerrorred_outlined,
  NotificationCategory.billing => Icons.receipt_long_outlined,
  NotificationCategory.shift => Icons.badge_outlined,
  NotificationCategory.system => Icons.info_outline_rounded,
};

StatusTone notificationTone(NotificationCategory c) => switch (c) {
  NotificationCategory.delay ||
  NotificationCategory.routeChange => StatusTone.warning,
  NotificationCategory.incident => StatusTone.danger,
  NotificationCategory.billing => StatusTone.teal,
  NotificationCategory.tripAssignment ||
  NotificationCategory.pickupReminder => StatusTone.info,
  _ => StatusTone.neutral,
};

/// Shared notification inbox. Read state persists locally; tapping marks
/// it read and calls [onOpen] so the workspace can open the related record.
class NotificationsList extends ConsumerStatefulWidget {
  const NotificationsList({
    super.key,
    required this.role,
    this.recipientId,
    required this.onOpen,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpace.gutter,
      AppSpace.xs,
      AppSpace.gutter,
      AppSpace.xxxl,
    ),
    this.showHeader = true,
  });

  final UserRole role;
  final String? recipientId;
  final void Function(AppNotification n) onOpen;
  final EdgeInsetsGeometry padding;
  final bool showHeader;

  @override
  ConsumerState<NotificationsList> createState() => _NotificationsListState();
}

class _NotificationsListState extends ConsumerState<NotificationsList> {
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final all = data.notificationsFor(widget.role, widget.recipientId);
    final items = _unreadOnly ? all.where((n) => !n.isRead).toList() : all;
    final unread = all.where((n) => !n.isRead).length;
    final now = data.now;
    final t = Theme.of(context).textTheme;

    return ListView(
      padding: widget.padding,
      children: [
        if (widget.showHeader)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Row(
              children: [
                Expanded(
                  child: FilterChipBar<bool>(
                    options: const [false, true],
                    selected: _unreadOnly,
                    onSelected: (v) => setState(() => _unreadOnly = v),
                    labelOf: (v) => v ? 'Unread' : 'All',
                    countOf: (v) => v ? unread : all.length,
                  ),
                ),
                TextButton(
                  onPressed: unread == 0
                      ? null
                      : () async {
                          final r = await ref
                              .read(servicesProvider)
                              .notifications
                              .markAllRead(widget.role, widget.recipientId);
                          if (context.mounted) {
                            showToast(
                              context,
                              '${r.valueOrNull ?? 0} marked as read',
                            );
                          }
                        },
                  child: const Text('Mark all read'),
                ),
              ],
            ),
          ),
        if (items.isEmpty)
          EmptyState(
            icon: Icons.notifications_none_rounded,
            title: _unreadOnly
                ? 'You\'re all caught up'
                : 'No notifications yet',
            message: _unreadOnly
                ? 'No unread notifications.'
                : 'Trip assignments, delays and updates will appear here.',
            actionLabel: _unreadOnly ? 'Show all' : null,
            onAction: _unreadOnly
                ? () => setState(() => _unreadOnly = false)
                : null,
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 64),
                  _tile(context, items[i], now, t),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpace.md),
        const SimulatedNote(DemoLabels.notificationDemo),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    AppNotification n,
    DateTime now,
    TextTheme t,
  ) {
    final tone = notificationTone(n.category);
    return Semantics(
      label: '${n.isRead ? '' : 'Unread. '}${n.title}. ${n.body}',
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: () async {
          await ref.read(servicesProvider).notifications.markRead(n.id);
          widget.onOpen(n);
        },
        onLongPress: () =>
            ref.read(servicesProvider).notifications.markUnread(n.id),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                icon: notificationIcon(n.category),
                color: tone.foreground,
                background: tone.background,
                size: 36,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: t.titleSmall!.copyWith(
                              fontWeight: n.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          Fmt.ago(n.createdAt, now),
                          style: t.bodySmall!.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      n.body,
                      style: t.bodySmall!.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!n.isRead)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpace.xs, top: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
