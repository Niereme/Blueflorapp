class Tree {
  final String nombre;
  final String? especie;
  final double? altura;
  final String frecuenciaRiego;
  final DateTime? ultimoRiego;

  Tree({
    required this.nombre,
    this.especie,
    this.altura,
    required this.frecuenciaRiego,
    this.ultimoRiego,
  });
  int diasRestantes() {
    if (ultimoRiego == null) return 0;

    int frecuencia =
        int.tryParse(frecuenciaRiego.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    DateTime proximoRiego = ultimoRiego!.add(Duration(days: frecuencia));

    Duration diferencia = proximoRiego.difference(DateTime.now());

    return (diferencia.inHours / 24).ceil();
  }

  Tree copyWith({
    String? nombre,
    String? especie,
    double? altura,
    String? frecuenciaRiego,
    DateTime? ultimoRiego,
  }) {
    return Tree(
      nombre: nombre ?? this.nombre,
      especie: especie ?? this.especie,
      altura: altura ?? this.altura,
      frecuenciaRiego: frecuenciaRiego ?? this.frecuenciaRiego,
      ultimoRiego: ultimoRiego ?? this.ultimoRiego,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "nombre": nombre,
      "especie": especie,
      "altura": altura,
      "frecuenciaRiego": frecuenciaRiego,
      "ultimoRiego": ultimoRiego?.toIso8601String(),
    };
  }

  factory Tree.fromJson(Map<String, dynamic> json) {
    return Tree(
      nombre: json["nombre"],
      especie: json["especie"],
      altura: json["altura"]?.toDouble(),
      frecuenciaRiego: json["frecuenciaRiego"],
      ultimoRiego: json["ultimoRiego"] != null
          ? DateTime.parse(json["ultimoRiego"])
          : null,
    );
  }
}
