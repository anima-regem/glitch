import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'voice_model_catalog.dart';
import 'voice_model_capability_service.dart';

enum VoiceModelInstallStatus {
  notInstalled,
  downloading,
  preparing,
  ready,
  error,
}

class VoiceModelState {
  const VoiceModelState({
    required this.status,
    this.model,
    this.installedModel,
    this.progress,
    this.downloadedBytes,
    this.totalBytes,
    this.message,
    this.error,
    this.requiresCellularOverride = false,
    this.selectedModelId,
  });

  factory VoiceModelState.notInstalled({
    VoiceModelSpec? model,
    String? message,
    bool requiresCellularOverride = false,
  }) {
    return VoiceModelState(
      status: VoiceModelInstallStatus.notInstalled,
      model: model,
      selectedModelId: model?.id,
      message: message,
      requiresCellularOverride: requiresCellularOverride,
    );
  }

  factory VoiceModelState.downloading({
    required VoiceModelSpec model,
    required double? progress,
    required int? downloadedBytes,
    required int? totalBytes,
    String? message,
  }) {
    return VoiceModelState(
      status: VoiceModelInstallStatus.downloading,
      model: model,
      selectedModelId: model.id,
      progress: progress,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      message: message,
    );
  }

  factory VoiceModelState.preparing({
    required VoiceModelSpec model,
    String? message,
  }) {
    return VoiceModelState(
      status: VoiceModelInstallStatus.preparing,
      model: model,
      selectedModelId: model.id,
      message: message ?? 'Extracting model files...',
    );
  }

  factory VoiceModelState.ready({required InstalledVoiceModel model}) {
    return VoiceModelState(
      status: VoiceModelInstallStatus.ready,
      model: model.spec,
      selectedModelId: model.spec.id,
      installedModel: model,
      message: '${model.spec.displayName} is ready for offline voice typing.',
    );
  }

  factory VoiceModelState.error({
    VoiceModelSpec? model,
    required String error,
    String? message,
  }) {
    return VoiceModelState(
      status: VoiceModelInstallStatus.error,
      model: model,
      selectedModelId: model?.id,
      error: error,
      message: message,
    );
  }

  final VoiceModelInstallStatus status;
  final VoiceModelSpec? model;
  final InstalledVoiceModel? installedModel;
  final double? progress;
  final int? downloadedBytes;
  final int? totalBytes;
  final String? message;
  final String? error;
  final bool requiresCellularOverride;
  final String? selectedModelId;

  bool get isDownloading => status == VoiceModelInstallStatus.downloading;

  bool get isPreparing => status == VoiceModelInstallStatus.preparing;

  bool get isInProgress => isDownloading || isPreparing;

  bool get isReady =>
      status == VoiceModelInstallStatus.ready && installedModel != null;
}

class InstalledVoiceModel {
  const InstalledVoiceModel({
    required this.spec,
    required this.installDirectoryPath,
    required this.modelRootPath,
    required this.installedAt,
  });

  final VoiceModelSpec spec;
  final String installDirectoryPath;
  final String modelRootPath;
  final DateTime installedAt;

  String get encoderPath => p.join(modelRootPath, spec.encoderFile);

  String get decoderPath => p.join(modelRootPath, spec.decoderFile);

  String get joinerPath => p.join(modelRootPath, spec.joinerFile);

  String get tokensPath => p.join(modelRootPath, spec.tokensFile);
}

abstract class VoiceModelManager {
  Stream<VoiceModelState> get states;

  VoiceModelState get currentState;

  Future<List<VoiceModelSpec>> listAvailableModels();

  Future<VoiceModelState> prepareModel({
    required String modelId,
    bool allowCellular = false,
  });

  Future<void> cancelDownload();

  Future<void> removeModel();

  Future<InstalledVoiceModel?> getInstalledModel({required String modelId});
}

typedef VoiceModelCatalogLoader = Future<VoiceModelCatalog> Function();
typedef VoiceModelsDirectoryProvider = Future<Directory> Function();
typedef VoiceModelArchiveExtractor =
    Future<void> Function(String archivePath, String outputDir);
typedef VoiceModelHttpClientFactory = http.Client Function();

class FileVoiceModelManager implements VoiceModelManager {
  FileVoiceModelManager({
    VoiceModelCatalogLoader? catalogLoader,
    VoiceModelsDirectoryProvider? modelsDirectoryProvider,
    VoiceModelArchiveExtractor? archiveExtractor,
    Connectivity? connectivity,
    Future<List<ConnectivityResult>> Function()? connectivityChecker,
    VoiceModelHttpClientFactory? httpClientFactory,
    VoiceModelCapabilityService? capabilityService,
  }) : _catalogLoader = catalogLoader ?? loadVoiceModelCatalog,
       _modelsDirectoryProvider =
           modelsDirectoryProvider ?? _defaultModelsDirectoryProvider,
       _archiveExtractor = archiveExtractor ?? _defaultArchiveExtractor,
       _checkConnectivity =
           connectivityChecker ??
           (connectivity ?? Connectivity()).checkConnectivity,
       _httpClientFactory = httpClientFactory ?? http.Client.new,
       _capabilityService =
           capabilityService ?? AndroidVoiceModelCapabilityService() {
    _bootstrapFuture = _refreshStateFromDisk().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _emit(
        VoiceModelState.error(
          error: error.toString(),
          message: 'Unable to load offline voice model catalog.',
        ),
      );
    });
  }

  final VoiceModelCatalogLoader _catalogLoader;
  final VoiceModelsDirectoryProvider _modelsDirectoryProvider;
  final VoiceModelArchiveExtractor _archiveExtractor;
  final Future<List<ConnectivityResult>> Function() _checkConnectivity;
  final VoiceModelHttpClientFactory _httpClientFactory;
  final VoiceModelCapabilityService _capabilityService;

  final StreamController<VoiceModelState> _statesController =
      StreamController<VoiceModelState>.broadcast();

  VoiceModelState _currentState = VoiceModelState.notInstalled();
  VoiceModelCatalog? _catalog;
  _InstalledModelBundle? _installedBundle;
  String? _lastSelectedModelId;
  Future<void>? _bootstrapFuture;
  Future<VoiceModelState>? _activePrepareFuture;
  Future<void>? _activeRemoveFuture;

  http.Client? _activeHttpClient;
  bool _cancelRequested = false;

  @override
  Stream<VoiceModelState> get states => _statesController.stream;

  @override
  VoiceModelState get currentState => _currentState;

  void dispose() {
    _activeHttpClient?.close();
    _statesController.close();
  }

  @override
  Future<List<VoiceModelSpec>> listAvailableModels() async {
    await (_bootstrapFuture ?? Future<void>.value());
    final catalog = await _catalogOrLoad();
    return List<VoiceModelSpec>.unmodifiable(catalog.models);
  }

  @override
  Future<InstalledVoiceModel?> getInstalledModel({
    required String modelId,
  }) async {
    await (_bootstrapFuture ?? Future<void>.value());
    final spec = await _resolveModelSpec(modelId);
    _lastSelectedModelId = spec.id;

    if (_currentState.isInProgress &&
        _currentState.selectedModelId == spec.id) {
      return null;
    }

    var installed = await _resolveInstalledModelForSpec(
      spec,
      refreshIfMissing: true,
    );

    if (installed != null) {
      final ready = VoiceModelState.ready(model: installed);
      _emit(ready);
      return installed;
    }

    await _refreshStateFromDisk(selectedModelId: spec.id);
    installed = await _resolveInstalledModelForSpec(
      spec,
      refreshIfMissing: false,
    );
    if (installed != null) {
      final ready = VoiceModelState.ready(model: installed);
      _emit(ready);
      return installed;
    }

    _emit(
      VoiceModelState.notInstalled(
        model: spec,
        message: '${spec.displayName} is not installed on this device.',
      ),
    );
    return null;
  }

  @override
  Future<VoiceModelState> prepareModel({
    required String modelId,
    bool allowCellular = false,
  }) {
    final inFlight = _activePrepareFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _prepareModelInternal(
      modelId: modelId,
      allowCellular: allowCellular,
    );
    _activePrepareFuture = future.whenComplete(() {
      _activePrepareFuture = null;
    });
    return _activePrepareFuture!;
  }

  @override
  Future<void> cancelDownload() async {
    _cancelRequested = true;
    _activeHttpClient?.close();
  }

  @override
  Future<void> removeModel() async {
    final inFlight = _activeRemoveFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _removeModelInternal();
    _activeRemoveFuture = future.whenComplete(() {
      _activeRemoveFuture = null;
    });
    return _activeRemoveFuture!;
  }

  Future<VoiceModelState> _prepareModelInternal({
    required String modelId,
    required bool allowCellular,
  }) async {
    await (_bootstrapFuture ?? Future<void>.value());

    final spec = await _resolveModelSpec(modelId);
    _lastSelectedModelId = spec.id;

    final capability = await _capabilityService.evaluateModel(spec);
    if (!capability.supported) {
      final blocked = VoiceModelState.notInstalled(
        model: spec,
        message:
            capability.reason ??
            '${spec.displayName} is not supported on this device right now.',
      );
      _emit(blocked);
      return blocked;
    }

    final existing = await _resolveInstalledModelForSpec(
      spec,
      refreshIfMissing: true,
    );
    if (existing != null) {
      final ready = VoiceModelState.ready(model: existing);
      _emit(ready);
      return ready;
    }

    if (_isCellularOnlyNetwork(await _checkConnectivity()) && !allowCellular) {
      final state = VoiceModelState.notInstalled(
        model: spec,
        requiresCellularOverride: true,
        message:
            'You are on cellular data. Connect to Wi-Fi or continue explicitly to download ${spec.displayName}.',
      );
      _emit(state);
      return state;
    }

    _cancelRequested = false;

    final rootDir = await _modelsDirectoryProvider();
    await rootDir.create(recursive: true);

    final archiveFile = File(p.join(rootDir.path, spec.archiveFileName));
    final tempArchiveFile = File('${archiveFile.path}.part');

    if (await tempArchiveFile.exists()) {
      await tempArchiveFile.delete();
    }

    try {
      await _downloadArchive(
        spec: spec,
        targetFile: tempArchiveFile,
        progressMessage: 'Downloading ${spec.displayName}...',
      );

      if (_cancelRequested) {
        throw const _VoiceModelDownloadCanceled();
      }

      if (await archiveFile.exists()) {
        await archiveFile.delete();
      }
      await tempArchiveFile.rename(archiveFile.path);

      await _verifyArchive(spec: spec, archiveFile: archiveFile);
      if (_cancelRequested) {
        throw const _VoiceModelDownloadCanceled();
      }

      final installDir = Directory(
        p.join(rootDir.path, spec.installDirectoryName),
      );
      if (await installDir.exists()) {
        await installDir.delete(recursive: true);
      }
      await installDir.create(recursive: true);

      _emit(
        VoiceModelState.preparing(
          model: spec,
          message: 'Extracting model files...',
        ),
      );
      await _archiveExtractor(archiveFile.path, installDir.path);
      if (_cancelRequested) {
        throw const _VoiceModelDownloadCanceled();
      }

      final modelRoot = await _findModelRoot(
        installDir: installDir,
        requiredFiles: spec.requiredFiles,
      );

      if (modelRoot == null) {
        throw StateError('Downloaded model is missing required runtime files.');
      }

      final installedAt = DateTime.now();
      final bundle = _InstalledModelBundle(
        bundleId: spec.bundleId,
        version: spec.version,
        installDirectoryPath: installDir.path,
        modelRootPath: modelRoot.path,
        installedAt: installedAt,
      );
      _installedBundle = bundle;

      await _cleanupInactiveModels(
        rootDir: rootDir,
        activeDirectoryPath: installDir.path,
        keepFiles: <String>{spec.archiveFileName},
      );

      final installed = bundle.asInstalledModel(spec);
      final ready = VoiceModelState.ready(model: installed);
      _emit(ready);
      return ready;
    } on _VoiceModelDownloadCanceled {
      if (await tempArchiveFile.exists()) {
        await tempArchiveFile.delete();
      }
      await _cleanupModelArtifactsForSpec(rootDir: rootDir, spec: spec);
      final state = VoiceModelState.notInstalled(
        model: spec,
        message: 'Offline voice model download cancelled.',
      );
      _emit(state);
      return state;
    } catch (error) {
      await _cleanupModelArtifactsForSpec(rootDir: rootDir, spec: spec);
      final state = VoiceModelState.error(
        model: spec,
        error: error.toString(),
        message: 'Offline voice model download failed. Please try again.',
      );
      _emit(state);
      return state;
    } finally {
      _activeHttpClient?.close();
      _activeHttpClient = null;
      _cancelRequested = false;
    }
  }

  Future<void> _downloadArchive({
    required VoiceModelSpec spec,
    required File targetFile,
    required String progressMessage,
  }) async {
    _activeHttpClient = _httpClientFactory();
    final request = http.Request('GET', Uri.parse(spec.downloadUrl));
    final response = await _activeHttpClient!.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Model download failed with status ${response.statusCode}.',
      );
    }

    final expectedTotal = spec.expectedBytes > 0
        ? spec.expectedBytes
        : response.contentLength;
    var downloaded = 0;

    final sink = targetFile.openWrite(mode: FileMode.writeOnly);
    try {
      try {
        await for (final chunk in response.stream) {
          if (_cancelRequested) {
            throw const _VoiceModelDownloadCanceled();
          }

          sink.add(chunk);
          downloaded += chunk.length;

          final progress = expectedTotal == null || expectedTotal <= 0
              ? null
              : downloaded / expectedTotal;

          _emit(
            VoiceModelState.downloading(
              model: spec,
              progress: progress,
              downloadedBytes: downloaded,
              totalBytes: expectedTotal,
              message: progressMessage,
            ),
          );
        }
      } on http.ClientException {
        if (_cancelRequested) {
          throw const _VoiceModelDownloadCanceled();
        }
        rethrow;
      } on SocketException {
        if (_cancelRequested) {
          throw const _VoiceModelDownloadCanceled();
        }
        rethrow;
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (spec.expectedBytes > 0 && downloaded != spec.expectedBytes) {
      throw StateError(
        'Model size mismatch. Expected ${spec.expectedBytes} bytes, got $downloaded bytes.',
      );
    }
  }

  Future<void> _verifyArchive({
    required VoiceModelSpec spec,
    required File archiveFile,
  }) async {
    final digest = await sha256.bind(archiveFile.openRead()).first;
    final hash = digest.toString().toLowerCase();

    if (hash != spec.sha256) {
      throw StateError('Model checksum verification failed.');
    }
  }

  Future<void> _refreshStateFromDisk({String? selectedModelId}) async {
    final spec = await _resolveModelSpec(
      selectedModelId ?? _lastSelectedModelId,
    );
    _lastSelectedModelId = spec.id;

    final rootDir = await _modelsDirectoryProvider();
    if (!await rootDir.exists()) {
      _installedBundle = null;
      _emit(
        VoiceModelState.notInstalled(
          model: spec,
          message: '${spec.displayName} is not installed.',
        ),
      );
      return;
    }

    final catalog = await _catalogOrLoad();
    _installedBundle = await _discoverInstalledBundle(
      rootDir: rootDir,
      catalog: catalog,
    );

    if (_installedBundle == null) {
      _emit(
        VoiceModelState.notInstalled(
          model: spec,
          message: '${spec.displayName} is not installed.',
        ),
      );
      return;
    }

    final installed = await _resolveInstalledModelForSpec(
      spec,
      refreshIfMissing: false,
    );

    if (installed == null) {
      _emit(
        VoiceModelState.notInstalled(
          model: spec,
          message:
              '${spec.displayName} is not installed. Download the selected model to use offline voice typing.',
        ),
      );
      return;
    }

    _emit(VoiceModelState.ready(model: installed));
  }

  Future<InstalledVoiceModel?> _resolveInstalledModelForSpec(
    VoiceModelSpec spec, {
    required bool refreshIfMissing,
  }) async {
    if (_installedBundle == null && refreshIfMissing) {
      await _refreshStateFromDisk(selectedModelId: spec.id);
    }

    final bundle = _installedBundle;
    if (bundle == null || bundle.bundleKey != spec.bundleKey) {
      return null;
    }

    final filesPresent = await _modelFilesExist(
      modelRootPath: bundle.modelRootPath,
      requiredFiles: spec.requiredFiles,
    );
    if (!filesPresent) {
      return null;
    }

    return bundle.asInstalledModel(spec);
  }

  Future<bool> _modelFilesExist({
    required String modelRootPath,
    required List<String> requiredFiles,
  }) async {
    for (final fileName in requiredFiles) {
      if (fileName.trim().isEmpty) {
        return false;
      }
      final exists = await File(p.join(modelRootPath, fileName)).exists();
      if (!exists) {
        return false;
      }
    }
    return true;
  }

  Future<_InstalledModelBundle?> _discoverInstalledBundle({
    required Directory rootDir,
    required VoiceModelCatalog catalog,
  }) async {
    final representatives = <String, VoiceModelSpec>{};
    for (final spec in catalog.models) {
      representatives.putIfAbsent(spec.bundleKey, () => spec);
    }

    for (final spec in representatives.values) {
      final installDir = Directory(
        p.join(rootDir.path, spec.installDirectoryName),
      );
      if (!await installDir.exists()) {
        continue;
      }

      final modelRoot = await _findModelRoot(
        installDir: installDir,
        requiredFiles: <String>[spec.tokensFile],
      );
      if (modelRoot == null) {
        continue;
      }

      final stat = await installDir.stat();
      return _InstalledModelBundle(
        bundleId: spec.bundleId,
        version: spec.version,
        installDirectoryPath: installDir.path,
        modelRootPath: modelRoot.path,
        installedAt: stat.modified,
      );
    }

    return null;
  }

  Future<VoiceModelCatalog> _catalogOrLoad() async {
    final cached = _catalog;
    if (cached != null) {
      return cached;
    }

    final loaded = await _catalogLoader();
    _catalog = loaded;
    return loaded;
  }

  Future<VoiceModelSpec> _resolveModelSpec(String? modelId) async {
    final catalog = await _catalogOrLoad();
    return catalog.resolveModel(modelId);
  }

  bool _isCellularOnlyNetwork(List<ConnectivityResult> results) {
    final hasMobile = results.contains(ConnectivityResult.mobile);
    final hasWifiLike =
        results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);

    return hasMobile && !hasWifiLike;
  }

  Future<Directory?> _findModelRoot({
    required Directory installDir,
    required List<String> requiredFiles,
  }) async {
    final candidates = <Directory>[installDir];
    final recursive = installDir
        .listSync(recursive: true, followLinks: false)
        .whereType<Directory>()
        .toList(growable: false);
    candidates.addAll(recursive);

    for (final candidate in candidates) {
      var allPresent = true;
      for (final fileName in requiredFiles) {
        final exists = await File(p.join(candidate.path, fileName)).exists();
        if (!exists) {
          allPresent = false;
          break;
        }
      }
      if (allPresent) {
        return candidate;
      }
    }

    return null;
  }

  Future<void> _cleanupInactiveModels({
    required Directory rootDir,
    required String activeDirectoryPath,
    required Set<String> keepFiles,
  }) async {
    for (final entity in rootDir.listSync(followLinks: false)) {
      final normalized = p.normalize(entity.path);
      if (entity is Directory &&
          normalized == p.normalize(activeDirectoryPath)) {
        continue;
      }

      if (entity is File && keepFiles.contains(p.basename(entity.path))) {
        continue;
      }

      try {
        await entity.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }

  void _emit(VoiceModelState state) {
    _currentState = state;
    if (!_statesController.isClosed) {
      _statesController.add(state);
    }
  }

  Future<void> _removeModelInternal() async {
    await (_bootstrapFuture ?? Future<void>.value());

    _cancelRequested = true;
    _activeHttpClient?.close();

    final prepareFuture = _activePrepareFuture;
    if (prepareFuture != null) {
      try {
        await prepareFuture;
      } catch (_) {
        // Ignore in-flight prepare failures during explicit remove.
      }
    }

    final rootDir = await _modelsDirectoryProvider();
    await _deleteAllModelArtifacts(rootDir);

    _installedBundle = null;
    final model = await _resolveModelSpec(_lastSelectedModelId);
    _emit(
      VoiceModelState.notInstalled(
        model: model,
        message: 'Offline voice model removed from this device.',
      ),
    );

    _cancelRequested = false;
  }

  Future<void> _cleanupModelArtifactsForSpec({
    required Directory rootDir,
    required VoiceModelSpec spec,
  }) async {
    final archiveFile = File(p.join(rootDir.path, spec.archiveFileName));
    final tempArchiveFile = File('${archiveFile.path}.part');
    final installDir = Directory(
      p.join(rootDir.path, spec.installDirectoryName),
    );

    if (await tempArchiveFile.exists()) {
      try {
        await tempArchiveFile.delete();
      } catch (_) {}
    }
    if (await archiveFile.exists()) {
      try {
        await archiveFile.delete();
      } catch (_) {}
    }
    if (await installDir.exists()) {
      try {
        await installDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _deleteAllModelArtifacts(Directory rootDir) async {
    if (!await rootDir.exists()) {
      return;
    }
    for (final entity in rootDir.listSync(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup for model artifacts.
      }
    }
  }

  static Future<Directory> _defaultModelsDirectoryProvider() async {
    final supportDir = await getApplicationSupportDirectory();
    return Directory(p.join(supportDir.path, 'voice_models'));
  }

  static Future<void> _defaultArchiveExtractor(
    String archivePath,
    String outputDir,
  ) async {
    await Isolate.run<void>(() {
      extractFileToDisk(archivePath, outputDir);
    });
  }
}

class _InstalledModelBundle {
  const _InstalledModelBundle({
    required this.bundleId,
    required this.version,
    required this.installDirectoryPath,
    required this.modelRootPath,
    required this.installedAt,
  });

  final String bundleId;
  final String version;
  final String installDirectoryPath;
  final String modelRootPath;
  final DateTime installedAt;

  String get bundleKey => '$bundleId::$version';

  InstalledVoiceModel asInstalledModel(VoiceModelSpec spec) {
    return InstalledVoiceModel(
      spec: spec,
      installDirectoryPath: installDirectoryPath,
      modelRootPath: modelRootPath,
      installedAt: installedAt,
    );
  }
}

class _VoiceModelDownloadCanceled implements Exception {
  const _VoiceModelDownloadCanceled();
}
