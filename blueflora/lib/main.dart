import 'package:blueflora/application/settings_controller.dart';
import 'package:blueflora/domain/app_settings.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/screens/main_screen.dart';
import 'package:blueflora/services/notification_service.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Blueflora());
}

class Blueflora extends StatefulWidget {
  const Blueflora({super.key, this.settings, this.notificationGateway});
  final SettingsController? settings;
  final NotificationGateway? notificationGateway;
  @override
  State<Blueflora> createState() => _BluefloraState();
}

class _BluefloraState extends State<Blueflora> {
  late final SettingsController _settings;
  @override
  void initState() {
    super.initState();
    _settings = widget.settings ?? SettingsController();
    _settings.load();
  }

  @override
  void dispose() {
    if (widget.settings == null) _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _settings,
    builder: (context, child) => MaterialApp(
      title: 'blueflora',
      debugShowCheckedModeBanner: false,
      theme: BluefloraTheme.light,
      darkTheme: BluefloraTheme.dark,
      themeAnimationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : FloraTokens.motion,
      themeMode: switch (_settings.value.theme) {
        AppTheme.system => ThemeMode.system,
        AppTheme.light => ThemeMode.light,
        AppTheme.dark => ThemeMode.dark,
      },
      home: MainScreen(
        settings: _settings,
        notificationGateway: widget.notificationGateway,
      ),
    ),
  );
}
