import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadThemeAsync();
    return ThemeMode.light;
  }

  Future<void> _loadThemeAsync() async {
    try {
      final mode = await loadThemeModeFromDisk();
      state = mode;
    } catch (_) {}
  }

  static Future<ThemeMode> loadThemeModeFromDisk() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/theme_settings.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content) as Map<String, dynamic>;
        final themeStr = data['themeMode'] as String?;
        if (themeStr != null) {
          return ThemeMode.values.firstWhere(
            (e) => e.toString() == themeStr,
            orElse: () => ThemeMode.light,
          );
        }
      }
    } catch (_) {}
    return ThemeMode.light;
  }

  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/theme_settings.json');
  }

  Future<void> _saveTheme(ThemeMode mode) async {
    try {
      final file = await _localFile;
      final jsonString = json.encode({'themeMode': mode.toString()});
      await file.writeAsString(jsonString);
    } catch (_) {}
  }

  void toggleTheme() {
    final newMode = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    state = newMode;
    _saveTheme(newMode);
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    _saveTheme(mode);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);
