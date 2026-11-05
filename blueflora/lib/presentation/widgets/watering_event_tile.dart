import 'package:blueflora/domain/watering_event.dart';
import 'package:flutter/material.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/design/flora_components.dart';

String formatLocalDateTime(DateTime date) {
  final local = date.toLocal();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} ${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
}

class WateringEventTile extends StatelessWidget {
  const WateringEventTile({
    super.key,
    required this.event,
    this.currentName,
    this.onOpen,
    this.detailed = false,
  });
  final WateringEvent event;
  final String? currentName;
  final VoidCallback? onOpen;
  final bool detailed;

  @override
  Widget build(BuildContext context) => detailed
      ? FloraInfoCard(
          child: Column(
            key: ValueKey('event-${event.id}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FloraStatusLabel(
                label: 'Registro manual',
                status: FloraStatus.neutral,
              ),
              const SizedBox(height: FloraTokens.space),
              Text(
                formatLocalDateTime(event.occurredAt),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: FloraTokens.space),
              Text(currentName ?? event.plantName),
              if (currentName != null && currentName != event.plantName)
                Text('Nombre al registrar: ${event.plantName}'),
              const Text('Riego registrado por ti, sin activar hardware.'),
            ],
          ),
        )
      : Card(
          child: ListTile(
            key: ValueKey('event-${event.id}'),
            contentPadding: const EdgeInsets.all(FloraTokens.padding),
            title: Text(
              currentName ?? event.plantName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: FloraTokens.space),
                Wrap(
                  spacing: FloraTokens.space,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.water_drop_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    const Text('Registro manual'),
                  ],
                ),
                const SizedBox(height: FloraTokens.space),
                Text(formatLocalDateTime(event.occurredAt)),
                if (currentName == null) ...[
                  const SizedBox(height: FloraTokens.space),
                  const Text('Planta eliminada'),
                ],
                if (currentName != null && currentName != event.plantName) ...[
                  const SizedBox(height: FloraTokens.space),
                  Text('Nombre al registrar: ${event.plantName}'),
                ],
              ],
            ),
            onTap: onOpen,
            trailing: onOpen == null ? null : const Icon(Icons.chevron_right),
          ),
        );
}
