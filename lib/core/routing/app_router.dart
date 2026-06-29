import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/conversion/presentation/conversion_screen.dart';
import '../../features/compression/presentation/compression_screen.dart';
import '../../features/compression/presentation/compression_hub_screen.dart';
import '../../features/image_resizer/presentation/image_resizer_screen.dart';
import '../../features/img_to_pdf/presentation/img_to_pdf_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final goRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/compression-hub',
      builder: (context, state) => const CompressionHubScreen(),
    ),
    GoRoute(
      path: '/analysis',
      builder: (context, state) {
        final filePath = state.extra as String;
        return ConversionScreen(sourceFilePath: filePath);
      },
    ),
    GoRoute(
      path: '/conversion',
      builder: (context, state) {
        if (state.extra is Map) {
          final args = state.extra as Map<String, dynamic>;
          return ConversionScreen(
            sourceFilePath: args['sourceFilePath'] as String,
            targetFormat: args['targetFormat'] as String?,
          );
        } else {
          final filePath = state.extra as String;
          return ConversionScreen(sourceFilePath: filePath);
        }
      },
    ),
    GoRoute(
      path: '/compression',
      builder: (context, state) {
        final filePath = state.extra as String;
        return CompressionScreen(sourceFilePath: filePath);
      },
    ),
    GoRoute(
      path: '/image-resizer',
      builder: (context, state) {
        final filePath = state.extra as String;
        return ImageResizerScreen(sourceFilePath: filePath);
      },
    ),
    GoRoute(
      path: '/img-to-pdf',
      builder: (context, state) {
        final filePaths = (state.extra as List<String>?) ?? const <String>[];
        return ImgToPdfScreen(sourceFilePaths: filePaths);
      },
    ),
  ],
);
