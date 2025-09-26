import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:sqflite/sqflite.dart';
import '../main.dart'; // Import main.dart để lấy navigatorKey
import '../services/sync_service.dart';
import '../services/database_service.dart';

class AuthProvider with ChangeNotifier {
  GoogleSignInAccount? _user;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.file',
    ],
  );
  fb.User? _fbUser;

  GoogleSignInAccount? get user => _user;
  fb.User? get firebaseUser => _fbUser;
  String? get uid => _fbUser?.uid;

  // Initialize the auth state
  Future<void> initialize() async {
    try {
      print('Starting silent sign in...');
      // Try to sign in silently first
      _user = await _googleSignIn.signInSilently();
      print('Silent sign in result: $_user');
      
      if (_user != null) {
        print('User found, authenticating with Firebase...');
        final auth = await _user!.authentication;
        final credential = fb.GoogleAuthProvider.credential(
          accessToken: auth.accessToken,
          idToken: auth.idToken,
        );
        final credResult = await fb.FirebaseAuth.instance.signInWithCredential(credential);
        _fbUser = credResult.user;
        print('Firebase authentication successful, user: ${_fbUser?.uid}');
        // SyncService đã được khởi tạo trong main.dart
        notifyListeners();
      } else {
        print('No user found in silent sign in');
        // Make sure to notify listeners even when no user is found
        notifyListeners();
      }
    } catch (e) {
      // Silent sign-in failed, user needs to sign in manually
      print('Silent sign in failed: $e');
      // Notify listeners to update UI
      notifyListeners();
    }
  }

  // Retrieve current Google OAuth access token (for Google Drive API)
  Future<String?> getAccessToken() async {
    try {
      if (_user == null) {
        // attempt silent sign-in to refresh token
        _user = await _googleSignIn.signInSilently();
      }
      final auth = await _user?.authentication;
      return auth?.accessToken;
    } catch (e) {
      debugPrint('getAccessToken error: $e');
      return null;
    }
  }

  Future<bool> signIn() async {
    try {
      print('Starting Google Sign In...');
      _user = await _googleSignIn.signIn();
      print('Google Sign In result: $_user');
      
      if (_user == null) {
        print('User cancelled sign in');
        return false;
      }

      print('Authenticating with Firebase...');
      final auth = await _user!.authentication;
      final credential = fb.GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      
      final credResult = await fb.FirebaseAuth.instance.signInWithCredential(credential);
      _fbUser = credResult.user;
      print('Firebase authentication successful, user: ${_fbUser?.uid}');
      
      // Clear local data before syncing
      await _clearLocalData();
      
      // Perform initial sync
      if (_fbUser != null) {
        // SyncService đã được khởi tạo trong main.dart
        // và sẽ tự động đồng bộ khi có người dùng đăng nhập
      }
      
      notifyListeners();
      return true;
    } catch (e) {
      print('Error during sign in: $e');
      // Clear any partial state on error
      await _googleSignIn.signOut();
      await fb.FirebaseAuth.instance.signOut();
      _user = null;
      _fbUser = null;
      notifyListeners();
      rethrow;
    }
  }
  
  // Clear all local data
  Future<void> _clearLocalData() async {
    try {
      final db = await openDatabase(await getDatabasesPath() + '/market_vendor.db');
      
      // Get list of all tables
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'"
      );
      
      // Delete all data from each table
      final batch = db.batch();
      for (final table in tables) {
        final tableName = table['name'] as String;
        if (tableName != 'deleted_entities') { // Keep deleted_entities for sync
          batch.delete(tableName);
        }
      }
      
      await batch.commit(noResult: true);
      
      // Reinitialize the database
      await DatabaseService.instance.init();
      
    } catch (e) {
      print('Error clearing local data: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      // Sync one last time before signing out
      if (_fbUser != null) {
        final syncService = SyncService(navigatorKey: navigatorKey);
        await syncService.syncNow(userId: _fbUser!.uid);
      }
      
      // Sign out from Google and Firebase
      await _googleSignIn.signOut();
      await fb.FirebaseAuth.instance.signOut();
      
      _user = null;
      _fbUser = null;
      notifyListeners();
      print('Sign out successful, notifying listeners...');
      print('Sign out completed');
    } catch (e) {
      print('Error during sign out: $e');
      rethrow;
    }
  }
  
  // Check if user is signed in
  bool get isSignedIn => _fbUser != null;
}
