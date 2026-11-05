import 'package:blueflora/application/settings_controller.dart';
import 'package:blueflora/application/reminders_controller.dart';
import 'package:blueflora/services/notification_service.dart';
import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/data/local_tree_repository.dart';

import 'package:blueflora/presentation/screens/views/history_view.dart';
import 'package:blueflora/presentation/screens/views/home_view.dart';
import 'package:blueflora/presentation/screens/views/profile_view.dart';
import 'package:blueflora/presentation/screens/views/trees_view.dart';
import 'package:flutter/material.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    this.repository,
    this.settings,
    this.notificationGateway,
  });

  final LocalTreeRepository? repository;
  final SettingsController? settings;
  final NotificationGateway? notificationGateway;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;
  late final TreesController _controller;
  late final SettingsController _settings;
  late final RemindersController _reminders;

  @override
  void initState() {
    super.initState();
    _controller = TreesController(
      repository: widget.repository ?? LocalTreeRepository(),
    );
    _settings = widget.settings ?? SettingsController();
    _reminders = RemindersController(
      trees: _controller,
      settings: _settings,
      gateway: widget.notificationGateway ?? NotificationService(),
    );
    if (widget.settings == null) _settings.load();
    _controller.load();
  }

  @override
  void dispose() {
    _reminders.dispose();
    if (widget.settings == null) _settings.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeView(
        controller: _controller,
        onOpenTrees: () => setState(() => selectedIndex = 1),
      ),
      TreesView(controller: _controller),
      HistoryView(controller: _controller),
      ProfileView(settings: _settings, reminders: _reminders),
    ];
    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: screens),

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.shifting,
        selectedItemColor: Theme.of(context).colorScheme.onPrimaryContainer,
        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
        currentIndex: selectedIndex,
        onTap: (value) {
          setState(() {
            selectedIndex = value;
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            activeIcon: const Icon(Icons.home),
            label: "Inicio",
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.forest),
            activeIcon: const Icon(Icons.forest),
            label: "Árboles",
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.history),
            activeIcon: const Icon(Icons.history),
            label: "Historial",
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.account_circle),
            activeIcon: const Icon(Icons.account_circle),
            label: "Perfil",
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          ),
        ],
      ),
    );
  }
}
