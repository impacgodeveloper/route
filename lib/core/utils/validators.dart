/// Reusable form validators returning null when valid.
abstract final class Validators {
  static String? required(String? v, [String label = 'This field']) =>
      (v == null || v.trim().isEmpty) ? '$label is required' : null;

  static String? minLength(String? v, int n, [String label = 'This field']) =>
      (v == null || v.trim().length < n)
      ? '$label needs at least $n characters'
      : null;

  static String? nonNegativeNumber(String? v, [String label = 'Value']) {
    if (v == null || v.trim().isEmpty) return '$label is required';
    final n = double.tryParse(v.trim());
    if (n == null) return '$label must be a number';
    if (n < 0) return '$label cannot be negative';
    return null;
  }

  static String? intRange(
    String? v,
    int min,
    int max, [
    String label = 'Value',
  ]) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null) return '$label must be a whole number';
    if (n < min || n > max) return '$label must be between $min and $max';
    return null;
  }
}
