// lib/services/auth_handler.dart - NEW FILE
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthHandler {
  static final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  
  /// Detect which authentication system is active and return the appropriate token
  static Future<TokenInfo?> getActiveToken() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check authentication source flag
    final authSource = prefs.getString('auth_source') ?? 'unknown';
    
    print('Auth source detected: $authSource');
    
    // Option 1: User authenticated with NestJS (primary)
    if (authSource == 'nestjs') {
      final token = prefs.getString('token') ?? prefs.getString('jwt_token');
      if (token != null && token.isNotEmpty) {
        print('Using NestJS JWT token');
        return TokenInfo(token: token, source: 'nestjs');
      }
    }
    
    // Option 2: User authenticated with Firebase (backup)
    else if (authSource == 'firebase') {
      try {
        final firebaseUser = _firebaseAuth.currentUser;
        if (firebaseUser != null) {
          final firebaseToken = await firebaseUser.getIdToken();
          if (firebaseToken != null && firebaseToken.isNotEmpty) {
            print('Using Firebase ID token');
            return TokenInfo(token: firebaseToken, source: 'firebase');
          }
        }
      } catch (e) {
        print('Failed to get Firebase token: $e');
      }
    }
    
    // Option 3: Auto-detect (for backward compatibility)
    else {
      // Try NestJS token first
      final nestToken = prefs.getString('token') ?? prefs.getString('jwt_token');
      if (nestToken != null && nestToken.isNotEmpty) {
        print('Auto-detected NestJS token');
        await prefs.setString('auth_source', 'nestjs');
        return TokenInfo(token: nestToken, source: 'nestjs');
      }
      
      // Try Firebase token second
      try {
        final firebaseUser = _firebaseAuth.currentUser;
        if (firebaseUser != null) {
          final firebaseToken = await firebaseUser.getIdToken();
          if (firebaseToken != null && firebaseToken.isNotEmpty) {
            print('Auto-detected Firebase token');
            await prefs.setString('auth_source', 'firebase');
            return TokenInfo(token: firebaseToken, source: 'firebase');
          }
        }
      } catch (e) {
        print('Firebase token auto-detect failed: $e');
      }
    }
    
    print('No valid token found');
    return null;
  }
  
  /// Set the active authentication source after login
  static Future<void> setAuthSource(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_source', source);
    print('Auth source set to: $source');
  }
  
  /// Check if user is authenticated with either system
  static Future<bool> isAuthenticated() async {
    final tokenInfo = await getActiveToken();
    return tokenInfo != null;
  }
  
  /// Clear all authentication data
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_source');
    await prefs.remove('token');
    await prefs.remove('jwt_token');
    await _firebaseAuth.signOut();
    print('All auth data cleared');
  }
}

class TokenInfo {
  final String token;
  final String source; // 'nestjs' or 'firebase'
  
  TokenInfo({required this.token, required this.source});
}