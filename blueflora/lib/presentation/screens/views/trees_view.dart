import 'package:blueflora/presentation/squares/tree_square.dart';
import 'package:flutter/material.dart';



class TreesView extends StatefulWidget {
  const TreesView({super.key});
  @override
  State<TreesView> createState() => _TreesViewState();
}

class _TreesViewState extends State<TreesView> {
  final List treesCount = ['post 1', 'post 2', 'post 3'];
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Text("Historial"),
          Text("hola"),
          ListView.builder(
            itemCount: treesCount.length,
            itemBuilder: (context, index) {
              return TreeSquare();
            },
          ),
        ],
      ),
    );
  }
}
