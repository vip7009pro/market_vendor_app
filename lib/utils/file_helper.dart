import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';
import 'package:device_info_plus/device_info_plus.dart';
// Thêm thư viện cho MediaStore API
import 'package:flutter/services.dart';

class FileHelper {
  /// Xuất dữ liệu sang file CSV và lưu vào thư mục phù hợp
  /// 
  /// [context] - BuildContext hiện tại
  /// [csvContent] - Nội dung CSV dạng String
  /// [fileName] - Tên file (không bao gồm thời gian và phần mở rộng)
  /// [openAfterExport] - Có mở file sau khi xuất không
  static Future<bool> exportCsv({
    required BuildContext context,
    required String csvContent,
    required String fileName,
    bool openAfterExport = false,
  }) async {
    try {
      // Thêm timestamp vào tên file
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fullFileName = '${fileName}_$timestamp.csv';
      
      // Lưu file CSV
      final filePath = await _saveCSVFile(csvContent, fullFileName);
      if (filePath == null) {
        if (!context.mounted) return false;
        _showErrorMessage(context, 'Không thể lưu file CSV. Vui lòng kiểm tra quyền truy cập.');
        return false;
      }
      
      if (!context.mounted) return false;
      
      // Hiển thị thông báo thành công
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xuất CSV thành công'),
          action: SnackBarAction(
            label: openAfterExport ? 'Mở file' : 'Đóng',
            onPressed: () {
              if (openAfterExport) {
                OpenFilex.open(filePath);
              }
            },
          ),
        ),
      );
      
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      _showErrorMessage(context, 'Lỗi khi xuất file: $e');
      return false;
    }
  }

  static Future<String?> saveBytesToDownloads({
    required List<int> bytes,
    required String fileName,
    String? mimeType,
  }) async {
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final dir = await getDownloadsDirectory();
        final targetDir = dir ?? await getApplicationDocumentsDirectory();
        final file = File('${targetDir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        return file.path;
      }

      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        // Với Android 10+ dùng MediaStore plugin để file hiện đúng trong Downloads
        if (sdkInt >= 29) {
          try {
            const platform = MethodChannel('com.marketvendor.market_vendor_app/file_storage');
            final result = await platform.invokeMethod('saveBytes', {
              'bytes': Uint8List.fromList(bytes),
              'fileName': fileName,
              'mimeType': mimeType ?? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            });
            return result as String?;
          } catch (e) {
            print('Lỗi khi sử dụng FileStoragePlugin (bytes): $e');
          }
        }

        if (await Permission.storage.request().isGranted) {
          Directory? directory;
          final downloadDir = Directory('/storage/emulated/0/Download');
          if (await downloadDir.exists()) {
            directory = downloadDir;
          } else {
            final externalDir = await getExternalStorageDirectory();
            if (externalDir != null) {
              final List<String> paths = externalDir.path.split('/');
              final basePath = paths.sublist(0, paths.indexOf('Android')).join('/');
              final downloadPath = '$basePath/Download';
              directory = Directory(downloadPath);
              if (!await directory.exists()) {
                await directory.create(recursive: true);
              }
            }
          }
          if (directory != null) {
            final file = File('${directory.path}/$fileName');
            await file.writeAsBytes(bytes, flush: true);
            return file.path;
          }
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      print('Lỗi khi lưu bytes: $e');
      return null;
    }
  }
  
  /// Lưu file CSV sử dụng FileStoragePlugin cho Android 11+ hoặc cách thông thường cho các phiên bản cũ hơn
  static Future<String?> _saveCSVFile(String csvContent, String fileName) async {
    // Kiểm tra phiên bản Android
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      
      // Với Android 10 trở lên, sử dụng FileStoragePlugin
      if (sdkInt >= 29) {
        try {
          // Sử dụng MethodChannel để gọi FileStoragePlugin
          const platform = MethodChannel('com.marketvendor.market_vendor_app/file_storage');
          
          // Gọi phương thức saveFile từ plugin native
          final result = await platform.invokeMethod('saveFile', {
            'content': csvContent,
            'fileName': fileName,
            'mimeType': 'text/csv',
          });
          
          return result as String?;
        } catch (e) {
          print('Lỗi khi sử dụng FileStoragePlugin: $e');
          // Nếu không thành công, thử cách thông thường
        }
      }
      
      // Cách thông thường cho Android 9 trở xuống
      if (await Permission.storage.request().isGranted) {
        try {
          // Thử lấy thư mục Downloads
          Directory? directory;
          
          // Thử sử dụng đường dẫn trực tiếp
          final downloadDir = Directory('/storage/emulated/0/Download');
          if (await downloadDir.exists()) {
            directory = downloadDir;
          } else {
            // Thử cách khác
            final externalDir = await getExternalStorageDirectory();
            if (externalDir != null) {
              final List<String> paths = externalDir.path.split('/');
              final basePath = paths.sublist(0, paths.indexOf('Android')).join('/');
              final downloadPath = '$basePath/Download';
              
              directory = Directory(downloadPath);
              if (!await directory.exists()) {
                await directory.create(recursive: true);
              }
            }
          }
          
          if (directory != null) {
            final filePath = '${directory.path}/$fileName';
            final file = File(filePath);
            await file.writeAsString(csvContent);
            return filePath;
          }
        } catch (e) {
          print('Lỗi khi lưu file: $e');
        }
      }
    } else if (Platform.isIOS) {
      // iOS không cần quyền đặc biệt để lưu vào thư mục ứng dụng
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(csvContent);
      return filePath;
    }
    
    // Nếu tất cả cách trên đều thất bại, sử dụng thư mục ứng dụng
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(csvContent);
      return filePath;
    } catch (e) {
      print('Lỗi khi lưu vào thư mục ứng dụng: $e');
      return null;
    }
  }
  
  /// Hiển thị thông báo lỗi
  static void _showErrorMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message))
    );
  }
  
  /// Kiểm tra và yêu cầu quyền truy cập bộ nhớ
  static Future<bool> requestStoragePermission(BuildContext context) async {
    if (Platform.isAndroid) {
      // Kiểm tra phiên bản Android
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      
      // Android 13 (API 33) trở lên sử dụng quyền cụ thể
      if (sdkInt >= 33) {
        // Yêu cầu quyền truy cập ảnh và video
        final photos = await Permission.photos.request();
        if (!photos.isGranted) {
          if (!context.mounted) return false;
          _showErrorMessage(
            context, 
            'Cần quyền truy cập ảnh và video để lưu file. Vui lòng cấp quyền trong cài đặt ứng dụng.'
          );
          return false;
        }
        return true;
      } 
      // Android 11-12 (API 30-32)
      else if (sdkInt >= 30) {
        // Yêu cầu quyền storage cơ bản
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          if (!context.mounted) return false;
          _showErrorMessage(
            context, 
            'Không có quyền lưu tệp. Vui lòng cấp quyền lưu trữ trong cài đặt ứng dụng.'
          );
          return false;
        }
        return true;
      } 
      // Android 10 trở xuống
      else {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          if (!context.mounted) return false;
          _showErrorMessage(
            context, 
            'Không có quyền lưu tệp. Vui lòng cấp quyền lưu trữ trong cài đặt ứng dụng.'
          );
          return false;
        }
      }
    }
    return true;
  }
}