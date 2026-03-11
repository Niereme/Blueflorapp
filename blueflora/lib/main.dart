import 'package:blueflora/presentation/screens/main_screen.dart';
import 'package:flutter/material.dart';
import 'services/notification_service.dart';
void main() async {

  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.init();

  runApp(Blueflora());
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
