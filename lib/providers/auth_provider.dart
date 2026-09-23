// lib/providers/auth_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../services/online_sync_service.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  static const String _driveFileScope = 'https://www.googleapis.com/auth/drive.file';
  static const String _sheetsScope = 'https://www.googleapis.com/auth/spreadsheets';
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'profile',
      _driveFileScope,
      _sheetsScope,
    ],
  );

  User? _firebaseUser;
  bool _isLoading = false;
  bool _initialChecked = false;
  String? _errorMessage;

  User? get firebaseUser => _firebaseUser;
  String? get uid => _firebaseUser?.uid;
  bool get isSignedIn => _firebaseUser != null;
  bool get isLoading => _isLoading;
  bool get initialChecked => _initialChecked;
  String? get errorMessage => _errorMessage;

  AuthProvider() {
    // Khởi tạo ngay trạng thái người dùng hiện tại từ cache Firebase
    _firebaseUser = _firebaseAuth.currentUser;
    _initialChecked = true;

    // Lắng nghe trạng thái auth từ Firebase
    _firebaseAuth.authStateChanges().listen((user) {
      _firebaseUser = user;
      _initialChecked = true;
      notifyListeners();
    });
  }

  // Đăng nhập Google → Firebase Auth
  Future<void> signInWithGoogle() async {
    _setLoading(true);
    _errorMessage = null;

    try {
      // Đảm bảo luôn hiện popup chọn tài khoản (đặc biệt quan trọng trên Samsung S24 Ultra)
      await _googleSignIn.signOut(); // Clear session cũ để hiện bottom sheet

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _errorMessage = 'Đăng nhập bị hủy';
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      _firebaseUser = userCredential.user;

      // Khởi chạy đồng bộ ngầm trong background (không block luồng đăng nhập UI)
      if (_firebaseUser != null) {
        unawaited(
          OnlineSyncService.startAutoSync(auth: this).catchError((e) {
            debugPrint('startAutoSync background error: $e');
          }),
        );
      }
    } catch (e) {
      _errorMessage = 'Lỗi đăng nhập: $e';
      debugPrint('Firebase Google Sign In error: $e');
    } finally {
      // Luôn kết thúc loading để UI cập nhật trạng thái (AuthGate chuyển sang HomeScreen nếu thành công)
      _setLoading(false);
    }
  }

  // Request quyền Google Drive (gọi sau khi đã có Firebase user)
  Future<bool> requestDriveScope() async {
    try {
      final granted = await _googleSignIn.requestScopes([
        _driveFileScope, // An toàn, chỉ truy cập file app tạo
      ]);
      notifyListeners();
      return granted;
    } catch (e) {
      debugPrint('Request Drive scope error: $e');
      return false;
    }
  }

  Future<bool> requestSheetsScope() async {
    try {
      final granted = await _googleSignIn.requestScopes([
        _sheetsScope,
      ]);
      notifyListeners();
      return granted;
    } catch (e) {
      debugPrint('Request Sheets scope error: $e');
      return false;
    }
  }

  // Lấy access token Google để dùng Drive API
  Future<String?> getAccessToken() async {
    try {
      final currentGoogleUser = _googleSignIn.currentUser ??
          await _googleSignIn.signInSilently().timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );
      if (currentGoogleUser == null) return null;
      final auth = await currentGoogleUser.authentication;
      return auth.accessToken;
    } catch (e) {
      debugPrint('Get access token error: $e');
      return null;
    }
  }

  Future<String?> getIdToken() async {
    try {
      final currentGoogleUser = _googleSignIn.currentUser ??
          await _googleSignIn.signInSilently().timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );
      if (currentGoogleUser == null) return null;
      final auth = await currentGoogleUser.authentication;
      return auth.idToken;
    } catch (e) {
      debugPrint('Get id token error: $e');
      return null;
    }
  }

  // Lấy DriveApi client
  Future<drive.DriveApi?> getDriveApi() async {
    final token = await getAccessToken();
    if (token == null) return null;
    final client = GoogleAuthClient({'Authorization': 'Bearer $token'});
    return drive.DriveApi(client);
  }

  // Đăng xuất
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    // IMPORTANT: disconnect() revokes scopes and will trigger consent again next login.
    await _googleSignIn.signOut();
    _firebaseUser = null;
    OnlineSyncService.stopAutoSync();
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }

  @override
  void close() => _client.close();
}