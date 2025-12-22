import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

class DriveSyncService {
  static const String backupFolderName = 'GhiNoBackUp';
  static const String purchaseDocFolderName = 'NhapHangDauVao';
  static const String expenseDocFolderName = 'CHUNGTU';

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
    final dbPath = await getDatabasesPath();
    final filePath = '$dbPath/market_vendor.db';
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Không tìm thấy tệp cơ sở dữ liệu: $filePath');
    }

    final fileBytes = await file.readAsBytes();
    final fileName = 'market_vendor_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.db';

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
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files?q=$q&fields=files(id,name,modifiedTime)&orderBy=modifiedTime desc');
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $accessToken'});
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final files = (data['files'] as List<dynamic>? ?? [])
          .map((e) => {
                'id': (e as Map<String, dynamic>)['id'] as String,
                'name': e['name'] as String,
                'modifiedTime': (e['modifiedTime'] as String?) ?? '',
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
    final dbPath = await getDatabasesPath();
    final filePath = '$dbPath/market_vendor.db';
    final tmpPath = '$filePath.tmp';

    final tmp = File(tmpPath);
    await tmp.writeAsBytes(bytes, flush: true);

    final dbFile = File(filePath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await tmp.rename(filePath);
  }

  Future<void> deleteFile({required String accessToken, required String fileId}) async {
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId');
    final resp = await http.delete(uri, headers: {'Authorization': 'Bearer $accessToken'});
    if (resp.statusCode == 204) return;
    debugPrint('Drive delete failed: ${resp.statusCode} ${resp.body}');
    throw Exception('Xóa tệp trên Google Drive thất bại (${resp.statusCode})');
  }
}
