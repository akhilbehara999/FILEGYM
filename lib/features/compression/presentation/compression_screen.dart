import 'dart:io';
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
import '../../../core/utils/file_converter.dart';
import '../../../core/intelligence/analysis_result.dart';
import '../../../core/intelligence/file_intelligence_engine.dart';

class CompressionScreen extends ConsumerStatefulWidget {
  final String sourceFilePath;

  const CompressionScreen({
    super.key,
    required this.sourceFilePath,
  });

  @override
  ConsumerState<CompressionScreen> createState() => _CompressionScreenState();
}

class _CompressionScreenState extends ConsumerState<CompressionScreen> with SingleTickerProviderStateMixin {
  // Analysis State
  bool _isAnalyzing = true;
  AnalysisResult? _analysisResult;
  String? _analysisError;
  late AnimationController _scannerController;

  // Compression Configuration
  String _compressionMethod = 'ZIP'; // ZIP or DIRECT
  double _quality = 60.0;
  double _scale = 0.8;

  // Compression Progress State
  bool _isCompressing = false;
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
        final origFileName = widget.sourceFilePath.split(Platform.pathSeparator).last;
        final cleanBaseName = origFileName.contains('.')
            ? origFileName.substring(0, origFileName.lastIndexOf('.'))
            : origFileName;

        final isImage = result.trueType.toLowerCase().contains('image');
        setState(() {
          _analysisResult = result;
          _isAnalyzing = false;
          _filenameController.text = "${cleanBaseName}_compressed";
          _compressionMethod = isImage ? 'DIRECT' : 'ZIP';
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
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  Future<void> _startCompression() async {
    setState(() {
      _isCompressing = true;
      _progress = 0.0;
      _statusMessage = 'Reading source file...';
    });

    try {
      final origFileName = widget.sourceFilePath.split(Platform.pathSeparator).last;
      final ext = origFileName.contains('.') 
          ? origFileName.substring(origFileName.lastIndexOf('.') + 1).toLowerCase() 
          : 'zip';

      final compressionFuture = _compressionMethod == 'ZIP'
          ? FileConverter.convert(
              sourcePath: widget.sourceFilePath,
              targetFormat: 'ZIP',
            )
          : FileConverter.convert(
              sourcePath: widget.sourceFilePath,
              targetFormat: ext.toUpperCase(),
              quality: _quality,
              scale: _scale,
            );

      for (int i = 0; i <= 90; i += 5) {
        await Future.delayed(const Duration(milliseconds: 60));
        if (!mounted) return;
        setState(() {
          _progress = i / 100.0;
          if (i < 30) {
            _statusMessage = 'Reading source file...';
          } else if (i < 75) {
            _statusMessage = _compressionMethod == 'ZIP' ? 'Compressing to ZIP...' : 'Compressing image data...';
          } else {
            _statusMessage = _compressionMethod == 'ZIP' ? 'Packaging ZIP archive...' : 'Saving compressed file...';
          }
        });
      }

      final resultPath = await compressionFuture;
      
      // Calculate output size
      final outputFile = File(resultPath);
      final outBytes = await outputFile.length();
      final outSizeStr = _formatBytes(outBytes);

      // Save to history
      final cleanBaseName = origFileName.contains('.')
          ? origFileName.substring(0, origFileName.lastIndexOf('.'))
          : origFileName;
      final compressedFileName = _compressionMethod == 'ZIP'
          ? "${cleanBaseName}_compressed.zip"
          : "${cleanBaseName}_compressed.$ext";

      await ref.read(historyProvider.notifier).addHistoryItem(
        fileName: compressedFileName,
        sourceFormat: _analysisResult?.trueType ?? 'Unknown',
        targetFormat: _compressionMethod == 'ZIP' ? 'ZIP' : ext.toUpperCase(),
        sizeString: outSizeStr,
        sourcePath: widget.sourceFilePath,
        outputPath: resultPath,
      );

      if (!mounted) return;
      
      setState(() {
        _progress = 1.0;
        _statusMessage = 'Compression finished!';
        _outputPath = resultPath;
        _newSizeString = outSizeStr;
        _isCompressing = false;
      });

    } catch (e) {
      if (mounted) {
        setState(() {
          _isCompressing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Compression failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _saveToDevice() async {
    if (_outputPath == null) return;
    
    try {
      final sourceFile = File(_outputPath!);
      if (!await sourceFile.exists()) {
        throw Exception('Compressed file cache does not exist');
      }

      final enteredName = _filenameController.text.trim();
      if (enteredName.isEmpty) return;

      final origFileName = widget.sourceFilePath.split(Platform.pathSeparator).last;
      final ext = origFileName.contains('.') 
          ? origFileName.substring(origFileName.lastIndexOf('.') + 1).toLowerCase() 
          : 'zip';
      final finalName = _compressionMethod == 'ZIP' ? "$enteredName.zip" : "$enteredName.$ext";

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
    final file = File(_outputPath!);
    if (await file.exists()) {
      await Share.shareXFiles([XFile(_outputPath!)], text: 'Compressed ZIP archive via FileGym');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090A0F) : const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(
          _outputPath != null ? 'Ready' : (_isCompressing ? 'Compressing...' : 'ZIP Compression'),
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
          // Background soft ambient glows
          Positioned(
            top: 100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.05),
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
                          : _isCompressing
                              ? _buildProgressState(isDark)
                              : _buildConfigState(isDark),
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
                  color: const Color(0xFFFF5C00).withValues(alpha: 0.1),
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
                            const Color(0xFFFF5C00).withValues(alpha: 0.0),
                            const Color(0xFFFF5C00).withValues(alpha: 0.5),
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
    final origFileName = widget.sourceFilePath.split(Platform.pathSeparator).last;

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
                  color: const Color(0xFFFF5C00).withValues(alpha: 0.1),
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${result.trueType} • ${result.fileSize}',
                      style: const TextStyle(color: Color(0xFF70727D), fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (_isImage()) ...[
          const Text(
            'Compression Method',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _compressionMethod = 'DIRECT';
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    decoration: BoxDecoration(
                      color: _compressionMethod == 'DIRECT' 
                          ? Theme.of(context).colorScheme.primary 
                          : Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _compressionMethod == 'DIRECT' 
                            ? Theme.of(context).colorScheme.primary 
                            : (isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE)),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          LucideIcons.shrink,
                          color: _compressionMethod == 'DIRECT' ? Colors.white : Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Direct Compress',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _compressionMethod == 'DIRECT' ? Colors.white : (isDark ? Colors.white : const Color(0xFF111116)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _compressionMethod = 'ZIP';
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    decoration: BoxDecoration(
                      color: _compressionMethod == 'ZIP' 
                          ? Theme.of(context).colorScheme.primary 
                          : Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _compressionMethod == 'ZIP' 
                            ? Theme.of(context).colorScheme.primary 
                            : (isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE)),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          LucideIcons.fileArchive,
                          color: _compressionMethod == 'ZIP' ? Colors.white : Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'ZIP Archive',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _compressionMethod == 'ZIP' ? Colors.white : (isDark ? Colors.white : const Color(0xFF111116)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_compressionMethod == 'DIRECT') ...[
            _buildQualitySlider(),
            const SizedBox(height: 12),
            _buildScaleSlider(),
            const SizedBox(height: 12),
          ],
        ] else ...[
          const Text(
            'Target Output Spec',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.5),
          ),
          const SizedBox(height: 12),
          _buildZipLockedRow(),
          const SizedBox(height: 12),
        ],
        const Spacer(),
        
        // Compression Action triggers
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: _startCompression,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Text(
              'Compress Now',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildProgressState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.shrink,
              color: Theme.of(context).colorScheme.primary,
              size: 40,
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .scale(begin: const Offset(1, 1), end: const Offset(1.15, 1.15), duration: 1.2.seconds),
          ),
          const SizedBox(height: 32),
          Text(
            _statusMessage,
            style: TextStyle(
              fontSize: 18, 
              fontWeight: FontWeight.bold, 
              color: isDark ? Colors.white : const Color(0xFF111116)
            ),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 240,
              height: 8,
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${(_progress * 100).toInt()}%',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF70727D)),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsState(bool isDark) {
    final sizeString = _analysisResult?.fileSize ?? '0 B';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.checkCircle2, 
                color: Color(0xFF10B981), 
                size: 56
              ),
            ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Compression Completed!',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.5),
            ),
          ),
          const SizedBox(height: 32),
          
          // Original and New details Comparison Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE), width: 1.5),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Original Size', style: TextStyle(color: Color(0xFF70727D), fontWeight: FontWeight.bold)),
                    Text(sizeString, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF111116))),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Compressed Size', style: TextStyle(color: Color(0xFF70727D), fontWeight: FontWeight.bold)),
                    Text(_newSizeString, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF10B981))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          // Rename file field
          const Text(
            'Rename Compressed File',
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              fontSize: 15,
              color: Color(0xFF70727D)
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _filenameController,
            style: const TextStyle(fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'Enter name',
              suffixText: _compressionMethod == 'ZIP' ? '.zip' : '.${_getOrigExtension()}',
              suffixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF5C00)),
              filled: true,
              fillColor: Theme.of(context).cardTheme.color,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE), width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 32),
          
          // Open Compressed File Button
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton.icon(
              onPressed: () async {
                if (_outputPath != null) {
                  try {
                    final ext = _getOrigExtension();
                    String? mimeType;
                    if (ext == 'pdf') {
                      mimeType = 'application/pdf';
                    } else if (ext == 'png') {
                      mimeType = 'image/png';
                    } else if (ext == 'jpg' || ext == 'jpeg') {
                      mimeType = 'image/jpeg';
                    } else if (ext == 'webp') {
                      mimeType = 'image/webp';
                    } else if (ext == 'zip') {
                      mimeType = 'application/zip';
                    }
                    await OpenFilex.open(_outputPath!, type: mimeType);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Cannot open compressed file: $e'),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  }
                }
              },
              icon: const Icon(LucideIcons.externalLink, size: 20),
              label: const Text(
                'Open Compressed File',
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
          
          // Download and Share buttons rows
          if (!_isSaved) ...[
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _saveToDevice,
                      icon: const Icon(LucideIcons.download, size: 20),
                      label: const Text(
                        'Save to Downloads',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFF141622) : const Color(0xFFEEEEF2),
                        foregroundColor: isDark ? Colors.white : const Color(0xFF111116),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  width: 56,
                  child: ElevatedButton(
                    onPressed: _shareFile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF141622) : const Color(0xFFEEEEF2),
                      foregroundColor: isDark ? Colors.white : const Color(0xFF111116),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Icon(LucideIcons.share2, size: 20),
                  ),
                ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
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
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(LucideIcons.share2, color: Colors.green),
                    onPressed: _shareFile,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _getOrigExtension() {
    final origFileName = widget.sourceFilePath.split(Platform.pathSeparator).last;
    return origFileName.contains('.') 
        ? origFileName.substring(origFileName.lastIndexOf('.') + 1).toLowerCase() 
        : 'zip';
  }

  bool _isImage() {
    if (_analysisResult == null) return false;
    final type = _analysisResult!.trueType.toLowerCase();
    return type.contains('image');
  }

  Widget _buildZipLockedRow() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(LucideIcons.fileArchive, color: Theme.of(context).colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('ZIP Archive', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  SizedBox(height: 2),
                  Text('Standard compressed package', style: TextStyle(color: Color(0xFF70727D), fontSize: 12)),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '.zip',
              style: TextStyle(color: Color(0xFFFF5C00), fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualitySlider() {
    return Container(
      padding: const EdgeInsets.all(16),
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
              const Text('Compression Quality', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('${_quality.toInt()}%', style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: _quality,
            min: 10,
            max: 95,
            divisions: 17,
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

  Widget _buildScaleSlider() {
    return Container(
      padding: const EdgeInsets.all(16),
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
              const Text('Resolution Scale', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('${(_scale * 100).toInt()}%', style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: _scale,
            min: 0.3,
            max: 1.0,
            divisions: 7,
            activeColor: Theme.of(context).colorScheme.primary,
            onChanged: (val) {
              setState(() {
                _scale = val;
              });
            },
          ),
        ],
      ),
    );
  }
}
