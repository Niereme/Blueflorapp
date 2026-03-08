import 'package:flutter/material.dart';

class TreeSquare extends StatelessWidget {
  const TreeSquare({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        height: 200,
        color: const Color.fromARGB(255, 132, 235, 137),
      ),
    );
  }
}