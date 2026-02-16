import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_data.dart';

class BackupService {
  BackupService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _keyStorageName = 'glitch_backup_key_v1';
  static const String _backupPrefix = 'glitch-backup';

  final FlutterSecureStorage _secureStorage;

  Future<String> exportToFile(AppData data) async {
    final key = await _loadOrCreateKey();
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(
        encrypt.Key.fromBase64(key),
        mode: encrypt.AESMode.cbc,
        padding: 'PKCS7',
      ),
    );

    final encrypted = encrypter.encrypt(jsonEncode(data.toJson()), iv: iv);

    final payload = <String, dynamic>{
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'iv': iv.base64,
      'payload': encrypted.base64,
    };

    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${directory.path}/$_backupPrefix-$timestamp.json');
    await file.writeAsString(jsonEncode(payload));
    return file.path;
  }

  Future<AppData> importFromFile(String filePath) async {
    final raw = await File(filePath).readAsString();
    final envelope = jsonDecode(raw) as Map<String, dynamic>;

    final key = await _loadOrCreateKey();
    final iv = encrypt.IV.fromBase64(envelope['iv'] as String);
    final encryptedPayload = envelope['payload'] as String;

    final encrypter = encrypt.Encrypter(
      encrypt.AES(
        encrypt.Key.fromBase64(key),
        mode: encrypt.AESMode.cbc,
        padding: 'PKCS7',
      ),
    );

    final decrypted = encrypter.decrypt64(encryptedPayload, iv: iv);
    final decoded = jsonDecode(decrypted) as Map<String, dynamic>;
    return AppData.fromJson(decoded);
  }

  Future<String> _loadOrCreateKey() async {
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
}
