import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'voice_model_capability_service.dart';
import 'voice_model_manager.dart';
import 'voice_typing_service.dart';

class SherpaVoiceTypingService implements VoiceTypingService {
  SherpaVoiceTypingService({
    required VoiceModelManager modelManager,
    required VoiceModelCapabilityService capabilityService,
    required String? Function() selectedModelId,
    AudioRecorder? recorder,
  }) : _modelManager = modelManager,
       _capabilityService = capabilityService,
       _selectedModelId = selectedModelId,
       _recorder = recorder ?? AudioRecorder();

  final VoiceModelManager _modelManager;
  final VoiceModelCapabilityService _capabilityService;
  final String? Function() _selectedModelId;
  final AudioRecorder _recorder;
  final StreamController<VoiceTypingEvent> _events =
      StreamController<VoiceTypingEvent>.broadcast();

  static bool _bindingsInitialized = false;
  static const int _maxDecodeIterationsPerChunk = 24;
  static const Duration _maxDecodeWallTimePerChunk = Duration(milliseconds: 45);
  static const int _maxDecodeOverrunStreak = 6;

  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _audioSubscription;
  InstalledVoiceModel? _activeModel;

  bool _listening = false;
  bool _partialResults = true;
  String _lastTranscript = '';
  int _decodeOverrunStreak = 0;

  @override
  Stream<VoiceTypingEvent> get events => _events.stream;

  @override
  Future<VoiceTypingAvailability> initialize() async {
    if (!Platform.isAndroid) {
      return const VoiceTypingAvailability(
        supported: false,
        initialized: false,
        message: 'Offline voice typing is currently available on Android only.',
      );
    }

    final installed = await _modelManager.getInstalledModel(
      modelId: _selectedModelId() ?? '',
    );
    if (installed == null) {
      return const VoiceTypingAvailability(
        supported: true,
        initialized: false,
        message: 'Offline voice model is not installed.',
      );
    }

    final capability = await _capabilityService.evaluateModel(installed.spec);
    if (!capability.supported) {
      return VoiceTypingAvailability(
        supported: true,
        initialized: false,
        message:
            capability.reason ??
            '${installed.spec.displayName} is not supported on this device right now.',
      );
    }

    try {
      _ensureBindings();
      _ensureRecognizer(installed);
      return const VoiceTypingAvailability(supported: true, initialized: true);
    } catch (error) {
      return VoiceTypingAvailability(
        supported: true,
        initialized: false,
        message: 'Offline voice model failed to initialize: $error',
      );
    }
  }

  @override
  Future<VoiceTypingStartResult> startListening({
    required bool onDevicePreferred,
    required bool partialResults,
  }) async {
    if (!onDevicePreferred) {
      return const VoiceTypingStartResult(
        started: false,
        usingOnDevice: false,
        failure: VoiceTypingStartFailure.unsupported,
        message: 'Offline model service supports on-device mode only.',
      );
    }

    if (!Platform.isAndroid) {
      return const VoiceTypingStartResult(
        started: false,
        usingOnDevice: false,
        failure: VoiceTypingStartFailure.unsupported,
        message: 'Offline voice typing is currently available on Android only.',
        errorReason: VoiceTypingErrorReason.unsupported,
      );
    }

    if (_listening) {
      return const VoiceTypingStartResult(
        started: false,
        usingOnDevice: true,
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
        errorReason: permission.permanentlyDenied
            ? VoiceTypingErrorReason.permissionPermanentlyDenied
            : VoiceTypingErrorReason.permissionDenied,
      );
    }

    final installed = await _modelManager.getInstalledModel(
      modelId: _selectedModelId() ?? '',
    );
    if (installed == null) {
      return _startFailureForModelState(_modelManager.currentState);
    }

    final capability = await _capabilityService.evaluateModel(installed.spec);
    if (!capability.supported) {
      return VoiceTypingStartResult(
        started: false,
        usingOnDevice: false,
        failure: VoiceTypingStartFailure.initializeFailed,
        message:
            capability.reason ??
            '${installed.spec.displayName} is not supported on this device right now.',
        errorReason: VoiceTypingErrorReason.modelRuntimeFailed,
      );
    }

    _partialResults = partialResults;
    _lastTranscript = '';
    _decodeOverrunStreak = 0;

    try {
      _ensureBindings();
      _ensureRecognizer(installed);

      final stream = _recognizer!.createStream();
      _stream = stream;

      final audioStream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: installed.spec.sampleRate,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );

      _audioSubscription = audioStream.listen(
        _onAudioChunk,
        onError: (Object error, StackTrace stackTrace) {
          _emitRuntimeErrorAndReset(
            'Offline voice runtime failed while reading microphone audio: $error',
          );
        },
        onDone: () {
          if (_listening) {
            unawaited(_stopInternal(emitFinal: true));
          }
        },
      );

      _listening = true;
      _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.listening));
      return const VoiceTypingStartResult(
        started: true,
        usingOnDevice: true,
        message: 'Listening with offline voice model.',
      );
    } catch (error) {
      await _resetSessionResources();
      return VoiceTypingStartResult(
        started: false,
        usingOnDevice: true,
        failure: VoiceTypingStartFailure.listenFailed,
        message: 'Unable to start offline voice typing: $error',
        errorReason: VoiceTypingErrorReason.modelRuntimeFailed,
      );
    }
  }

  @override
  Future<void> stopListening() async {
    await _stopInternal(emitFinal: true);
  }

  @override
  Future<void> cancel() async {
    await _stopInternal(emitFinal: false);
  }

  Future<void> _stopInternal({required bool emitFinal}) async {
    if (!_listening && _stream == null) {
      return;
    }

    _listening = false;

    await _audioSubscription?.cancel();
    _audioSubscription = null;

    try {
      await _recorder.stop();
    } catch (_) {
      try {
        await _recorder.cancel();
      } catch (_) {
        // Ignore cleanup errors.
      }
    }

    if (emitFinal) {
      _emitFinalResult();
    }

    await _resetSessionResources();
    _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.stopped));
  }

  void _onAudioChunk(Uint8List bytes) {
    final recognizer = _recognizer;
    final stream = _stream;
    final activeModel = _activeModel;
    if (!_listening ||
        recognizer == null ||
        stream == null ||
        activeModel == null) {
      return;
    }

    try {
      final int16 = _recorder.convertBytesToInt16(bytes);
      final floatSamples = Float32List(int16.length);
      for (var i = 0; i < int16.length; i += 1) {
        floatSamples[i] = int16[i] / 32768.0;
      }

      stream.acceptWaveform(
        samples: floatSamples,
        sampleRate: activeModel.spec.sampleRate,
      );

      final decodedWithinBudget = _decodeWithBudget(recognizer, stream);
      if (!decodedWithinBudget) {
        _decodeOverrunStreak += 1;
        if (_decodeOverrunStreak >= _maxDecodeOverrunStreak) {
          _emitRuntimeErrorAndReset(
            'Offline voice model is overloading this device. Switched to system speech.',
          );
        }
        return;
      }
      _decodeOverrunStreak = 0;

      if (!_partialResults) {
        return;
      }

      final partial = recognizer.getResult(stream).text.trim();
      if (partial.isEmpty || partial == _lastTranscript) {
        return;
      }

      _lastTranscript = partial;
      _events.add(VoiceTypingEventPartial(partial));
    } catch (error) {
      _emitRuntimeErrorAndReset(
        'Offline voice runtime failed while decoding audio: $error',
      );
    }
  }

  void _emitFinalResult() {
    final recognizer = _recognizer;
    final stream = _stream;
    if (recognizer == null || stream == null) {
      return;
    }

    try {
      stream.inputFinished();
      var safetyCounter = 0;
      while (recognizer.isReady(stream) && safetyCounter < 64) {
        recognizer.decode(stream);
        safetyCounter += 1;
      }
      final finalText = recognizer.getResult(stream).text.trim();
      if (finalText.isNotEmpty) {
        _lastTranscript = finalText;
        _events.add(VoiceTypingEventFinal(finalText));
      }
    } catch (_) {
      // Swallow finalization decode errors and finish session cleanup.
    }
  }

  Future<void> _resetSessionResources() async {
    _stream?.free();
    _stream = null;
    _audioSubscription = null;
    _lastTranscript = '';
    _decodeOverrunStreak = 0;
  }

  void _emitRuntimeErrorAndReset(String message) {
    _events.add(
      VoiceTypingEventError(
        message,
        reason: VoiceTypingErrorReason.modelRuntimeFailed,
      ),
    );
    unawaited(_stopInternal(emitFinal: false));
  }

  VoiceTypingStartResult _startFailureForModelState(VoiceModelState state) {
    if (state.status == VoiceModelInstallStatus.downloading ||
        state.status == VoiceModelInstallStatus.preparing) {
      return const VoiceTypingStartResult(
        started: false,
        usingOnDevice: false,
        failure: VoiceTypingStartFailure.initializeFailed,
        message: 'Offline voice model is still being prepared.',
        errorReason: VoiceTypingErrorReason.modelDownloading,
      );
    }

    if (state.status == VoiceModelInstallStatus.error) {
      return VoiceTypingStartResult(
        started: false,
        usingOnDevice: false,
        failure: VoiceTypingStartFailure.initializeFailed,
        message:
            state.message ?? 'Offline voice model download failed. Try again.',
        errorReason: VoiceTypingErrorReason.modelDownloadFailed,
      );
    }

    return const VoiceTypingStartResult(
      started: false,
      usingOnDevice: false,
      failure: VoiceTypingStartFailure.initializeFailed,
      message:
          'Offline voice model is not installed. Download it from Settings.',
      errorReason: VoiceTypingErrorReason.modelNotInstalled,
    );
  }

  bool _decodeWithBudget(
    sherpa_onnx.OnlineRecognizer recognizer,
    sherpa_onnx.OnlineStream stream,
  ) {
    final watch = Stopwatch()..start();
    var iterations = 0;

    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
      iterations += 1;

      final timedOut = watch.elapsed >= _maxDecodeWallTimePerChunk;
      final tooManyIterations = iterations >= _maxDecodeIterationsPerChunk;
      if (timedOut || tooManyIterations) {
        if (recognizer.isReady(stream)) {
          return false;
        }
        break;
      }
    }

    return true;
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

  void _ensureBindings() {
    if (_bindingsInitialized) {
      return;
    }
    sherpa_onnx.initBindings();
    _bindingsInitialized = true;
  }

  void _ensureRecognizer(InstalledVoiceModel installed) {
    if (_activeModel != null &&
        _activeModel!.spec.id == installed.spec.id &&
        _activeModel!.spec.version == installed.spec.version &&
        _recognizer != null) {
      return;
    }

    _recognizer?.free();

    final config = sherpa_onnx.OnlineRecognizerConfig(
      model: sherpa_onnx.OnlineModelConfig(
        transducer: sherpa_onnx.OnlineTransducerModelConfig(
          encoder: installed.encoderPath,
          decoder: installed.decoderPath,
          joiner: installed.joinerPath,
        ),
        tokens: installed.tokensPath,
        numThreads: installed.spec.numThreads,
        provider: 'cpu',
        debug: false,
      ),
      decodingMethod: 'greedy_search',
      maxActivePaths: 4,
      enableEndpoint: false,
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 1.2,
      rule3MinUtteranceLength: 60,
    );

    _recognizer = sherpa_onnx.OnlineRecognizer(config);
    _activeModel = installed;
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
