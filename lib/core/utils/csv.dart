/// Minimal RFC-4180 CSV reader/writer (quoted fields, escaped quotes,
/// CRLF/LF line endings). Kept dependency-free on purpose.
abstract final class Csv {
  static List<List<String>> parse(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var i = 0;
    final text = input.startsWith('﻿') ? input.substring(1) : input;
    while (i < text.length) {
      final c = text[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        row.add(field.toString());
        field.clear();
      } else if (c == '\n' || c == '\r') {
        row.add(field.toString());
        field.clear();
        if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      } else {
        field.write(c);
      }
      i++;
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
    }
    return rows;
  }

  static String encode(List<List<Object?>> rows) =>
      rows.map((r) => r.map(_cell).join(',')).join('\r\n');

  static String _cell(Object? v) {
    final s = v?.toString() ?? '';
    if (s.contains(RegExp(r'[",\r\n]'))) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}
