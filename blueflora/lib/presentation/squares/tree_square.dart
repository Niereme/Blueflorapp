import 'package:blueflora/domain/tree.dart';
import 'package:flutter/material.dart';

class TreeSquare extends StatelessWidget {
  final VoidCallback onWater;
  final Tree tree;

  const TreeSquare({super.key, required this.tree, required this.onWater});

  @override
  Widget build(BuildContext context) {
    int dias = tree.diasRestantes();

    Color color;

    if (dias <= 0) {
      color = Colors.red.shade300;
    } else if (dias <= 1) {
      color = Colors.orange.shade300;
    } else {
      color = Colors.green.shade300;
    }
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: color,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.park, size: 32, color: Colors.green),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      tree.nombre,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              if (tree.especie != null) Text("🌿 Especie: ${tree.especie}"),

              if (tree.altura != null) Text("📏 Altura: ${tree.altura} m"),

              const SizedBox(height: 6),

              Text(
                "💧 Riego: cada ${tree.frecuenciaRiego} días",
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),

              const SizedBox(height: 6),

              Text(
                tree.diasRestantes() <= 0
                    ? "⚠️ Regar hoy"
                    : "Faltan ${tree.diasRestantes()} días para regar",
              ),

              const SizedBox(height: 10),

              // Barra visual de riego
              LinearProgressIndicator(
                value: tree.diasRestantes() <= 0
                    ? 1
                    : 1 - (tree.diasRestantes() / 3),
              ),

              const SizedBox(height: 10),

              Center(
                child: ElevatedButton.icon(
                  onPressed: onWater,
                  icon: const Icon(Icons.water_drop),
                  label: const Text("Regar"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
