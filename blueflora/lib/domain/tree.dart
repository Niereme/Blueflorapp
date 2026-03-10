class Tree {
  final String nombre;
  final String? especie;
  final double? altura;
  final String frecuenciaRiego;

  Tree({
    required this.nombre,
    this.especie,
    this.altura,
    required this.frecuenciaRiego,
  });
}