import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/app_data.dart';

abstract class LocalStore {
  Future<AppData> load();
  Future<void> save(AppData data);
  Future<void> overwrite(AppData data);
}

class HiveLocalStore implements LocalStore {
  static const String _boxName = 'glitch_local_box';
  static const String _snapshotKey = 'app_snapshot';

  Box<String>? _box;

  Future<Box<String>> _ensureBox() async {
    if (_box != null && _box!.isOpen) {
      return _box!;
    }

    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
    return _box!;
  }

  @override
  Future<AppData> load() async {
    final box = await _ensureBox();
    final snapshot = box.get(_snapshotKey);

    if (snapshot == null || snapshot.isEmpty) {
      return AppData.empty();
    }

    try {
      final decoded = jsonDecode(snapshot) as Map<String, dynamic>;
      return AppData.fromJson(decoded);
    } catch (_) {
      return AppData.empty();
    }
  }

  @override
  Future<void> save(AppData data) async {
    final box = await _ensureBox();
    await box.put(_snapshotKey, jsonEncode(data.toJson()));
  }

  @override
  Future<void> overwrite(AppData data) => save(data);
}
