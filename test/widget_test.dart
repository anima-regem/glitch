import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glitch/core/models/app_data.dart';
import 'package:glitch/core/storage/local_store.dart';
import 'package:glitch/main.dart';
import 'package:glitch/shared/state/app_controller.dart';
import 'package:glitch/shared/widgets/glitch_logo.dart';

class _MemoryStore implements LocalStore {
  AppData _data = AppData.empty();

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

void main() {
  testWidgets('splash renders glitch branding', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localStoreProvider.overrideWithValue(_MemoryStore()),
        ],
        child: const GlitchApp(),
      ),
    );

    expect(find.byType(GlitchLogo), findsOneWidget);
    expect(find.text('single-focus day tracking'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1900));
  });
}
