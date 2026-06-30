import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/utils/file_converter.dart';

class ResultsScreen extends StatelessWidget {
  final String sourcePath;
  final String targetFormat;
  final String originalSize;
  final String newSize;

  const ResultsScreen({
    super.key,
    required this.sourcePath,
    required this.targetFormat,
    required this.originalSize,
    required this.newSize,
  });

  void _saveToDevice(BuildContext context) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        throw Exception('Converted file does not exist');
      }

      final fileName = sourcePath.split(Platform.pathSeparator).last;
      final ext = targetFormat.toLowerCase();
      final baseName = fileName.contains('_converted')
          ? fileName.substring(0, fileName.lastIndexOf('_converted'))
          : (fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName);
      final suggestedName = "${baseName}_converted.$ext";

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) {
            final controller = TextEditingController(text: suggestedName.split('.').first);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF151D30) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                'Save File',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1E1E2D),
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter a name for your file:',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E1E2D)),
                    decoration: InputDecoration(
                      hintText: 'Filename',
                      hintStyle: const TextStyle(color: Colors.grey),
                      suffixText: '.$ext',
                      suffixStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFEDEEFC).withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final enteredName = controller.text.trim();
                    if (enteredName.isEmpty) return;
                    
                    final finalName = "$enteredName.$ext";
                    Navigator.pop(context);
                    
                    await _performSave(context, sourceFile, finalName);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, e.toString());
      }
    }
  }

  Future<void> _performSave(BuildContext context, File sourceFile, String finalName) async {
    try {
      final downloadDir = await FileConverter.getSafeDownloadDirectory();
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      final targetPath = '${downloadDir.path}/$finalName';
      await sourceFile.copy(targetPath);
      
      // Notify native Android MediaScanner
      try {
        const channel = MethodChannel('com.akhilbehara.filegym/media_scanner');
        await channel.invokeMethod('scanFile', {'path': targetPath});
      } catch (_) {}

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File saved successfully to Downloads as $finalName'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, e.toString());
      }
    }
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save file: $message'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _shareFile(BuildContext context) {
    Share.shareXFiles(
      [XFile(sourcePath)], 
      text: 'Check out my converted file from FileGym!'
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090A0F) : const Color(0xFFFAFAFA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Conversion Complete', 
          style: TextStyle(
            fontWeight: FontWeight.w900, 
            letterSpacing: -0.5,
            color: isDark ? Colors.white : const Color(0xFF111116)
          )
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.x, color: isDark ? Colors.white : const Color(0xFF111116)),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: 50,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.08),
              ),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 4.seconds),
          ),
          Positioned(
            bottom: -50,
            left: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.secondary.withValues(alpha: isDark ? 0.15 : 0.05),
              ),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .scale(begin: const Offset(1, 1), end: const Offset(1.3, 1.3), duration: 5.seconds),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Spacer(),
                  _buildSuccessCard(context).animate().scale(delay: 100.ms, duration: 500.ms, curve: Curves.easeOutBack).fadeIn(),
                  const SizedBox(height: 48),
                  _buildActionButtons(context).animate().fadeIn(delay: 400.ms).slideY(begin: 0.3, end: 0, curve: Curves.easeOutCirc),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                blurRadius: 40,
                spreadRadius: -5,
              )
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  LucideIcons.check,
                  size: 56,
                  color: Colors.white,
                ).animate().scale(delay: 400.ms, duration: 400.ms, curve: Curves.easeOutBack),
              ),
              const SizedBox(height: 32),
              Text(
                'Successfully Converted!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900, 
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : const Color(0xFF111116)
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your file is now in $targetFormat format.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 16,
                    ),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFEAEAEE)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSizeInfo(context, 'Original', originalSize),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Icon(LucideIcons.arrowRight, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
                    ),
                    _buildSizeInfo(context, 'New Size', newSize, highlight: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSizeInfo(BuildContext context, String label, String size, {bool highlight = false}) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          size,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: highlight ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton.icon(
            onPressed: () => _saveToDevice(context),
            icon: const Icon(LucideIcons.downloadCloud),
            label: const Text('Save to Device', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 60,
                child: OutlinedButton.icon(
                  onPressed: () => _shareFile(context),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4), width: 1.5),
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  icon: const Icon(LucideIcons.share2),
                  label: const Text('Share', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 60,
                child: OutlinedButton.icon(
                  onPressed: () {
                    context.go('/');
                  },
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFEAEAEE), width: 1.5),
                    foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                  icon: const Icon(LucideIcons.rotateCcw),
                  label: const Text('Convert Another', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
