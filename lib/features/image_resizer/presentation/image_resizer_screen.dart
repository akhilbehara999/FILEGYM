import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img;

import '../../../core/utils/file_converter.dart';
import '../../../core/history/history_provider.dart';

class ImageResizerScreen extends ConsumerStatefulWidget {
  final String sourceFilePath;

  const ImageResizerScreen({
    super.key,
    required this.sourceFilePath,
  });

  @override
  ConsumerState<ImageResizerScreen> createState() => _ImageResizerScreenState();
}

class _ImageResizerScreenState extends ConsumerState<ImageResizerScreen> with SingleTickerProviderStateMixin {
  // Analysis & Scanner State
  bool _isDecoding = true;
  int _origWidth = 0;
  int _origHeight = 0;
  double _aspectRatio = 1.0;
  String _origSizeString = '';
  late AnimationController _scannerController;
  final FocusNode _widthFocusNode = FocusNode();
  final FocusNode _heightFocusNode = FocusNode();

  // Control state
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  bool _lockAspectRatio = true;
  String _targetFormat = 'JPG';
  double _quality = 80.0;
  double _selectedScalePreset = 1.0;

  // Processing state
  bool _isProcessing = false;
  double _progress = 0.0;
  String _statusMessage = '';

  // Results state
  String? _outputPath;
  String _newSizeString = '';
  int _newWidth = 0;
  int _newHeight = 0;
  final TextEditingController _filenameController = TextEditingController();
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _analyzeImage();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _widthFocusNode.dispose();
    _heightFocusNode.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _filenameController.dispose();
    super.dispose();
  }

  Future<void> _analyzeImage() async {
    try {
      final file = File(widget.sourceFilePath);
      final sizeBytes = await file.length();
      _origSizeString = _formatBytes(sizeBytes);

      final bytes = await file.readAsBytes();
      final dims = FileConverter.readImageDimensions(bytes);

      int? w;
      int? h;
      if (dims != null) {
        w = dims[0];
        h = dims[1];
      } else {
        // Fallback to full decode only if header read failed
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          w = decoded.width;
          h = decoded.height;
        }
      }

      if (w != null && h != null && mounted) {
        setState(() {
          _origWidth = w!;
          _origHeight = h!;
          _aspectRatio = _origWidth / _origHeight;
          _widthController.text = _origWidth.toString();
          _heightController.text = _origHeight.toString();
          
          final ext = widget.sourceFilePath.split('.').last.toUpperCase();
          _targetFormat = ['PNG', 'JPG', 'JPEG', 'WEBP'].contains(ext) ? ext : 'JPG';
          
          _isDecoding = false;
        });
        _scannerController.stop();
      } else {
        throw Exception('Could not read image dimensions');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to analyze image: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        context.pop();
      }
    }
  }

  String _formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  void _applyPreset(double scale) {
    if (_origWidth == 0 || _origHeight == 0) return;
    setState(() {
      _selectedScalePreset = scale;
      final targetW = (_origWidth * scale).round();
      final targetH = (_origHeight * scale).round();
      _widthController.text = targetW.toString();
      _heightController.text = targetH.toString();
    });
  }

  Future<void> _startResizing() async {
    final w = int.tryParse(_widthController.text.trim());
    final h = int.tryParse(_heightController.text.trim());

    if (w == null || w <= 0 || h == null || h <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid width and height dimensions.'),
          backgroundColor: Color(0xFFFF3D00),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _statusMessage = 'Reading image pixels...';
    });

    try {
      final resizeFuture = FileConverter.resizeImage(
        sourcePath: widget.sourceFilePath,
        width: w,
        height: h,
        targetFormat: _targetFormat,
        quality: _quality,
      );

      for (int i = 0; i <= 90; i += 10) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
        setState(() {
          _progress = i / 100.0;
          if (i < 40) {
            _statusMessage = 'Resampling pixels to $w x $h...';
          } else if (i < 80) {
            _statusMessage = 'Encoding as $_targetFormat...';
          } else {
            _statusMessage = 'Optimizing image compression...';
          }
        });
      }

      final resultPath = await resizeFuture;

      final outputFile = File(resultPath);
      final outBytes = await outputFile.length();
      final outSizeStr = _formatBytes(outBytes);

      final origFileName = widget.sourceFilePath.split(Platform.pathSeparator).last;
      final cleanBaseName = origFileName.contains('.')
          ? origFileName.substring(0, origFileName.lastIndexOf('.'))
          : origFileName;

      final resizedFileName = "${cleanBaseName}_resized.${_targetFormat.toLowerCase()}";

      await ref.read(historyProvider.notifier).addHistoryItem(
        fileName: resizedFileName,
        sourceFormat: 'Image',
        targetFormat: _targetFormat,
        sizeString: outSizeStr,
        sourcePath: widget.sourceFilePath,
        outputPath: resultPath,
      );

      if (!mounted) return;

      setState(() {
        _progress = 1.0;
        _statusMessage = 'Resizing complete!';
        _outputPath = resultPath;
        _newSizeString = outSizeStr;
        _newWidth = w;
        _newHeight = h;
        _filenameController.text = "${cleanBaseName}_resized";
        _isProcessing = false;
      });

    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Resizing failed: $e'),
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
        throw Exception('Resized image cache does not exist');
      }

      final enteredName = _filenameController.text.trim();
      if (enteredName.isEmpty) return;

      final finalName = "$enteredName.${_targetFormat.toLowerCase()}";

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
            content: Text('Resized image saved to Downloads as $finalName'),
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
      final enteredName = _filenameController.text.trim();
      final finalName = enteredName.isNotEmpty
          ? "$enteredName.${_targetFormat.toLowerCase()}"
          : "resized_image.${_targetFormat.toLowerCase()}";
      await Share.shareXFiles([XFile(_outputPath!, name: finalName)]);
    }
  }

  void _showFormatSelectorSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F1017) : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
            border: Border.all(
              color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE),
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2E3147) : const Color(0xFFE2E4E9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Choose Output Format',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              _buildFormatOption('JPG', 'JPG Image File', 'Highly compatible standard image format, best for general photos.', LucideIcons.image, isDark),
              const SizedBox(height: 12),
              _buildFormatOption('PNG', 'PNG Image File', 'Lossless compression with support for transparent backgrounds.', LucideIcons.fileImage, isDark),
              const SizedBox(height: 12),
              _buildFormatOption('WEBP', 'WebP Image File', 'Next-gen Google format offering superior quality at smaller sizes.', LucideIcons.fileCode, isDark),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFormatOption(String format, String title, String subtitle, IconData icon, bool isDark) {
    final isSelected = _targetFormat == format;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: () {
        setState(() {
          _targetFormat = format;
        });
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.08)
              : (isDark ? const Color(0xFF141622) : const Color(0xFFF6F7F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : (isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE)),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? primaryColor.withValues(alpha: 0.15) : (isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE)),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: isSelected ? primaryColor : (isDark ? Colors.white70 : Colors.black87), size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: isSelected ? primaryColor : (isDark ? Colors.white : const Color(0xFF111116)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF70727D),
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(LucideIcons.checkCircle, color: primaryColor, size: 22),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090A0F) : const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text('Image Resizer', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: isDark ? Colors.white : const Color(0xFF111116)),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          // Background soft ambient glow
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.12 : 0.05),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 6.seconds),
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: AnimatedSwitcher(
                duration: 300.ms,
                child: _isDecoding
                    ? _buildScanningState(isDark)
                    : _isProcessing
                        ? _buildProgressState(isDark)
                        : _outputPath != null
                            ? _buildResultsState(isDark)
                            : _buildConfigState(isDark),
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
            'Analyzing Image Details...',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: isDark ? Colors.white : const Color(0xFF111116),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Decoding original dimensions & ratio',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF70727D),
            ),
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
              fontWeight: FontWeight.bold, 
              fontSize: 16,
              color: isDark ? Colors.white : const Color(0xFF111116)
            ),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${(_progress * 100).toInt()}%',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.primary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigState(bool isDark) {
    final origFileName = widget.sourceFilePath.split(Platform.pathSeparator).last;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        // Premium File Preview Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ]
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(widget.sourceFilePath),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      origFileName,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Original: $_origWidth x $_origHeight • $_origSizeString',
                      style: const TextStyle(color: Color(0xFF70727D), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Target Dimensions', 
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.5)
        ),
        const SizedBox(height: 16),

        // Text Fields Row with aspect lock
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _widthController,
                focusNode: _widthFocusNode,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Width',
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF70727D)),
                  suffixText: 'px',
                  suffixStyle: const TextStyle(fontWeight: FontWeight.bold),
                  filled: true,
                  fillColor: Theme.of(context).cardTheme.color,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE), width: 1.5)
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
                onChanged: (val) {
                  if (!_lockAspectRatio) return;
                  if (!_widthFocusNode.hasFocus) return;
                  final w = int.tryParse(val);
                  if (w != null && _aspectRatio > 0) {
                    final h = (w / _aspectRatio).round();
                    _heightController.text = h.toString();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                _lockAspectRatio ? LucideIcons.link2 : LucideIcons.link2Off,
                color: _lockAspectRatio ? Theme.of(context).colorScheme.primary : const Color(0xFF70727D),
                size: 24,
              ),
              onPressed: () {
                setState(() {
                  _lockAspectRatio = !_lockAspectRatio;
                });
                if (_lockAspectRatio) {
                  final w = int.tryParse(_widthController.text.trim());
                  if (w != null && _aspectRatio > 0) {
                    final h = (w / _aspectRatio).round();
                    _heightController.text = h.toString();
                  }
                }
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _heightController,
                focusNode: _heightFocusNode,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Height',
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF70727D)),
                  suffixText: 'px',
                  suffixStyle: const TextStyle(fontWeight: FontWeight.bold),
                  filled: true,
                  fillColor: Theme.of(context).cardTheme.color,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE), width: 1.5)
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
                onChanged: (val) {
                  if (!_lockAspectRatio) return;
                  if (!_heightFocusNode.hasFocus) return;
                  final h = int.tryParse(val);
                  if (h != null && _aspectRatio > 0) {
                    final w = (h * _aspectRatio).round();
                    _widthController.text = w.toString();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Quick Preset Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildPresetChip('25%', 0.25, isDark),
              const SizedBox(width: 8),
              _buildPresetChip('50%', 0.50, isDark),
              const SizedBox(width: 8),
              _buildPresetChip('75%', 0.75, isDark),
              const SizedBox(width: 8),
              _buildPresetChip('100% (Fit)', 1.0, isDark),
              const SizedBox(width: 8),
              _buildPresetChip('150%', 1.50, isDark),
              const SizedBox(width: 8),
              _buildPresetChip('200%', 2.0, isDark),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const Text(
          'Target Format', 
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.5)
        ),
        const SizedBox(height: 12),        // Format selector card
        GestureDetector(
          onTap: () => _showFormatSelectorSheet(isDark),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141622) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _targetFormat == 'PNG'
                        ? LucideIcons.fileImage
                        : (_targetFormat == 'WEBP' ? LucideIcons.fileCode : LucideIcons.image),
                    color: Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_targetFormat Format',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: isDark ? Colors.white : const Color(0xFF111116),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _targetFormat == 'PNG'
                            ? 'Lossless compression, supports transparency'
                            : (_targetFormat == 'WEBP'
                                ? 'Modern format, optimal file size & quality'
                                : 'Highly compatible, smaller file size'),
                        style: TextStyle(
                          color: isDark ? Colors.white54 : const Color(0xFF70727D),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronDown, color: Theme.of(context).colorScheme.primary, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (_targetFormat != 'PNG') ...[
          _buildQualitySlider(isDark),
          const SizedBox(height: 20),
        ],
        
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: _startResizing,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Text('Resize Now', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    ),);
  }

  Widget _buildPresetChip(String label, double scale, bool isDark) {
    final isSelected = _selectedScalePreset == scale;
    final color = Theme.of(context).colorScheme.primary;

    return ActionChip(
      label: Text(label),
      labelStyle: TextStyle(
        fontWeight: FontWeight.bold, 
        color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87)
      ),
      backgroundColor: isSelected ? color : Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected ? color : (isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE)),
          width: 1.5,
        ),
      ),
      onPressed: () => _applyPreset(scale),
    );
  }

  Widget _buildQualitySlider(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Resizing Quality', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('${_quality.toInt()}%', style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
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

  Widget _buildResultsState(bool isDark) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        // Success Circle Check
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.check, color: Colors.white, size: 36),
          ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
        ),
        const SizedBox(height: 20),
        const Center(
          child: Text(
            'Resizing Completed!',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.5),
          ),
        ),
        const SizedBox(height: 28),

        // Dimensions and size stats card
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
                  const Text('Original Resolution', style: TextStyle(color: Color(0xFF70727D), fontWeight: FontWeight.bold)),
                  Text('$_origWidth x $_origHeight px', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF111116))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Resized Resolution', style: TextStyle(color: Color(0xFF70727D), fontWeight: FontWeight.bold)),
                  Text('$_newWidth x $_newHeight px', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFF5C00))),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Original Size', style: TextStyle(color: Color(0xFF70727D), fontWeight: FontWeight.bold)),
                  Text(_origSizeString, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF111116))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Resized Size', style: TextStyle(color: Color(0xFF70727D), fontWeight: FontWeight.bold)),
                  Text(_newSizeString, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF10B981))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Rename file field
        const Text(
          'Rename Resized Image', 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF70727D))
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _filenameController,
          style: const TextStyle(fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'Enter file name',
            suffixText: '.${_targetFormat.toLowerCase()}',
            suffixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF5C00)),
            filled: true,
            fillColor: Theme.of(context).cardTheme.color,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE), width: 1.5)
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Open Resized Image Button
        SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton.icon(
            onPressed: () async {
              if (_outputPath != null) {
                try {
                  final ext = _targetFormat.toLowerCase();
                  final mimeType = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
                  await OpenFilex.open(_outputPath!, type: mimeType);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Cannot open image: $e'),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                }
              }
            },
            icon: const Icon(LucideIcons.externalLink, size: 20),
            label: const Text(
              'Open Resized Image',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5C00),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Actions row
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isSaved ? null : _saveToDevice,
                  icon: Icon(_isSaved ? LucideIcons.check : LucideIcons.download, size: 18),
                  label: Text(
                    _isSaved ? 'Saved to Downloads' : 'Save to Downloads',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF141622) : const Color(0xFFEEEEF2),
                    foregroundColor: isDark ? Colors.white : const Color(0xFF111116),
                    disabledBackgroundColor: const Color(0xFF10B981).withValues(alpha: 0.2),
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
        const SizedBox(height: 16),
      ],
    ),);
  }
}
