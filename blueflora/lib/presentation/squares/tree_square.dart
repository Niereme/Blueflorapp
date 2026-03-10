import 'package:flutter/material.dart';

class TreeSquare extends StatelessWidget {

  final String nombre;
  final String? especie;
  final double? altura;
  final String frecuenciaRiego;

  const TreeSquare({
    super.key,
    required this.nombre,
    this.especie,
    this.altura,
    required this.frecuenciaRiego,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 132, 235, 137),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Text(
              nombre,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            if (especie != null)
              Text("Especie: $especie"),

            if (altura != null)
              Text("Altura: $altura m"),

            const Spacer(),

            Text(
              "Riego: cada $frecuenciaRiego",
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}