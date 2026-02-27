import 'dart:convert';

import 'package:flutter/services.dart';

class VoiceModelCatalog {
  const VoiceModelCatalog({
    required this.schemaVersion,
    required this.defaultModelId,
    required this.models,
  });

  factory VoiceModelCatalog.fromJson(Map<String, dynamic> json) {
    final models = (json['models'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (entry) => VoiceModelSpec.fromJson(Map<String, dynamic>.from(entry)),
        )
        .where((model) => model.id.trim().isNotEmpty)
        .toList(growable: false);

    return VoiceModelCatalog(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      defaultModelId: json['defaultModelId'] as String? ?? '',
      models: models,
    );
  }

  final int schemaVersion;
  final String defaultModelId;
  final List<VoiceModelSpec> models;

  VoiceModelSpec resolveDefaultModel() {
    if (models.isEmpty) {
      throw StateError('No voice models configured in manifest.');
    }
    final defaultId = defaultModelId.trim();
    if (defaultId.isEmpty) {
      return models.first;
    }
    return models.firstWhere(
      (model) => model.id == defaultId,
      orElse: () => models.first,
    );
  }

  VoiceModelSpec resolveModel(String? modelId) {
    if (models.isEmpty) {
      throw StateError('No voice models configured in manifest.');
    }

    final preferredId = modelId?.trim() ?? '';
    if (preferredId.isNotEmpty) {
      final matched = models.where((model) => model.id == preferredId);
      if (matched.isNotEmpty) {
        return matched.first;
      }
      return resolveDefaultModel();
    }

    return resolveDefaultModel();
  }
}

class VoiceModelSpec {
  const VoiceModelSpec({
    required this.id,
    required this.displayName,
    required this.bundleId,
    required this.profile,
    required this.qualityHint,
    required this.sizeLabel,
    required this.language,
    required this.version,
    required this.downloadUrl,
    required this.sha256,
    required this.expectedBytes,
    required this.sampleRate,
    required this.numThreads,
    required this.encoderFile,
    required this.decoderFile,
    required this.joinerFile,
    required this.tokensFile,
  });

  factory VoiceModelSpec.fromJson(Map<String, dynamic> json) {
    return VoiceModelSpec(
      id: json['id'] as String? ?? '',
      displayName:
          (json['displayName'] as String?) ?? (json['id'] as String? ?? ''),
      bundleId: (json['bundleId'] as String?) ?? (json['id'] as String? ?? ''),
      profile: (json['profile'] as String? ?? 'int8').toLowerCase(),
      qualityHint: json['qualityHint'] as String? ?? '',
      sizeLabel: json['sizeLabel'] as String? ?? '',
      language: json['language'] as String? ?? 'en',
      version: json['version'] as String? ?? 'unknown',
      downloadUrl: json['downloadUrl'] as String? ?? '',
      sha256: (json['sha256'] as String? ?? '').toLowerCase(),
      expectedBytes: (json['expectedBytes'] as num?)?.toInt() ?? 0,
      sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 16000,
      numThreads: (json['numThreads'] as num?)?.toInt() ?? 2,
      encoderFile: json['encoderFile'] as String? ?? '',
      decoderFile: json['decoderFile'] as String? ?? '',
      joinerFile: json['joinerFile'] as String? ?? '',
      tokensFile: json['tokensFile'] as String? ?? 'tokens.txt',
    );
  }

  final String id;
  final String displayName;
  final String bundleId;
  final String profile;
  final String qualityHint;
  final String sizeLabel;
  final String language;
  final String version;
  final String downloadUrl;
  final String sha256;
  final int expectedBytes;
  final int sampleRate;
  final int numThreads;
  final String encoderFile;
  final String decoderFile;
  final String joinerFile;
  final String tokensFile;

  String get bundleKey => '$bundleId::$version';

  String get installDirectoryName {
    final raw = '$bundleId-$version';
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String get archiveFileName => '$installDirectoryName.tar.bz2';

  List<String> get requiredFiles => <String>[
    encoderFile,
    decoderFile,
    joinerFile,
    tokensFile,
  ];
}

Future<VoiceModelCatalog> loadVoiceModelCatalog({
  String assetPath = 'assets/voice_models/manifest.json',
}) async {
  final raw = await rootBundle.loadString(assetPath);
  final parsed = jsonDecode(raw);
  if (parsed is! Map<String, dynamic>) {
    throw const FormatException('Voice model manifest must be a JSON object.');
  }
  return VoiceModelCatalog.fromJson(parsed);
}
