import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/domain/watering_summary.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/design/flora_components.dart';
import 'package:blueflora/presentation/widgets/watering_event_tile.dart';
import 'package:flutter/material.dart';

import 'addtree_view.dart';
import 'package:blueflora/domain/tree.dart';

class TreeDetailView extends StatefulWidget {
  const TreeDetailView({
    super.key,
    required this.controller,
    required this.plantId,
  });
  final TreesController controller;
  final String plantId;

  @override
  State<TreeDetailView> createState() => _TreeDetailViewState();
}

class _TreeDetailViewState extends State<TreeDetailView> {
  bool _editing = false;

  Future<void> _edit(Tree tree) async {
    if (_editing || !widget.controller.canModify) return;
    setState(() => _editing = true);
    final result = await Navigator.push<Tree>(
      context,
      MaterialPageRoute(builder: (_) => AddTreeView(tree: tree)),
    );
    if (!mounted) return;
    setState(() => _editing = false);
    if (result != null) await widget.controller.edit(result);
  }

  String _status(Tree tree) =>
      switch (WateringSummary.statusOf(tree, widget.controller.now)) {
        WateringStatus.undated =>
          'Calendario desconocido: falta la fecha del último riego.',
        WateringStatus.overdue => 'Riego vencido según el calendario.',
        WateringStatus.today => 'Riego programado para hoy.',
        WateringStatus.tomorrow => 'Riego programado para mañana.',
        WateringStatus.later => 'Riego programado para más adelante.',
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, child) {
      final controller = widget.controller;
      final tree = controller.plantById(widget.plantId);
      final events = controller.eventsFor(widget.plantId);
      final theme = Theme.of(context);
      final canEdit = controller.canModify && !_editing;
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle de planta')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(FloraTokens.padding),
            children: [
              if (controller.loading)
                const FloraInfoCard(
                  child: FloraLoading(label: 'Abriendo la ficha de tu planta…'),
                )
              else if (controller.loadError != null)
                FloraMessage(
                  title: 'No pudimos abrir la ficha',
                  message: controller.loadError!,
                  status: FloraStatus.error,
                  action: TextButton(
                    onPressed: controller.load,
                    child: const Text('Reintentar'),
                  ),
                )
              else if (tree == null)
                const FloraMessage(
                  title: 'Una etapa de tu jardín',
                  message:
                      'Esta planta ya no está registrada. Su historial se conserva.',
                )
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.spa_outlined,
                      color: theme.colorScheme.primary,
                      size: 36,
                    ),
                    const SizedBox(width: FloraTokens.padding),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tree.nombre,
                            key: const ValueKey('detail-name'),
                            style: theme.textTheme.headlineMedium,
                          ),
                          if (tree.especie != null)
                            Text(
                              tree.especie!,
                              style: theme.textTheme.titleMedium,
                            ),
                          const Text('Una ficha para acompañar sus cuidados.'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FloraTokens.padding),
                OutlinedButton.icon(
                  onPressed: canEdit ? () => _edit(tree) : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar planta'),
                ),
                FloraInfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FloraSectionHeading(title: 'Conoce tu planta'),
                      Text('Nombre: ${tree.nombre}'),
                      const SizedBox(height: FloraTokens.space),
                      Text(
                        tree.especie == null
                            ? 'Especie no registrada'
                            : 'Especie: ${tree.especie}',
                      ),
                      const SizedBox(height: FloraTokens.space),
                      Text(
                        tree.altura == null
                            ? 'Altura no registrada'
                            : 'Altura: ${tree.altura} m',
                      ),
                      const SizedBox(height: FloraTokens.space),
                      Text(
                        'Frecuencia: cada ${tree.frecuenciaRiegoDias} ${tree.frecuenciaRiegoDias == 1 ? 'día' : 'días'}',
                      ),
                    ],
                  ),
                ),
                FloraInfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FloraSectionHeading(
                        title: 'Su calendario de riego',
                      ),
                      FloraStatusLabel(
                        label: _status(tree),
                        status: switch (WateringSummary.statusOf(
                          tree,
                          controller.now,
                        )) {
                          WateringStatus.overdue => FloraStatus.error,
                          WateringStatus.today => FloraStatus.warning,
                          WateringStatus.undated => FloraStatus.neutral,
                          _ => FloraStatus.success,
                        },
                      ),
                      const SizedBox(height: FloraTokens.padding),
                      Text(
                        tree.ultimoRiego == null
                            ? 'Último riego: desconocido'
                            : 'Último riego: ${formatLocalDateTime(tree.ultimoRiego!)}',
                        key: const ValueKey('detail-last-water'),
                      ),
                      const SizedBox(height: FloraTokens.space),
                      Text(
                        tree.ultimoRiego == null
                            ? 'Próximo riego: no se puede calcular sin una fecha previa.'
                            : 'Próximo riego: ${formatLocalDateTime(tree.ultimoRiego!.add(Duration(days: tree.frecuenciaRiegoDias)))}',
                      ),
                      if (tree.ultimoRiego != null) ...[
                        const SizedBox(height: FloraTokens.space),
                        Text(
                          _remaining(tree),
                          key: const ValueKey('detail-remaining'),
                        ),
                      ],
                      const SizedBox(height: FloraTokens.padding),
                      const Text(
                        'Este calendario usa fechas registradas, no mediciones de humedad. Una fecha desconocida no indica falta de agua.',
                      ),
                    ],
                  ),
                ),
                if (controller.saving)
                  const FloraLoading(label: 'Guardando cambios…'),
                if (controller.saveError != null)
                  FloraMessage(
                    title: 'El registro sigue pendiente',
                    message: controller.saveError!,
                    status: FloraStatus.error,
                    action: TextButton(
                      onPressed: controller.canRetrySave
                          ? controller.retrySave
                          : null,
                      child: const Text('Reintentar guardado'),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(FloraTokens.space),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        onPressed: canEdit
                            ? () => controller.water(tree.id)
                            : null,
                        icon: const Icon(Icons.water_drop_outlined),
                        label: const Text('Registrar riego manual'),
                      ),
                      const SizedBox(height: FloraTokens.space),
                      const Text(
                        'Registra un riego que hayas realizado. Esta acción no activa una bomba.',
                      ),
                    ],
                  ),
                ),
                const FloraSectionHeading(title: 'Historial de riegos'),
                if (events.isEmpty)
                  const FloraMessage(
                    title: 'Cada cuidado cuenta',
                    message: 'Aún no hay riegos registrados para esta planta.',
                  )
                else
                  for (final event in events)
                    WateringEventTile(
                      event: event,
                      currentName: tree.nombre,
                      detailed: true,
                    ),
              ],
            ],
          ),
        ),
      );
    },
  );

  String _remaining(Tree tree) {
    final days = tree.diasRestantes(ahora: widget.controller.now);
    if (WateringSummary.statusOf(tree, widget.controller.now) ==
        WateringStatus.overdue) {
      // El modelo redondea hacia arriba: un vencido reciente puede devolver 0.
      return days == 0
          ? 'Vencido hace menos de 24 horas.'
          : 'Vencido: ${days.abs()} ${days.abs() == 1 ? 'día completo' : 'días completos'} de 24 horas.';
    }
    return days == 0
        ? 'Programado para este momento.'
        : 'Faltan $days ${days == 1 ? 'periodo' : 'periodos'} de hasta 24 horas.';
  }
}
