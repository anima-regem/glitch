import 'dart:async';
import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum VoiceTypingStatus { listening, stopped, unavailable }

enum VoiceTypingStartFailure {
  unsupported,
  permissionDenied,
  permissionPermanentlyDenied,
  initializeFailed,
  alreadyListening,
  listenFailed,
}

class VoiceTypingAvailability {
  const VoiceTypingAvailability({
    required this.supported,
    required this.initialized,
    this.message,
  });

  final bool supported;
  final bool initialized;
  final String? message;
}

class VoiceTypingStartResult {
  const VoiceTypingStartResult({
    required this.started,
    required this.usingOnDevice,
    this.failure,
    this.message,
    this.supportsFallbackHint = false,
  });

  final bool started;
  final bool usingOnDevice;
  final VoiceTypingStartFailure? failure;
  final String? message;
  final bool supportsFallbackHint;
}

abstract class VoiceTypingEvent {
  const VoiceTypingEvent();
}

class VoiceTypingEventPartial extends VoiceTypingEvent {
  const VoiceTypingEventPartial(this.text);

  final String text;
}

class VoiceTypingEventFinal extends VoiceTypingEvent {
  const VoiceTypingEventFinal(this.text);

  final String text;
}

class VoiceTypingEventError extends VoiceTypingEvent {
  const VoiceTypingEventError(
    this.message, {
    this.supportsFallbackHint = false,
  });

  final String message;
  final bool supportsFallbackHint;
}

class VoiceTypingEventStatus extends VoiceTypingEvent {
  const VoiceTypingEventStatus(this.status);

  final VoiceTypingStatus status;
}

abstract class VoiceTypingService {
  Future<VoiceTypingAvailability> initialize();

  Future<VoiceTypingStartResult> startListening({
    required bool onDevicePreferred,
    required bool partialResults,
  });

  Future<void> stopListening();

  Future<void> cancel();

  Stream<VoiceTypingEvent> get events;
}

class NativeVoiceTypingService implements VoiceTypingService {
  NativeVoiceTypingService({SpeechToText? speechToText})
    : _speech = speechToText ?? SpeechToText();

  static const Duration _listenFor = Duration(minutes: 2);

  final SpeechToText _speech;
  final StreamController<VoiceTypingEvent> _events =
      StreamController<VoiceTypingEvent>.broadcast();

  bool _initialized = false;
  bool _lastListenRequestedOnDevice = true;

  @override
  Stream<VoiceTypingEvent> get events => _events.stream;

  @override
  Future<VoiceTypingAvailability> initialize() async {
    if (!Platform.isAndroid) {
      _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.unavailable));
      return const VoiceTypingAvailability(
        supported: false,
        initialized: false,
        message: 'Voice typing is currently available on Android only.',
      );
    }

    if (_initialized) {
      return const VoiceTypingAvailability(supported: true, initialized: true);
    }

    try {
      _initialized = await _speech.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
      );
    } catch (error) {
      _initialized = false;
      _events.add(
        VoiceTypingEventError(
          'Speech engine initialization failed: $error',
          supportsFallbackHint: false,
        ),
      );
      _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.unavailable));
    }

    if (!_initialized) {
      _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.unavailable));
      return const VoiceTypingAvailability(
        supported: false,
        initialized: false,
        message: 'Speech recognition is unavailable on this device.',
      );
    }

    return const VoiceTypingAvailability(supported: true, initialized: true);
  }

  @override
  Future<VoiceTypingStartResult> startListening({
    required bool onDevicePreferred,
    required bool partialResults,
  }) async {
    if (!Platform.isAndroid) {
      return const VoiceTypingStartResult(
        started: false,
        usingOnDevice: false,
        failure: VoiceTypingStartFailure.unsupported,
        message: 'Voice typing is currently available on Android only.',
      );
    }

    if (_speech.isListening) {
      return const VoiceTypingStartResult(
        started: false,
        usingOnDevice: false,
        failure: VoiceTypingStartFailure.alreadyListening,
        message: 'Voice typing is already active.',
      );
    }

    final permission = await _ensureMicrophonePermission();
    if (!permission.granted) {
      return VoiceTypingStartResult(
        started: false,
        usingOnDevice: false,
        failure: permission.permanentlyDenied
            ? VoiceTypingStartFailure.permissionPermanentlyDenied
            : VoiceTypingStartFailure.permissionDenied,
        message: permission.message,
      );
    }

    final availability = await initialize();
    if (!availability.supported || !availability.initialized) {
      return VoiceTypingStartResult(
        started: false,
        usingOnDevice: false,
        failure: VoiceTypingStartFailure.initializeFailed,
        message:
            availability.message ?? 'Speech recognition is not available yet.',
      );
    }

    _lastListenRequestedOnDevice = onDevicePreferred;
    final options = SpeechListenOptions(
      partialResults: partialResults,
      onDevice: onDevicePreferred,
      listenMode: ListenMode.dictation,
      cancelOnError: true,
    );

    try {
      final started = await _speech.listen(
        onResult: _handleResult,
        listenFor: _listenFor,
        listenOptions: options,
      );
      if (!started) {
        return VoiceTypingStartResult(
          started: false,
          usingOnDevice: false,
          failure: VoiceTypingStartFailure.listenFailed,
          message: onDevicePreferred
              ? 'On-device speech mode is unavailable for this language/device.'
              : 'Unable to start speech recognition right now.',
          supportsFallbackHint: onDevicePreferred,
        );
      }
    } catch (error) {
      return VoiceTypingStartResult(
        started: false,
        usingOnDevice: false,
        failure: VoiceTypingStartFailure.listenFailed,
        message: 'Unable to start voice typing: $error',
        supportsFallbackHint: onDevicePreferred,
      );
    }

    return VoiceTypingStartResult(
      started: true,
      usingOnDevice: onDevicePreferred,
      message: onDevicePreferred
          ? 'Listening with on-device recognition.'
          : 'Listening with fallback speech mode.',
    );
  }

  @override
  Future<void> stopListening() async {
    if (!_initialized) {
      return;
    }
    await _speech.stop();
  }

  @override
  Future<void> cancel() async {
    if (!_initialized) {
      return;
    }
    await _speech.cancel();
  }

  Future<_PermissionOutcome> _ensureMicrophonePermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }

    if (status.isGranted) {
      return const _PermissionOutcome(granted: true, permanentlyDenied: false);
    }

    if (status.isPermanentlyDenied || status.isRestricted) {
      return const _PermissionOutcome(
        granted: false,
        permanentlyDenied: true,
        message:
            'Microphone permission is required for voice typing. Open system settings to allow it.',
      );
    }

    return const _PermissionOutcome(
      granted: false,
      permanentlyDenied: false,
      message: 'Microphone permission is required for voice typing.',
    );
  }

  void _handleResult(SpeechRecognitionResult recognitionResult) {
    final text = recognitionResult.recognizedWords;
    if (recognitionResult.finalResult) {
      _events.add(VoiceTypingEventFinal(text));
      return;
    }
    _events.add(VoiceTypingEventPartial(text));
  }

  void _handleStatus(String status) {
    if (status == SpeechToText.listeningStatus) {
      _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.listening));
      return;
    }

    if (status == SpeechToText.notListeningStatus ||
        status == SpeechToText.doneStatus) {
      _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.stopped));
    }
  }

  void _handleError(SpeechRecognitionError error) {
    _events.add(
      VoiceTypingEventError(
        _humanizeError(error.errorMsg),
        supportsFallbackHint: _isFallbackLikely(error.errorMsg),
      ),
    );
    if (error.permanent) {
      _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.stopped));
    }
  }

  bool _isFallbackLikely(String message) {
    if (!_lastListenRequestedOnDevice) {
      return false;
    }
    final normalized = message.toLowerCase();
    return normalized.contains('language') ||
        normalized.contains('unavailable') ||
        normalized.contains('not supported') ||
        normalized.contains('network') ||
        normalized.contains('server') ||
        normalized.contains('no_match');
  }

  String _humanizeError(String code) {
    final normalized = code.trim();
    if (normalized.isEmpty) {
      return 'Voice typing failed. Please try again.';
    }

    switch (normalized) {
      case 'error_permission':
        return 'Microphone permission is required for voice typing.';
      case 'error_network':
      case 'error_network_timeout':
        return 'Network error while recognizing speech.';
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        return 'Speech language is unavailable on this device.';
      case 'error_no_match':
        return 'No speech was detected.';
      default:
        return 'Voice typing failed: $normalized';
    }
  }
}

class _PermissionOutcome {
  const _PermissionOutcome({
    required this.granted,
    required this.permanentlyDenied,
    this.message,
  });

  final bool granted;
  final bool permanentlyDenied;
  final String? message;
}
