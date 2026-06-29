import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

class CompressionHubScreen extends ConsumerStatefulWidget {
  const CompressionHubScreen({super.key});

  @override
  ConsumerState<CompressionHubScreen> createState() => _CompressionHubScreenState();
}

class _CompressionHubScreenState extends ConsumerState<CompressionHubScreen> {
  Future<void> _pickFileForCompression() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final file = File(path);
        
        // Validate Size: 30 MB
        final sizeBytes = await file.length();
        const maxBytes = 30 * 1024 * 1024;
        if (sizeBytes > maxBytes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('File exceeds the maximum 30 MB compression limit.'),
                backgroundColor: const Color(0xFFFF3D00),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            );
          }
          return;
        }

        // Validate Extension
        final ext = path.split('.').last.toLowerCase();
        final forbidden = ['apk', 'mp4', 'mp3', 'mkv', 'avi', 'wav', 'mov', '3gp', 'flac'];
        if (forbidden.contains(ext)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Format .$ext cannot be compressed. Select documents or images.'),
                backgroundColor: const Color(0xFFFF3D00),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            );
          }
          return;
        }

        if (mounted) {
          context.push('/compression', extra: path);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking file: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
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
        title: const Text(
          'Compression Hub',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: isDark ? Colors.white : const Color(0xFF111116)),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.03),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pulsing Zipper Folder Icon
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.fileArchive,
                        color: Theme.of(context).colorScheme.primary,
                        size: 40,
                      ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                       .scale(begin: const Offset(1, 1), end: const Offset(1.15, 1.15), duration: 1.8.seconds),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Turbo File & ZIP Compressor',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Select any file to compress it directly or archive it into a high-ratio ZIP.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    
                    // Size Limit Tracker Bar
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text('Maximum Limit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF70727D))),
                            Text('30 MB', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFFFF5C00))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: 1.0,
                            minHeight: 6,
                            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Exclusions details card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF141622) : const Color(0xFFF1F1F5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.info, size: 16, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Supports all documents and images. Excludes media files (.mp3, .mp4) and packages (.apk).',
                              style: TextStyle(fontSize: 11, color: Color(0xFF70727D), fontWeight: FontWeight.bold, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 28),
                    
                    // Compressing trigger button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _pickFileForCompression,
                        icon: const Icon(LucideIcons.filePlus, size: 18),
                        label: const Text(
                          'Select File to Compress',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
