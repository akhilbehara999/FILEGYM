import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class HistoryItem {
  final String id;
  final String fileName;
  final String sourceFormat;
  final String targetFormat;
  final String sizeString;
  final DateTime timestamp;
  final String sourcePath;
  final String outputPath;

  HistoryItem({
    required this.id,
    required this.fileName,
    required this.sourceFormat,
    required this.targetFormat,
    required this.sizeString,
    required this.timestamp,
    required this.sourcePath,
    required this.outputPath,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fileName': fileName,
      'sourceFormat': sourceFormat,
      'targetFormat': targetFormat,
      'sizeString': sizeString,
      'timestamp': timestamp.toIso8601String(),
      'sourcePath': sourcePath,
      'outputPath': outputPath,
    };
  }

  factory HistoryItem.fromMap(Map<String, dynamic> map) {
    return HistoryItem(
      id: map['id'] ?? '',
      fileName: map['fileName'] ?? '',
      sourceFormat: map['sourceFormat'] ?? '',
      targetFormat: map['targetFormat'] ?? '',
      sizeString: map['sizeString'] ?? '',
      timestamp: DateTime.parse(map['timestamp'] ?? DateTime.now().toIso8601String()),
      sourcePath: map['sourcePath'] ?? '',
      outputPath: map['outputPath'] ?? '',
    );
  }
}

class HistoryNotifier extends Notifier<List<HistoryItem>> {
  @override
  List<HistoryItem> build() {
    _loadHistory();
    return [];
  }

  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/conversion_history.json');
  }

  Future<void> _loadHistory() async {
    try {
      final file = await _localFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        state = jsonList.map((e) => HistoryItem.fromMap(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> addHistoryItem({
    required String fileName,
    required String sourceFormat,
    required String targetFormat,
    required String sizeString,
    required String sourcePath,
    required String outputPath,
  }) async {
    final newItem = HistoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: fileName,
      sourceFormat: sourceFormat,
      targetFormat: targetFormat,
      sizeString: sizeString,
      timestamp: DateTime.now(),
      sourcePath: sourcePath,
      outputPath: outputPath,
    );

    state = [newItem, ...state];
    await _saveHistory();
  }

  Future<void> deleteHistoryItem(String id) async {
    state = state.where((item) => item.id != id).toList();
    await _saveHistory();
  }

  Future<void> clearHistory() async {
    state = [];
    await _saveHistory();
  }

  Future<void> _saveHistory() async {
    try {
      final file = await _localFile;
      final jsonString = json.encode(state.map((e) => e.toMap()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
      // Handle error
    }
  }
}

final historyProvider = NotifierProvider<HistoryNotifier, List<HistoryItem>>(HistoryNotifier.new);
