import 'dart:async';

import 'voice_model_manager.dart';
import 'voice_typing_service.dart';

class CompositeVoiceTypingService implements VoiceTypingService {
  CompositeVoiceTypingService({
    required VoiceTypingService sherpaService,
    required VoiceTypingService nativeService,
    required VoiceModelManager modelManager,
    required bool Function() isOfflineModelBetaEnabled,
    required String? Function() selectedModelId,
  }) : _sherpaService = sherpaService,
       _nativeService = nativeService,
       _modelManager = modelManager,
       _isOfflineModelBetaEnabled = isOfflineModelBetaEnabled,
       _selectedModelId = selectedModelId {
    _sherpaSubscription = _sherpaService.events.listen(
      (event) => _handleBackendEvent(source: _Backend.sherpa, event: event),
    );
    _nativeSubscription = _nativeService.events.listen(
      (event) => _handleBackendEvent(source: _Backend.native, event: event),
    );
  }

  final VoiceTypingService _sherpaService;
  final VoiceTypingService _nativeService;
  final VoiceModelManager _modelManager;
  final bool Function() _isOfflineModelBetaEnabled;
  final String? Function() _selectedModelId;

  final StreamController<VoiceTypingEvent> _events =
      StreamController<VoiceTypingEvent>.broadcast();

  late final StreamSubscription<VoiceTypingEvent> _sherpaSubscription;
  late final StreamSubscription<VoiceTypingEvent> _nativeSubscription;

  _Backend _activeBackend = _Backend.none;
  bool _recoveringFromSherpaRuntimeFailure = false;
  bool _lastPartialResults = true;

  @override
  Stream<VoiceTypingEvent> get events => _events.stream;

  void dispose() {
    _sherpaSubscription.cancel();
    _nativeSubscription.cancel();
    _events.close();
  }

  @override
  Future<VoiceTypingAvailability> initialize() async {
    final nativeAvailability = await _nativeService.initialize();

    if (!_isOfflineModelBetaEnabled()) {
      return nativeAvailability;
    }

    final installed = await _modelManager.getInstalledModel(
      modelId: _selectedModelId() ?? '',
    );
    if (installed == null) {
      return nativeAvailability;
    }

    final sherpaAvailability = await _sherpaService.initialize();
    if (sherpaAvailability.supported && sherpaAvailability.initialized) {
      return sherpaAvailability;
    }

    return nativeAvailability;
  }

  @override
  Future<VoiceTypingStartResult> startListening({
    required bool onDevicePreferred,
    required bool partialResults,
  }) async {
    _lastPartialResults = partialResults;

    if (!onDevicePreferred) {
      return _startNative(
        onDevicePreferred: false,
        partialResults: partialResults,
      );
    }

    if (!_isOfflineModelBetaEnabled()) {
      return _startNative(
        onDevicePreferred: true,
        partialResults: partialResults,
      );
    }

    final modelReady = await _modelManager.getInstalledModel(
      modelId: _selectedModelId() ?? '',
    );
    final modelState = _modelManager.currentState;

    if (modelReady == null) {
      _emitModelStateError(modelState);
      return _startNative(
        onDevicePreferred: true,
        partialResults: partialResults,
      );
    }

    final sherpaResult = await _sherpaService.startListening(
      onDevicePreferred: true,
      partialResults: partialResults,
    );
    if (sherpaResult.started) {
      _activeBackend = _Backend.sherpa;
      return sherpaResult;
    }

    if (_isModelReason(sherpaResult.errorReason)) {
      _events.add(
        VoiceTypingEventError(
          sherpaResult.message ??
              'Offline voice model failed to start. Using system speech.',
          reason: sherpaResult.errorReason,
        ),
      );
    }

    return _startNative(
      onDevicePreferred: true,
      partialResults: partialResults,
    );
  }

  @override
  Future<void> stopListening() async {
    switch (_activeBackend) {
      case _Backend.sherpa:
        await _sherpaService.stopListening();
        return;
      case _Backend.native:
        await _nativeService.stopListening();
        return;
      case _Backend.none:
        await _sherpaService.stopListening();
        await _nativeService.stopListening();
        return;
    }
  }

  @override
  Future<void> cancel() async {
    switch (_activeBackend) {
      case _Backend.sherpa:
        await _sherpaService.cancel();
        break;
      case _Backend.native:
        await _nativeService.cancel();
        break;
      case _Backend.none:
        await _sherpaService.cancel();
        await _nativeService.cancel();
        break;
    }
    _activeBackend = _Backend.none;
  }

  Future<VoiceTypingStartResult> _startNative({
    required bool onDevicePreferred,
    required bool partialResults,
  }) async {
    final result = await _nativeService.startListening(
      onDevicePreferred: onDevicePreferred,
      partialResults: partialResults,
    );
    _activeBackend = result.started ? _Backend.native : _Backend.none;
    return result;
  }

  void _handleBackendEvent({
    required _Backend source,
    required VoiceTypingEvent event,
  }) {
    if (_activeBackend != source) {
      return;
    }

    if (event is VoiceTypingEventError &&
        source == _Backend.sherpa &&
        event.reason == VoiceTypingErrorReason.modelRuntimeFailed &&
        !_recoveringFromSherpaRuntimeFailure) {
      _recoveringFromSherpaRuntimeFailure = true;
      _events.add(event);
      unawaited(_recoverToNativeAfterSherpaRuntimeFailure());
      return;
    }

    if (event is VoiceTypingEventStatus &&
        event.status == VoiceTypingStatus.stopped) {
      _activeBackend = _Backend.none;
    }

    _events.add(event);
  }

  Future<void> _recoverToNativeAfterSherpaRuntimeFailure() async {
    await _sherpaService.stopListening();

    final result = await _startNative(
      onDevicePreferred: true,
      partialResults: _lastPartialResults,
    );

    if (!result.started) {
      _events.add(
        VoiceTypingEventError(
          result.message ?? 'Failed to recover with system speech recognizer.',
          supportsFallbackHint: result.supportsFallbackHint,
          reason: result.errorReason,
        ),
      );
    }

    _recoveringFromSherpaRuntimeFailure = false;
  }

  void _emitModelStateError(VoiceModelState state) {
    final reason = switch (state.status) {
      VoiceModelInstallStatus.downloading =>
        VoiceTypingErrorReason.modelDownloading,
      VoiceModelInstallStatus.preparing =>
        VoiceTypingErrorReason.modelDownloading,
      VoiceModelInstallStatus.error =>
        VoiceTypingErrorReason.modelDownloadFailed,
      VoiceModelInstallStatus.ready =>
        VoiceTypingErrorReason.modelRuntimeFailed,
      VoiceModelInstallStatus.notInstalled =>
        VoiceTypingErrorReason.modelNotInstalled,
    };

    final message = switch (reason) {
      VoiceTypingErrorReason.modelDownloading =>
        'Offline voice model is still being prepared. Using system speech for now.',
      VoiceTypingErrorReason.modelDownloadFailed =>
        state.message ??
            'Offline voice model download failed. Using system speech for now.',
      VoiceTypingErrorReason.modelNotInstalled =>
        'Offline voice model is not installed. Download it from Settings.',
      VoiceTypingErrorReason.modelRuntimeFailed =>
        'Offline voice model failed. Using system speech for now.',
      _ => 'Offline voice model unavailable. Using system speech for now.',
    };

    _events.add(VoiceTypingEventError(message, reason: reason));
  }

  bool _isModelReason(VoiceTypingErrorReason reason) {
    return reason == VoiceTypingErrorReason.modelNotInstalled ||
        reason == VoiceTypingErrorReason.modelDownloading ||
        reason == VoiceTypingErrorReason.modelDownloadFailed ||
        reason == VoiceTypingErrorReason.modelRuntimeFailed;
  }
}

enum _Backend { none, sherpa, native }
