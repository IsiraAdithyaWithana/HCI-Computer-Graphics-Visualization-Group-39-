import 'package:flutter/material.dart';
import 'room_canvas.dart';

class MouseToolSidebar extends StatelessWidget {
  final MouseMode currentMode;
  final Function(MouseMode) onModeChanged;

  const MouseToolSidebar({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      color: Colors.grey[900],
      child: Column(
        children: [
          const SizedBox(height: 20),

          _buildButton(icon: Icons.mouse, mode: MouseMode.select),

          _buildButton(icon: Icons.pan_tool, mode: MouseMode.hand),

          _buildButton(icon: Icons.crop_square, mode: MouseMode.draw),
        ],
      ),
    );
  }

  Widget _buildButton({required IconData icon, required MouseMode mode}) {
    final isActive = currentMode == mode;

    return GestureDetector(
      onTap: () => onModeChanged(mode),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
