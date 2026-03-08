import 'package:flutter/material.dart';

class AddtreeView extends StatefulWidget{
  const AddtreeView ({super.key});
  @override 
  State<AddtreeView> createState ()=> _AddtreeState();
}

class _AddtreeState extends State<AddtreeView>{

  @override
  Widget build(BuildContext context) {
    return Center(child: Column(children: [Text("Perfil")],),);
  }
}