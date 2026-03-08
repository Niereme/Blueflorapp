import 'package:blueflora/presentation/screens/main_screen.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const Blueflora());
}

class Blueflora extends StatelessWidget {
  const Blueflora({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "blueflora",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const MainScreen(),
    );
  }
}
