import 'unique_id.dart';

class Tree {
  static const maxFrecuenciaDias = 36500;
  static const _unchanged = Object();

  final String id;
  final String nombre;
  final String? especie;
  final double? altura;
  final int frecuenciaRiegoDias;
  final DateTime? ultimoRiego;

  Tree({
    String? id,
    required String nombre,
    String? especie,
    this.altura,
    required this.frecuenciaRiegoDias,
    this.ultimoRiego,
  }) : id = id ?? createUniqueId(),
       nombre = nombre.trim(),
       especie = especie == null || especie.trim().isEmpty
           ? null
           : especie.trim() {
    if (this.id.trim().isEmpty) {
      throw ArgumentError('El ID no puede estar vacío.');
    }
    if (this.nombre.isEmpty) {
      throw ArgumentError('Escribe el nombre de la planta.');
    }
    if (altura != null && (!altura!.isFinite || altura! <= 0)) {
      throw ArgumentError('La altura debe ser un número positivo.');
    }
    if (frecuenciaRiegoDias < 1 || frecuenciaRiegoDias > maxFrecuenciaDias) {
      throw ArgumentError(
        'La frecuencia debe estar entre 1 y $maxFrecuenciaDias días.',
      );
    }
  }

  /// El formulario acepta exclusivamente días enteros, sin unidades ni decimales.
  static int? parseFrecuenciaDias(String text) {
    final value = text.trim();
    if (!RegExp(r'^[0-9]+$').hasMatch(value)) return null;
    final days = int.tryParse(value);
    return days != null && days >= 1 && days <= maxFrecuenciaDias ? days : null;
  }

  int diasRestantes({DateTime? ahora}) {
    if (ultimoRiego == null) return 0;

    DateTime proximoRiego = ultimoRiego!.add(
      Duration(days: frecuenciaRiegoDias),
    );

    Duration diferencia = proximoRiego.difference(ahora ?? DateTime.now());

    // Días de 24 horas, conservando la fracción antes de redondear hacia arriba.
    // El instante opcional permite probar los límites sin depender del reloj.
    final microsegundos = diferencia.inMicroseconds;
    final diasCompletos = microsegundos ~/ Duration.microsecondsPerDay;
    return diasCompletos +
        (microsegundos > 0 && microsegundos % Duration.microsecondsPerDay != 0
            ? 1
            : 0);
  }

  /// Omitir un campo opcional lo conserva; pasar null lo limpia.
  /// La identidad nunca cambia mediante copyWith.
  Tree copyWith({
    String? nombre,
    Object? especie = _unchanged,
    Object? altura = _unchanged,
    int? frecuenciaRiegoDias,
    Object? ultimoRiego = _unchanged,
  }) => Tree(
    id: id,
    nombre: nombre ?? this.nombre,
    especie: identical(especie, _unchanged) ? this.especie : especie as String?,
    altura: identical(altura, _unchanged)
        ? this.altura
        : (altura as num?)?.toDouble(),
    frecuenciaRiegoDias: frecuenciaRiegoDias ?? this.frecuenciaRiegoDias,
    ultimoRiego: identical(ultimoRiego, _unchanged)
        ? this.ultimoRiego
        : ultimoRiego as DateTime?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'especie': especie,
    'altura': altura,
    'frecuenciaRiegoDias': frecuenciaRiegoDias,
    'ultimoRiego': ultimoRiego?.toIso8601String(),
  };

  factory Tree.fromJson(Map<String, dynamic> json) {
    int days;
    if (json.containsKey('frecuenciaRiegoDias')) {
      final value = json['frecuenciaRiegoDias'];
      if (value is! int) {
        throw const FormatException(
          'La frecuencia debe ser un entero en días.',
        );
      }
      days = value;
    } else {
      // Compatibilidad sencilla: nunca extraer dígitos de textos ambiguos.
      final legacy = json['frecuenciaRiego'];
      final match = legacy is String
          ? RegExp(
              r'^([0-9]+)(?:\s+d[ií]as?)?$',
              caseSensitive: false,
            ).firstMatch(legacy.trim())
          : null;
      final parsed = match == null
          ? null
          : parseFrecuenciaDias(match.group(1)!);
      if (parsed == null) {
        throw const FormatException(
          'Frecuencia antigua no válida: se requieren días enteros.',
        );
      }
      days = parsed;
    }
    if (json.containsKey('id') &&
        (json['id'] is! String || (json['id'] as String).trim().isEmpty)) {
      throw const FormatException('El identificador de planta no es válido.');
    }
    return Tree(
      id: json['id'] as String?,
      nombre: json['nombre'] as String,
      especie: json['especie'] as String?,
      altura: (json['altura'] as num?)?.toDouble(),
      frecuenciaRiegoDias: days,
      ultimoRiego: json['ultimoRiego'] != null
          ? DateTime.parse(json['ultimoRiego'] as String)
          : null,
    );
  }
}
