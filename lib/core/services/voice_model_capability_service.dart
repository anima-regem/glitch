import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'voice_model_catalog.dart';

class VoiceModelCapabilityDecision {
  const VoiceModelCapabilityDecision({
    required this.supported,
    this.reason,
    this.recommendedModelId,
  });

  const VoiceModelCapabilityDecision.supported()
    : supported = true,
      reason = null,
      recommendedModelId = null;

  const VoiceModelCapabilityDecision.unsupported({
    required String this.reason,
    this.recommendedModelId = 'standard',
  }) : supported = false;

  final bool supported;
  final String? reason;
  final String? recommendedModelId;
}

class VoiceModelCapabilityMetrics {
  const VoiceModelCapabilityMetrics({
    required this.isLowRamDevice,
    required this.physicalRamMb,
    required this.availableRamMb,
  });

  final bool isLowRamDevice;
  final int? physicalRamMb;
  final int? availableRamMb;
}

abstract class VoiceModelCapabilityService {
  Future<VoiceModelCapabilityDecision> evaluateModel(VoiceModelSpec model);
}

typedef VoiceModelCapabilityMetricsLoader =
    Future<VoiceModelCapabilityMetrics?> Function();

class AndroidVoiceModelCapabilityService
    implements VoiceModelCapabilityService {
  AndroidVoiceModelCapabilityService({
    DeviceInfoPlugin? deviceInfoPlugin,
    VoiceModelCapabilityMetricsLoader? metricsLoader,
    bool Function()? isAndroidChecker,
  }) : _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin(),
       _metricsLoader = metricsLoader,
       _isAndroidChecker = isAndroidChecker ?? (() => Platform.isAndroid);

  static const int _ultraInt8MinPhysicalRamMb = 6144;
  static const int _ultraInt8MinAvailableRamMb = 1200;
  static const int _ultraFullMinPhysicalRamMb = 8192;
  static const int _ultraFullMinAvailableRamMb = 1800;

  final DeviceInfoPlugin _deviceInfoPlugin;
  final VoiceModelCapabilityMetricsLoader? _metricsLoader;
  final bool Function() _isAndroidChecker;

  @override
  Future<VoiceModelCapabilityDecision> evaluateModel(
    VoiceModelSpec model,
  ) async {
    final requirement = _requirementForModel(model.id);
    if (requirement == null) {
      return const VoiceModelCapabilityDecision.supported();
    }

    final metrics = await _loadMetrics();
    if (metrics == null) {
      return VoiceModelCapabilityDecision.unsupported(
        reason:
            '${model.displayName} requires Android RAM metrics that are unavailable right now. Use Standard.',
        recommendedModelId: 'standard',
      );
    }

    if (metrics.isLowRamDevice) {
      return VoiceModelCapabilityDecision.unsupported(
        reason:
            '${model.displayName} is unsupported on low-RAM devices. Use Standard.',
        recommendedModelId: 'standard',
      );
    }

    final physicalRamMb = metrics.physicalRamMb;
    final availableRamMb = metrics.availableRamMb;
    if (physicalRamMb == null ||
        availableRamMb == null ||
        physicalRamMb <= 0 ||
        availableRamMb <= 0) {
      return VoiceModelCapabilityDecision.unsupported(
        reason:
            '${model.displayName} requires RAM metrics that are unavailable right now. Use Standard.',
        recommendedModelId: 'standard',
      );
    }

    if (physicalRamMb < requirement.minPhysicalRamMb) {
      return VoiceModelCapabilityDecision.unsupported(
        reason:
            '${model.displayName} needs at least ${requirement.minPhysicalRamMb ~/ 1024} GB physical RAM.',
        recommendedModelId: _recommendedFallbackModelId(
          requestedModelId: model.id,
          physicalRamMb: physicalRamMb,
          availableRamMb: availableRamMb,
        ),
      );
    }

    if (availableRamMb < requirement.minAvailableRamMb) {
      final neededGb = (requirement.minAvailableRamMb / 1024).toStringAsFixed(
        1,
      );
      return VoiceModelCapabilityDecision.unsupported(
        reason:
            '${model.displayName} needs at least $neededGb GB free RAM available right now.',
        recommendedModelId: _recommendedFallbackModelId(
          requestedModelId: model.id,
          physicalRamMb: physicalRamMb,
          availableRamMb: availableRamMb,
        ),
      );
    }

    return const VoiceModelCapabilityDecision.supported();
  }

  Future<VoiceModelCapabilityMetrics?> _loadMetrics() async {
    final override = _metricsLoader;
    if (override != null) {
      return override();
    }

    if (!_isAndroidChecker()) {
      return null;
    }

    final info = await _deviceInfoPlugin.androidInfo;
    return VoiceModelCapabilityMetrics(
      isLowRamDevice: info.isLowRamDevice,
      physicalRamMb: info.physicalRamSize,
      availableRamMb: info.availableRamSize,
    );
  }

  _ModelRequirement? _requirementForModel(String modelId) {
    switch (modelId.trim()) {
      case 'ultra_int8':
        return const _ModelRequirement(
          minPhysicalRamMb: _ultraInt8MinPhysicalRamMb,
          minAvailableRamMb: _ultraInt8MinAvailableRamMb,
        );
      case 'ultra_full':
        return const _ModelRequirement(
          minPhysicalRamMb: _ultraFullMinPhysicalRamMb,
          minAvailableRamMb: _ultraFullMinAvailableRamMb,
        );
      default:
        return null;
    }
  }

  String _recommendedFallbackModelId({
    required String requestedModelId,
    required int physicalRamMb,
    required int availableRamMb,
  }) {
    final canRunUltraInt8 =
        physicalRamMb >= _ultraInt8MinPhysicalRamMb &&
        availableRamMb >= _ultraInt8MinAvailableRamMb;

    if (requestedModelId == 'ultra_full' && canRunUltraInt8) {
      return 'ultra_int8';
    }
    return 'standard';
  }
}

class _ModelRequirement {
  const _ModelRequirement({
    required this.minPhysicalRamMb,
    required this.minAvailableRamMb,
  });

  final int minPhysicalRamMb;
  final int minAvailableRamMb;
}
