import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/result.dart';
import 'states.dart';
import 'status_badge.dart';

/// Confirmation for consequential actions. Returns true only on confirm.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  Widget? extra,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (extra != null) ...[
                const SizedBox(height: AppSpace.md),
                extra,
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.lg,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Result of [showReasonDialog].
class ReasonInput {
  const ReasonInput(this.reason, this.authorizedBy);
  final String reason;
  final String? authorizedBy;
}

/// Asks for a mandatory reason (and optionally who authorized it).
/// Keeps the typed text if validation fails. Returns null on cancel.
Future<ReasonInput?> showReasonDialog(
  BuildContext context, {
  required String title,
  String? message,
  String label = 'Reason',
  String confirmLabel = 'Confirm',
  int minLength = 5,
  bool requireAuthorizer = false,
  String authorizerLabel = 'Authorized by',
  String? authorizerHint,
  bool destructive = false,
  String? initial,
}) {
  return showDialog<ReasonInput>(
    context: context,
    builder: (c) => _ReasonDialog(
      title: title,
      message: message,
      label: label,
      confirmLabel: confirmLabel,
      minLength: minLength,
      requireAuthorizer: requireAuthorizer,
      authorizerLabel: authorizerLabel,
      authorizerHint: authorizerHint,
      destructive: destructive,
      initial: initial,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.confirmLabel,
    required this.minLength,
    required this.requireAuthorizer,
    required this.authorizerLabel,
    required this.authorizerHint,
    required this.destructive,
    required this.initial,
  });

  final String title;
  final String? message;
  final String label;
  final String confirmLabel;
  final int minLength;
  final bool requireAuthorizer;
  final String authorizerLabel;
  final String? authorizerHint;
  final bool destructive;
  final String? initial;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _form = GlobalKey<FormState>();
  late final _reason = TextEditingController(text: widget.initial);
  final _auth = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, minWidth: 280),
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.message != null) ...[
                  Text(widget.message!),
                  const SizedBox(height: AppSpace.md),
                ],
                TextFormField(
                  controller: _reason,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: widget.label,
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => (v ?? '').trim().length < widget.minLength
                      ? 'Enter at least ${widget.minLength} characters'
                      : null,
                ),
                if (widget.requireAuthorizer) ...[
                  const SizedBox(height: AppSpace.sm),
                  TextFormField(
                    controller: _auth,
                    decoration: InputDecoration(
                      labelText: widget.authorizerLabel,
                      hintText: widget.authorizerHint,
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.lg,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.pop(
                context,
                ReasonInput(
                  _reason.text.trim(),
                  widget.requireAuthorizer ? _auth.text.trim() : null,
                ),
              );
            }
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Short, non-critical confirmation toast.
void showToast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            error
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: error ? AppColors.danger : AppColors.midnightNavy,
    ),
  );
}

/// Shows the outcome of a service call: toast for success; a dialog with
/// every message for failures (so important errors don't vanish).
Future<bool> showResult(
  BuildContext context,
  Result result, {
  String? successMessage,
  String failureTitle = 'Action not completed',
}) async {
  if (result.isOk) {
    final info = successMessage ?? (result as Ok).info ?? 'Done';
    showToast(context, info);
    final warnings = (result as Ok).warnings;
    if (warnings.isNotEmpty && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Saved with warnings'),
          content: InlineBanner(
            tone: StatusTone.warning,
            title: 'Please review',
            messages: warnings,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    return true;
  }
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(failureTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: InlineBanner(
            tone: StatusTone.danger,
            title: 'Please review',
            messages: result.errors,
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  return false;
}

/// Bottom sheet scaffold with title + scrollable content (mobile).
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
  bool expand = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(c).height * (expand ? 0.92 : 0.85),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                0,
                AppSpace.gutter,
                AppSpace.sm,
              ),
              child: Text(title, style: Theme.of(c).textTheme.titleLarge),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter,
                  0,
                  AppSpace.gutter,
                  AppSpace.xl,
                ),
                child: builder(c),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
