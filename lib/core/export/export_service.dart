import '../utils/csv.dart';
import 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart';

/// CSV export. Web: browser download. Native: file in the downloads or
/// documents folder. The UI also offers "Copy CSV" as a universal fallback.
class ExportService {
  const ExportService();

  String toCsv(List<String> header, List<List<Object?>> rows) =>
      Csv.encode([header, ...rows]);

  /// Returns a human-readable description of where the file went.
  Future<String> saveCsv(String fileName, String csv) =>
      saveTextFile(fileName, csv);
}
