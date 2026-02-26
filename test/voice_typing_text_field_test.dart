import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/core/models/app_data.dart';
import 'package:glitch/core/services/voice_typing_service.dart';
import 'package:glitch/core/storage/local_store.dart';
import 'package:glitch/core/theme/app_theme.dart';
import 'package:glitch/features/backup/passphrase_prompt.dart';
import 'package:glitch/features/projects/project_creation_sheet.dart';
import 'package:glitch/features/tasks/task_creation_sheet.dart';
import 'package:glitch/shared/state/app_controller.dart';
import 'package:glitch/shared/widgets/voice_typing_text_field.dart';

class _MemoryStore implements LocalStore {
  _MemoryStore({AppData? initialData}) : _data = initialData ?? AppData.empty();

  AppData _data;

  @override
  Future<AppData> load() async => _data;

  @override
  Future<void> overwrite(AppData data) async {
    _data = data;
  }

  @override
  Future<void> save(AppData data) async {
    _data = data;
  }
}

class _FakeVoiceTypingService implements VoiceTypingService {
  final StreamController<VoiceTypingEvent> _events =
      StreamController<VoiceTypingEvent>.broadcast();

  VoiceTypingStartResult onDeviceResult = const VoiceTypingStartResult(
    started: true,
    usingOnDevice: true,
  );
  VoiceTypingStartResult fallbackResult = const VoiceTypingStartResult(
    started: true,
    usingOnDevice: false,
  );

  int onDeviceStartCalls = 0;
  int fallbackStartCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  @override
  Stream<VoiceTypingEvent> get events => _events.stream;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.stopped));
  }

  void emitPartial(String text) {
    _events.add(VoiceTypingEventPartial(text));
  }

  void emitFinal(String text) {
    _events.add(VoiceTypingEventFinal(text));
  }

  void emitError(
    String message, {
    bool supportsFallbackHint = false,
    VoiceTypingErrorReason reason = VoiceTypingErrorReason.unknown,
  }) {
    _events.add(
      VoiceTypingEventError(
        message,
        supportsFallbackHint: supportsFallbackHint,
        reason: reason,
      ),
    );
  }

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
      onDeviceStartCalls += 1;
      if (onDeviceResult.started) {
        _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.listening));
      }
      return onDeviceResult;
    }

    fallbackStartCalls += 1;
    if (fallbackResult.started) {
      _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.listening));
    }
    return fallbackResult;
  }

  @override
  Future<void> stopListening() async {
    stopCalls += 1;
    _events.add(const VoiceTypingEventStatus(VoiceTypingStatus.stopped));
  }
}

Widget _buildVoiceTypingHarness({
  required _FakeVoiceTypingService service,
  required TextEditingController controller,
  required FocusNode focusNode,
  bool allowNetworkFallback = false,
  Future<void> Function(bool value)? onAllowNetworkFallbackChanged,
}) {
  return ProviderScope(
    overrides: <Override>[
      voiceTypingServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(
      theme: AppTheme.light(highContrast: false),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: VoiceTypingTextField(
            controller: controller,
            focusNode: focusNode,
            voiceTypingEnabled: true,
            allowNetworkFallback: allowNetworkFallback,
            onAllowNetworkFallbackChanged: onAllowNetworkFallbackChanged,
            platformSupportOverride: true,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
        ),
      ),
    ),
  );
}

Finder _textFieldByLabel(String label) {
  return find.byWidgetPredicate((widget) {
    return widget is TextField && widget.decoration?.labelText == label;
  });
}

void main() {
  testWidgets('voice mic appears only when field is focused', (tester) async {
    final service = _FakeVoiceTypingService();
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _buildVoiceTypingHarness(
        service: service,
        controller: controller,
        focusNode: focusNode,
      ),
    );

    expect(find.byIcon(Icons.mic_none), findsNothing);

    await tester.tap(_textFieldByLabel('Title'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.mic_none), findsOneWidget);

    focusNode.unfocus();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.mic_none), findsNothing);
  });

  testWidgets('mic tap streams partial transcript and stops on second tap', (
    tester,
  ) async {
    final service = _FakeVoiceTypingService();
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _buildVoiceTypingHarness(
        service: service,
        controller: controller,
        focusNode: focusNode,
      ),
    );

    await tester.tap(_textFieldByLabel('Title'));
    await tester.pumpAndSettle();

    final mic = find.byIcon(Icons.mic_none);
    await tester.tap(mic);
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.onDeviceStartCalls, 1);
    expect(find.byIcon(Icons.mic), findsOneWidget);

    service.emitPartial('Buy groceries tomorrow');
    await tester.pump();
    expect(controller.text, 'Buy groceries tomorrow');

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pumpAndSettle();
    expect(service.stopCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('fallback consent path retries speech and persists preference', (
    tester,
  ) async {
    final service = _FakeVoiceTypingService();
    service.onDeviceResult = const VoiceTypingStartResult(
      started: false,
      usingOnDevice: false,
      supportsFallbackHint: true,
      message: 'On-device unavailable',
    );
    service.fallbackResult = const VoiceTypingStartResult(
      started: true,
      usingOnDevice: false,
    );

    final controller = TextEditingController();
    final focusNode = FocusNode();
    bool persistedFallbackConsent = false;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _buildVoiceTypingHarness(
        service: service,
        controller: controller,
        focusNode: focusNode,
        allowNetworkFallback: false,
        onAllowNetworkFallbackChanged: (value) async {
          persistedFallbackConsent = value;
        },
      ),
    );

    await tester.tap(_textFieldByLabel('Title'));
    await tester.pumpAndSettle();

    final mic = find.byIcon(Icons.mic_none);
    await tester.tap(mic);
    await tester.pumpAndSettle();

    expect(find.text('Fallback speech mode?'), findsOneWidget);

    await tester.tap(find.text('Allow fallback'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(persistedFallbackConsent, isTrue);
    expect(service.onDeviceStartCalls, 1);
    expect(service.fallbackStartCalls, 1);
  });

  testWidgets('voice typing failures surface inline and in snackbar', (
    tester,
  ) async {
    final service = _FakeVoiceTypingService();
    service.onDeviceResult = const VoiceTypingStartResult(
      started: false,
      usingOnDevice: false,
      message: 'Microphone permission is required for voice typing.',
    );
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _buildVoiceTypingHarness(
        service: service,
        controller: controller,
        focusNode: focusNode,
      ),
    );

    await tester.tap(_textFieldByLabel('Title'));
    await tester.pumpAndSettle();

    final mic = find.byIcon(Icons.mic_none);
    await tester.tap(mic);
    await tester.pumpAndSettle();

    expect(
      find.text('Microphone permission is required for voice typing.'),
      findsWidgets,
    );
  });

  testWidgets(
    'runtime on-device error retries fallback once when fallback is allowed',
    (tester) async {
      final service = _FakeVoiceTypingService();
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _buildVoiceTypingHarness(
          service: service,
          controller: controller,
          focusNode: focusNode,
          allowNetworkFallback: true,
        ),
      );

      await tester.tap(_textFieldByLabel('Title'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_none));
      await tester.pump(const Duration(milliseconds: 300));
      expect(service.onDeviceStartCalls, 1);

      service.emitError(
        'Speech language is unavailable on this device.',
        supportsFallbackHint: true,
        reason: VoiceTypingErrorReason.languageUnavailable,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(service.stopCalls, greaterThanOrEqualTo(1));
      expect(service.fallbackStartCalls, 1);

      service.emitError(
        'Speech language is unavailable on this device.',
        supportsFallbackHint: true,
        reason: VoiceTypingErrorReason.languageUnavailable,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(service.fallbackStartCalls, 1);
    },
  );

  testWidgets('recognizer unavailable shows keyboard dictation guidance', (
    tester,
  ) async {
    final service = _FakeVoiceTypingService();
    service.onDeviceResult = const VoiceTypingStartResult(
      started: false,
      usingOnDevice: false,
      failure: VoiceTypingStartFailure.initializeFailed,
      message: 'Speech recognition service is unavailable on this device.',
      errorReason: VoiceTypingErrorReason.recognizerUnavailable,
    );
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _buildVoiceTypingHarness(
        service: service,
        controller: controller,
        focusNode: focusNode,
      ),
    );

    await tester.tap(_textFieldByLabel('Title'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pumpAndSettle();

    expect(find.text('Use keyboard voice typing'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'task creation enables voice wrapper for title and description only',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            localStoreProvider.overrideWithValue(_MemoryStore()),
            voiceTypingServiceProvider.overrideWithValue(
              _FakeVoiceTypingService(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(highContrast: false),
            home: const Scaffold(body: TaskCreationSheet()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final titleField = _textFieldByLabel('Title');
      final descriptionField = _textFieldByLabel('Description');
      final estimateField = _textFieldByLabel('Estimated minutes');

      expect(
        find.ancestor(
          of: titleField,
          matching: find.byType(VoiceTypingTextField),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: descriptionField,
          matching: find.byType(VoiceTypingTextField),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: estimateField,
          matching: find.byType(VoiceTypingTextField),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('project creation enables voice wrapper on both text fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localStoreProvider.overrideWithValue(_MemoryStore()),
          voiceTypingServiceProvider.overrideWithValue(
            _FakeVoiceTypingService(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(highContrast: false),
          home: const Scaffold(body: ProjectCreationSheet()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final nameField = _textFieldByLabel('Project name');
    final descriptionField = _textFieldByLabel('Description');

    expect(
      find.ancestor(of: nameField, matching: find.byType(VoiceTypingTextField)),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: descriptionField,
        matching: find.byType(VoiceTypingTextField),
      ),
      findsOneWidget,
    );
  });

  testWidgets('backup passphrase dialog excludes voice typing wrapper', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(highContrast: false),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () {
                  unawaited(
                    showBackupPassphraseDialog(
                      context: context,
                      title: 'Set passphrase',
                      description: 'Secure your backup',
                      confirmPassphrase: true,
                    ),
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(VoiceTypingTextField), findsNothing);
  });
}
