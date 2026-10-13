import 'package:flutter/material.dart';

import '../demo/demo_labels.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'status_badge.dart';

/// Useful empty state: explains why and offers the next action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: compact ? AppSpace.lg : AppSpace.xxxl,
            horizontal: AppSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 48 : 64,
                height: compact ? 48 : 64,
                decoration: const BoxDecoration(
                  color: AppColors.softBlue,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: AppColors.primary,
                  size: compact ? 24 : 30,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(title, textAlign: TextAlign.center, style: t.titleMedium),
              const SizedBox(height: AppSpace.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: t.bodyMedium!.copyWith(color: AppColors.textSecondary),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpace.lg),
                OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Something went wrong',
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.danger,
              size: 40,
            ),
            const SizedBox(height: AppSpace.sm),
            Text(title, style: t.titleMedium),
            const SizedBox(height: AppSpace.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: t.bodyMedium!.copyWith(color: AppColors.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpace.lg),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message = 'Loading…'});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(message, style: AppText.secondary(context)),
      ],
    ),
  );
}

/// Persistent inline feedback (validation summaries, outcomes, warnings).
/// Important results use this instead of a transient toast.
class InlineBanner extends StatelessWidget {
  const InlineBanner({
    super.key,
    required this.tone,
    required this.title,
    this.message,
    this.messages = const [],
    this.icon,
    this.actions = const [],
    this.onClose,
  });

  final StatusTone tone;
  final String title;
  final String? message;
  final List<String> messages;
  final IconData? icon;
  final List<Widget> actions;
  final VoidCallback? onClose;

  IconData get _icon =>
      icon ??
      switch (tone) {
        StatusTone.success => Icons.check_circle_outline_rounded,
        StatusTone.warning => Icons.warning_amber_rounded,
        StatusTone.danger => Icons.error_outline_rounded,
        _ => Icons.info_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: tone.foreground.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, color: tone.foreground, size: 20),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.titleSmall!.copyWith(color: tone.foreground),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      message!,
                      style: t.bodySmall!.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                  for (final m in messages)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6, right: 8),
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: tone.foreground,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              m,
                              style: t.bodySmall!.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Wrap(
                      spacing: AppSpace.xs,
                      runSpacing: AppSpace.xs,
                      children: actions,
                    ),
                  ],
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: tone.foreground,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small "DEMO DATA" pill shown in shells.
class DemoBadge extends StatelessWidget {
  const DemoBadge({
    super.key,
    this.label = DemoLabels.demoData,
    this.onDark = false,
  });
  final String label;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: DemoLabels.localOnly,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.12)
            : AppColors.warningBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: onDark
              ? Colors.white24
              : AppColors.warning.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: onDark ? Colors.white : AppColors.warning,
        ),
      ),
    ),
  );
}

/// One-line honest note for simulated features ("Simulated location…").
class SimulatedNote extends StatelessWidget {
  const SimulatedNote(
    this.text, {
    super.key,
    this.icon = Icons.science_outlined,
  });
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icon, size: 14, color: AppColors.textMuted),
      ),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: AppText.muted(context))),
    ],
  );
}
