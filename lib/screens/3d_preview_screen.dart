import 'package:flutter/material.dart';

class Preview3DScreen extends StatelessWidget {
  const Preview3DScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("3D Preview")),
      body: Center(
        child: Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(-0.5)
            ..rotateY(0.5),
          alignment: Alignment.center,
          child: Container(
            width: 300,
            height: 200,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }
}
