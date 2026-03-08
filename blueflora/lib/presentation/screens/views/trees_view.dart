import 'package:flutter/material.dart';

class TreesView extends StatefulWidget{
  const TreesView ({super.key});
  @override 
  State<TreesView> createState ()=> _TreesViewState();
}

class _TreesViewState extends State<TreesView>{

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Center(child: Column(children: [Text("Mis arboles")],),),
    );
  }
}