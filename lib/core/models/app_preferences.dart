import 'package:flutter/foundation.dart';

enum DarkThemeStyle { amoled, black }

extension DarkThemeStyleLabel on DarkThemeStyle {
  String get label {
    switch (this) {
      case DarkThemeStyle.amoled:
        return 'AMOLED';
      case DarkThemeStyle.black:
        return 'Black';
    }
  }

  static DarkThemeStyle fromStorage(String? value) {
    return DarkThemeStyle.values.firstWhere(
      (item) => item.name == value,
      orElse: () => DarkThemeStyle.amoled,
    );
  }
}

@immutable
class AppPreferences {
  const AppPreferences({
    required this.useDarkMode,
    required this.highContrast,
    required this.textScale,
    required this.darkThemeStyle,
  });

  factory AppPreferences.defaults() {
    return const AppPreferences(
      useDarkMode: true,
      highContrast: false,
      textScale: 1,
      darkThemeStyle: DarkThemeStyle.amoled,
    );
  }

  final bool useDarkMode;
  final bool highContrast;
  final double textScale;
  final DarkThemeStyle darkThemeStyle;

  AppPreferences copyWith({
    bool? useDarkMode,
    bool? highContrast,
    double? textScale,
    DarkThemeStyle? darkThemeStyle,
  }) {
    return AppPreferences(
      useDarkMode: useDarkMode ?? this.useDarkMode,
      highContrast: highContrast ?? this.highContrast,
      textScale: textScale ?? this.textScale,
      darkThemeStyle: darkThemeStyle ?? this.darkThemeStyle,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'useDarkMode': useDarkMode,
      'highContrast': highContrast,
      'textScale': textScale,
      'darkThemeStyle': darkThemeStyle.name,
    };
  }

  factory AppPreferences.fromJson(Map<String, dynamic> json) {
    return AppPreferences(
      useDarkMode: json['useDarkMode'] as bool? ?? true,
      highContrast: json['highContrast'] as bool? ?? false,
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1,
      darkThemeStyle: DarkThemeStyleLabel.fromStorage(
        json['darkThemeStyle'] as String?,
      ),
    );
  }
}
