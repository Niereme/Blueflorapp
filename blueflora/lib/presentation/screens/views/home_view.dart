import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/domain/watering_summary.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/design/flora_components.dart';
import 'package:flutter/material.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.controller, this.onOpenTrees});

  final TreesController controller;
  final VoidCallback? onOpenTrees;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, child) {
      final summary = controller.summary;
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      return Scaffold(
        appBar: AppBar(title: const Text('Inicio')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(FloraTokens.padding),
            children: [
              if (controller.saving)
                const Padding(
                  padding: EdgeInsets.only(bottom: FloraTokens.padding),
                  child: FloraLoading(label: 'Guardando cambios…'),
                ),
              if (controller.saveError != null)
                FloraMessage(
                  title: 'No pudimos guardar los cambios',
                  message: controller.saveError!,
                  status: FloraStatus.error,
                  action: TextButton(
                    onPressed: controller.canRetrySave
                        ? controller.retrySave
                        : null,
                    child: const Text('Reintentar guardado'),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(FloraTokens.radius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        Icons.spa_outlined,
                        color: colors.onPrimaryContainer,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(width: FloraTokens.padding),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bienvenido a BlueFlora',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: FloraTokens.space),
                        Text(
                          'Un momento para cuidar tu jardín.',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FloraTokens.section),
              if (controller.loading)
                const FloraInfoCard(
                  child: FloraLoading(label: 'Preparando tu jardín…'),
                )
              else if (controller.loadError != null)
                FloraMessage(
                  title: 'Tu jardín sigue aquí',
                  message: controller.loadError!,
                  status: FloraStatus.error,
                  action: TextButton(
                    onPressed: controller.load,
                    child: const Text('Reintentar'),
                  ),
                )
              else ...[
                FloraInfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tu jardín',
                                  style: theme.textTheme.titleLarge,
                                ),
                                Text(
                                  'Total de plantas',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: FloraTokens.space),
                          Text(
                            '${summary.total}',
                            key: const ValueKey('summary-total'),
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: FloraTokens.padding),
                      if (summary.total == 0) ...[
                        const FloraSectionHeading(
                          title: 'Tu jardín empieza aquí',
                        ),
                        const Text(
                          'Agrega tu primera planta en Mis árboles. Iremos organizando su calendario contigo.',
                        ),
                      ] else
                        FloraStatusLabel(
                          label: _gardenMessage(summary),
                          status: summary.overdue > 0 || summary.today > 0
                              ? FloraStatus.warning
                              : summary.undated > 0
                              ? FloraStatus.neutral
                              : FloraStatus.success,
                        ),
                      if (onOpenTrees != null) ...[
                        const SizedBox(height: FloraTokens.padding),
                        FilledButton.icon(
                          key: const ValueKey('home-open-trees'),
                          onPressed: onOpenTrees,
                          icon: const Icon(Icons.forest_outlined),
                          label: const Text('Mis árboles'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: FloraTokens.space),
                FloraInfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FloraSectionHeading(title: 'Calendario de riego'),
                      _CalendarMetric(
                        name: 'overdue',
                        label: 'Riegos vencidos',
                        description: 'La fecha registrada ya pasó.',
                        value: summary.overdue,
                        status: FloraStatus.error,
                        icon: Icons.history_outlined,
                      ),
                      const Divider(height: FloraTokens.section),
                      _CalendarMetric(
                        name: 'today',
                        label: 'Pendientes hoy',
                        description: 'Programados para más tarde o ahora.',
                        value: summary.today,
                        status: FloraStatus.warning,
                        icon: Icons.today_outlined,
                      ),
                      const Divider(height: FloraTokens.section),
                      _CalendarMetric(
                        name: 'tomorrow',
                        label: 'Programados para mañana',
                        value: summary.tomorrow,
                        status: FloraStatus.success,
                        icon: Icons.event_outlined,
                      ),
                      const Divider(height: FloraTokens.section),
                      _CalendarMetric(
                        name: 'undated',
                        label: 'Sin fecha de último riego',
                        description:
                            'Información desconocida; no indica falta de agua.',
                        value: summary.undated,
                        status: FloraStatus.neutral,
                        icon: Icons.help_outline,
                      ),
                      const Divider(height: FloraTokens.section),
                      Row(
                        children: [
                          const Expanded(child: Text('Por revisar')),
                          Text(
                            '${summary.pending}',
                            key: const ValueKey('summary-pending'),
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: FloraTokens.space),
                      const Text(
                        'Incluye vencidos, pendientes hoy y fechas desconocidas. Cada planta se cuenta una sola vez.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FloraTokens.space),
                const FloraInfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FloraSectionHeading(title: 'Un consejo para cuidar'),
                      Icon(Icons.eco_outlined),
                      SizedBox(height: FloraTokens.space),
                      Text(
                        'Antes de regar, revisa el sustrato y las necesidades de cada especie. El calendario es una guía.',
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(FloraTokens.space),
                  child: Text(
                    'Avisos basados en fechas, no en sensores. Hoy y mañana son fechas locales; cada día de frecuencia equivale a 24 horas.',
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  // Solo selecciona el mensaje de presentación a partir del resumen existente.
  String _gardenMessage(WateringSummary summary) {
    if (summary.overdue > 0) {
      return 'Hay fechas de riego vencidas. Revisa el calendario de tus plantas.';
    }
    if (summary.today > 0) {
      return 'Hoy tienes riegos en el calendario. Un pequeño cuidado a su tiempo.';
    }
    if (summary.undated > 0) {
      return 'Completa las fechas de último riego para conocer los próximos pasos.';
    }
    return '¡Tu calendario está al día! Los próximos riegos están organizados.';
  }
}

/// Presentación local de una fila del calendario, sin cálculos de riego.
class _CalendarMetric extends StatelessWidget {
  const _CalendarMetric({
    required this.name,
    required this.label,
    required this.value,
    required this.icon,
    required this.status,
    this.description,
  });
  final String name, label;
  final String? description;
  final int value;
  final IconData icon;
  final FloraStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = FloraStatusColors.of(context);
    final (background, foreground) = palette.pair(status, theme.colorScheme);
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(FloraTokens.radius),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, color: foreground),
            ),
          ),
          const SizedBox(width: FloraTokens.space),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.titleMedium),
                if (description != null)
                  Text(description!, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(width: FloraTokens.space),
          Text(
            '$value',
            key: ValueKey('summary-$name'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
