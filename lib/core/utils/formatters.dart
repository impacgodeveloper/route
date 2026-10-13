import 'package:intl/intl.dart';

/// Central date/time/currency formatting (Indian conventions, ₹).
abstract final class Fmt {
  static final _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );
  static final _inr0 = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static final _num = NumberFormat.decimalPattern('en_IN');
  static final _date = DateFormat('d MMM yyyy');
  static final _dateShort = DateFormat('d MMM');
  static final _weekday = DateFormat('EEE, d MMM');
  static final _weekdayLong = DateFormat('EEEE, d MMMM');
  static final _time = DateFormat('h:mm a');
  static final _dateTime = DateFormat('d MMM yyyy, h:mm a');

  static String inr(num v) => _inr.format(v);
  static String inr0(num v) => _inr0.format(v);
  static String number(num v) => _num.format(v);
  static String km(num? v) => v == null ? '—' : '${v.toStringAsFixed(1)} km';
  static String percent(num v, {int digits = 0}) =>
      '${v.toStringAsFixed(digits)}%';

  static String date(DateTime? d) => d == null ? '—' : _date.format(d);
  static String dateShort(DateTime? d) =>
      d == null ? '—' : _dateShort.format(d);
  static String weekday(DateTime? d) => d == null ? '—' : _weekday.format(d);
  static String weekdayLong(DateTime? d) =>
      d == null ? '—' : _weekdayLong.format(d);
  static String time(DateTime? d) => d == null ? '—' : _time.format(d);
  static String dateTime(DateTime? d) => d == null ? '—' : _dateTime.format(d);

  /// Minutes after midnight → "9:30 AM".
  static String minutesOfDay(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return _time.format(DateTime(2000, 1, 1, h, m));
  }

  /// "HH:mm" (24h) for CSV/inputs.
  static String hhmm(int minutes) =>
      '${((minutes ~/ 60) % 24).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  static String duration(int? minutes) {
    if (minutes == null) return '—';
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  /// Relative day label: Today / Tomorrow / Yesterday / weekday.
  static String dayLabel(DateTime d, DateTime now) {
    final a = DateTime(d.year, d.month, d.day);
    final b = DateTime(now.year, now.month, now.day);
    final diff = a.difference(b).inDays;
    return switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => weekday(d),
    };
  }

  static String ago(DateTime d, DateTime now) {
    final diff = now.difference(d);
    if (diff.isNegative) return 'in ${duration(-diff.inMinutes)}';
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return date(d);
  }

  /// Parses "9:30", "09:30", "9:30 AM", "17:45" → minutes of day.
  static int? parseTime(String input) {
    final s = input.trim().toUpperCase();
    final m = RegExp(r'^(\d{1,2})[:.](\d{2})\s*(AM|PM)?$').firstMatch(s);
    if (m == null) return null;
    var h = int.parse(m[1]!);
    final min = int.parse(m[2]!);
    final ampm = m[3];
    if (min > 59) return null;
    if (ampm != null) {
      if (h < 1 || h > 12) return null;
      if (ampm == 'AM' && h == 12) h = 0;
      if (ampm == 'PM' && h != 12) h += 12;
    } else if (h > 23) {
      return null;
    }
    return h * 60 + min;
  }
}
