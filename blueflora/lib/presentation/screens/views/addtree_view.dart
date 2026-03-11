import 'package:blueflora/domain/tree.dart';
import 'package:flutter/material.dart';

class AddTreeView extends StatefulWidget {
  const AddTreeView({super.key});

  @override
  State<AddTreeView> createState() => _AddTreeViewState();
}

class _AddTreeViewState extends State<AddTreeView> {
  final TextEditingController nombreController = TextEditingController();
  final TextEditingController especieController = TextEditingController();
  final TextEditingController alturaController = TextEditingController();
  final TextEditingController riegoController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Agregar árbol")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: nombreController,
              decoration: const InputDecoration(
                labelText: "Nombre del árbol",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: especieController,
              decoration: const InputDecoration(
                labelText: "Especie (opcional)",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: alturaController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Altura en metros (opcional)",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: riegoController,
              decoration: const InputDecoration(
                labelText: "Cada cuánto regarlo (ej: 3 días)",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 25),

            ElevatedButton(
              onPressed: () {
                final newTree = Tree(
                  nombre: nombreController.text,
                  especie: especieController.text.isEmpty
                      ? null
                      : especieController.text,
                  altura: alturaController.text.isEmpty
                      ? null
                      : double.parse(alturaController.text),
                  frecuenciaRiego: riegoController.text,
                  ultimoRiego: DateTime.now(),
                );

                Navigator.pop(context, newTree);
              },
              child: const Text("Guardar árbol"),
            ),
          ],
        ),
      ),
    );
  }
}
