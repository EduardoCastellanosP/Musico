import 'package:flutter/material.dart';

/// App-wide theme mode controller.
///
/// A single [ValueNotifier] is enough here: only [MyApp] listens to it via
/// [ValueListenableBuilder], so a full state-management package would be
/// overkill for toggling light/dark.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(
  ThemeMode.dark,
);

void toggleThemeMode() {
  themeModeNotifier.value = themeModeNotifier.value == ThemeMode.dark
      ? ThemeMode.light
      : ThemeMode.dark;
}
