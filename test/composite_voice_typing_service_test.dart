import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/core/services/composite_voice_typing_service.dart';
import 'package:glitch/core/services/voice_model_catalog.dart';
import 'package:glitch/core/services/voice_model_manager.dart';
import 'package:glitch/core/services/voice_typing_service.dart';

class _FakeVoiceService implements VoiceTypingService {
  VoiceTypingStartResult onDeviceResult = const VoiceTypingStartResult(
    started: true,
    usingOnDevice: true,
  );
  VoiceTypingStartResult fallbackResult = const VoiceTypingStartResult(
    started: true,
    usingOnDevice: false,
  );

  int onDeviceCalls = 0;
  int fallbackCalls = 0;

  final StreamController<VoiceTypingEvent> _events =
      StreamController<VoiceTypingEvent>.broadcast();

  @override
  Stream<VoiceTypingEvent> get events => _events.stream;

  @override
  Future<void> cancel() async {}

  @override
  Future<VoiceTypingAvailability> initialize() async {
    return const VoiceTypingAvailability(supported: true, initialized: true);
  }

  @override
  Future<VoiceTypingStartResult> startListening({
    required bool onDevicePreferred,
    required bool partialResults,
  }) async {
    if (onDevicePreferred) {
      onDeviceCalls += 1;
      return onDeviceResult;
    }
    fallbackCalls += 1;
    return fallbackResult;
  }

  @override
  Future<void> stopListening() async {}
}

class _FakeVoiceModelManager implements VoiceModelManager {
  _FakeVoiceModelManager({this.installed, required this.availableModels});

  InstalledVoiceModel? installed;
  final List<VoiceModelSpec> availableModels;

  @override
  Future<void> cancelDownload() async {}

  @override
  VoiceModelState get currentState {
    if (installed != null) {
      return VoiceModelState.ready(model: installed!);
    }
    return VoiceModelState.notInstalled(
      message: 'Offline voice model is not installed.',
    );
  }

  @override
  Future<InstalledVoiceModel?> getInstalledModel({
    required String modelId,
  }) async {
    if (installed == null) {
      return null;
    }
    if (modelId.trim().isEmpty || installed!.spec.id == modelId) {
      return installed;
    }
    return null;
  }

  @override
  Future<List<VoiceModelSpec>> listAvailableModels() async => availableModels;

  @override
  Future<VoiceModelState> prepareModel({
    required String modelId,
    bool allowCellular = false,
  }) async {
    return currentState;
  }

  @override
  Future<void> removeModel() async {
    installed = null;
  }

  @override
  Stream<VoiceModelState> get states =>
      const Stream<VoiceModelState>.empty(broadcast: true);
}

InstalledVoiceModel _installedModel() {
  const spec = VoiceModelSpec(
    id: 'standard',
    displayName: 'Standard',
    bundleId: 'standard_bundle',
    profile: 'int8',
    qualityHint: 'Balanced',
    sizeLabel: '~122 MB',
    language: 'en',
    version: '1.0.0',
    downloadUrl: 'https://example.com',
    sha256: 'abc',
    expectedBytes: 12,
    sampleRate: 16000,
    numThreads: 1,
    encoderFile: 'encoder.onnx',
    decoderFile: 'decoder.onnx',
    joinerFile: 'joiner.onnx',
    tokensFile: 'tokens.txt',
  );

  return InstalledVoiceModel(
    spec: spec,
    installDirectoryPath: '/tmp/model',
    modelRootPath: '/tmp/model/root',
    installedAt: DateTime(2026, 2, 26),
  );
}

void main() {
  test(
    'uses sherpa first when beta is enabled and selected model is installed',
    () async {
      final sherpa = _FakeVoiceService();
      final native = _FakeVoiceService();
      final manager = _FakeVoiceModelManager(
        installed: _installedModel(),
        availableModels: <VoiceModelSpec>[_installedModel().spec],
      );

      final composite = CompositeVoiceTypingService(
        sherpaService: sherpa,
        nativeService: native,
        modelManager: manager,
        isOfflineModelBetaEnabled: () => true,
        selectedModelId: () => 'standard',
      );
      addTearDown(composite.dispose);

      final result = await composite.startListening(
        onDevicePreferred: true,
        partialResults: true,
      );

      expect(result.started, isTrue);
      expect(sherpa.onDeviceCalls, 1);
      expect(native.onDeviceCalls, 0);
    },
  );

  test('falls back to native when selected model is missing', () async {
    final sherpa = _FakeVoiceService();
    final native = _FakeVoiceService();
    final manager = _FakeVoiceModelManager(
      installed: null,
      availableModels: const <VoiceModelSpec>[],
    );

    final composite = CompositeVoiceTypingService(
      sherpaService: sherpa,
      nativeService: native,
      modelManager: manager,
      isOfflineModelBetaEnabled: () => true,
      selectedModelId: () => 'ultra_full',
    );
    addTearDown(composite.dispose);

    final events = <VoiceTypingEvent>[];
    final sub = composite.events.listen(events.add);
    addTearDown(sub.cancel);

    final result = await composite.startListening(
      onDevicePreferred: true,
      partialResults: true,
    );

    expect(result.started, isTrue);
    expect(sherpa.onDeviceCalls, 0);
    expect(native.onDeviceCalls, 1);
    expect(
      events.whereType<VoiceTypingEventError>().first.reason,
      VoiceTypingErrorReason.modelNotInstalled,
    );
  });

  test('falls back to native when sherpa start fails', () async {
    final sherpa = _FakeVoiceService()
      ..onDeviceResult = const VoiceTypingStartResult(
        started: false,
        usingOnDevice: true,
        failure: VoiceTypingStartFailure.listenFailed,
        errorReason: VoiceTypingErrorReason.modelRuntimeFailed,
        message: 'Sherpa failed',
      );
    final native = _FakeVoiceService();
    final manager = _FakeVoiceModelManager(
      installed: _installedModel(),
      availableModels: <VoiceModelSpec>[_installedModel().spec],
    );

    final composite = CompositeVoiceTypingService(
      sherpaService: sherpa,
      nativeService: native,
      modelManager: manager,
      isOfflineModelBetaEnabled: () => true,
      selectedModelId: () => 'standard',
    );
    addTearDown(composite.dispose);

    final result = await composite.startListening(
      onDevicePreferred: true,
      partialResults: true,
    );

    expect(result.started, isTrue);
    expect(sherpa.onDeviceCalls, 1);
    expect(native.onDeviceCalls, 1);
  });
}
