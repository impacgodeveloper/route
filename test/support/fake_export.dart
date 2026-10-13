import 'package:executive_fleet/core/export/export_service.dart';

/// Records exports in memory instead of writing files.
class FakeExportService extends ExportService {
  FakeExportService();
  final saved = <String, String>{};

  @override
  Future<String> saveCsv(String fileName, String csv) async {
    saved[fileName] = csv;
    return 'Saved $fileName (test)';
  }
}
