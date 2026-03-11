

import 'package:blueflora/presentation/screens/views/history_view.dart';
import 'package:blueflora/presentation/screens/views/home_view.dart';
import 'package:blueflora/presentation/screens/views/profile_view.dart';
import 'package:blueflora/presentation/screens/views/trees_view.dart';
import 'package:flutter/material.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;
  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeView(),
      const TreesView(),
      const HistoryView(),
      const ProfileView(),
    ];
    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: screens),
     
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.shifting,
        currentIndex: selectedIndex,
        onTap: (value) {
          setState(() {
            selectedIndex = value;
          });
        },
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home),
            activeIcon: Icon(Icons.home),
            label: "inicio",
            backgroundColor: Color.fromARGB(255, 7, 146, 14),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.forest),
            activeIcon: const Icon(Icons.forest),
            label: "arboles",
            backgroundColor: const Color.fromARGB(255, 7, 146, 14),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.history),
            activeIcon: const Icon(Icons.history),
            label: "historial",
            backgroundColor: const Color.fromARGB(255, 7, 146, 14),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.account_circle),
            activeIcon: const Icon(Icons.account_circle),
            label: "Perfil",
            backgroundColor: const Color.fromARGB(255, 7, 146, 14),
          ),
        ],
      ),
    );
  }
}
