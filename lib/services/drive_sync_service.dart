import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DriveSyncService {
  static const String backupFolderName = 'GhiNoBackUp';
  static const String purchaseDocFolderName = 'NhapHangDauVao';
  static const String expenseDocFolderName = 'CHUNGTU';

  static const String _dbFileName = 'market_vendor.db';
  static const String _imagesDirName = 'product_images';
  static const String _purchaseDocsDirName = 'purchase_docs';
  static const String _purchaseOrderDocsDirName = 'purchase_order_docs';
  static const String _expenseDocsDirName = 'expense_docs';

  bool _looksLikeZip(Uint8List bytes) {
    return bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B; // PK
  }

  Future<Uint8List> _downloadFileWithProgress({
    required String accessToken,
    required String fileId,
    void Function(double progress, String stage)? onProgress,
    double startProgress = 0.0,
    double endProgress = 1.0,
  }) async {
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
    final req = http.Request('GET', uri);
    req.headers['Authorization'] = 'Bearer $accessToken';

    onProgress?.call(startProgress, 'Đang tải bản sao lưu...');

    final streamed = await req.send();
    if (streamed.statusCode != 200) {
      final resp = await http.Response.fromStream(streamed);
      throw Exception('Tải tệp sao lưu thất bại (${resp.statusCode})');
    }

    final contentLength = streamed.contentLength ?? -1;
    final builder = BytesBuilder(copy: false);
    int received = 0;
    await for (final chunk in streamed.stream) {
      builder.add(chunk);
      received += chunk.length;
      if (contentLength > 0) {
        final raw = received / contentLength;
        final clamped = raw.clamp(0.0, 1.0).toDouble();
        final p = startProgress + (endProgress - startProgress) * clamped;
        onProgress?.call(p, 'Đang tải bản sao lưu...');
      }
    }

    onProgress?.call(endProgress, 'Đang xử lý...');
    return builder.takeBytes();
  }

  Future<Uint8List> _buildBackupZipBytes() async {
    final dbPath = await getDatabasesPath();
    final dbFile = File(p.join(dbPath, _dbFileName));
    if (!await dbFile.exists()) {
      throw Exception('Không tìm thấy tệp cơ sở dữ liệu: ${dbFile.path}');
    }

    final archive = Archive();

    final dbBytes = await dbFile.readAsBytes();
    archive.addFile(ArchiveFile(_dbFileName, dbBytes.length, dbBytes));

    final docs = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(docs.path, _imagesDirName));
    if (await imagesDir.exists()) {
      await for (final ent in imagesDir.list(recursive: true, followLinks: false)) {
        if (ent is! File) continue;
        final rel = p.relative(ent.path, from: docs.path);
        final b = await ent.readAsBytes();
        archive.addFile(ArchiveFile(p.normalize(rel), b.length, b));
      }
    }

    final purchaseDocsDir = Directory(p.join(docs.path, _purchaseDocsDirName));
    if (await purchaseDocsDir.exists()) {
      await for (final ent in purchaseDocsDir.list(recursive: true, followLinks: false)) {
        if (ent is! File) continue;
        final rel = p.relative(ent.path, from: docs.path);
        final b = await ent.readAsBytes();
        archive.addFile(ArchiveFile(p.normalize(rel), b.length, b));
      }
    }

    final purchaseOrderDocsDir = Directory(p.join(docs.path, _purchaseOrderDocsDirName));
    if (await purchaseOrderDocsDir.exists()) {
      await for (final ent in purchaseOrderDocsDir.list(recursive: true, followLinks: false)) {
        if (ent is! File) continue;
        final rel = p.relative(ent.path, from: docs.path);
        final b = await ent.readAsBytes();
        archive.addFile(ArchiveFile(p.normalize(rel), b.length, b));
      }
    }

    final expenseDocsDir = Directory(p.join(docs.path, _expenseDocsDirName));
    if (await expenseDocsDir.exists()) {
      await for (final ent in expenseDocsDir.list(recursive: true, followLinks: false)) {
        if (ent is! File) continue;
        final rel = p.relative(ent.path, from: docs.path);
        final b = await ent.readAsBytes();
        archive.addFile(ArchiveFile(p.normalize(rel), b.length, b));
      }
    }

    final zipped = ZipEncoder().encode(archive);
    if (zipped == null) {
      throw Exception('Không tạo được file zip sao lưu');
    }
    return Uint8List.fromList(zipped);
  }

  Future<void> _restoreFromZipBytes(
    Uint8List bytes, {
    void Function(double progress, String stage)? onProgress,
    double startProgress = 0.0,
    double endProgress = 1.0,
  }) async {
    onProgress?.call(startProgress, 'Đang giải nén...');
    final decoded = ZipDecoder().decodeBytes(bytes);

    Uint8List? dbBytes;
    final imagesToWrite = <String, Uint8List>{};
    final purchaseDocsToWrite = <String, Uint8List>{};
    final purchaseOrderDocsToWrite = <String, Uint8List>{};
    final expenseDocsToWrite = <String, Uint8List>{};

    for (final f in decoded) {
      if (f.isFile != true) continue;
      final name = (f.name).trim();
      final content = f.content;
      if (content is! List<int>) continue;
      final fileBytes = Uint8List.fromList(content);

      if (p.basename(name) == _dbFileName) {
        dbBytes = fileBytes;
        continue;
      }

      final norm = p.normalize(name);
      if (norm.startsWith('$_imagesDirName${p.separator}') || norm.startsWith('$_imagesDirName/')) {
        imagesToWrite[norm] = fileBytes;
        continue;
      }

      if (norm.startsWith('$_purchaseDocsDirName${p.separator}') || norm.startsWith('$_purchaseDocsDirName/')) {
        purchaseDocsToWrite[norm] = fileBytes;
        continue;
      }

      if (norm.startsWith('$_purchaseOrderDocsDirName${p.separator}') || norm.startsWith('$_purchaseOrderDocsDirName/')) {
        purchaseOrderDocsToWrite[norm] = fileBytes;
        continue;
      }

      if (norm.startsWith('$_expenseDocsDirName${p.separator}') || norm.startsWith('$_expenseDocsDirName/')) {
        expenseDocsToWrite[norm] = fileBytes;
      }
    }

    if (dbBytes == null) {
      throw Exception('File zip không có $_dbFileName');
    }

    final totalWriteOps =
        1 + imagesToWrite.length + purchaseDocsToWrite.length + purchaseOrderDocsToWrite.length + expenseDocsToWrite.length;
    int writtenOps = 0;
    void tickProgress(String stage) {
      if (totalWriteOps <= 0) return;
      writtenOps += 1;
      final raw = writtenOps / totalWriteOps;
      final clamped = raw.clamp(0.0, 1.0).toDouble();
      final p = startProgress + (endProgress - startProgress) * clamped;
      onProgress?.call(p, stage);
    }

    // Restore DB
    final dbPath = await getDatabasesPath();
    final filePath = p.join(dbPath, _dbFileName);
    final tmpPath = '$filePath.tmp';

    final tmp = File(tmpPath);
    await tmp.writeAsBytes(dbBytes, flush: true);
    final dbFile = File(filePath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await tmp.rename(filePath);
    tickProgress('Đang khôi phục dữ liệu...');

    // Restore images
    final docs = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(docs.path, _imagesDirName));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    for (final e in imagesToWrite.entries) {
      final outPath = p.join(docs.path, e.key);
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(e.value, flush: true);
      tickProgress('Đang khôi phục hình ảnh...');
    }

    final purchaseDocsDir = Directory(p.join(docs.path, _purchaseDocsDirName));
    if (!await purchaseDocsDir.exists()) {
      await purchaseDocsDir.create(recursive: true);
    }
    for (final e in purchaseDocsToWrite.entries) {
      final outPath = p.join(docs.path, e.key);
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(e.value, flush: true);
      tickProgress('Đang khôi phục chứng từ nhập...');
    }

    final purchaseOrderDocsDir = Directory(p.join(docs.path, _purchaseOrderDocsDirName));
    if (!await purchaseOrderDocsDir.exists()) {
      await purchaseOrderDocsDir.create(recursive: true);
    }
    for (final e in purchaseOrderDocsToWrite.entries) {
      final outPath = p.join(docs.path, e.key);
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(e.value, flush: true);
      tickProgress('Đang khôi phục chứng từ đơn nhập...');
    }

    final expenseDocsDir = Directory(p.join(docs.path, _expenseDocsDirName));
    if (!await expenseDocsDir.exists()) {
      await expenseDocsDir.create(recursive: true);
    }
    for (final e in expenseDocsToWrite.entries) {
      final outPath = p.join(docs.path, e.key);
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(e.value, flush: true);
      tickProgress('Đang khôi phục chứng từ chi phí...');
    }

    onProgress?.call(endProgress, 'Hoàn tất');
  }

  /// Ensures the backup folder exists and returns its folderId.
  Future<String> _ensureBackupFolder({required String accessToken}) async {
    return _ensureFolder(accessToken: accessToken, folderName: backupFolderName);
  }

  Future<String> _ensureFolder({required String accessToken, required String folderName}) async {
    // Search for existing folder by name
    final q = Uri.encodeQueryComponent(
      "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
    );
    final listUri = Uri.parse('https://www.googleapis.com/drive/v3/files?q=$q&fields=files(id,name)');
    final listResp = await http.get(listUri, headers: {
      'Authorization': 'Bearer $accessToken',
    });
    if (listResp.statusCode == 200) {
      final data = jsonDecode(listResp.body) as Map<String, dynamic>;
      final files = (data['files'] as List<dynamic>?) ?? [];
      if (files.isNotEmpty) {
        return (files.first as Map<String, dynamic>)['id'] as String;
      }
    } else {
      debugPrint('Drive list folder failed: ${listResp.statusCode} ${listResp.body}');
    }

    // Create folder
    final createUri = Uri.parse('https://www.googleapis.com/drive/v3/files');
    final createResp = await http.post(
      createUri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode({
        'name': folderName,
        'mimeType': 'application/vnd.google-apps.folder',
        'parents': ['root'],
      }),
    );
    if (createResp.statusCode == 200 || createResp.statusCode == 201) {
      final data = jsonDecode(createResp.body) as Map<String, dynamic>;
      return data['id'] as String;
    }
    throw Exception('Không thể tạo thư mục trên Google Drive');
  }

  /// Uploads the local SQLite database file to the user's Google Drive backup folder.
  /// Requires a valid OAuth access token with drive.file scope.
  Future<String> uploadLocalDb({required String accessToken}) async {
    final fileBytes = await _buildBackupZipBytes();
    final fileName = 'market_vendor_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip';

    final folderId = await _ensureBackupFolder(accessToken: accessToken);
    final uri = Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart');

    // Build multipart body: part 1 metadata, part 2 file content
    final boundary = 'drive_boundary_${DateTime.now().microsecondsSinceEpoch}';
    final meta = jsonEncode({
      'name': fileName,
      'mimeType': 'application/octet-stream',
      'parents': [folderId],
    });

    final body = <int>[];
    void writeString(String s) => body.addAll(utf8.encode(s));

    writeString('--$boundary\r\n');
    writeString('Content-Type: application/json; charset=UTF-8\r\n\r\n');
    writeString('$meta\r\n');

    writeString('--$boundary\r\n');
    writeString('Content-Type: application/octet-stream\r\n\r\n');
    body.addAll(fileBytes);
    writeString('\r\n');

    writeString('--$boundary--\r\n');

    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: Uint8List.fromList(body),
    );

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      return 'Đã tải lên Google Drive: $fileName';
    }

    debugPrint('Drive upload failed: ${resp.statusCode} ${resp.body}');
    throw Exception('Tải lên Google Drive thất bại (${resp.statusCode})');
  }

  Future<Map<String, String>?> getPurchaseDocByName({
    required String accessToken,
    required String purchaseId,
  }) async {
    final folderId = await _ensureFolder(accessToken: accessToken, folderName: purchaseDocFolderName);
    final fileName = '$purchaseId.jpg';

    final q = Uri.encodeQueryComponent(
      "name = '$fileName' and '$folderId' in parents and trashed = false",
    );
    final uri = Uri.parse(
      'https://www.googleapis.com/drive/v3/files?q=$q&fields=files(id,name,webViewLink,webContentLink)',
    );
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $accessToken'});
    if (resp.statusCode != 200) {
      debugPrint('Drive list purchase doc failed: ${resp.statusCode} ${resp.body}');
      return null;
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final files = (data['files'] as List<dynamic>? ?? []);
    if (files.isEmpty) return null;
    final f = files.first as Map<String, dynamic>;
    return {
      'id': (f['id'] as String?) ?? '',
      'name': (f['name'] as String?) ?? '',
      'webViewLink': (f['webViewLink'] as String?) ?? '',
      'webContentLink': (f['webContentLink'] as String?) ?? '',
    };
  }

  Future<Map<String, String>> uploadOrUpdatePurchaseDocJpg({
    required String accessToken,
    required String purchaseId,
    required Uint8List bytes,
  }) async {
    final folderId = await _ensureFolder(accessToken: accessToken, folderName: purchaseDocFolderName);
    final fileName = '$purchaseId.jpg';

    final existing = await getPurchaseDocByName(accessToken: accessToken, purchaseId: purchaseId);
    final boundary = 'drive_boundary_${DateTime.now().microsecondsSinceEpoch}';

    final meta = jsonEncode({
      'name': fileName,
      'mimeType': 'image/jpeg',
      'parents': [folderId],
    });

    final body = <int>[];
    void writeString(String s) => body.addAll(utf8.encode(s));

    writeString('--$boundary\r\n');
    writeString('Content-Type: application/json; charset=UTF-8\r\n\r\n');
    writeString('$meta\r\n');

    writeString('--$boundary\r\n');
    writeString('Content-Type: image/jpeg\r\n\r\n');
    body.addAll(bytes);
    writeString('\r\n');

    writeString('--$boundary--\r\n');

    final Uri uri;
    final String method;
    if (existing != null && (existing['id'] ?? '').isNotEmpty) {
      method = 'PATCH';
      uri = Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files/${existing['id']}?uploadType=multipart&fields=id,name,webViewLink,webContentLink',
      );
    } else {
      method = 'POST';
      uri = Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,webViewLink,webContentLink',
      );
    }

    final req = http.Request(method, uri);
    req.headers.addAll({
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'multipart/related; boundary=$boundary',
    });
    req.bodyBytes = Uint8List.fromList(body);
    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return {
        'id': (data['id'] as String?) ?? '',
        'name': (data['name'] as String?) ?? '',
        'webViewLink': (data['webViewLink'] as String?) ?? '',
        'webContentLink': (data['webContentLink'] as String?) ?? '',
      };
    }

    debugPrint('Drive upload purchase doc failed: ${resp.statusCode} ${resp.body}');
    throw Exception('Tải chứng từ lên Google Drive thất bại (${resp.statusCode})');
  }

  Future<Map<String, String>?> getExpenseDocByName({
    required String accessToken,
    required String expenseId,
  }) async {
    final folderId = await _ensureFolder(accessToken: accessToken, folderName: expenseDocFolderName);
    final fileName = '$expenseId.jpg';

    final q = Uri.encodeQueryComponent(
      "name = '$fileName' and '$folderId' in parents and trashed = false",
    );
    final uri = Uri.parse(
      'https://www.googleapis.com/drive/v3/files?q=$q&fields=files(id,name,webViewLink,webContentLink)',
    );
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $accessToken'});
    if (resp.statusCode != 200) {
      debugPrint('Drive list expense doc failed: ${resp.statusCode} ${resp.body}');
      return null;
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final files = (data['files'] as List<dynamic>? ?? []);
    if (files.isEmpty) return null;
    final f = files.first as Map<String, dynamic>;
    return {
      'id': (f['id'] as String?) ?? '',
      'name': (f['name'] as String?) ?? '',
      'webViewLink': (f['webViewLink'] as String?) ?? '',
      'webContentLink': (f['webContentLink'] as String?) ?? '',
    };
  }

  Future<Map<String, String>> uploadOrUpdateExpenseDocJpg({
    required String accessToken,
    required String expenseId,
    required Uint8List bytes,
  }) async {
    final folderId = await _ensureFolder(accessToken: accessToken, folderName: expenseDocFolderName);
    final fileName = '$expenseId.jpg';

    final existing = await getExpenseDocByName(accessToken: accessToken, expenseId: expenseId);
    final boundary = 'drive_boundary_${DateTime.now().microsecondsSinceEpoch}';

    final meta = jsonEncode({
      'name': fileName,
      'mimeType': 'image/jpeg',
      'parents': [folderId],
    });

    final body = <int>[];
    void writeString(String s) => body.addAll(utf8.encode(s));

    writeString('--$boundary\r\n');
    writeString('Content-Type: application/json; charset=UTF-8\r\n\r\n');
    writeString('$meta\r\n');

    writeString('--$boundary\r\n');
    writeString('Content-Type: image/jpeg\r\n\r\n');
    body.addAll(bytes);
    writeString('\r\n');

    writeString('--$boundary--\r\n');

    final Uri uri;
    final String method;
    if (existing != null && (existing['id'] ?? '').isNotEmpty) {
      method = 'PATCH';
      uri = Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files/${existing['id']}?uploadType=multipart&fields=id,name,webViewLink,webContentLink',
      );
    } else {
      method = 'POST';
      uri = Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,webViewLink,webContentLink',
      );
    }

    final req = http.Request(method, uri);
    req.headers.addAll({
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'multipart/related; boundary=$boundary',
    });
    req.bodyBytes = Uint8List.fromList(body);
    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return {
        'id': (data['id'] as String?) ?? '',
        'name': (data['name'] as String?) ?? '',
        'webViewLink': (data['webViewLink'] as String?) ?? '',
        'webContentLink': (data['webContentLink'] as String?) ?? '',
      };
    }

    debugPrint('Drive upload expense doc failed: ${resp.statusCode} ${resp.body}');
    throw Exception('Tải chứng từ chi phí lên Google Drive thất bại (${resp.statusCode})');
  }

  /// Lists backup files in the backup folder (id, name, modifiedTime).
  Future<List<Map<String, String>>> listBackups({required String accessToken}) async {
    final folderId = await _ensureBackupFolder(accessToken: accessToken);
    final q = Uri.encodeQueryComponent("'${folderId}' in parents and trashed = false");
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files?q=$q&fields=files(id,name,modifiedTime,size)&orderBy=modifiedTime desc');
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $accessToken'});
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final files = (data['files'] as List<dynamic>? ?? [])
          .map((e) => {
                'id': (e as Map<String, dynamic>)['id'] as String,
                'name': e['name'] as String,
                'modifiedTime': (e['modifiedTime'] as String?) ?? '',
                'size': (e['size']?.toString() ?? ''),
              })
          .toList();
      return files;
    }
    throw Exception('Không thể tải danh sách bản sao lưu từ Google Drive');
  }

  /// Downloads a file content by id.
  Future<Uint8List> downloadFile({required String accessToken, required String fileId}) async {
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $accessToken'});
    if (resp.statusCode == 200) {
      return resp.bodyBytes;
    }
    throw Exception('Tải tệp sao lưu thất bại (${resp.statusCode})');
  }

  /// Downloads the selected backup and restores it to the local SQLite DB path.
  /// Sau khi khôi phục, sẽ tự động thực hiện migration nếu cần thiết.
  Future<void> restoreToLocal({required String accessToken, required String fileId}) async {
    final bytes = await downloadFile(accessToken: accessToken, fileId: fileId);
    if (_looksLikeZip(bytes)) {
      await _restoreFromZipBytes(bytes);
      return;
    }

    // Legacy: db-only backup
    final dbPath = await getDatabasesPath();
    final filePath = p.join(dbPath, _dbFileName);
    final tmpPath = '$filePath.tmp';

    final tmp = File(tmpPath);
    await tmp.writeAsBytes(bytes, flush: true);

    final dbFile = File(filePath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await tmp.rename(filePath);
  }

  Future<void> restoreToLocalWithProgress({
    required String accessToken,
    required String fileId,
    void Function(double progress, String stage)? onProgress,
  }) async {
    final bytes = await _downloadFileWithProgress(
      accessToken: accessToken,
      fileId: fileId,
      onProgress: onProgress,
      startProgress: 0.0,
      endProgress: 0.60,
    );

    if (_looksLikeZip(bytes)) {
      await _restoreFromZipBytes(
        bytes,
        onProgress: onProgress,
        startProgress: 0.60,
        endProgress: 1.0,
      );
      return;
    }

    onProgress?.call(0.70, 'Đang khôi phục dữ liệu...');

    // Legacy: db-only backup
    final dbPath = await getDatabasesPath();
    final filePath = p.join(dbPath, _dbFileName);
    final tmpPath = '$filePath.tmp';

    final tmp = File(tmpPath);
    await tmp.writeAsBytes(bytes, flush: true);

    final dbFile = File(filePath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await tmp.rename(filePath);
    onProgress?.call(1.0, 'Hoàn tất');
  }

  Future<void> deleteFile({required String accessToken, required String fileId}) async {
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId');
    final resp = await http.delete(uri, headers: {'Authorization': 'Bearer $accessToken'});
    if (resp.statusCode == 204) return;
    debugPrint('Drive delete failed: ${resp.statusCode} ${resp.body}');
    throw Exception('Xóa tệp trên Google Drive thất bại (${resp.statusCode})');
  }
}
