import '../models/models.dart';

/// Standard pre-trip checklist. Critical items block trip start on failure.
abstract final class InspectionRules {
  static const template = <(String key, String label, bool critical)>[
    ('tyres', 'Tyres & pressure', true),
    ('lights', 'Head, brake & indicator lights', true),
    ('brakes', 'Brakes', true),
    ('mirrors', 'Mirrors', false),
    ('seatBelts', 'Seat belts (all seats)', true),
    ('doors', 'Doors & child locks', true),
    ('emergencyExits', 'Emergency exits', true),
    ('safetyKit', 'First-aid & safety kit', false),
    ('cleanliness', 'Cabin cleanliness', false),
    ('damage', 'No visible body damage', false),
  ];

  static List<InspectionItem> blankChecklist() => [
    for (final (key, label, critical) in template)
      InspectionItem(
        key: key,
        label: label,
        critical: critical,
        result: CheckResult.pass,
      ),
  ];

  static InspectionOutcome outcomeFor(List<InspectionItem> items) {
    if (items.any((i) => i.critical && i.result == CheckResult.fail)) {
      return InspectionOutcome.failed;
    }
    if (items.any((i) => i.result == CheckResult.fail)) {
      return InspectionOutcome.needsReview;
    }
    return InspectionOutcome.passed;
  }

  /// Non-critical failures still allow the trip to start.
  static bool allowsTripStart(Inspection? i) =>
      i != null && i.overallStatus != InspectionOutcome.failed;
}
