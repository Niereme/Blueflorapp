import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/presentation/screens/views/addtree_view.dart';
import 'package:blueflora/presentation/squares/tree_square.dart';
import 'package:flutter/material.dart';



class TreesView extends StatefulWidget {
  const TreesView({super.key});
  @override
  State<TreesView> createState() => _TreesViewState();
}
class _TreesViewState extends State<TreesView> {

  List<Tree> trees = [];
  Future<void> addTree() async {

  final newTree = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const AddTreeView(),
    ),
  );

  if (newTree != null) {
    setState(() {
      trees.add(newTree);
    });
  }

}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Árboles"),
      ),
      body: Column(
        children: [

          const SizedBox(height: 10),

          const Text(
            "Mis árboles",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          Expanded(
             child: ListView.builder(
    itemCount: trees.length,
    itemBuilder: (context, index) {

      final tree = trees[index];

      return TreeSquare(
        nombre: tree.nombre,
        especie: tree.especie,
        altura: tree.altura,
        frecuenciaRiego: tree.frecuenciaRiego,
      );

    },
  ),
          ),

        ],
      ),
      floatingActionButton: FloatingActionButton(
  onPressed: addTree,
  child: const Icon(Icons.add),
),
    );
  }
}
