import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/design/flora_components.dart';
import 'package:blueflora/presentation/widgets/watering_event_tile.dart';
import 'package:flutter/material.dart';

import 'tree_detail_view.dart';

class HistoryView extends StatelessWidget {
  const HistoryView({super.key, required this.controller});
  final TreesController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, child) {
      final events = controller.eventsFor();
      return Scaffold(
        appBar: AppBar(title: const Text('Historial')),
        body: SafeArea(
          top: false,
          child: ListView.builder(
            padding: const EdgeInsets.all(FloraTokens.padding),
            itemCount: controller.loading || controller.loadError != null
                ? 1
                : events.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.history_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 32,
                        ),
                        const SizedBox(width: FloraTokens.space),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FloraSectionHeading(
                                title: 'Los cuidados de tu jardín',
                              ),
                              const Text(
                                'Consulta los riegos que has registrado, del más reciente al más antiguo.',
                              ),
                              const SizedBox(height: FloraTokens.space),
                              Text(
                                'Registros manuales, sin activar bombas.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: FloraTokens.padding),
                    if (controller.loading)
                      const FloraInfoCard(
                        child: FloraLoading(label: 'Abriendo tu historial…'),
                      )
                    else if (controller.loadError != null)
                      FloraMessage(
                        title: 'No pudimos consultar los registros',
                        message: controller.loadError!,
                        status: FloraStatus.error,
                        action: TextButton(
                          onPressed: controller.load,
                          child: const Text('Reintentar'),
                        ),
                      )
                    else ...[
                      if (controller.saving)
                        const FloraLoading(label: 'Guardando cambios…'),
                      if (controller.saveError != null)
                        FloraMessage(
                          title: 'El guardado sigue pendiente',
                          message: controller.saveError!,
                          status: FloraStatus.error,
                          action: TextButton(
                            onPressed: controller.canRetrySave
                                ? controller.retrySave
                                : null,
                            child: const Text('Reintentar guardado'),
                          ),
                        ),
                      if (events.isEmpty)
                        FloraInfoCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Icon(
                                Icons.eco_outlined,
                                color: Theme.of(context).colorScheme.primary,
                                size: 36,
                              ),
                              const FloraSectionHeading(
                                title: 'Aún no hay riegos registrados',
                              ),
                              const Text(
                                'Tu historial empieza con el próximo riego que registres.',
                              ),
                              const SizedBox(height: FloraTokens.space),
                              const Text(
                                'Los riegos manuales que guardes aparecerán aquí. Las fechas previas no se convierten en eventos históricos.',
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                );
              }
              final event = events[index - 1];
              final plant = controller.plantById(event.plantId);
              return WateringEventTile(
                key: ValueKey('history-${event.id}'),
                event: event,
                currentName: plant?.nombre,
                onOpen: plant == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TreeDetailView(
                            controller: controller,
                            plantId: event.plantId,
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      );
    },
  );
}
