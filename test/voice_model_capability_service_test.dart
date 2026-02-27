import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/core/services/voice_model_capability_service.dart';
import 'package:glitch/core/services/voice_model_catalog.dart';

VoiceModelSpec _model(String id) {
  return VoiceModelSpec(
    id: id,
    displayName: id,
    bundleId: id,
    profile: id == 'ultra_full' ? 'full' : 'int8',
    qualityHint: '',
    sizeLabel: '',
    language: 'en',
    version: '1.0.0',
    downloadUrl: 'https://example.com/$id.tar.bz2',
    sha256: 'abc',
    expectedBytes: 1,
    sampleRate: 16000,
    numThreads: 1,
    encoderFile: 'encoder.onnx',
    decoderFile: 'decoder.onnx',
    joinerFile: 'joiner.onnx',
    tokensFile: 'tokens.txt',
  );
}

void main() {
  test('standard is always supported', () async {
    final service = AndroidVoiceModelCapabilityService(
      isAndroidChecker: () => false,
      metricsLoader: () async => null,
    );

    final decision = await service.evaluateModel(_model('standard'));
    expect(decision.supported, isTrue);
  });

  test('ultra int8 blocked on low-RAM device', () async {
    final service = AndroidVoiceModelCapabilityService(
      isAndroidChecker: () => true,
      metricsLoader: () async => const VoiceModelCapabilityMetrics(
        isLowRamDevice: true,
        physicalRamMb: 8192,
        availableRamMb: 4096,
      ),
    );

    final decision = await service.evaluateModel(_model('ultra_int8'));
    expect(decision.supported, isFalse);
    expect(decision.recommendedModelId, 'standard');
  });

  test(
    'ultra full recommends ultra int8 when full thresholds are not met',
    () async {
      final service = AndroidVoiceModelCapabilityService(
        isAndroidChecker: () => true,
        metricsLoader: () async => const VoiceModelCapabilityMetrics(
          isLowRamDevice: false,
          physicalRamMb: 7000,
          availableRamMb: 1500,
        ),
      );

      final decision = await service.evaluateModel(_model('ultra_full'));
      expect(decision.supported, isFalse);
      expect(decision.recommendedModelId, 'ultra_int8');
    },
  );

  test('ultra full is supported on high-memory devices', () async {
    final service = AndroidVoiceModelCapabilityService(
      isAndroidChecker: () => true,
      metricsLoader: () async => const VoiceModelCapabilityMetrics(
        isLowRamDevice: false,
        physicalRamMb: 12288,
        availableRamMb: 4096,
      ),
    );

    final decision = await service.evaluateModel(_model('ultra_full'));
    expect(decision.supported, isTrue);
  });

  test('ultra models are blocked when RAM metrics are unavailable', () async {
    final service = AndroidVoiceModelCapabilityService(
      isAndroidChecker: () => true,
      metricsLoader: () async => const VoiceModelCapabilityMetrics(
        isLowRamDevice: false,
        physicalRamMb: null,
        availableRamMb: null,
      ),
    );

    final decision = await service.evaluateModel(_model('ultra_int8'));
    expect(decision.supported, isFalse);
    expect(decision.recommendedModelId, 'standard');
  });
}
