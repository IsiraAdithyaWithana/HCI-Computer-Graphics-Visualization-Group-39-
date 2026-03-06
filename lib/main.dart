import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'services/custom_furniture_registry.dart';
import 'services/furniture_scale_service.dart';
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
