import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:open_filex/open_filex.dart';

import '../../../core/history/history_provider.dart';
import '../../../core/utils/file_converter.dart';

class ImgToPdfScreen extends ConsumerStatefulWidget {
  final List<String> sourceFilePaths;

  const ImgToPdfScreen({
    super.key,
    required this.sourceFilePaths,
  });

  @override
  ConsumerState<ImgToPdfScreen> createState() => _ImgToPdfScreenState();
}

class _ImgToPdfScreenState extends ConsumerState<ImgToPdfScreen> {
  // Input Paths
  final List<String> _paths = [];
  final Map<String, int> _fileSizes = {};

  // Configuration
  String _pageSize = 'A4'; // 'A4', 'Letter', 'Fit'
  String _orientation = 'Auto'; // 'Portrait', 'Landscape', 'Auto'
  String _margin = 'None'; // 'None', 'Small', 'Medium'

  // Conversion Progress State
  bool _isConverting = false;
  double _progress = 0.0;
  String _statusMessage = '';

  // Results State
  String? _outputPath;
  String _newSizeString = '';
  final TextEditingController _filenameController = TextEditingController();
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _paths.addAll(widget.sourceFilePaths);
    _loadSizes();
    _filenameController.text = 'stitched_document';
  }

  @override
  void dispose() {
    _filenameController.dispose();
    super.dispose();
  }

  Future<void> _loadSizes() async {
    for (final path in _paths) {
      if (!_fileSizes.containsKey(path)) {
        try {
          final size = await File(path).length();
          setState(() {
            _fileSizes[path] = size;
          });
        } catch (_) {}
      }
    }
  }

  String _getFileSizeString(String path) {
    final bytes = _fileSizes[path];
    if (bytes == null) return 'Loading...';
    return _formatBytes(bytes);
  }

  String _formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return ((bytes / math.pow(1024, i)).toStringAsFixed(decimals)) + ' ' + suffixes[i];
  }

  String _getTotalSize() {
    int total = 0;
    for (final path in _paths) {
      total += _fileSizes[path] ?? 0;
    }
    return _formatBytes(total);
  }

  Future<void> _pickMoreImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final newPaths = result.files.map((f) => f.path).whereType<String>().toList();
        setState(() {
          _paths.addAll(newPaths);
        });
        _loadSizes();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking images: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _moveUp(int index) {
    if (index > 0) {
      setState(() {
        final item = _paths.removeAt(index);
        _paths.insert(index - 1, item);
      });
    }
  }

  void _moveDown(int index) {
    if (index < _paths.length - 1) {
      setState(() {
        final item = _paths.removeAt(index);
        _paths.insert(index + 1, item);
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _paths.removeAt(index);
    });
  }

  Future<void> _startConversion() async {
    if (_paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one image to convert'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isConverting = true;
      _progress = 0.0;
      _statusMessage = 'Initializing PDF creator...';
    });

    try {
      // Setup fake progress steps while compiling the PDF
      final conversionFuture = FileConverter.stitchImagesToPdf(
        imagePaths: _paths,
        pageSize: _pageSize,
        orientation: _orientation,
        margin: _margin,
      );

      for (int i = 0; i <= 90; i += 10) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
        setState(() {
          _progress = i / 100.0;
          if (i < 30) {
            _statusMessage = 'Loading image structures...';
          } else if (i < 70) {
            _statusMessage = 'Stitching pages together...';
          } else {
            _statusMessage = 'Writing PDF layout & compression...';
          }
        });
      }

      final resultPath = await conversionFuture;
      
      // Calculate output size
      final outputFile = File(resultPath);
      final outBytes = await outputFile.length();
      final outSizeStr = _formatBytes(outBytes);

      // Save to history
      final displayFileName = "${_filenameController.text.trim()}.pdf";
      await ref.read(historyProvider.notifier).addHistoryItem(
        fileName: displayFileName,
        sourceFormat: 'BATCH IMAGES',
        targetFormat: 'PDF',
        sizeString: outSizeStr,
        sourcePath: _paths.join(';'),
        outputPath: resultPath,
      );

      if (!mounted) return;
      
      setState(() {
        _progress = 1.0;
        _statusMessage = 'Stitching completed!';
        _outputPath = resultPath;
        _newSizeString = outSizeStr;
        _isConverting = false;
      });

    } catch (e) {
      if (mounted) {
        setState(() {
          _isConverting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to stitch images: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
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
        throw Exception('Stitched PDF file does not exist in cache');
      }

      final enteredName = _filenameController.text.trim();
      if (enteredName.isEmpty) return;

      final finalName = "$enteredName.pdf";
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
            content: Text('Failed to save file: $e'),
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
      await Share.shareXFiles([XFile(_outputPath!)], text: 'Stitched PDF document via FileGym');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Theme.of(context).colorScheme.primary; // Use app's orange theme

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090A0F) : const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(
          _outputPath != null ? 'Ready' : (_isConverting ? 'Stitching...' : 'Image to PDF'),
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
                color: themeColor.withOpacity(isDark ? 0.15 : 0.05),
              ),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 6.seconds),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: _outputPath != null
                  ? _buildResultsState(isDark, themeColor)
                  : _isConverting
                      ? _buildProgressState(isDark, themeColor)
                      : _buildConfigState(isDark, themeColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressState(bool isDark, Color themeColor) {
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
                      backgroundColor: themeColor.withOpacity(0.1),
                      color: themeColor,
                      strokeCap: StrokeCap.round,
                    );
                  },
                ),
              ),
              Icon(LucideIcons.fileText, size: 56, color: themeColor)
                  .animate(onPlay: (controller) => controller.repeat(reverse: true))
                  .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 800.ms),
            ],
          ).animate().fadeIn().scale(curve: Curves.easeOutBack),
          const SizedBox(height: 48),
          Text(
            '${(_progress * 100).toInt()}%',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: themeColor,
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

  Widget _buildResultsState(bool isDark, Color themeColor) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Center(
            child: Container(
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
                color: Colors.white, 
                size: 48
              ),
            ).animate().scale(delay: 100.ms, duration: 450.ms, curve: Curves.easeOutBack),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'PDF Stitched Successfully!',
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
                    const Text('Total Original Images', style: TextStyle(color: Color(0xFF70727D), fontWeight: FontWeight.bold)),
                    Text('${_paths.length} Images', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF111116))),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Combined Original Size', style: TextStyle(color: Color(0xFF70727D), fontWeight: FontWeight.bold)),
                    Text(_getTotalSize(), style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF111116))),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Output PDF Size', style: TextStyle(color: Color(0xFF70727D), fontWeight: FontWeight.bold)),
                    Text(_newSizeString, style: TextStyle(fontWeight: FontWeight.w900, color: themeColor)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          // Rename file field
          const Text(
            'Rename PDF Document',
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
              suffixText: '.pdf',
              suffixStyle: TextStyle(fontWeight: FontWeight.bold, color: themeColor),
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
                borderSide: BorderSide(color: themeColor, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 32),
          
          // Open PDF File Button
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton.icon(
              onPressed: () async {
                if (_outputPath != null) {
                  try {
                    await OpenFilex.open(_outputPath!, type: 'application/pdf');
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Cannot open PDF: $e'),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  }
                }
              },
              icon: const Icon(LucideIcons.externalLink, size: 20),
              label: const Text(
                'Open PDF File',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Download and Share buttons rows
          Row(
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isSaved ? null : _saveToDevice,
                    icon: Icon(_isSaved ? LucideIcons.check : LucideIcons.download, size: 20),
                    label: Text(
                      _isSaved ? 'Saved to Downloads' : 'Save to Downloads',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF141622) : const Color(0xFFEEEEF2),
                      foregroundColor: isDark ? Colors.white : const Color(0xFF111116),
                      disabledBackgroundColor: const Color(0xFF10B981).withOpacity(0.2),
                      disabledForegroundColor: const Color(0xFF10B981),
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildConfigState(bool isDark, Color themeColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // List of selected files with reorder and delete options
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Selected Images (${_paths.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900, 
                      fontSize: 18, 
                      letterSpacing: -0.5
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickMoreImages,
                    icon: Icon(LucideIcons.plus, size: 16, color: themeColor),
                    label: Text(
                      'Add Images',
                      style: TextStyle(color: themeColor, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _paths.isEmpty
                    ? _buildEmptyState(isDark, themeColor)
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: _paths.length,
                        itemBuilder: (context, index) {
                          final path = _paths[index];
                          final fileName = p.basename(path);
                          final isHeic = path.toLowerCase().endsWith('.heic') || path.toLowerCase().endsWith('.heif');

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardTheme.color,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    color: isDark ? const Color(0xFF141622) : const Color(0xFFEEEEF2),
                                    child: isHeic
                                        ? Icon(LucideIcons.fileImage, color: themeColor, size: 24)
                                        : Image.file(
                                            File(path),
                                            width: 50,
                                            height: 50,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Icon(LucideIcons.image, color: themeColor, size: 24),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        fileName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _getFileSizeString(path),
                                        style: const TextStyle(color: Color(0xFF70727D), fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(LucideIcons.arrowUp, size: 16, color: index == 0 ? Colors.grey : (isDark ? Colors.white70 : Colors.black87)),
                                      onPressed: index == 0 ? null : () => _moveUp(index),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(LucideIcons.arrowDown, size: 16, color: index == _paths.length - 1 ? Colors.grey : (isDark ? Colors.white70 : Colors.black87)),
                                      onPressed: index == _paths.length - 1 ? null : () => _moveDown(index),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton(
                                      icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.redAccent),
                                      onPressed: () => _removeImage(index),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Layout Settings Accordion/Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PDF Layout Settings',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF70727D)),
              ),
              const SizedBox(height: 14),
              // Page Size Segment
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Page Size', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF70727D))),
                  const SizedBox(height: 8),
                  _buildSegmentedPicker(
                    options: ['A4', 'Letter', 'Fit'],
                    selectedValue: _pageSize,
                    onChanged: (val) {
                      setState(() {
                        _pageSize = val;
                      });
                    },
                    themeColor: themeColor,
                    isDark: isDark,
                  ),
                ],
              ),
              if (_pageSize != 'Fit') ...[
                const SizedBox(height: 16),
                // Orientation Segment
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Orientation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF70727D))),
                    const SizedBox(height: 8),
                    _buildSegmentedPicker(
                      options: ['Portrait', 'Landscape', 'Auto'],
                      selectedValue: _orientation,
                      onChanged: (val) {
                        setState(() {
                          _orientation = val;
                        });
                      },
                      themeColor: themeColor,
                      isDark: isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Margins Segment
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Margins', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF70727D))),
                    const SizedBox(height: 8),
                    _buildSegmentedPicker(
                      options: ['None', 'Small', 'Medium'],
                      selectedValue: _margin,
                      onChanged: (val) {
                        setState(() {
                          _margin = val;
                        });
                      },
                      themeColor: themeColor,
                      isDark: isDark,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        // Convert trigger
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: _paths.isEmpty ? null : _startConversion,
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: isDark ? const Color(0xFF1E2130) : const Color(0xFFEAEAEE),
              disabledForegroundColor: Colors.grey,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Text(
              'Stitch Images to PDF',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark, Color themeColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: themeColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.image, color: themeColor, size: 40),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Images Selected',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add some PNG/JPG files to start stitching',
            style: TextStyle(color: Color(0xFF70727D), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _pickMoreImages,
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Select Images', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedPicker({
    required List<String> options,
    required String selectedValue,
    required ValueChanged<String> onChanged,
    required Color themeColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141622) : const Color(0xFFEEEEF2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: options.map((opt) {
          final isSelected = opt == selectedValue;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(opt),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                decoration: BoxDecoration(
                  color: isSelected ? themeColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      opt,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected 
                            ? Colors.white 
                            : (isDark ? Colors.white60 : Colors.black54),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
