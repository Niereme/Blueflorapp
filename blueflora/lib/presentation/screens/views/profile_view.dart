import 'package:blueflora/application/reminders_controller.dart';
import 'package:blueflora/application/settings_controller.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/design/flora_components.dart';
import 'package:flutter/material.dart';
import 'settings_view.dart';

class ProfileView extends StatelessWidget {
  const ProfileView({
    super.key,
    required this.settings,
    required this.reminders,
  });
  final SettingsController settings;
  final RemindersController reminders;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Perfil')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(FloraTokens.padding),
        children: [
          Icon(
            Icons.spa_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const FloraSectionHeading(title: 'Tu espacio en BlueFlora'),
          Text(
            'Un jardín a tu ritmo',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: FloraTokens.space),
          const Text('Personaliza cómo acompañas los cuidados de tus plantas.'),
          const SizedBox(height: FloraTokens.section),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(FloraTokens.padding),
              title: const Text('Configuraciones'),
              subtitle: const Text(
                'Apariencia, horario y recordatorios de riego.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SettingsView(settings: settings, reminders: reminders),
                ),
              ),
            ),
          ),
          const FloraInfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FloraSectionHeading(title: 'Tu jardín en este dispositivo'),
                Text(
                  'Las plantas, el historial y las preferencias se guardan localmente. No necesitas una cuenta para usar BlueFlora.',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
