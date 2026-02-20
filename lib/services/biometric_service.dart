import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _emailKey = 'bio_auth_email';
  static const String _passwordKey = 'bio_auth_password';
  static const String _enabledKey = 'bio_auth_enabled';

  /// Check if device supports biometrics and has enrolled biometrics.
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      debugPrint('BiometricService: canCheck=$canCheck, isDeviceSupported=$isDeviceSupported');
      if (!canCheck || !isDeviceSupported) return false;

      final available = await _localAuth.getAvailableBiometrics();
      debugPrint('BiometricService: available biometrics=$available');
      return available.isNotEmpty;
    } catch (e) {
      debugPrint('BiometricService: Error checking availability: $e');
      return false;
    }
  }

  /// Trigger the biometric authentication prompt.
  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Sign in to Vineyard Inventory',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (e) {
      debugPrint('BiometricService: Authentication error: $e');
      return false;
    }
  }

  /// Save credentials to encrypted secure storage. Returns true if verified.
  Future<bool> saveCredentials(String email, String password) async {
    debugPrint('BiometricService: Saving credentials for email="$email", pw length=${password.length}');
    try {
      await _secureStorage.write(key: _emailKey, value: email);
      await _secureStorage.write(key: _passwordKey, value: password);
      // Verify the write succeeded
      final savedEmail = await _secureStorage.read(key: _emailKey);
      final savedPassword = await _secureStorage.read(key: _passwordKey);
      final verified = savedEmail == email && savedPassword == password;
      debugPrint('BiometricService: Verify save: ${verified ? "OK" : "FAILED"} (email=${savedEmail != null})');
      return verified;
    } catch (e) {
      debugPrint('BiometricService: ERROR saving credentials: $e');
      return false;
    }
  }

  /// Retrieve stored credentials. Returns null if not found.
  Future<({String email, String password})?> getCredentials() async {
    final email = await _secureStorage.read(key: _emailKey);
    final password = await _secureStorage.read(key: _passwordKey);
    debugPrint('BiometricService: getCredentials email=${email != null ? '"${email}"' : 'null'}, pw=${password != null ? 'present' : 'null'}');
    if (email != null && password != null) {
      return (email: email, password: password);
    }
    return null;
  }

  /// Remove stored credentials.
  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: _emailKey);
    await _secureStorage.delete(key: _passwordKey);
    await setBiometricLoginEnabled(false);
  }

  /// Check if the user has opted in to biometric login.
  Future<bool> isBiometricLoginEnabled() async {
    final value = await _secureStorage.read(key: _enabledKey);
    return value == 'true';
  }

  /// Set the biometric login opt-in flag.
  Future<void> setBiometricLoginEnabled(bool enabled) async {
    await _secureStorage.write(key: _enabledKey, value: enabled.toString());
  }
}
