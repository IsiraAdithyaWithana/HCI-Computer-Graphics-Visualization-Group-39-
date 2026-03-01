import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'services/custom_furniture_registry.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved custom furniture from disk before the UI starts.
  // This reads %APPDATA%\furniture_visualizer\custom_furniture.json
  // so all previously added GLB models appear in the sidebar immediately.
  await CustomFurnitureRegistry.instance.load();

  runApp(const FurnitureApp());
}

class FurnitureApp extends StatelessWidget {
  const FurnitureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Furniture Visualizer',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blueGrey),
      home: const LoginScreen(),
    );
  }
}
