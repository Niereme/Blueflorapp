import 'package:flutter/material.dart';

class ProfileView extends StatefulWidget{
  const ProfileView ({super.key});
  @override 
  State<ProfileView> createState ()=> _ProfileState();
}

class _ProfileState extends State<ProfileView>{

  @override
  Widget build(BuildContext context) {
    return Center(child: Column(children: [Text("Perfil")],),);
  }
}