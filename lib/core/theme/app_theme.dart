import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_preferences.dart';

@immutable
class GlitchPalette extends ThemeExtension<GlitchPalette> {
  const GlitchPalette({
    required this.amoled,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceStroke,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.accentSecondary,
    required this.warning,
    required this.pillChore,
    required this.pillHabit,
    required this.pillMilestone,
    required this.pillText,
  });

  final Color amoled;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceStroke;
  final Color textPrimary;
  final Color textMuted;
  final Color accent;
  final Color accentSecondary;
  final Color warning;
  final Color pillChore;
  final Color pillHabit;
  final Color pillMilestone;
  final Color pillText;

  @override
  GlitchPalette copyWith({
    Color? amoled,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceStroke,
    Color? textPrimary,
    Color? textMuted,
    Color? accent,
    Color? accentSecondary,
    Color? warning,
    Color? pillChore,
    Color? pillHabit,
    Color? pillMilestone,
    Color? pillText,
  }) {
    return GlitchPalette(
      amoled: amoled ?? this.amoled,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceStroke: surfaceStroke ?? this.surfaceStroke,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      warning: warning ?? this.warning,
      pillChore: pillChore ?? this.pillChore,
      pillHabit: pillHabit ?? this.pillHabit,
      pillMilestone: pillMilestone ?? this.pillMilestone,
      pillText: pillText ?? this.pillText,
    );
  }

  @override
  GlitchPalette lerp(ThemeExtension<GlitchPalette>? other, double t) {
    if (other is! GlitchPalette) {
      return this;
    }

    return GlitchPalette(
      amoled: Color.lerp(amoled, other.amoled, t) ?? amoled,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceRaised:
          Color.lerp(surfaceRaised, other.surfaceRaised, t) ?? surfaceRaised,
      surfaceStroke:
          Color.lerp(surfaceStroke, other.surfaceStroke, t) ?? surfaceStroke,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      accentSecondary:
          Color.lerp(accentSecondary, other.accentSecondary, t) ??
          accentSecondary,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      pillChore: Color.lerp(pillChore, other.pillChore, t) ?? pillChore,
      pillHabit: Color.lerp(pillHabit, other.pillHabit, t) ?? pillHabit,
      pillMilestone:
          Color.lerp(pillMilestone, other.pillMilestone, t) ?? pillMilestone,
      pillText: Color.lerp(pillText, other.pillText, t) ?? pillText,
    );
  }
}

extension GlitchThemeX on BuildContext {
  GlitchPalette get glitchPalette {
    final extension = Theme.of(this).extension<GlitchPalette>();
    assert(
      extension != null,
      'GlitchPalette extension is missing on ThemeData.',
    );
    return extension!;
  }
}

class AppTheme {
  static ThemeData light({required bool highContrast}) {
    final palette = GlitchPalette(
      amoled: const Color(0xFFF5F7F7),
      surface: const Color(0xFFFFFFFF),
      surfaceRaised: const Color(0xFFEDF2F2),
      surfaceStroke: const Color(0xFFD9E2E0),
      textPrimary: const Color(0xFF102020),
      textMuted: const Color(0xFF4E6361),
      accent: highContrast ? const Color(0xFF006E54) : const Color(0xFF008E6B),
      accentSecondary: highContrast
          ? const Color(0xFF005F75)
          : const Color(0xFF0A7A92),
      warning: const Color(0xFFB67900),
      pillChore: const Color(0xFFD7EFFA),
      pillHabit: const Color(0xFFD1F7E8),
      pillMilestone: const Color(0xFFE4E1FF),
      pillText: const Color(0xFF122221),
    );

    return _buildTheme(brightness: Brightness.light, palette: palette);
  }

  static ThemeData dark({
    required bool highContrast,
    required DarkThemeStyle style,
  }) {
    final useAmoled = style == DarkThemeStyle.amoled;

    final palette = GlitchPalette(
      amoled: useAmoled ? const Color(0xFF000000) : const Color(0xFF0B0E11),
      surface: useAmoled ? const Color(0xFF080808) : const Color(0xFF141A20),
      surfaceRaised: useAmoled
          ? const Color(0xFF111111)
          : const Color(0xFF1A222A),
      surfaceStroke: useAmoled
          ? const Color(0xFF202020)
          : const Color(0xFF2A333D),
      textPrimary: highContrast
          ? const Color(0xFFFFFFFF)
          : const Color(0xFFE8F7F1),
      textMuted: highContrast
          ? const Color(0xFFC6D1CD)
          : const Color(0xFF95A39D),
      accent: highContrast ? const Color(0xFF00F2B3) : const Color(0xFF00D89B),
      accentSecondary: highContrast
          ? const Color(0xFF6BEAFF)
          : (useAmoled ? const Color(0xFF33D8FB) : const Color(0xFF57CCFF)),
      warning: const Color(0xFFFFB04D),
      pillChore: const Color(0xFF153443),
      pillHabit: const Color(0xFF0E362B),
      pillMilestone: const Color(0xFF2A2351),
      pillText: const Color(0xFFE7FFFA),
    );

    return _buildTheme(brightness: Brightness.dark, palette: palette);
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required GlitchPalette palette,
  }) {
    final textTheme = GoogleFonts.spaceGroteskTextTheme().apply(
      bodyColor: palette.textPrimary,
      displayColor: palette.textPrimary,
    );

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: palette.surfaceStroke),
    );

    return ThemeData(
      useMaterial3: false,
      brightness: brightness,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: palette.amoled,
      canvasColor: palette.amoled,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: palette.accent,
        onPrimary: palette.amoled,
        secondary: palette.accentSecondary,
        onSecondary: palette.amoled,
        error: palette.warning,
        onError: palette.amoled,
        surface: palette.surface,
        onSurface: palette.textPrimary,
      ),
      extensions: <ThemeExtension<dynamic>>[palette],
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        labelLarge: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.surfaceStroke,
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.amoled,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: palette.surfaceStroke),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: palette.textPrimary,
        iconColor: palette.textMuted,
        tileColor: Colors.transparent,
        selectedColor: palette.textPrimary,
        selectedTileColor: palette.surfaceRaised,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        hintStyle: TextStyle(color: palette.textMuted),
        labelStyle: TextStyle(color: palette.textMuted),
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: palette.accent, width: 1.4),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: palette.warning, width: 1.4),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(color: palette.warning, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll<double>(0),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return palette.surfaceRaised;
            }
            return palette.accent;
          }),
          foregroundColor: WidgetStatePropertyAll<Color>(palette.amoled),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll<double>(0),
          backgroundColor: WidgetStatePropertyAll<Color>(palette.accent),
          foregroundColor: WidgetStatePropertyAll<Color>(palette.amoled),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: palette.surfaceStroke),
          ),
          foregroundColor: WidgetStatePropertyAll<Color>(palette.textPrimary),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll<Color>(palette.accent),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        backgroundColor: palette.accent,
        foregroundColor: palette.amoled,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        circularTrackColor: palette.surfaceRaised,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accent,
        inactiveTrackColor: palette.surfaceRaised,
        thumbColor: palette.accent,
        overlayColor: palette.accent.withValues(alpha: 0.2),
        valueIndicatorColor: palette.surfaceRaised,
        valueIndicatorTextStyle: TextStyle(color: palette.textPrimary),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.accent.withValues(alpha: 0.45);
          }
          return palette.surfaceRaised;
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.accent;
          }
          return palette.textMuted;
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.amoled,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceRaised,
        contentTextStyle: TextStyle(color: palette.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
