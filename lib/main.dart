import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/app_preferences.dart';
import 'core/services/reminder_service.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'shared/state/app_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: <Override>[
        reminderServiceProvider.overrideWithValue(LocalReminderService()),
      ],
      child: const GlitchApp(),
    ),
  );
}

class GlitchApp extends ConsumerWidget {
  const GlitchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appControllerProvider);
    final preferences =
        appState.valueOrNull?.preferences ?? AppPreferences.defaults();

    return MaterialApp(
      title: 'Glitch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(highContrast: preferences.highContrast),
      darkTheme: AppTheme.dark(
        highContrast: preferences.highContrast,
        style: preferences.darkThemeStyle,
      ),
      themeMode: preferences.useDarkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final systemScale = mediaQuery.textScaler.scale(1);
        final composedScale = (systemScale * preferences.textScale).clamp(
          0.8,
          3.0,
        );
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(composedScale.toDouble()),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SplashScreen(),
    );
  }
}
