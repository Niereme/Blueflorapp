import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/presentation/screens/views/addtree_view.dart';
import 'package:blueflora/presentation/squares/tree_square.dart';
import 'package:flutter/material.dart';

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';



class TreesView extends StatefulWidget {
  const TreesView({super.key});
  @override
  State<TreesView> createState() => _TreesViewState();
}
class _TreesViewState extends State<TreesView> {
  Future<void> saveTrees() async {

  final prefs = await SharedPreferences.getInstance();

  List<String> treesJson =
      trees.map((tree) => jsonEncode(tree.toJson())).toList();

  await prefs.setStringList("trees", treesJson);

}
  Future<void> loadTrees() async {

  final prefs = await SharedPreferences.getInstance();

  final List<String>? treesJson = prefs.getStringList("trees");

  if (treesJson != null) {

    setState(() {

      trees = treesJson
          .map((tree) => Tree.fromJson(jsonDecode(tree)))
          .toList();

    });

  }

}

  List<Tree> trees = [ Tree(
    nombre: "Árbol de prueba",
    especie: "Pino de Bosque",
    altura: 4,
    frecuenciaRiego: "3 días",
  )];
  Future<void> addTree() async {

   final result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const AddTreeView(),
    ),
  );

  if (result is Tree) {
    setState(() {
      trees.add(result);
    });
    saveTrees();
  }

}
@override
void initState() {
  super.initState();
  loadTrees();
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

      return Dismissible(
  key: Key(tree.nombre + index.toString()),

  direction: DismissDirection.endToStart,

  background: Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    color: Colors.red,
    child: const Icon(
      Icons.delete,
      color: Colors.white,
    ),
  ),

  confirmDismiss: (direction) async {

    return await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Eliminar árbol"),
          content: const Text("¿Seguro que quieres eliminar este árbol?"),
          actions: [

            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text("Cancelar"),
            ),

            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text("Eliminar"),
            ),

          ],
        );
      },
    );

  },

  onDismissed: (direction) {

    setState(() {
      trees.removeAt(index);
    });

    saveTrees();

  },

  child:TreeSquare(
  tree: tree,
  onWater: () {
    setState(() {
      trees[index] = tree.copyWith(
        ultimoRiego: DateTime.now(),
      );
      saveTrees();
    });
  },
)
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
