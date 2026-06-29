import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;

import '../../../core/intelligence/analysis_result.dart';
import '../../../core/intelligence/file_intelligence_engine.dart';

class AnalysisScreen extends StatefulWidget {
  final String filePath;

  const AnalysisScreen({super.key, required this.filePath});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> with SingleTickerProviderStateMixin {
  bool _isAnalyzing = true;
  AnalysisResult? _result;
  String? _error;
  late AnimationController _scannerController;

  @override
  void initState() {
    super.initState();
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    _runIntelligenceEngine();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _runIntelligenceEngine() async {
    try {
      final result = await FileIntelligenceEngine.analyze(widget.filePath);
      if (mounted) {
        setState(() {
          _result = result;
          _isAnalyzing = false;
        });
        _scannerController.stop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to analyze file: $e';
          _isAnalyzing = false;
        });
        _scannerController.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090A0F) : const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: isDark ? Colors.white : const Color(0xFF111116)),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'File Analysis',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF111116), 
            fontWeight: FontWeight.bold
          ),
        ),
      ),
      body: _isAnalyzing
          ? _buildScanningState(isDark)
          : _error != null
              ? _buildErrorState(isDark)
              : _buildResultState(isDark),
    );
  }

  Widget _buildScanningState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF5C00).withOpacity(0.1),
                ),
              ),
              AnimatedBuilder(
                animation: _scannerController,
                builder: (_, child) {
                  return Transform.rotate(
                    angle: _scannerController.value * 2 * math.pi,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          colors: [
                            const Color(0xFFFF5C00).withOpacity(0.0),
                            const Color(0xFFFF5C00).withOpacity(0.5),
                          ],
                          stops: const [0.5, 1.0],
                        ),
                      ),
                    ),
                  );
                },
              ),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141622) : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.fileSearch, color: Color(0xFFFF5C00), size: 36),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'Analyzing File...',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF111116),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Extracting magic bytes & metadata',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF70727D),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.alertCircle, color: Color(0xFFFF3D00), size: 64),
            const SizedBox(height: 16),
            Text(
              'Analysis Failed',
              style: TextStyle(
                fontSize: 20, 
                fontWeight: FontWeight.bold, 
                color: isDark ? Colors.white : const Color(0xFF111116)
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error occurred.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF70727D)),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5C00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Go Back'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildResultState(bool isDark) {
    final result = _result!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File Identity Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: isDark ? const Color(0xFF222431) : const Color(0xFFEDEDF2), width: 1.0),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5C00).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.fileCheck2, color: Color(0xFFFF5C00), size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.fileName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold, 
                          fontSize: 16, 
                          color: isDark ? Colors.white : const Color(0xFF111116)
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Size: ${result.fileSize}',
                        style: const TextStyle(color: Color(0xFF70727D), fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Detection Results
          Text(
            'Detection Results',
            style: TextStyle(
              fontSize: 18, 
              fontWeight: FontWeight.bold, 
              color: isDark ? Colors.white : const Color(0xFF111116)
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFEDEEFC)),
            ),
            child: Column(
              children: [
                _buildInfoRow('True Type', result.trueType, isHighlight: true),
                Divider(height: 24, color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFEDEEFC)),
                _buildInfoRow('Confidence', '${(result.confidenceScore * 100).toInt()}%'),
                Divider(height: 24, color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFEDEEFC)),
                _buildInfoRow('MIME Type', result.trueMimeType),
                ...result.metadata.entries.map((e) {
                  return Column(
                    children: [
                      Divider(height: 24, color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFEDEEFC)),
                      _buildInfoRow(e.key, e.value),
                    ],
                  );
                }),
              ],
            ),
          ),

          if (result.anomalyWarning != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3D00).withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF3D00).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.alertTriangle, color: Color(0xFFFF3D00)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      result.anomalyWarning!,
                      style: const TextStyle(color: Color(0xFFFF3D00), fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          const SizedBox(height: 32),
          Text(
            'Available Conversions',
            style: TextStyle(
              fontSize: 18, 
              fontWeight: FontWeight.bold, 
              color: isDark ? Colors.white : const Color(0xFF111116)
            ),
          ),
          const SizedBox(height: 16),
          
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 2.5,
            ),
            itemCount: result.availableConversions.length,
            itemBuilder: (context, index) {
              final conversion = result.availableConversions[index];
              return InkWell(
                onTap: () {
                  context.push('/conversion', extra: {
                    'sourceFilePath': widget.filePath,
                    'sourceFormat': result.trueType,
                    'targetFormat': conversion.format,
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 8, offset: const Offset(0, 2))
                    ],
                    border: Border.all(color: conversion.color.withOpacity(0.4), width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(conversion.icon, color: conversion.color, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        conversion.format,
                        style: TextStyle(
                          color: conversion.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isHighlight = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF70727D), fontSize: 14, fontWeight: FontWeight.bold),
        ),
        Text(
          value,
          style: TextStyle(
            color: isHighlight 
                ? const Color(0xFFFF5C00) 
                : (isDark ? Colors.white : const Color(0xFF111116)),
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
