import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

final taskAudioServiceProvider = Provider<TaskAudioService>((ref) {
  final service = TaskAudioService();
  ref.onDispose(service.dispose);
  return service;
});

class TaskAudioService {
  TaskAudioService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _configured = false;

  Future<void> speakTaskText({required String title, String? description}) async {
    await _configure();
    final normalizedTitle = title.trim();
    final normalizedDescription = description?.trim() ?? '';
    if (normalizedTitle.isEmpty && normalizedDescription.isEmpty) {
      return;
    }

    final content = normalizedDescription.isEmpty
        ? normalizedTitle
        : '$normalizedTitle. $normalizedDescription';

    await _tts.stop();
    await _tts.speak(content);
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  Future<void> _configure() async {
    if (_configured) {
      return;
    }

    if (Platform.isAndroid) {
      await _tts.setEngine('com.google.android.tts');
    }

    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
    _configured = true;
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}
