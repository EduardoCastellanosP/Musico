import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vallenato_connect/core/theme/app_theme.dart';

void main() {
  test('AppTheme builds distinct light and dark themes', () {
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.dark.brightness, Brightness.dark);
    expect(AppTheme.dark.scaffoldBackgroundColor, AppColors.darkBackground);
    expect(AppTheme.light.scaffoldBackgroundColor, AppColors.lightBackground);
  });
}
