import 'package:blueflora/application/reminders_controller.dart';
import 'package:blueflora/application/settings_controller.dart';
import 'package:blueflora/domain/app_settings.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/design/flora_components.dart';
import 'package:flutter/material.dart';
import 'package:blueflora/presentation/widgets/flora_time_picker.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    required this.settings,
    required this.reminders,
  });
  final SettingsController settings;
  final RemindersController reminders;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([settings, reminders]),
    builder: (context, child) {
      final value = settings.value;
      final enabled =
          settings.canModify &&
          !reminders.working &&
          !reminders.changingPermission;
      return Scaffold(
        appBar: AppBar(title: const Text('Configuraciones')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(FloraTokens.padding),
            children: [
              const FloraSectionHeading(title: 'BlueFlora, a tu manera'),
              const Text('Elige una apariencia y un horario que te acompañen.'),
              const SizedBox(height: FloraTokens.padding),
              if (settings.loading)
                const FloraInfoCard(
                  child: FloraLoading(label: 'Cargando tus preferencias…'),
                )
              else ...[
                if (settings.saving ||
                    reminders.working ||
                    reminders.changingPermission)
                  const FloraLoading(
                    label: 'Actualizando preferencias y recordatorios…',
                  ),
                if (settings.error != null)
                  FloraMessage(
                    title: 'No pudimos completar el cambio',
                    message: settings.error!,
                    status: FloraStatus.error,
                    action: !settings.ready
                        ? TextButton(
                            onPressed: settings.load,
                            child: const Text('Reintentar preferencias'),
                          )
                        : const Text(
                            'Vuelve a elegir la preferencia para reintentar.',
                          ),
                  ),
                FloraInfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FloraSectionHeading(title: 'Apariencia'),
                      const Text(
                        'El tema automático sigue la apariencia de tu dispositivo.',
                      ),
                      const SizedBox(height: FloraTokens.padding),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Tema'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<AppTheme>(
                            key: const ValueKey('theme-choice'),
                            value: value.theme,
                            isExpanded: true,
                            itemHeight: null,
                            items: const [
                              DropdownMenuItem(
                                value: AppTheme.system,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text('Automático (sistema)'),
                                ),
                              ),
                              DropdownMenuItem(
                                value: AppTheme.light,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text('Claro'),
                                ),
                              ),
                              DropdownMenuItem(
                                value: AppTheme.dark,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text('Oscuro'),
                                ),
                              ),
                            ],
                            onChanged: !enabled
                                ? null
                                : (theme) {
                                    if (theme != null) {
                                      settings.save(
                                        settings.value.copyWith(theme: theme),
                                      );
                                    }
                                  },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                FloraInfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FloraSectionHeading(title: 'Cuida tu calendario'),
                      SwitchListTile(
                        key: const ValueKey('reminders-toggle'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Recordatorios de riego'),
                        subtitle: const Text(
                          'Avisos basados en calendario, sin sensores.',
                        ),
                        value: value.remindersEnabled,
                        onChanged: enabled ? reminders.setEnabled : null,
                      ),
                      const SizedBox(height: FloraTokens.space),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Hora preferida'),
                        subtitle: Text(
                          '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
                        ),
                        trailing: const Icon(Icons.schedule_outlined),
                        onTap: !enabled
                            ? null
                            : () async {
                                final time = await showFloraTimePicker(
                                  context,
                                  TimeOfDay(
                                    hour: value.hour,
                                    minute: value.minute,
                                  ),
                                );
                                if (time != null && context.mounted) {
                                  await settings.save(
                                    settings.value.copyWith(
                                      hour: time.hour,
                                      minute: time.minute,
                                    ),
                                  );
                                }
                              },
                      ),
                      const SizedBox(height: FloraTokens.padding),
                      FloraStatusLabel(
                        label: value.remindersEnabled
                            ? 'Preferencia: recordatorios activados'
                            : 'Preferencia: recordatorios desactivados',
                        status: FloraStatus.neutral,
                      ),
                      const SizedBox(height: FloraTokens.space),
                      const Text(
                        'Activar esta preferencia no garantiza el permiso de Android ni la entrega del aviso.',
                      ),
                      if (reminders.error != null) ...[
                        const SizedBox(height: FloraTokens.padding),
                        FloraStatusLabel(
                          label: reminders.error!,
                          status: FloraStatus.error,
                        ),
                        TextButton(
                          onPressed: enabled
                              ? () => reminders.sync(force: true)
                              : null,
                          child: const Text('Reintentar recordatorios'),
                        ),
                        if (reminders.permissionDenied)
                          TextButton(
                            onPressed: enabled
                                ? () => reminders.setEnabled(true)
                                : null,
                            child: const Text('Solicitar permiso'),
                          ),
                      ],
                      const SizedBox(height: FloraTokens.padding),
                      const Text(
                        'Como máximo un aviso por planta y ciclo, según el último riego y la frecuencia. Se usa el primer horario preferido que no sea anterior al vencimiento y que todavía sea futuro.',
                      ),
                      const SizedBox(height: FloraTokens.space),
                      const Text(
                        'Sin fecha de último riego no se programa. Los vencidos pasan al siguiente horario futuro, sin acumular avisos antiguos ni repetirse diariamente.',
                      ),
                    ],
                  ),
                ),
                const FloraInfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FloraSectionHeading(title: 'Información y ayuda'),
                      FloraStatusLabel(
                        label:
                            'Android puede retrasar los avisos para ahorrar batería. Usamos alarmas inexactas.',
                        status: FloraStatus.warning,
                      ),
                      SizedBox(height: FloraTokens.padding),
                      Text(
                        'Si cambias de zona horaria, abre la app para actualizar la programación. Los permisos se administran desde los ajustes de Android.',
                      ),
                      SizedBox(height: FloraTokens.space),
                      Text(
                        'BlueFlora organiza tus plantas y registra riegos manuales. Registrar un riego no activa bombas.',
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
