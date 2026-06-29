import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/history/history_provider.dart';
import '../../../core/config/config_provider.dart';
import '../../../core/utils/file_converter.dart';
import '../../../core/intelligence/analysis_result.dart';
import '../../../core/intelligence/file_intelligence_engine.dart';

class ConversionScreen extends ConsumerStatefulWidget {
  final String sourceFilePath;
  final String? targetFormat;

  const ConversionScreen({
    super.key,
    required this.sourceFilePath,
    this.targetFormat,
  });

  @override
  ConsumerState<ConversionScreen> createState() => _ConversionScreenState();
}

class _ConversionScreenState extends ConsumerState<ConversionScreen> with SingleTickerProviderStateMixin {
  // Analysis State
  bool _isAnalyzing = true;
  AnalysisResult? _analysisResult;
  String? _analysisError;
  late AnimationController _scannerController;

  // Config State
  String? _selectedTargetFormat;
  double _quality = 80.0;

  // Conversion Progress State
  bool _isConverting = false;
  double _progress = 0.0;
  String _statusMessage = '';

  // Results State
  String? _outputPath;
  String _newSizeString = '';
  final TextEditingController _filenameController = TextEditingController();
  bool _isSaved = false;
  String? _savedFileName;

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
    _filenameController.dispose();
    super.dispose();
  }

  Future<void> _runIntelligenceEngine() async {
    try {
      final result = await FileIntelligenceEngine.analyze(widget.sourceFilePath);
      if (mounted) {
        setState(() {
          _analysisResult = result;
          _isAnalyzing = false;
          
          // Pre-select format if provided, otherwise default to first available
          if (widget.targetFormat != null) {
            _selectedTargetFormat = widget.targetFormat;
          } else if (result.availableConversions.isNotEmpty) {
            _selectedTargetFormat = result.availableConversions.first.format;
          }
        });
        _scannerController.stop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analysisError = 'Failed to analyze file details: $e';
          _isAnalyzing = false;
        });
        _scannerController.stop();
      }
    }
  }

  String _formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return ((bytes / math.pow(1024, i)).toStringAsFixed(decimals)) + ' ' + suffixes[i];
  }

  Future<void> _startConversion() async {
    if (_selectedTargetFormat == null) return;

    setState(() {
      _isConverting = true;
      _progress = 0.0;
      _statusMessage = 'Reading source file...';
    });

    try {
      final conversionFuture = FileConverter.convert(
        sourcePath: widget.sourceFilePath,
        targetFormat: _selectedTargetFormat!,
        quality: _quality,
      );

      for (int i = 0; i <= 90; i += 5) {
        await Future.delayed(const Duration(milliseconds: 60));
        if (!mounted) {
          // Ensure the future is awaited so its error is always caught
          await conversionFuture.catchError((_) => '');
          return;
        }
        setState(() {
          _progress = i / 100.0;
          if (i < 30) {
            _statusMessage = 'Reading source file...';
          } else if (i < 75) {
            _statusMessage = 'Converting to ${_selectedTargetFormat}...';
          } else {
            _statusMessage = 'Packaging output bytes...';
          }
        });
      }

      final resultPath = await conversionFuture;
      
      // Calculate output size
      final outputFile = File(resultPath);
      final outBytes = await outputFile.length();
      final outSizeStr = _formatBytes(outBytes);

      // Save to history
      final String origFileName;
      if (widget.sourceFilePath.contains(';')) {
        origFileName = 'stitch_batch.pdf';
      } else {
        origFileName = widget.sourceFilePath.split(Platform.pathSeparator).last;
      }
      final cleanBaseName = origFileName.contains('.')
          ? origFileName.substring(0, origFileName.lastIndexOf('.'))
          : origFileName;
      final convertedFileName = "${cleanBaseName}_converted.${_selectedTargetFormat!.toLowerCase()}";

      await ref.read(historyProvider.notifier).addHistoryItem(
        fileName: convertedFileName,
        sourceFormat: _analysisResult?.trueType ?? 'Unknown',
        targetFormat: _selectedTargetFormat!,
        sizeString: outSizeStr,
        sourcePath: widget.sourceFilePath,
        outputPath: resultPath,
      );

      if (!mounted) return;
      
      setState(() {
        _progress = 1.0;
        _statusMessage = 'Finished!';
        _outputPath = resultPath;
        _newSizeString = outSizeStr;
        _filenameController.text = "${cleanBaseName}_converted";
        _isConverting = false;
      });

    } catch (e) {
      if (mounted) {
        setState(() {
          _isConverting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conversion failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _saveToDevice() async {
    if (_outputPath == null || _selectedTargetFormat == null) return;
    
    try {
      final sourceFile = File(_outputPath!);
      if (!await sourceFile.exists()) {
        throw Exception('Converted file cache does not exist');
      }

      final enteredName = _filenameController.text.trim();
      if (enteredName.isEmpty) return;

      final ext = _selectedTargetFormat!.toLowerCase();
      final finalName = "$enteredName.$ext";

      final downloadDir = await FileConverter.getSafeDownloadDirectory();
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      final targetPath = '${downloadDir.path}/$finalName';
      await sourceFile.copy(targetPath);

      // Trigger MediaScanner
      try {
        const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
        await channel.invokeMethod('scanFile', {'path': targetPath});
      } catch (_) {}

      setState(() {
        _isSaved = true;
        _savedFileName = finalName;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved successfully to Downloads as $finalName'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _shareFile() async {
    if (_outputPath == null) return;
    try {
      final file = File(_outputPath!);
      if (await file.exists()) {
        await Share.shareXFiles([XFile(_outputPath!)], text: 'My converted file via FileGym');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090A0F) : const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(
          _outputPath != null ? 'Ready' : (_isConverting ? 'Converting...' : 'File Conversion'),
          style: TextStyle(
            fontWeight: FontWeight.w900, 
            color: isDark ? Colors.white : const Color(0xFF111116)
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: isDark ? Colors.white : const Color(0xFF111116)),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Stack(
        children: [
          // Background soft warm ambient glows
          Positioned(
            top: 100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withOpacity(isDark ? 0.15 : 0.05),
              ),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 6.seconds),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: _isAnalyzing
                  ? _buildScanningState(isDark)
                  : _analysisError != null
                      ? _buildErrorState(isDark)
                      : _outputPath != null
                          ? _buildResultsState(isDark)
                          : _isConverting
                              ? _buildProgressState(isDark)
                              : SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: MediaQuery.of(context).size.height * 0.7,
                                    ),
                                    child: _buildConfigState(isDark),
                                  ),
                                ),
            ),
          ),
        ],
      ),
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
            'Analyzing File Details...',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF111116),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scanning magic bytes & structure',
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
        padding: const EdgeInsets.all(16.0),
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
              _analysisError ?? 'Unknown error occurred.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF70727D)),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5C00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Go Home'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildConfigState(bool isDark) {
    final result = _analysisResult!;
    final String origFileName;
    if (widget.sourceFilePath.contains(';')) {
      origFileName = 'Stitched Batch PDF';
    } else {
      origFileName = widget.sourceFilePath.split(Platform.pathSeparator).last;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // File Overview Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5C00).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.fileCheck, color: Theme.of(context).colorScheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      origFileName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark ? Colors.white : const Color(0xFF111116),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Format: ${result.trueType.toUpperCase()} • Size: ${result.fileSize}',
                      style: const TextStyle(color: Color(0xFF70727D), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        
        Text(
          'Target Format',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : const Color(0xFF111116),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        
        // Horizontal Chip list of available conversions
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: result.availableConversions.map((conv) {
            final isSelected = _selectedTargetFormat == conv.format;
            return InkWell(
              onTap: () {
                setState(() {
                  _selectedTargetFormat = conv.format;
                });
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? Theme.of(context).colorScheme.primary : (isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE)),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      conv.icon, 
                      color: isSelected ? Colors.white : conv.color, 
                      size: 16
                    ),
                    const SizedBox(width: 8),
                    Text(
                      conv.format,
                      style: TextStyle(
                        color: isSelected ? Colors.white : (isDark ? Colors.white : const Color(0xFF111116)),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        
        const SizedBox(height: 28),

        // Dynamic Quality Presets (Image conversion, PDF export)
        if (widget.sourceFilePath.toLowerCase().endsWith('.png') ||
            widget.sourceFilePath.toLowerCase().endsWith('.jpg') ||
            widget.sourceFilePath.toLowerCase().endsWith('.jpeg') ||
            widget.sourceFilePath.toLowerCase().endsWith('.webp') ||
            _selectedTargetFormat == 'PNG' ||
            _selectedTargetFormat == 'JPEG') ...[
          _buildQualitySlider(),
        ],

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton.icon(
            onPressed: _startConversion,
            icon: const Icon(LucideIcons.zap),
            label: const Text('Convert Now', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQualitySlider() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Preset Quality', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('${_quality.toInt()}%', style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          Slider(
            value: _quality,
            min: 20,
            max: 100,
            divisions: 16,
            activeColor: Theme.of(context).colorScheme.primary,
            onChanged: (val) {
              setState(() {
                _quality = val;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProgressState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 180,
                height: 180,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: _progress),
                  duration: const Duration(milliseconds: 250),
                  builder: (context, value, _) {
                    return CircularProgressIndicator(
                      value: value,
                      strokeWidth: 12,
                      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      color: Theme.of(context).colorScheme.primary,
                      strokeCap: StrokeCap.round,
                    );
                  },
                ),
              ),
              Icon(LucideIcons.zap, size: 60, color: Theme.of(context).colorScheme.primary)
                  .animate(onPlay: (controller) => controller.repeat(reverse: true))
                  .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 800.ms),
            ],
          ).animate().fadeIn().scale(curve: Curves.easeOutBack),
          const SizedBox(height: 48),
          Text(
            '${(_progress * 100).toInt()}%',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: -1.0,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            _statusMessage,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
          ).animate(key: ValueKey(_statusMessage)).fade().slideY(begin: 0.2, end: 0),
        ],
      ),
    );
  }

  Widget _buildResultsState(bool isDark) {
    final origSizeStr = _analysisResult?.fileSize ?? 'Unknown';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // Success Card
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                  blurRadius: 30,
                  spreadRadius: -5,
                )
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF5C00), Color(0xFFFF9E00)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF5C00).withOpacity(0.4),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.check,
                    size: 48,
                    color: Colors.white,
                  ).animate().scale(delay: 100.ms, duration: 450.ms, curve: Curves.easeOutBack),
                ),
                const SizedBox(height: 24),
                Text(
                  'Conversion Complete!',
                  style: TextStyle(
                    fontWeight: FontWeight.w900, 
                    fontSize: 20, 
                    color: isDark ? Colors.white : const Color(0xFF111116),
                    letterSpacing: -0.5
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'File successfully formatted to $_selectedTargetFormat',
                  style: const TextStyle(color: Color(0xFF70727D), fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFEAEAEE)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSizeLabel('Original', origSizeStr),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Icon(LucideIcons.arrowRight, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
                      ),
                      _buildSizeLabel('New Size', _newSizeString, highlight: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),

          // File Naming Input Box
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rename Converted File',
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 15,
                    color: isDark ? Colors.white : const Color(0xFF111116)
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _filenameController,
                  autofocus: false,
                  style: TextStyle(color: isDark ? Colors.white : const Color(0xFF111116), fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    suffixText: '.${_selectedTargetFormat!.toLowerCase()}',
                    suffixStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    filled: true,
                    fillColor: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFEDEEFC).withOpacity(0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Open Converted File Button
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              onPressed: () async {
                if (_outputPath != null) {
                  try {
                    final ext = (_selectedTargetFormat ?? '').toLowerCase();
                    String? mimeType;
                    if (ext == 'pdf') {
                      mimeType = 'application/pdf';
                    } else if (ext == 'png') {
                      mimeType = 'image/png';
                    } else if (ext == 'jpg' || ext == 'jpeg') {
                      mimeType = 'image/jpeg';
                    } else if (ext == 'webp') {
                      mimeType = 'image/webp';
                    }
                    await OpenFilex.open(_outputPath!, type: mimeType);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Cannot open file: $e'),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  }
                }
              },
              icon: const Icon(LucideIcons.externalLink, size: 20),
              label: const Text(
                'Open Converted File',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Save & Share Actions
          if (!_isSaved) ...[
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _saveToDevice,
                icon: const Icon(LucideIcons.downloadCloud),
                label: const Text('Save to Downloads', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF141622) : const Color(0xFFEEEEF2),
                  foregroundColor: isDark ? Colors.white : const Color(0xFF111116),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.checkCircle, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Saved as $_savedFileName',
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _shareFile,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.4), width: 1.5),
                      foregroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    icon: const Icon(LucideIcons.share2),
                    label: const Text('Share File', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      side: BorderSide(color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFEAEAEE), width: 1.5),
                      foregroundColor: isDark ? Colors.white70 : Colors.black87,
                    ),
                    icon: const Icon(LucideIcons.rotateCcw),
                    label: const Text('Convert Another', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSizeLabel(String label, String size, {bool highlight = false}) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          size,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: highlight ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}
