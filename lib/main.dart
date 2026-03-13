import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'services/custom_furniture_registry.dart';
import 'services/furniture_scale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/thumbnail_cache.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved custom furniture from disk before the UI starts.
  // This reads %APPDATA%\furniture_visualizer\custom_furniture.json
  // so all previously added GLB models appear in the sidebar immediately.
  await CustomFurnitureRegistry.instance.load();

  // Load persisted per-type scale factors so resized furniture remembers
  // its size across sessions, hot reloads, and full app restarts.
  await FurnitureScaleService.instance.load();

  // Wipe any thumbnails cached before the orientation/stretch fix (v2).
  // After this one-time clear they will regenerate with correct aspect ratio.
  const thumbVersion = 'v7';
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString('thumb_cache_version') != thumbVersion) {
    await ThumbnailCache.instance.clearAll();
    await prefs.setString('thumb_cache_version', thumbVersion);
    debugPrint('[Main] thumbnail cache cleared for $thumbVersion');
  } else {
    // Load previously generated thumbnails from disk (instant on subsequent launches)
    await ThumbnailCache.instance.loadAll();
  }

  runApp(const FurnitureApp());
}

class FurnitureApp extends StatelessWidget {
  const FurnitureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Spazio — Room Designer',
      theme: AppTheme.themeData,
      home: const LoginScreen(),
    );
  }
}
