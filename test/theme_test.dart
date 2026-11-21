import 'package:airport_mobile/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('system theme follows the platform, explicit choices do not', () {
    expect(resolveThemeMode(ThemeMode.system, Brightness.dark), ThemeMode.dark);
    expect(
      resolveThemeMode(ThemeMode.system, Brightness.light),
      ThemeMode.light,
    );
    expect(resolveThemeMode(ThemeMode.light, Brightness.dark), ThemeMode.light);
    expect(resolveThemeMode(ThemeMode.dark, Brightness.light), ThemeMode.dark);
  });
}
