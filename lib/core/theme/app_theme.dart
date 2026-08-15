import 'package:flutter/material.dart';

/// Central color palette for VallenatoConnect.
///
/// Keeping raw values here (instead of scattering hex codes across widgets)
/// is what lets [AppTheme.light] / [AppTheme.dark] and any widget stay in
/// sync with the approved design.
abstract final class AppColors {
  static const Color accent = Color(0xFFD4AF37);

  static const Color darkBackground = Color(0xFF121212);
  static const Color darkCard = Color(0xFF1E1E1E);
  static const Color darkInput = Color(0xFF2A2A2B);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFA1A1AA);

  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightInput = Color(0xFFF1F5F9);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF64748B);

  /// Shadow used under light-mode cards: blur 24, offset (0, 4), black @ 5%.
  static List<BoxShadow> get lightCardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 24,
      offset: const Offset(0, 4),
    ),
  ];
}

/// Builds the light/dark [ThemeData] pairs used by [MaterialApp.theme] and
/// [MaterialApp.darkTheme]. Screens read semantic colors off
/// [Theme.of(context).colorScheme] / [TextTheme] rather than [AppColors]
/// directly, so the same widget tree renders correctly in both modes.
abstract final class AppTheme {
  static ThemeData get light => _base(
    brightness: Brightness.light,
    scaffoldBackground: AppColors.lightBackground,
    cardColor: AppColors.lightCard,
    inputFill: AppColors.lightInput,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
  );

  static ThemeData get dark => _base(
    brightness: Brightness.dark,
    scaffoldBackground: AppColors.darkBackground,
    cardColor: AppColors.darkCard,
    inputFill: AppColors.darkInput,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
  );

  static ThemeData _base({
    required Brightness brightness,
    required Color scaffoldBackground,
    required Color cardColor,
    required Color inputFill,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: brightness,
      primary: AppColors.accent,
      surface: cardColor,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      cardColor: cardColor,
      dividerColor: textSecondary.withValues(alpha: 0.2),
      textTheme: ThemeData(
        brightness: brightness,
      ).textTheme.apply(bodyColor: textPrimary, displayColor: textPrimary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        hintStyle: TextStyle(color: textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      extensions: [
        AppThemeExtension(
          cardColor: cardColor,
          inputFill: inputFill,
          textSecondary: textSecondary,
        ),
      ],
    );
  }
}

/// Extra semantic colors not covered by [ColorScheme], exposed through
/// `Theme.of(context).extension<AppThemeExtension>()`.
@immutable
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  const AppThemeExtension({
    required this.cardColor,
    required this.inputFill,
    required this.textSecondary,
  });

  final Color cardColor;
  final Color inputFill;
  final Color textSecondary;

  @override
  AppThemeExtension copyWith({
    Color? cardColor,
    Color? inputFill,
    Color? textSecondary,
  }) {
    return AppThemeExtension(
      cardColor: cardColor ?? this.cardColor,
      inputFill: inputFill ?? this.inputFill,
      textSecondary: textSecondary ?? this.textSecondary,
    );
  }

  @override
  AppThemeExtension lerp(AppThemeExtension? other, double t) {
    if (other == null) return this;
    return AppThemeExtension(
      cardColor: Color.lerp(cardColor, other.cardColor, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
    );
  }
}
