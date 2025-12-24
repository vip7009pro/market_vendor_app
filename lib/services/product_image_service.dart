import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ProductImageService {
  static final ProductImageService instance = ProductImageService._();
  ProductImageService._();

  static const String _dirName = 'product_images';

  Future<Directory> _baseDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory(p.join(dir.path, _dirName));
  }

  Future<void> ensureDir() async {
    final dir = await _baseDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<String> saveFromXFile({required XFile source, required String productId}) async {
    await ensureDir();
    final dir = await _baseDir();

    final extRaw = p.extension(source.path).toLowerCase();
    final ext = (extRaw == '.png' || extRaw == '.webp') ? extRaw : '.jpg';

    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'p_${productId}_$ts$ext';
    final dest = File(p.join(dir.path, fileName));

    await File(source.path).copy(dest.path);

    // Store relative path so backup/restore can move together with DB.
    return p.join(_dirName, fileName);
  }

  Future<String?> resolvePath(String? imagePath) async {
    if (imagePath == null || imagePath.trim().isEmpty) return null;

    // If already absolute, keep it.
    if (p.isAbsolute(imagePath)) return imagePath;

    final docs = await getApplicationDocumentsDirectory();
    return p.normalize(p.join(docs.path, imagePath));
  }

  Future<File?> resolveFile(String? imagePath) async {
    final full = await resolvePath(imagePath);
    if (full == null) return null;
    return File(full);
  }

  Future<bool> exists(String? imagePath) async {
    final f = await resolveFile(imagePath);
    if (f == null) return false;
    return f.exists();
  }

  Future<void> delete(String? imagePath) async {
    if (imagePath == null || imagePath.trim().isEmpty) return;
    final f = await resolveFile(imagePath);
    if (f == null) return;

    // Best-effort delete.
    try {
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }

  Future<Directory> imagesDir() async {
    await ensureDir();
    return _baseDir();
  }
}
