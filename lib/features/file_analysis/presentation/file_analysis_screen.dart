import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../data/file_detection_service.dart';

class FileAnalysisScreen extends ConsumerStatefulWidget {
  final String filePath;
  
  const FileAnalysisScreen({super.key, required this.filePath});

  @override
  ConsumerState<FileAnalysisScreen> createState() => _FileAnalysisScreenState();
}

class _FileAnalysisScreenState extends ConsumerState<FileAnalysisScreen> {
  int _analysisStep = 0;
  DetectedFile? _detectedFile;
  
  final List<String> _steps = [
    'Analyzing file...',
    'Detecting format...',
    'Reading metadata...',
    'Ready'
  ];

  @override
  void initState() {
    super.initState();
    _startAnalysis();
  }

  Future<void> _startAnalysis() async {
    for (int i = 0; i < 3; i++) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() {
          _analysisStep = i + 1;
        });
      }
    }
    
    final detectionService = ref.read(fileDetectionServiceProvider);
    final file = await detectionService.analyzeFile(widget.filePath);
    
    if (mounted) {
      setState(() {
        _detectedFile = file;
        _analysisStep = 3; // Ready
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Analysis'),
        centerTitle: true,
      ),
      body: _detectedFile == null ? _buildLoadingState() : _buildResultState(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator()
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(duration: 1000.ms),
          ),
          const SizedBox(height: 32),
          Text(
            _steps[_analysisStep],
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ).animate(key: ValueKey(_analysisStep)).fadeIn().slideY(begin: 0.5, end: 0),
        ],
      ),
    );
  }

  Widget _buildResultState() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFileCard().animate().fadeIn().slideY(begin: 0.2, end: 0),
            const SizedBox(height: 32),
            Text(
              'Supported Conversions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ).animate().fadeIn(delay: 200.ms).slideX(),
            const SizedBox(height: 16),
            _buildConversionOptions().animate().fadeIn(delay: 300.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildFileCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          width: 2,
        ),
        boxShadow: Theme.of(context).brightness == Brightness.light
            ? [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 8))]
            : null,
      ),
      child: Column(
        children: [
          Icon(LucideIcons.fileCheck2, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            _detectedFile!.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildFileStat(LucideIcons.tag, 'Detected Type', _detectedFile!.detectedType),
              _buildFileStat(LucideIcons.hardDrive, 'Size', _formatBytes(_detectedFile!.sizeBytes)),
              _buildFileStat(LucideIcons.percent, 'Confidence', '${(_detectedFile!.confidence * 100).toInt()}%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFileStat(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildConversionOptions() {
    // Dummy targets based on type
    List<Map<String, dynamic>> targets = _getTargetsForType(_detectedFile!.detectedType);
    
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: targets.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final target = targets[index];
        return InkWell(
          onTap: () {
            context.push('/conversion', extra: {
              'sourceFilePath': _detectedFile!.path,
              'sourceFormat': _detectedFile!.detectedType,
              'targetFormat': target['format'],
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(16),
              border: Theme.of(context).brightness == Brightness.dark
                  ? Border.all(color: Colors.white.withOpacity(0.05))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(target['icon'] as IconData, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        target['format'] as String,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        target['description'] as String,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    target['speed'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _getTargetsForType(String type) {
    if (type.contains('Image')) {
      return [
        {'format': 'PNG', 'description': 'Lossless image format', 'speed': 'Fast', 'icon': LucideIcons.image},
        {'format': 'WEBP', 'description': 'Modern web optimized', 'speed': 'Fast', 'icon': LucideIcons.image},
        {'format': 'PDF', 'description': 'Document format', 'speed': 'Medium', 'icon': LucideIcons.fileText},
      ];
    } else if (type.contains('PDF')) {
      return [
        {'format': 'Word', 'description': 'Editable document', 'speed': 'Slow', 'icon': LucideIcons.fileText},
        {'format': 'Images', 'description': 'Extract pages to JPG', 'speed': 'Medium', 'icon': LucideIcons.image},
        {'format': 'Text', 'description': 'Extract raw text', 'speed': 'Fast', 'icon': LucideIcons.fileType2},
      ];
    } else if (type.contains('Excel') || type.contains('CSV')) {
      return [
        {'format': 'JSON', 'description': 'Data interchange format', 'speed': 'Fast', 'icon': LucideIcons.fileCode},
        {'format': 'CSV', 'description': 'Comma separated values', 'speed': 'Fast', 'icon': LucideIcons.table},
        {'format': 'PDF', 'description': 'Printable document', 'speed': 'Medium', 'icon': LucideIcons.fileText},
      ];
    }
    
    // Default fallback
    return [
      {'format': 'ZIP', 'description': 'Compress file', 'speed': 'Fast', 'icon': LucideIcons.archive},
    ];
  }
}
