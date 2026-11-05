import 'package:flutter/material.dart';
import 'blueflora_theme.dart';

/// Tarjeta flexible: no impone altura ni limita el escalado del texto.
class FloraInfoCard extends StatelessWidget {
  const FloraInfoCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(FloraTokens.padding),
      child: child,
    ),
  );
}

/// El significado siempre se expresa con texto e icono, además del color.
class FloraStatusLabel extends StatelessWidget {
  const FloraStatusLabel({
    super.key,
    required this.label,
    required this.status,
  });
  final String label;
  final FloraStatus status;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = FloraStatusColors.of(context);
    final (background, foreground) = palette.pair(status, theme.colorScheme);
    final icon = switch (status) {
      FloraStatus.success => Icons.check_circle_outline,
      FloraStatus.warning => Icons.schedule_outlined,
      FloraStatus.error => Icons.error_outline,
      FloraStatus.neutral => Icons.info_outline,
    };
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : FloraTokens.motion,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(FloraTokens.radius),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: FloraTokens.space),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class FloraSectionHeading extends StatelessWidget {
  const FloraSectionHeading({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: FloraTokens.space),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}

/// Estado vacío/error con acción opcional, sin alturas fijas.
class FloraMessage extends StatelessWidget {
  const FloraMessage({
    super.key,
    required this.title,
    required this.message,
    this.status = FloraStatus.neutral,
    this.action,
  });
  final String title, message;
  final FloraStatus status;
  final Widget? action;
  @override
  Widget build(BuildContext context) => FloraInfoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FloraSectionHeading(title: title),
        FloraStatusLabel(label: message, status: status),
        if (action != null) ...[
          const SizedBox(height: FloraTokens.space),
          action!,
        ],
      ],
    ),
  );
}

class FloraLoading extends StatelessWidget {
  const FloraLoading({super.key, this.label = 'Cargando…'});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (MediaQuery.disableAnimationsOf(context))
          const Icon(Icons.hourglass_empty)
        else
          LinearProgressIndicator(semanticsLabel: label),
        const SizedBox(height: FloraTokens.space),
        Text(label),
      ],
    ),
  );
}
