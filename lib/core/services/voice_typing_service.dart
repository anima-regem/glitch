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

enum VoiceTypingErrorReason {
  unknown,
  unsupported,
  recognizerUnavailable,
  permissionDenied,
  permissionPermanentlyDenied,
  network,
  languageUnavailable,
  noMatch,
  modelNotInstalled,
  modelDownloading,
  modelDownloadFailed,
  modelRuntimeFailed,
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
    this.errorReason = VoiceTypingErrorReason.unknown,
  });

  final bool started;
  final bool usingOnDevice;
  final VoiceTypingStartFailure? failure;
  final String? message;
  final bool supportsFallbackHint;
  final VoiceTypingErrorReason errorReason;
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
    this.reason = VoiceTypingErrorReason.unknown,
  });

  final String message;
  final bool supportsFallbackHint;
  final VoiceTypingErrorReason reason;
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
    } catch (_) {
      _initialized = false;
      _events.add(
        const VoiceTypingEventError(
          'Speech engine initialization failed. Speech recognition service may be unavailable on this device.',
          supportsFallbackHint: false,
          reason: VoiceTypingErrorReason.recognizerUnavailable,
        ),
      );
      _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.unavailable));
    }

    if (!_initialized) {
      _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.unavailable));
      return const VoiceTypingAvailability(
        supported: false,
        initialized: false,
        message: 'Speech recognition service is unavailable on this device.',
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
        errorReason: VoiceTypingErrorReason.unsupported,
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
      final reason = permission.permanentlyDenied
          ? VoiceTypingErrorReason.permissionPermanentlyDenied
          : VoiceTypingErrorReason.permissionDenied;
      return VoiceTypingStartResult(
        started: false,
        usingOnDevice: false,
        failure: permission.permanentlyDenied
            ? VoiceTypingStartFailure.permissionPermanentlyDenied
            : VoiceTypingStartFailure.permissionDenied,
        message: permission.message,
        errorReason: reason,
      );
    }

    final availability = await initialize();
    if (!availability.supported || !availability.initialized) {
      final reason = _reasonFromAvailabilityMessage(availability.message);
      return VoiceTypingStartResult(
        started: false,
        usingOnDevice: false,
        failure: VoiceTypingStartFailure.initializeFailed,
        message:
            availability.message ?? 'Speech recognition is not available yet.',
        errorReason: reason,
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
        final reason = onDevicePreferred
            ? VoiceTypingErrorReason.languageUnavailable
            : VoiceTypingErrorReason.recognizerUnavailable;
        return VoiceTypingStartResult(
          started: false,
          usingOnDevice: false,
          failure: VoiceTypingStartFailure.listenFailed,
          message: _messageForListenFailure(
            onDevicePreferred: onDevicePreferred,
            reason: reason,
          ),
          supportsFallbackHint:
              onDevicePreferred && _supportsFallbackForReason(reason),
          errorReason: reason,
        );
      }
    } catch (error) {
      final reason = _errorReasonFromException(error);
      return VoiceTypingStartResult(
        started: false,
        usingOnDevice: false,
        failure: VoiceTypingStartFailure.listenFailed,
        message: _messageForListenFailure(
          onDevicePreferred: onDevicePreferred,
          reason: reason,
          error: error,
        ),
        supportsFallbackHint:
            onDevicePreferred && _supportsFallbackForReason(reason),
        errorReason: reason,
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
    final reason = _errorReasonFromCode(error.errorMsg);
    _events.add(
      VoiceTypingEventError(
        _humanizeError(error.errorMsg, reason: reason),
        supportsFallbackHint: _supportsFallbackForReason(reason),
        reason: reason,
      ),
    );
    if (error.permanent) {
      _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.stopped));
    }
  }

  bool _supportsFallbackForReason(VoiceTypingErrorReason reason) {
    if (!_lastListenRequestedOnDevice) {
      return false;
    }
    return reason == VoiceTypingErrorReason.languageUnavailable ||
        reason == VoiceTypingErrorReason.network ||
        reason == VoiceTypingErrorReason.noMatch ||
        reason == VoiceTypingErrorReason.recognizerUnavailable;
  }

  VoiceTypingErrorReason _reasonFromAvailabilityMessage(String? message) {
    final normalized = (message ?? '').trim().toLowerCase();
    if (normalized.contains('android only')) {
      return VoiceTypingErrorReason.unsupported;
    }
    if (normalized.contains('unavailable')) {
      return VoiceTypingErrorReason.recognizerUnavailable;
    }
    return VoiceTypingErrorReason.unknown;
  }

  VoiceTypingErrorReason _errorReasonFromCode(String code) {
    final normalized = code.trim().toLowerCase();
    switch (normalized) {
      case 'error_permission':
        return VoiceTypingErrorReason.permissionDenied;
      case 'error_network':
      case 'error_network_timeout':
      case 'network':
        return VoiceTypingErrorReason.network;
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        return VoiceTypingErrorReason.languageUnavailable;
      case 'error_no_match':
      case 'error_speech_timeout':
        return VoiceTypingErrorReason.noMatch;
      default:
        if (normalized.contains('permission')) {
          return VoiceTypingErrorReason.permissionDenied;
        }
        if (normalized.contains('network') ||
            normalized.contains('server') ||
            normalized.contains('timeout')) {
          return VoiceTypingErrorReason.network;
        }
        if (normalized.contains('language') ||
            normalized.contains('not supported')) {
          return VoiceTypingErrorReason.languageUnavailable;
        }
        if (normalized.contains('recognition service') ||
            normalized.contains('recognizer') ||
            normalized.contains('unavailable') ||
            normalized.contains('not available')) {
          return VoiceTypingErrorReason.recognizerUnavailable;
        }
        if (normalized.contains('no_match') ||
            normalized.contains('no match')) {
          return VoiceTypingErrorReason.noMatch;
        }
        return VoiceTypingErrorReason.unknown;
    }
  }

  VoiceTypingErrorReason _errorReasonFromException(Object error) {
    final normalized = error.toString().trim().toLowerCase();
    // Some speech_to_text platform implementations return a null bool when
    // on-device mode is unsupported for a recognizer/language.
    if (normalized.contains("type 'null' is not a subtype of type 'bool'") ||
        normalized.contains('null is not a subtype of type bool')) {
      return VoiceTypingErrorReason.recognizerUnavailable;
    }
    if (normalized.contains('permanent') && normalized.contains('permission')) {
      return VoiceTypingErrorReason.permissionPermanentlyDenied;
    }
    if (normalized.contains('permission')) {
      return VoiceTypingErrorReason.permissionDenied;
    }
    if (normalized.contains('network') ||
        normalized.contains('server') ||
        normalized.contains('timeout')) {
      return VoiceTypingErrorReason.network;
    }
    if (normalized.contains('language') ||
        normalized.contains('not supported')) {
      return VoiceTypingErrorReason.languageUnavailable;
    }
    if (normalized.contains('no_match') || normalized.contains('no match')) {
      return VoiceTypingErrorReason.noMatch;
    }
    if (normalized.contains('recognition service') ||
        normalized.contains('recognizer') ||
        normalized.contains('unavailable') ||
        normalized.contains('not available')) {
      return VoiceTypingErrorReason.recognizerUnavailable;
    }
    return VoiceTypingErrorReason.unknown;
  }

  String _messageForListenFailure({
    required bool onDevicePreferred,
    required VoiceTypingErrorReason reason,
    Object? error,
  }) {
    if (onDevicePreferred) {
      switch (reason) {
        case VoiceTypingErrorReason.languageUnavailable:
          return 'On-device speech mode is unavailable for this language or device.';
        case VoiceTypingErrorReason.network:
          return 'On-device speech failed due to a network issue.';
        case VoiceTypingErrorReason.recognizerUnavailable:
          return 'Speech recognition service is unavailable on this device.';
        case VoiceTypingErrorReason.modelNotInstalled:
          return 'Offline voice model is not installed. Download it from Settings.';
        case VoiceTypingErrorReason.modelDownloading:
          return 'Offline voice model is still downloading.';
        case VoiceTypingErrorReason.modelDownloadFailed:
          return 'Offline voice model download failed. Please try again.';
        case VoiceTypingErrorReason.modelRuntimeFailed:
          return 'Offline voice model failed to start.';
        default:
          return error == null
              ? 'Unable to start on-device voice typing right now.'
              : 'Unable to start on-device voice typing: $error';
      }
    }

    switch (reason) {
      case VoiceTypingErrorReason.network:
        return 'Fallback speech mode could not start due to a network issue.';
      case VoiceTypingErrorReason.permissionDenied:
        return 'Microphone permission is required for voice typing.';
      case VoiceTypingErrorReason.permissionPermanentlyDenied:
        return 'Microphone permission is required for voice typing. Open system settings to allow it.';
      case VoiceTypingErrorReason.recognizerUnavailable:
        return 'Fallback speech recognition is unavailable on this device.';
      case VoiceTypingErrorReason.modelNotInstalled:
      case VoiceTypingErrorReason.modelDownloading:
      case VoiceTypingErrorReason.modelDownloadFailed:
      case VoiceTypingErrorReason.modelRuntimeFailed:
        return 'Offline voice model is unavailable right now.';
      default:
        return error == null
            ? 'Unable to start fallback speech recognition right now.'
            : 'Unable to start fallback speech recognition: $error';
    }
  }

  String _humanizeError(String code, {required VoiceTypingErrorReason reason}) {
    switch (reason) {
      case VoiceTypingErrorReason.permissionDenied:
        return 'Microphone permission is required for voice typing.';
      case VoiceTypingErrorReason.permissionPermanentlyDenied:
        return 'Microphone permission is required for voice typing. Open system settings to allow it.';
      case VoiceTypingErrorReason.network:
        return 'Network error while recognizing speech.';
      case VoiceTypingErrorReason.languageUnavailable:
        return 'Speech language is unavailable on this device.';
      case VoiceTypingErrorReason.noMatch:
        return 'No speech was detected.';
      case VoiceTypingErrorReason.recognizerUnavailable:
        return 'Speech recognition service is unavailable on this device.';
      case VoiceTypingErrorReason.modelNotInstalled:
        return 'Offline voice model is not installed. Download it from Settings.';
      case VoiceTypingErrorReason.modelDownloading:
        return 'Offline voice model is still downloading.';
      case VoiceTypingErrorReason.modelDownloadFailed:
        return 'Offline voice model download failed. Please try again.';
      case VoiceTypingErrorReason.modelRuntimeFailed:
        return 'Offline voice model runtime failed.';
      case VoiceTypingErrorReason.unsupported:
      case VoiceTypingErrorReason.unknown:
        final normalized = code.trim();
        if (normalized.isEmpty) {
          return 'Voice typing failed. Please try again.';
        }
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
