import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DocumentStorageService {
  static final DocumentStorageService instance = DocumentStorageService._();
  DocumentStorageService._();

  static const String _purchaseDocsDir = 'purchase_docs';
  static const String _expenseDocsDir = 'expense_docs';

  Future<String> savePurchaseDoc({
    required String purchaseId,
    required String sourcePath,
    String? extension,
  }) async {
    return _save(
      dirName: _purchaseDocsDir,
      baseName: purchaseId,
      sourcePath: sourcePath,
      extension: extension,
    );
  }

  Future<String> saveExpenseDoc({
    required String expenseId,
    required String sourcePath,
    String? extension,
  }) async {
    return _save(
      dirName: _expenseDocsDir,
      baseName: expenseId,
      sourcePath: sourcePath,
      extension: extension,
    );
  }

  Future<String?> resolvePath(String? relativePath) async {
    final rel = (relativePath ?? '').trim();
    if (rel.isEmpty) return null;
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, rel);
  }

  Future<void> delete(String? relativePath) async {
    final full = await resolvePath(relativePath);
    if (full == null || full.isEmpty) return;
    final f = File(full);
    if (await f.exists()) {
      await f.delete();
    }
  }

  Future<String> _save({
    required String dirName,
    required String baseName,
    required String sourcePath,
    String? extension,
  }) async {
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw Exception('Không tìm thấy file chứng từ');
    }

    final docs = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(docs.path, dirName));
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    var ext = (extension ?? '').trim();
    if (ext.isEmpty) {
      ext = p.extension(sourcePath);
    }
    if (ext.isEmpty) {
      ext = '.bin';
    }
    if (!ext.startsWith('.')) {
      ext = '.$ext';
    }

    final outName = '${baseName}_doc$ext';
    final outFile = File(p.join(outDir.path, outName));
    await src.copy(outFile.path);

    return p.join(dirName, outName);
  }
}
