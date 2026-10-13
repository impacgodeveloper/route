/// Injectable time source. Tests use [FixedClock]; the app uses
/// [SystemClock]. All business rules read time through a [Clock].
abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

class FixedClock implements Clock {
  FixedClock(this._now);
  DateTime _now;
  @override
  DateTime now() => _now;
  void set(DateTime value) => _now = value;
  void advance(Duration d) => _now = _now.add(d);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime atMinutes(DateTime day, int minutesOfDay) =>
    DateTime(day.year, day.month, day.day).add(Duration(minutes: minutesOfDay));

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
