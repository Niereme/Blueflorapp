import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/domain/watering_summary.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/design/flora_components.dart';
import 'package:blueflora/presentation/widgets/watering_event_tile.dart';
import 'package:flutter/material.dart';

class TreeSquare extends StatelessWidget {
  const TreeSquare({
    super.key,
    required this.tree,
    required this.onWater,
    required this.onEdit,
    required this.onOpen,
    this.onDelete,
    this.now,
    this.enabled = true,
  });
  final Tree tree;
  final VoidCallback onWater, onEdit, onOpen;
  final VoidCallback? onDelete;
  final DateTime? now;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = WateringSummary.statusOf(tree, now ?? DateTime.now());
    final (label, tone) = switch (status) {
      WateringStatus.overdue => ('Riego vencido', FloraStatus.error),
      WateringStatus.today => ('Pendiente hoy', FloraStatus.warning),
      WateringStatus.tomorrow => (
        'Programado para mañana',
        FloraStatus.success,
      ),
      WateringStatus.later => ('Próximo riego programado', FloraStatus.success),
      WateringStatus.undated => (
        'Último riego desconocido',
        FloraStatus.neutral,
      ),
    };
    final last = tree.ultimoRiego;
    return FloraInfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.park_outlined,
                color: theme.colorScheme.primary,
                size: 32,
              ),
              const SizedBox(width: FloraTokens.space),
              Expanded(
                child: Text(tree.nombre, style: theme.textTheme.titleLarge),
              ),
            ],
          ),
          if (tree.especie != null) ...[
            const SizedBox(height: FloraTokens.space),
            Text('Especie: ${tree.especie}'),
          ],
          if (tree.altura != null) Text('Altura: ${tree.altura} m'),
          const SizedBox(height: FloraTokens.padding),
          FloraStatusLabel(label: label, status: tone),
          const SizedBox(height: FloraTokens.space),
          Text(
            'Riego: cada ${tree.frecuenciaRiegoDias} ${tree.frecuenciaRiegoDias == 1 ? 'día' : 'días'}',
          ),
          if (last != null)
            Text(
              'Próximo riego: ${formatLocalDateTime(last.add(Duration(days: tree.frecuenciaRiegoDias)))}',
            )
          else
            const Text(
              'Completa el último riego para conocer su calendario. No indica que necesite agua.',
            ),
          const SizedBox(height: FloraTokens.space),
          Wrap(
            spacing: FloraTokens.space,
            children: [
              IconButton(
                tooltip: 'Ver detalle',
                onPressed: enabled ? onOpen : null,
                icon: const Icon(Icons.info_outline),
              ),
              IconButton(
                tooltip: 'Editar árbol',
                onPressed: enabled ? onEdit : null,
                icon: const Icon(Icons.edit),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Eliminar árbol',
                  onPressed: enabled ? onDelete : null,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: enabled ? onWater : null,
            icon: const Icon(Icons.water_drop_outlined),
            label: const Text('Registrar riego'),
          ),
          const SizedBox(height: FloraTokens.space),
          Text(
            'Registro manual. No activa bombas.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
