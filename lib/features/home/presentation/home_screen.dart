import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image/image.dart' as img;

import '../../../core/history/history_provider.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/config/config_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isProcessing = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickFileWithFilter(List<String> allowedExtensions) async {
    bool keepProcessing = false;
    try {
      setState(() {
        _isProcessing = true;
      });
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: allowedExtensions.isEmpty ? FileType.any : FileType.custom,
        allowedExtensions: allowedExtensions.isEmpty ? null : allowedExtensions,
      );
      if (result != null && result.files.single.path != null) {
        if (mounted) {
          context.push('/analysis', extra: result.files.single.path!);
          keepProcessing = true;
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) {
              setState(() {
                _isProcessing = false;
              });
            }
          });
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
    } finally {
      if (!keepProcessing && mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _pickFileForShortcut(List<String> allowedExtensions, String targetFormat) async {
    bool keepProcessing = false;
    try {
      setState(() {
        _isProcessing = true;
      });
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: allowedExtensions.isEmpty ? FileType.any : FileType.custom,
        allowedExtensions: allowedExtensions.isEmpty ? null : allowedExtensions,
      );
      if (result != null && result.files.single.path != null) {
        if (mounted) {
          context.push('/conversion', extra: {
            'sourceFilePath': result.files.single.path!,
            'targetFormat': targetFormat,
          });
          keepProcessing = true;
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) {
              setState(() {
                _isProcessing = false;
              });
            }
          });
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
    } finally {
      if (!keepProcessing && mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _trySampleFile(String name, String sourceFormat, String targetFormat) async {
    bool keepProcessing = false;
    try {
      setState(() {
        _isProcessing = true;
      });
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}${Platform.pathSeparator}$name');
      if (!await file.exists()) {
        if (sourceFormat.toLowerCase() == 'pdf') {
          await file.writeAsBytes(utf8.encode('%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\nstream\n(Sample Invoice Text) Tj\nendstream\nendobj\n%%EOF'));
        } else if (sourceFormat.toLowerCase() == 'jpg' || sourceFormat.toLowerCase() == 'jpeg' || sourceFormat.toLowerCase() == 'png') {
          final dummyImage = img.Image(width: 200, height: 200);
          img.fill(dummyImage, color: img.ColorRgb8(255, 92, 0));
          await file.writeAsBytes(img.encodeJpg(dummyImage));
        } else {
          await file.writeAsString('Header1,Header2,Header3\nValue1,Value2,Value3\nValue4,Value5,Value6');
        }
      }
      
      if (mounted) {
        context.push('/conversion', extra: {
          'sourceFilePath': file.path,
          'targetFormat': targetFormat,
        });
        keepProcessing = true;
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            setState(() {
              _isProcessing = false;
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load sample: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (!keepProcessing && mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _pickFileForResizing() async {
    bool keepProcessing = false;
    try {
      setState(() {
        _isProcessing = true;
      });
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (mounted) {
          context.push('/image-resizer', extra: path);
          keepProcessing = true;
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) {
              setState(() {
                _isProcessing = false;
              });
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (!keepProcessing && mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _stitchImagesToPdf() async {
    bool keepProcessing = false;
    try {
      setState(() {
        _isProcessing = true;
      });
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      final List<String> paths = result != null
          ? result.files.map((f) => f.path).whereType<String>().toList()
          : <String>[];
      if (paths.isNotEmpty && mounted) {
        context.push('/img-to-pdf', extra: paths);
        keepProcessing = true;
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            setState(() {
              _isProcessing = false;
            });
          }
        });
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
    } finally {
      if (!keepProcessing && mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  String _getRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Color _getFormatColor(String format) {
    final f = format.toLowerCase();
    if (f.contains('pdf')) return const Color(0xFFFF3D00);          // Red-Orange
    if (f.contains('doc') || f.contains('word')) return const Color(0xFFFF6D00);     // Coral Orange
    if (f.contains('xls') || f.contains('csv') || f.contains('excel')) return const Color(0xFFFFAB00);   // Gold Amber
    if (f.contains('png') || f.contains('jpg') || f.contains('jpeg') || f.contains('webp') || f.contains('image')) {
      return const Color(0xFFFFD600);                               // Sun Yellow
    }
    if (f.contains('zip') || f.contains('rar') || f.contains('archive')) return const Color(0xFFFF9100); // Amber Orange
    return const Color(0xFFFF8E53);                                 // Warm Peach
  }

  IconData _getFormatIcon(String format) {
    final f = format.toLowerCase();
    if (f.contains('pdf')) return LucideIcons.fileText;
    if (f.contains('doc') || f.contains('word')) return LucideIcons.fileText;
    if (f.contains('xls') || f.contains('csv') || f.contains('excel')) return LucideIcons.table;
    if (f.contains('png') || f.contains('jpg') || f.contains('jpeg') || f.contains('webp') || f.contains('image')) {
      return LucideIcons.image;
    }
    if (f.contains('zip') || f.contains('rar') || f.contains('archive')) return LucideIcons.archive;
    return LucideIcons.file;
  }

  void _openFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      final extension = path.split('.').last.toLowerCase();
      String? mimeType;
      switch (extension) {
        case 'pptx':
          mimeType = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
          break;
        case 'pdf':
          mimeType = 'application/pdf';
          break;
        case 'docx':
          mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
          break;
        case 'xlsx':
          mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
          break;
        case 'png':
          mimeType = 'image/png';
          break;
        case 'jpg':
        case 'jpeg':
          mimeType = 'image/jpeg';
          break;
        case 'webp':
          mimeType = 'image/webp';
          break;
        case 'heic':
        case 'heif':
          mimeType = 'image/heic';
          break;
        case 'ico':
          mimeType = 'image/x-icon';
          break;
        case 'svg':
          mimeType = 'image/svg+xml';
          break;
        case 'zip':
          mimeType = 'application/zip';
          break;
        case 'csv':
          mimeType = 'text/csv';
          break;
        case 'json':
          mimeType = 'application/json';
          break;
        case 'txt':
          mimeType = 'text/plain';
          break;
      }
      await OpenFilex.open(path, type: mimeType);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Cannot open file: File no longer exists.'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _shareFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await Share.shareXFiles([XFile(path)], text: 'My converted file via FileGym');
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Cannot share: File does not exist.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final historyList = ref.watch(historyProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090A0F) : const Color(0xFFFAFAFA),
      extendBody: true,
      appBar: _buildAppBar(isDark),
      body: Stack(
        children: [
          // Background soft warm ambient glow
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
            bottom: false,
            child: IndexedStack(
              index: _currentIndex,
              children: [
                _buildDashboardTab(historyList, isDark),
                _buildWorkspaceTab(isDark),
                _buildHistoryTab(historyList, isDark),
                _buildSettingsTab(isDark),
              ],
            ),
          ),
          if (_isProcessing)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.65),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF141622) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFEAEAEE),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 35,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          strokeWidth: 4.5,
                          strokeCap: StrokeCap.round,
                          valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Processing files...',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF111116),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ).animate().fadeIn(duration: 200.ms),
        ],
      ),
      bottomNavigationBar: _buildFloatingDock(isDark),
    );
  }

  Widget _buildFloatingDock(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
      height: 76,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141622).withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFEAEAEE),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildBottomNavItem(LucideIcons.home, 'Home', 0),
            _buildBottomNavItem(LucideIcons.layoutGrid, 'Workspace', 1),
            _buildCenterDockItem(),
            _buildBottomNavItem(LucideIcons.history, 'History', 2),
            _buildBottomNavItem(LucideIcons.settings, 'Settings', 3),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterDockItem() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5C00), Color(0xFFFF9E00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF5C00).withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _pickFileWithFilter([]),
          child: const Icon(LucideIcons.arrowRightLeft, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    final activeColor = Theme.of(context).colorScheme.primary;
    final color = isSelected ? activeColor : const Color(0xFF7E7D8A);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _currentIndex = index;
          });
        },
        child: SizedBox(
          width: 50,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: color,
                size: 22,
              ).animate(target: isSelected ? 1 : 0)
               .scale(begin: const Offset(1, 1), end: const Offset(1.15, 1.15), duration: 200.ms),
              const SizedBox(height: 4),
              if (isSelected)
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: activeColor,
                    shape: BoxShape.circle,
                  ),
                )
              else
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.normal,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    if (_currentIndex == 2) {
      return AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 24,
        title: Text(
          'Conversion History', 
          style: TextStyle(fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF111116))
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.trash2, color: Color(0xFFFF3D00)),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear All History?'),
                  content: const Text('This action will delete your conversion record list. The actual files will remain on your device.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () {
                        ref.read(historyProvider.notifier).clearHistory();
                        Navigator.pop(context);
                      },
                      child: const Text('Clear', style: TextStyle(color: Color(0xFFFF3D00), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      );
    }

    if (_currentIndex == 1) {
      return AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 24,
        title: Text(
          'Convert Workspace', 
          style: TextStyle(fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF111116))
        ),
        elevation: 0,
      );
    }

    if (_currentIndex == 3) {
      return AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 24,
        title: Text(
          'App Settings', 
          style: TextStyle(fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF111116))
        ),
        elevation: 0,
      );
    }

    return AppBar(
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 24,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF5C00), Color(0xFFFF9E00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.refreshCw, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FileGym',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF111116),
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'Universal File Converter',
                style: TextStyle(
                  color: Color(0xFF70727D),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(List<HistoryItem> historyList, bool isDark) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 110.0), // Padding for Dock
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroCard(isDark),
            const SizedBox(height: 32),
            _buildSectionHeader('Smart Suggestions', ''),
            const SizedBox(height: 16),
            _buildSmartSuggestionsList(),
            const SizedBox(height: 32),
            _buildSectionHeader('Recent Files', historyList.isNotEmpty ? 'See All' : '', onTapSeeAll: () {
              if (historyList.isNotEmpty) {
                setState(() {
                  _currentIndex = 2;
                });
              }
            }),
            const SizedBox(height: 16),
            _buildRecentFilesList(historyList),
            const SizedBox(height: 32),
            _buildSectionHeader('Past Conversions', 'View Full History', onTapSeeAll: () {
              setState(() {
                _currentIndex = 2;
              });
            }),
            const SizedBox(height: 16),
            _buildPastConversionsList(historyList, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(bool isDark) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5C00), Color(0xFFFF9E00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF5C00).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            bottom: -20,
            left: -20,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: -40,
            right: -20,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(LucideIcons.fileText, color: Color(0xFFFF5C00), size: 32),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Convert Any File',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'Quick import and format conversion',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _pickFileWithFilter([]),
                  icon: const Icon(LucideIcons.plus, color: Color(0xFFFF5C00), size: 18),
                  label: const Text(
                    'Select File',
                    style: TextStyle(color: Color(0xFFFF5C00), fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn().scale(delay: 50.ms, duration: 400.ms, curve: Curves.easeOutBack);
  }

  Widget _buildSectionHeader(String title, String action, {VoidCallback? onTapSeeAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        if (action.isNotEmpty)
          InkWell(
            onTap: onTapSeeAll,
            child: Text(
              action,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSmartSuggestionsList() {
    final items = [
      {'title': 'PDF to Word', 'ext': ['pdf'], 'target': 'DOCX', 'icon': LucideIcons.fileText, 'color': const Color(0xFFFF3D00)},
      {'title': 'Image to PDF', 'ext': ['png', 'jpg', 'jpeg', 'webp'], 'target': 'PDF', 'icon': LucideIcons.image, 'color': const Color(0xFFFF6D00)},
      {'title': 'Excel to CSV', 'ext': ['xlsx'], 'target': 'CSV', 'icon': LucideIcons.table, 'color': const Color(0xFFFFAB00)},
    ];

    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final color = item['color'] as Color;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _pickFileForShortcut(item['ext'] as List<String>, item['target'] as String),
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.01),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Icon(item['icon'] as IconData, color: color, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      item['title'] as String,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentFilesList(List<HistoryItem> historyList) {
    if (historyList.isEmpty) {
      final samples = [
        {'name': 'invoice.pdf', 'source': 'PDF', 'target': 'DOCX', 'size': '1.2 MB'},
        {'name': 'photo.jpg', 'source': 'JPG', 'target': 'PNG', 'size': '3.4 MB'},
        {'name': 'financials.xlsx', 'source': 'XLSX', 'target': 'CSV', 'size': '850 KB'},
      ];

      return SizedBox(
        height: 125,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: samples.length,
          separatorBuilder: (_, _) => const SizedBox(width: 16),
          itemBuilder: (context, index) {
            final sample = samples[index];
            final color = _getFormatColor(sample['target']!);
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _trySampleFile(sample['name']!, sample['source']!, sample['target']!),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 145,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.01),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(_getFormatIcon(sample['target']!), color: color, size: 20),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Sample',
                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        sample['name']!,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '→ ${sample['target']!.toUpperCase()}',
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    final recentItems = historyList.take(4).toList();

    return SizedBox(
      height: 125,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recentItems.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final item = recentItems[index];
          final color = _getFormatColor(item.targetFormat);

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openFile(item.outputPath),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 140,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.01),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_getFormatIcon(item.targetFormat), color: color, size: 20),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.fileName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '→ ${item.targetFormat.toUpperCase()}',
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPastConversionsList(List<HistoryItem> historyList, bool isDark) {
    if (historyList.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFEDEEFC)),
        ),
        child: Column(
          children: [
            Icon(LucideIcons.fileQuestion, color: const Color(0xFFFF9E00).withValues(alpha: 0.6), size: 48),
            const SizedBox(height: 16),
            const Text(
              'No Conversions Yet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select a file above to start converting.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final itemsToShow = historyList.take(5).toList();

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemsToShow.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = itemsToShow[index];
        final color = _getFormatColor(item.targetFormat);

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.01),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openFile(item.outputPath),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(_getFormatIcon(item.targetFormat), color: color, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.fileName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${item.sourceFormat.toUpperCase()} → ${item.targetFormat.toUpperCase()}',
                                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                item.sizeString,
                                style: const TextStyle(color: Color(0xFF70727D), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _getRelativeTime(item.timestamp),
                          style: const TextStyle(color: Color(0xFF70727D), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        PopupMenuButton<String>(
                          icon: const Icon(LucideIcons.moreVertical, size: 18, color: Color(0xFF70727D)),
                          padding: EdgeInsets.zero,
                          onSelected: (value) {
                            if (value == 'open') _openFile(item.outputPath);
                            if (value == 'share') _shareFile(item.outputPath);
                            if (value == 'delete') ref.read(historyProvider.notifier).deleteHistoryItem(item.id);
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'open', child: Row(children: [Icon(LucideIcons.externalLink, size: 16), SizedBox(width: 8), Text('Open')])),
                            const PopupMenuItem(value: 'share', child: Row(children: [Icon(LucideIcons.share2, size: 16), SizedBox(width: 8), Text('Share')])),
                            const PopupMenuItem(value: 'delete', child: Row(children: [Icon(LucideIcons.trash, size: 16, color: Colors.red), SizedBox(width: 8), Text('Remove', style: TextStyle(color: Colors.red))])),
                          ],
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWorkspaceTab(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 110.0), // Padding for Dock
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Workspace Tools', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          const Text('Explore and use utility tools to process your files.', style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              physics: const BouncingScrollPhysics(),
              children: [
                // Compression Hub Box (Active!)
                _buildToolBox(
                  isDark: isDark,
                  title: 'Compression Hub',
                  subtitle: 'Direct & ZIP Compress',
                  icon: LucideIcons.shrink,
                  color: const Color(0xFFFF5C00),
                  isActive: true,
                  onTap: () => context.push('/compression-hub'),
                ),
                // Active: Image Resizer
                _buildToolBox(
                  isDark: isDark,
                  title: 'Image Resizer',
                  subtitle: 'Aspect ratio scaling',
                  icon: LucideIcons.image,
                  color: const Color(0xFF10B981),
                  isActive: true,
                  onTap: _pickFileForResizing,
                ),
                // Active: Image to PDF
                _buildToolBox(
                  isDark: isDark,
                  title: 'Image to PDF',
                  subtitle: 'Stitch images to PDF',
                  icon: LucideIcons.fileText,
                  color: const Color(0xFF3B82F6),
                  isActive: true,
                  onTap: _stitchImagesToPdf,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolBox({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isActive 
              ? color.withValues(alpha: 0.4) 
              : (isDark ? const Color(0xFF222431) : const Color(0xFFEAEAEE)),
          width: isActive ? 2.0 : 1.5,
        ),
        boxShadow: isActive ? [
          BoxShadow(
            color: color.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          )
        ] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    if (!isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Soon',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      )
                    else
                      Icon(LucideIcons.arrowRight, color: color, size: 16),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: isActive 
                            ? (isDark ? Colors.white : const Color(0xFF111116))
                            : (isDark ? Colors.white54 : Colors.black45),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isActive ? const Color(0xFF70727D) : Colors.grey.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate(target: isActive ? 1.0 : 0.8)
     .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.0, 1.0), duration: 300.ms, curve: Curves.easeOutBack);
  }

  Widget _buildHistoryTab(List<HistoryItem> historyList, bool isDark) {
    final filteredList = historyList.where((item) {
      final query = _searchQuery.toLowerCase();
      return item.fileName.toLowerCase().contains(query) ||
             item.targetFormat.toLowerCase().contains(query) ||
             item.sourceFormat.toLowerCase().contains(query);
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 110.0), // Padding for Dock
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (val) {
              setState(() {
                _searchQuery = val;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search conversions...',
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(LucideIcons.x, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark ? const Color(0xFF141622) : const Color(0xFFF1F1F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filteredList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.searchX, size: 48, color: Colors.grey.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        const Text('No conversions found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        const Text('Try typing a different name or extension.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: filteredList.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = filteredList[index];
                      final color = _getFormatColor(item.targetFormat);

                      return Dismissible(
                        key: Key(item.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (dir) {
                          ref.read(historyProvider.notifier).deleteHistoryItem(item.id);
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3D00),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(LucideIcons.trash2, color: Colors.white),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.01),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _openFile(item.outputPath),
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(_getFormatIcon(item.targetFormat), color: color, size: 24),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.fileName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: color.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  '${item.sourceFormat.toUpperCase()} → ${item.targetFormat.toUpperCase()}',
                                                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                item.sizeString,
                                                style: const TextStyle(color: Color(0xFF70727D), fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _getRelativeTime(item.timestamp),
                                          style: const TextStyle(color: Color(0xFF70727D), fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 4),
                                        IconButton(
                                          icon: const Icon(LucideIcons.share2, size: 18, color: Color(0xFF70727D)),
                                          onPressed: () => _shareFile(item.outputPath),
                                        ),
                                      ],
                                    )
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(bool isDark) {
    final themeMode = ref.watch(themeProvider);
    final quality = ref.watch(conversionQualityProvider);
    final soundAlerts = ref.watch(soundAlertsProvider);
    final pushNotifications = ref.watch(pushNotificationsProvider);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 110.0), // Padding for Dock
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: -0.5)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  _buildThemeOptionTile(
                    title: 'Light Mode',
                    icon: LucideIcons.sun,
                    isSelected: themeMode == ThemeMode.light,
                    onTap: () => ref.read(themeProvider.notifier).setThemeMode(ThemeMode.light),
                  ),
                  const Divider(height: 16),
                  _buildThemeOptionTile(
                    title: 'Dark Mode',
                    icon: LucideIcons.moon,
                    isSelected: themeMode == ThemeMode.dark,
                    onTap: () => ref.read(themeProvider.notifier).setThemeMode(ThemeMode.dark),
                  ),
                  const Divider(height: 16),
                  _buildThemeOptionTile(
                    title: 'System Settings',
                    icon: LucideIcons.monitor,
                    isSelected: themeMode == ThemeMode.system,
                    onTap: () => ref.read(themeProvider.notifier).setThemeMode(ThemeMode.system),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: -0.5)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  _buildToggleTile(
                    title: 'Sound Alerts',
                    subtitle: 'Play sound when background conversion completes',
                    icon: LucideIcons.volume2,
                    value: soundAlerts,
                    onChanged: (val) => ref.read(soundAlertsProvider.notifier).setEnabled(val),
                  ),
                  const Divider(height: 16),
                  _buildToggleTile(
                    title: 'Push Notifications',
                    subtitle: 'Show notification when file conversion finishes',
                    icon: LucideIcons.bell,
                    value: pushNotifications,
                    onChanged: (val) => ref.read(pushNotificationsProvider.notifier).setEnabled(val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text('Image Quality Preset', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: -0.5)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Default Conversion Quality', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('${quality.toInt()}%', style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: quality,
                    min: 20,
                    max: 100,
                    divisions: 16,
                    activeColor: Theme.of(context).colorScheme.primary,
                    onChanged: (val) {
                      ref.read(conversionQualityProvider.notifier).setQuality(val);
                    },
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Applies to JPEG, PNG compression and image-pdf exports. Higher quality results in larger file size.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text('Information & Legal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: -0.5)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  _buildLinkTile(
                    title: 'Privacy Policy',
                    icon: LucideIcons.shieldCheck,
                    onTap: () => _showTextDialog(
                      context,
                      'Privacy Policy',
                      'At FileGym, we respect your privacy. FileGym is a local-first application. All file conversions, metadata analysis, image resizing, and compression happen entirely offline on your device. We do not collect, upload, share, or store any of your personal data or files on external servers.',
                    ),
                  ),
                  const Divider(height: 16),
                  _buildLinkTile(
                    title: 'Terms of Service',
                    icon: LucideIcons.fileSignature,
                    onTap: () => _showTextDialog(
                      context,
                      'Terms of Service',
                      'By using FileGym, you agree that all conversions and processing are executed locally on your own hardware. FileGym is provided "as is" without warranties of any kind. You are responsible for ensuring that you have the right to process and convert the files you import.',
                    ),
                  ),
                  const Divider(height: 16),
                  _buildLinkTile(
                    title: 'Credits',
                    icon: LucideIcons.award,
                    onTap: () => _showTextDialog(
                      context,
                      'Credits',
                      'FileGym is built using Flutter and powered by open-source libraries, including:\n• google_fonts\n• lucide_icons\n• flutter_riverpod\n• go_router\n• open_filex\n• share_plus\n• flutter_animate\n• image\n• pdf\n\nSpecial thanks to the Flutter and open-source communities!',
                    ),
                  ),
                  const Divider(height: 16),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      leading: Icon(LucideIcons.user, color: Theme.of(context).colorScheme.primary),
                      title: const Text('Developer Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      childrenPadding: const EdgeInsets.only(bottom: 12, top: 4),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1C1E2D) : const Color(0xFFF6F7F9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDeveloperInfoRow('Developer', 'Pondara Akhil Behara', isDark),
                              const SizedBox(height: 8),
                              _buildDeveloperInfoRow('Academic Level', 'B.Tech', isDark),
                              const SizedBox(height: 8),
                              _buildDeveloperInfoRow('Department', 'Artificial Intelligence & Data Science (AI & DS)', isDark),
                              const SizedBox(height: 8),
                              _buildDeveloperInfoRow('Institution', 'Chaitanya Engineering College, Kommadi, Visakhapatnam', isDark),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text('Maintenance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: -0.5)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(24),
              ),
              child: OutlinedButton.icon(
                icon: const Icon(LucideIcons.refreshCcw, color: Color(0xFFFF3D00)),
                label: const Text('Reset Application Database', style: TextStyle(color: Color(0xFFFF3D00), fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Color(0xFFFFC4C4), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Reset Everything?'),
                      content: const Text('This will delete all past conversion histories and reset theme configurations and preferences to factory defaults. This cannot be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () {
                            ref.read(historyProvider.notifier).clearHistory();
                            ref.read(themeProvider.notifier).setThemeMode(ThemeMode.light);
                            ref.read(conversionQualityProvider.notifier).setQuality(80.0);
                            ref.read(soundAlertsProvider.notifier).setEnabled(true);
                            ref.read(pushNotificationsProvider.notifier).setEnabled(true);
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('App successfully reset.')),
                            );
                          },
                          child: const Text('Reset', style: TextStyle(color: Color(0xFFFF3D00))),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 48),
            const Center(
              child: Text(
                'FileGym v1.0.0 • Premium Edition',
                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOptionTile({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final activeColor = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: Icon(icon, color: isSelected ? activeColor : Colors.grey),
      title: Text(title, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      trailing: isSelected ? Icon(LucideIcons.check, color: activeColor) : null,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _buildToggleTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final activeColor = Theme.of(context).colorScheme.primary;
    return SwitchListTile(
      secondary: Icon(icon, color: value ? activeColor : Colors.grey),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: activeColor,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildLinkTile({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      trailing: const Icon(LucideIcons.chevronRight, size: 16, color: Colors.grey),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildDeveloperInfoRow(String label, String value, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.grey,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: isDark ? Colors.white : const Color(0xFF111116),
            ),
          ),
        ),
      ],
    );
  }

  void _showTextDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        content: SingleChildScrollView(
          child: Text(
            content,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
