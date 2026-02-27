import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/core/services/voice_model_capability_service.dart';
import 'package:glitch/core/services/voice_model_catalog.dart';
import 'package:glitch/core/services/voice_model_manager.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class _RoutingHttpClient extends http.BaseClient {
  _RoutingHttpClient({
    required Map<String, List<int>> payloadByUrl,
    required void Function() onRequest,
  }) : _payloadByUrl = payloadByUrl,
       _onRequest = onRequest;

  final Map<String, List<int>> _payloadByUrl;
  final void Function() _onRequest;
  bool _closed = false;

  @override
  void close() {
    _closed = true;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw http.ClientException('client closed');
    }

    _onRequest();
    final payload = _payloadByUrl[request.url.toString()];
    if (payload == null) {
      return http.StreamedResponse(const Stream<List<int>>.empty(), 404);
    }

    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[payload]),
      200,
      contentLength: payload.length,
      request: request,
    );
  }
}

class _AllowAllCapabilityService implements VoiceModelCapabilityService {
  const _AllowAllCapabilityService();

  @override
  Future<VoiceModelCapabilityDecision> evaluateModel(
    VoiceModelSpec model,
  ) async {
    return const VoiceModelCapabilityDecision.supported();
  }
}

VoiceModelCatalog _catalogFor({
  required String standardSha,
  required int standardBytes,
  required String ultraSha,
  required int ultraBytes,
}) {
  return VoiceModelCatalog(
    schemaVersion: 2,
    defaultModelId: 'standard',
    models: <VoiceModelSpec>[
      VoiceModelSpec(
        id: 'standard',
        displayName: 'Standard',
        bundleId: 'standard_bundle',
        profile: 'int8',
        qualityHint: 'Balanced',
        sizeLabel: '~122 MB',
        language: 'en',
        version: '1.0.0',
        downloadUrl: 'https://example.com/standard.tar.bz2',
        sha256: standardSha,
        expectedBytes: standardBytes,
        sampleRate: 16000,
        numThreads: 1,
        encoderFile: 'encoder.int8.onnx',
        decoderFile: 'decoder.int8.onnx',
        joinerFile: 'joiner.int8.onnx',
        tokensFile: 'tokens.txt',
      ),
      VoiceModelSpec(
        id: 'ultra_int8',
        displayName: 'Ultra (int8)',
        bundleId: 'ultra_bundle',
        profile: 'int8',
        qualityHint: 'High quality',
        sizeLabel: '~507 MB',
        language: 'en',
        version: '2.0.0',
        downloadUrl: 'https://example.com/ultra.tar.bz2',
        sha256: ultraSha,
        expectedBytes: ultraBytes,
        sampleRate: 16000,
        numThreads: 1,
        encoderFile: 'encoder.int8.onnx',
        decoderFile: 'decoder.int8.onnx',
        joinerFile: 'joiner.int8.onnx',
        tokensFile: 'tokens.txt',
      ),
      VoiceModelSpec(
        id: 'ultra_full',
        displayName: 'Ultra Max (full)',
        bundleId: 'ultra_bundle',
        profile: 'full',
        qualityHint: 'Best quality',
        sizeLabel: '~507 MB',
        language: 'en',
        version: '2.0.0',
        downloadUrl: 'https://example.com/ultra.tar.bz2',
        sha256: ultraSha,
        expectedBytes: ultraBytes,
        sampleRate: 16000,
        numThreads: 1,
        encoderFile: 'encoder.onnx',
        decoderFile: 'decoder.onnx',
        joinerFile: 'joiner.onnx',
        tokensFile: 'tokens.txt',
      ),
    ],
  );
}

Future<void> _extractor(String archivePath, String outputDir) async {
  final nested = Directory('$outputDir/extracted_model');
  await nested.create(recursive: true);

  final archiveName = p.basename(archivePath);
  if (archiveName.contains('standard_bundle')) {
    await File('${nested.path}/encoder.int8.onnx').writeAsString('e');
    await File('${nested.path}/decoder.int8.onnx').writeAsString('d');
    await File('${nested.path}/joiner.int8.onnx').writeAsString('j');
    await File('${nested.path}/tokens.txt').writeAsString('t');
    return;
  }

  await File('${nested.path}/encoder.int8.onnx').writeAsString('ei');
  await File('${nested.path}/decoder.int8.onnx').writeAsString('di');
  await File('${nested.path}/joiner.int8.onnx').writeAsString('ji');
  await File('${nested.path}/encoder.onnx').writeAsString('ef');
  await File('${nested.path}/decoder.onnx').writeAsString('df');
  await File('${nested.path}/joiner.onnx').writeAsString('jf');
  await File('${nested.path}/tokens.txt').writeAsString('t');
}

void main() {
  test(
    'prepareModel installs selected model and returns ready state',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'voice-model-test-',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final standardPayload = List<int>.generate(32, (index) => index + 1);
      final ultraPayload = List<int>.generate(48, (index) => index + 5);
      final catalog = _catalogFor(
        standardSha: sha256.convert(standardPayload).toString(),
        standardBytes: standardPayload.length,
        ultraSha: sha256.convert(ultraPayload).toString(),
        ultraBytes: ultraPayload.length,
      );

      var requestCount = 0;
      final manager = FileVoiceModelManager(
        catalogLoader: () async => catalog,
        modelsDirectoryProvider: () async => tempRoot,
        connectivityChecker: () async => <ConnectivityResult>[
          ConnectivityResult.wifi,
        ],
        httpClientFactory: () => _RoutingHttpClient(
          payloadByUrl: <String, List<int>>{
            'https://example.com/standard.tar.bz2': standardPayload,
            'https://example.com/ultra.tar.bz2': ultraPayload,
          },
          onRequest: () => requestCount += 1,
        ),
        archiveExtractor: _extractor,
        capabilityService: const _AllowAllCapabilityService(),
      );
      addTearDown(manager.dispose);

      final finalState = await manager.prepareModel(modelId: 'standard');

      expect(finalState.isReady, isTrue);
      expect(finalState.installedModel, isNotNull);
      expect(finalState.installedModel!.spec.id, 'standard');
      expect(requestCount, 1);

      final installed = await manager.getInstalledModel(modelId: 'standard');
      expect(installed, isNotNull);
      expect(File(installed!.encoderPath).existsSync(), isTrue);
      expect(File(installed.tokensPath).existsSync(), isTrue);
    },
  );

  test('prepareModel surfaces checksum failures as error state', () async {
    final tempRoot = await Directory.systemTemp.createTemp('voice-model-test-');
    addTearDown(() => tempRoot.delete(recursive: true));

    final payload = List<int>.filled(32, 7);
    final catalog = _catalogFor(
      standardSha: 'deadbeef',
      standardBytes: payload.length,
      ultraSha: 'deadbeef',
      ultraBytes: payload.length,
    );

    final manager = FileVoiceModelManager(
      catalogLoader: () async => catalog,
      modelsDirectoryProvider: () async => tempRoot,
      connectivityChecker: () async => <ConnectivityResult>[
        ConnectivityResult.wifi,
      ],
      httpClientFactory: () => _RoutingHttpClient(
        payloadByUrl: <String, List<int>>{
          'https://example.com/standard.tar.bz2': payload,
          'https://example.com/ultra.tar.bz2': payload,
        },
        onRequest: () {},
      ),
      archiveExtractor: _extractor,
      capabilityService: const _AllowAllCapabilityService(),
    );
    addTearDown(manager.dispose);

    final state = await manager.prepareModel(modelId: 'standard');

    expect(state.status, VoiceModelInstallStatus.error);
    expect(state.message, contains('download failed'));
    expect(await manager.getInstalledModel(modelId: 'standard'), isNull);
  });

  test('switching ultra_int8 to ultra_full does not re-download', () async {
    final tempRoot = await Directory.systemTemp.createTemp('voice-model-test-');
    addTearDown(() => tempRoot.delete(recursive: true));

    final standardPayload = List<int>.generate(24, (index) => index + 1);
    final ultraPayload = List<int>.generate(40, (index) => index + 3);
    final catalog = _catalogFor(
      standardSha: sha256.convert(standardPayload).toString(),
      standardBytes: standardPayload.length,
      ultraSha: sha256.convert(ultraPayload).toString(),
      ultraBytes: ultraPayload.length,
    );

    var requestCount = 0;
    final manager = FileVoiceModelManager(
      catalogLoader: () async => catalog,
      modelsDirectoryProvider: () async => tempRoot,
      connectivityChecker: () async => <ConnectivityResult>[
        ConnectivityResult.wifi,
      ],
      httpClientFactory: () => _RoutingHttpClient(
        payloadByUrl: <String, List<int>>{
          'https://example.com/standard.tar.bz2': standardPayload,
          'https://example.com/ultra.tar.bz2': ultraPayload,
        },
        onRequest: () => requestCount += 1,
      ),
      archiveExtractor: _extractor,
      capabilityService: const _AllowAllCapabilityService(),
    );
    addTearDown(manager.dispose);

    final int8State = await manager.prepareModel(modelId: 'ultra_int8');
    expect(int8State.isReady, isTrue);

    final fullState = await manager.prepareModel(modelId: 'ultra_full');
    expect(fullState.isReady, isTrue);
    expect(fullState.installedModel!.spec.id, 'ultra_full');
    expect(requestCount, 1);
  });

  test('switching bundles replaces old bundle artifacts', () async {
    final tempRoot = await Directory.systemTemp.createTemp('voice-model-test-');
    addTearDown(() => tempRoot.delete(recursive: true));

    final standardPayload = List<int>.generate(28, (index) => index + 2);
    final ultraPayload = List<int>.generate(44, (index) => index + 4);
    final catalog = _catalogFor(
      standardSha: sha256.convert(standardPayload).toString(),
      standardBytes: standardPayload.length,
      ultraSha: sha256.convert(ultraPayload).toString(),
      ultraBytes: ultraPayload.length,
    );

    var requestCount = 0;
    final manager = FileVoiceModelManager(
      catalogLoader: () async => catalog,
      modelsDirectoryProvider: () async => tempRoot,
      connectivityChecker: () async => <ConnectivityResult>[
        ConnectivityResult.wifi,
      ],
      httpClientFactory: () => _RoutingHttpClient(
        payloadByUrl: <String, List<int>>{
          'https://example.com/standard.tar.bz2': standardPayload,
          'https://example.com/ultra.tar.bz2': ultraPayload,
        },
        onRequest: () => requestCount += 1,
      ),
      archiveExtractor: _extractor,
      capabilityService: const _AllowAllCapabilityService(),
    );
    addTearDown(manager.dispose);

    final standardState = await manager.prepareModel(modelId: 'standard');
    expect(standardState.isReady, isTrue);

    final ultraState = await manager.prepareModel(modelId: 'ultra_int8');
    expect(ultraState.isReady, isTrue);
    expect(requestCount, 2);

    final entries = tempRoot
        .listSync()
        .map((entry) => p.basename(entry.path))
        .toSet();
    expect(entries.where((name) => name.contains('standard_bundle')), isEmpty);
    expect(entries.any((name) => name.contains('ultra_bundle-2.0.0')), isTrue);
  });

  test('prepareModel emits preparing state during extraction', () async {
    final tempRoot = await Directory.systemTemp.createTemp('voice-model-test-');
    addTearDown(() => tempRoot.delete(recursive: true));

    final standardPayload = List<int>.generate(32, (index) => index + 1);
    final catalog = _catalogFor(
      standardSha: sha256.convert(standardPayload).toString(),
      standardBytes: standardPayload.length,
      ultraSha: sha256.convert(standardPayload).toString(),
      ultraBytes: standardPayload.length,
    );

    final extractionStarted = Completer<void>();
    final allowExtractionFinish = Completer<void>();

    Future<void> blockingExtractor(String archivePath, String outputDir) async {
      if (!extractionStarted.isCompleted) {
        extractionStarted.complete();
      }
      await allowExtractionFinish.future;
      await _extractor(archivePath, outputDir);
    }

    final manager = FileVoiceModelManager(
      catalogLoader: () async => catalog,
      modelsDirectoryProvider: () async => tempRoot,
      connectivityChecker: () async => <ConnectivityResult>[
        ConnectivityResult.wifi,
      ],
      httpClientFactory: () => _RoutingHttpClient(
        payloadByUrl: <String, List<int>>{
          'https://example.com/standard.tar.bz2': standardPayload,
          'https://example.com/ultra.tar.bz2': standardPayload,
        },
        onRequest: () {},
      ),
      archiveExtractor: blockingExtractor,
      capabilityService: const _AllowAllCapabilityService(),
    );
    addTearDown(manager.dispose);

    final prepareFuture = manager.prepareModel(modelId: 'standard');
    await extractionStarted.future;
    expect(manager.currentState.status, VoiceModelInstallStatus.preparing);

    allowExtractionFinish.complete();
    final result = await prepareFuture;
    expect(result.status, VoiceModelInstallStatus.ready);
  });

  test('removeModel during preparing cancels and cleans artifacts', () async {
    final tempRoot = await Directory.systemTemp.createTemp('voice-model-test-');
    addTearDown(() => tempRoot.delete(recursive: true));

    final standardPayload = List<int>.generate(32, (index) => index + 9);
    final catalog = _catalogFor(
      standardSha: sha256.convert(standardPayload).toString(),
      standardBytes: standardPayload.length,
      ultraSha: sha256.convert(standardPayload).toString(),
      ultraBytes: standardPayload.length,
    );

    final extractionStarted = Completer<void>();
    final allowExtractionFinish = Completer<void>();

    Future<void> blockingExtractor(String archivePath, String outputDir) async {
      if (!extractionStarted.isCompleted) {
        extractionStarted.complete();
      }
      await allowExtractionFinish.future;
      await _extractor(archivePath, outputDir);
    }

    final manager = FileVoiceModelManager(
      catalogLoader: () async => catalog,
      modelsDirectoryProvider: () async => tempRoot,
      connectivityChecker: () async => <ConnectivityResult>[
        ConnectivityResult.wifi,
      ],
      httpClientFactory: () => _RoutingHttpClient(
        payloadByUrl: <String, List<int>>{
          'https://example.com/standard.tar.bz2': standardPayload,
          'https://example.com/ultra.tar.bz2': standardPayload,
        },
        onRequest: () {},
      ),
      archiveExtractor: blockingExtractor,
      capabilityService: const _AllowAllCapabilityService(),
    );
    addTearDown(manager.dispose);

    final prepareFuture = manager.prepareModel(modelId: 'standard');
    await extractionStarted.future;
    expect(manager.currentState.status, VoiceModelInstallStatus.preparing);

    final removeFuture = manager.removeModel();
    allowExtractionFinish.complete();

    await Future.wait(<Future<void>>[removeFuture, manager.removeModel()]);
    final prepareResult = await prepareFuture;

    expect(prepareResult.status, VoiceModelInstallStatus.notInstalled);
    expect(manager.currentState.status, VoiceModelInstallStatus.notInstalled);
    expect(tempRoot.listSync(), isEmpty);
  });
}
