import 'package:blueflora/application/trees_controller.dart';
import 'package:flutter/material.dart';

/// El padre escucha el controlador; este widget solo presenta el resultado.
class StorageFeedback extends StatelessWidget {
  const StorageFeedback({super.key, required this.controller});
  final TreesController controller;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (controller.saving) ...[
        const LinearProgressIndicator(),
        const Text('Guardando cambios…'),
      ],
      if (controller.saveError != null) ...[
        Text(controller.saveError!),
        TextButton(
          onPressed: controller.canRetrySave ? controller.retrySave : null,
          child: const Text('Reintentar guardado'),
        ),
      ],
    ],
  );
}
