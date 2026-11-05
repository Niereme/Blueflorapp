import 'package:flutter/material.dart';

/// Tokens compartidos. Los widgets consumen colores semánticos del tema.
abstract final class FloraTokens {
  static const green = Color(0xFF4CAF7D);
  static const mint = Color(0xFFDDF5E5);
  static const cream = Color(0xFFFFF9EF);
  static const yellow = Color(0xFFFFD978);
  static const ink = Color(0xFF293D32);
  static const space = 8.0;
  static const padding = 16.0;
  static const section = 24.0;
  static const radius = 18.0;
  static const motion = Duration(milliseconds: 160);
}

enum FloraStatus { success, warning, error, neutral }

@immutable
class FloraStatusColors extends ThemeExtension<FloraStatusColors> {
  const FloraStatusColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
  });
  final Color success, onSuccess, warning, onWarning;

  /// Permite usar los componentes en vistas aisladas con un tema Material.
  static FloraStatusColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<FloraStatusColors>() ??
        FloraStatusColors(
          success: theme.colorScheme.primaryContainer,
          onSuccess: theme.colorScheme.onPrimaryContainer,
          warning: theme.colorScheme.tertiaryContainer,
          onWarning: theme.colorScheme.onTertiaryContainer,
        );
  }

  (Color, Color) pair(FloraStatus status, ColorScheme scheme) =>
      switch (status) {
        FloraStatus.success => (success, onSuccess),
        FloraStatus.warning => (warning, onWarning),
        FloraStatus.error => (scheme.errorContainer, scheme.onErrorContainer),
        FloraStatus.neutral => (
          scheme.surfaceContainerHighest,
          scheme.onSurface,
        ),
      };

  @override
  FloraStatusColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
  }) => FloraStatusColors(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
  );

  @override
  FloraStatusColors lerp(covariant FloraStatusColors? other, double t) =>
      other == null
      ? this
      : FloraStatusColors(
          success: Color.lerp(success, other.success, t)!,
          onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
          onWarning: Color.lerp(onWarning, other.onWarning, t)!,
        );
}

abstract final class BluefloraTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: FloraTokens.green,
          brightness: brightness,
        ).copyWith(
          primary: dark ? const Color(0xFF8BD5AC) : const Color(0xFF246342),
          onPrimary: dark ? const Color(0xFF103822) : Colors.white,
          primaryContainer: dark ? const Color(0xFF234C36) : FloraTokens.mint,
          onPrimaryContainer: dark ? FloraTokens.mint : FloraTokens.ink,
          surface: dark ? const Color(0xFF141D18) : FloraTokens.cream,
          onSurface: dark ? const Color(0xFFE1EADF) : FloraTokens.ink,
        );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(FloraTokens.radius),
    );
    final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      shape: WidgetStatePropertyAll(shape),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: base.textTheme.copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.45),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
      ),
      cardTheme: CardThemeData(
        shape: shape,
        elevation: 1,
        shadowColor: scheme.shadow.withValues(alpha: 0.12),
        color: scheme.surfaceContainerLow,
        margin: const EdgeInsets.all(FloraTokens.space),
      ),
      filledButtonTheme: FilledButtonThemeData(style: button),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: button.copyWith(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.disabled) ? null : scheme.primary,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.disabled) ? null : scheme.onPrimary,
          ),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(style: button),
      textButtonTheme: TextButtonThemeData(style: button),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(16),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      extensions: [
        FloraStatusColors(
          success: dark ? const Color(0xFF234C36) : FloraTokens.mint,
          onSuccess: dark ? FloraTokens.mint : FloraTokens.ink,
          warning: dark ? const Color(0xFF514219) : FloraTokens.yellow,
          onWarning: dark ? const Color(0xFFFFE6A3) : FloraTokens.ink,
        ),
      ],
    );
  }
}
