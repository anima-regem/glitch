import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

import '../models/app_data.dart';

class BackupService {
  BackupService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const int _currentBackupVersion = 2;
  static const String _keyStorageName = 'glitch_backup_key_v1';
  static const String _vaultPassphraseStorageName =
      'glitch_backup_vault_passphrase_v1';
  static const String _backupPrefix = 'glitch-backup';
  static const String vaultSnapshotFileName = 'glitch-vault-latest.json';
  static const int _pbkdf2Iterations = 120000;
  static const int _keySizeBytes = 32;
  static const int _saltSizeBytes = 16;
  static const String _kdfName = 'PBKDF2-HMAC-SHA256';
  static const String _cipherName = 'AES-256-CBC';

  final FlutterSecureStorage _secureStorage;

  Future<String> exportToFile(
    AppData data, {
    required String passphrase,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return exportToDirectory(
      data,
      directoryPath: directory.path,
      passphrase: passphrase,
      fileName: '$_backupPrefix-$timestamp.json',
    );
  }

  Future<String> exportToDirectory(
    AppData data, {
    required String directoryPath,
    required String passphrase,
    required String fileName,
  }) async {
    final normalizedPath = directoryPath.trim();
    if (normalizedPath.isEmpty) {
      throw const FormatException('Backup folder path cannot be empty.');
    }

    final parsed = Uri.tryParse(normalizedPath);
    final resolvedPath = (parsed != null && parsed.scheme == 'file')
        ? parsed.toFilePath()
        : normalizedPath;

    if (parsed != null &&
        parsed.hasScheme &&
        parsed.scheme.isNotEmpty &&
        parsed.scheme != 'file') {
      throw const FormatException(
        'Selected folder is not a local filesystem path. Choose a local folder path.',
      );
    }

    try {
      final directory = Directory(resolvedPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final payload = exportToJson(data, passphrase: passphrase);
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(payload);
      return file.path;
    } on FileSystemException catch (error) {
      final details = error.osError?.message ?? error.message;
      throw StateError(
        'Unable to access the selected folder. Check file permissions or try using another folder. ($details)',
      );
    }
  }

  String exportToJson(AppData data, {required String passphrase}) {
    final normalizedPassphrase = _normalizePassphrase(passphrase);
    final salt = _secureRandomBytes(_saltSizeBytes);
    final derivedKey = _deriveKeyFromPassphrase(
      passphrase: normalizedPassphrase,
      salt: salt,
      iterations: _pbkdf2Iterations,
    );
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = _buildEncrypter(derivedKey);

    final encrypted = encrypter.encrypt(jsonEncode(data.toJson()), iv: iv);

    final payload = <String, dynamic>{
      'version': _currentBackupVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'cipher': _cipherName,
      'kdf': _kdfName,
      'iterations': _pbkdf2Iterations,
      'salt': base64Encode(salt),
      'iv': iv.base64,
      'payload': encrypted.base64,
    };

    return jsonEncode(payload);
  }

  Future<AppData> importFromFile(
    String filePath, {
    required String passphrase,
  }) async {
    final raw = await File(filePath).readAsString();
    return importFromJson(raw, passphrase: passphrase);
  }

  Future<AppData> importFromJson(
    String raw, {
    required String passphrase,
  }) async {
    final envelope = Map<String, dynamic>.from(
      jsonDecode(raw) as Map<dynamic, dynamic>,
    );
    final iv = encrypt.IV.fromBase64(envelope['iv'] as String);
    final encryptedPayload = envelope['payload'] as String;
    final keyBytes = await _resolveImportKey(
      envelope: envelope,
      passphrase: passphrase,
    );
    final encrypter = _buildEncrypter(keyBytes);

    final decrypted = encrypter.decrypt64(encryptedPayload, iv: iv);
    final decoded = jsonDecode(decrypted) as Map<String, dynamic>;
    return AppData.fromJson(decoded);
  }

  Future<Uint8List> _resolveImportKey({
    required Map<String, dynamic> envelope,
    required String passphrase,
  }) async {
    final version = (envelope['version'] as num?)?.toInt() ?? 1;
    final usesPassphraseKdf =
        version >= _currentBackupVersion ||
        envelope.containsKey('salt') ||
        envelope.containsKey('iterations') ||
        envelope.containsKey('kdf');

    if (usesPassphraseKdf) {
      final normalizedPassphrase = _normalizePassphrase(passphrase);
      final saltBase64 = envelope['salt'] as String?;
      if (saltBase64 == null || saltBase64.isEmpty) {
        throw const FormatException('Invalid backup payload: missing salt.');
      }

      final iterations =
          (envelope['iterations'] as num?)?.toInt() ?? _pbkdf2Iterations;
      if (iterations <= 0) {
        throw const FormatException('Invalid backup payload: bad iterations.');
      }

      return _deriveKeyFromPassphrase(
        passphrase: normalizedPassphrase,
        salt: base64Decode(saltBase64),
        iterations: iterations,
      );
    }

    final legacyKey = await _loadOrCreateLegacyKey();
    return base64Decode(legacyKey);
  }

  Future<String> _loadOrCreateLegacyKey() async {
    final existing = await _secureStorage.read(key: _keyStorageName);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = base64Encode(bytes);
    await _secureStorage.write(key: _keyStorageName, value: key);
    return key;
  }

  Future<void> storeVaultPassphrase(String passphrase) async {
    final normalizedPassphrase = _normalizePassphrase(passphrase);
    await _secureStorage.write(
      key: _vaultPassphraseStorageName,
      value: normalizedPassphrase,
    );
  }

  Future<void> clearVaultPassphrase() async {
    await _secureStorage.delete(key: _vaultPassphraseStorageName);
  }

  Future<bool> hasVaultPassphrase() async {
    final passphrase = await _secureStorage.read(
      key: _vaultPassphraseStorageName,
    );
    return passphrase != null && passphrase.trim().isNotEmpty;
  }

  Future<String?> writeVaultSnapshot({
    required AppData data,
    required String directoryPath,
  }) async {
    final passphrase = await _secureStorage.read(
      key: _vaultPassphraseStorageName,
    );
    if (passphrase == null || passphrase.trim().isEmpty) {
      return null;
    }

    return exportToDirectory(
      data,
      directoryPath: directoryPath,
      passphrase: passphrase,
      fileName: vaultSnapshotFileName,
    );
  }

  String _normalizePassphrase(String passphrase) {
    final normalized = passphrase.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Passphrase cannot be empty.');
    }
    return normalized;
  }

  Uint8List _deriveKeyFromPassphrase({
    required String passphrase,
    required List<int> salt,
    required int iterations,
  }) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(
        Pbkdf2Parameters(Uint8List.fromList(salt), iterations, _keySizeBytes),
      );

    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  encrypt.Encrypter _buildEncrypter(Uint8List keyBytes) {
    return encrypt.Encrypter(
      encrypt.AES(
        encrypt.Key(keyBytes),
        mode: encrypt.AESMode.cbc,
        padding: 'PKCS7',
      ),
    );
  }
}
