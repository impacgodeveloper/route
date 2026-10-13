/// Small, dependency-free JSON helpers used by every model.
library;

typedef Json = Map<String, dynamic>;

/// Base type for every persisted record. IDs are stable and never reused.
abstract class Entity {
  String get id;
  Json toJson();
}

DateTime? dt(Object? v) => v is String ? DateTime.tryParse(v) : null;
DateTime dtReq(Object? v) => dt(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
String? dtOut(DateTime? v) => v?.toIso8601String();

List<String> strList(Object? v) =>
    v is List ? v.map((e) => e.toString()).toList() : <String>[];

double? dbl(Object? v) => v is num ? v.toDouble() : null;
double dblReq(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : fallback;
int intReq(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
int? intOpt(Object? v) => v is num ? v.toInt() : null;
bool boolReq(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

Map<String, double> dblMap(Object? v) => v is Map
    ? v.map((k, val) => MapEntry(k.toString(), (val as num).toDouble()))
    : <String, double>{};

Map<String, bool> boolMap(Object? v) => v is Map
    ? v.map((k, val) => MapEntry(k.toString(), val == true))
    : <String, bool>{};
