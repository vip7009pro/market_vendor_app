class EncryptionService {
  static final EncryptionService instance = EncryptionService._();
  EncryptionService._();

  // Không cần khởi tạo gì cả
  Future<void> init() async {}

  // Trả về ngay giá trị gốc, không mã hóa
  Future<String?> encryptNullable(String? plain) async => plain;

  // Trả về ngay giá trị gốc, không mã hóa
  Future<String> encrypt(String plain) async => plain;

  // Trả về ngay giá trị gốc, không giải mã
  Future<String?> decryptNullable(String? encrypted) async => encrypted;

  // Trả về ngay giá trị gốc, không giải mã
  Future<String> decrypt(String encrypted) async => encrypted;
}
