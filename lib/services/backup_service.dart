import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'database_service.dart';

class BackupService {
  static final BackupService instance = BackupService._();
  BackupService._();

  Future<File> exportToJson() async {
    final data = await DatabaseService.instance.getAllForBackup();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getApplicationDocumentsDirectory();
    final backups = Directory('${dir.path}/backups');
    if (!await backups.exists()) {
      await backups.create(recursive: true);
    }
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${backups.path}/backup_$ts.json');
    return file.writeAsString(jsonStr);
  }
}
