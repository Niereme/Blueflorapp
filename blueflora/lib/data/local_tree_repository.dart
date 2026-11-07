import 'dart:convert';

import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/domain/plant_snapshot.dart';
import 'package:blueflora/domain/watering_event.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tree_repository.dart';

/// Frontera de almacenamiento para probar fallos sin acceder al dispositivo.
abstract class TreePreferencesStore {
  Future<List<String>?> read();
  Future<bool> write(List<String> records);
}

class SharedPreferencesTreeStore implements TreePreferencesStore {
  static const key = 'trees';

  @override
  Future<List<String>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    // Releer disco evita reutilizar la caché optimista de un guardado fallido.
    await prefs.reload();
    return prefs.getStringList(key);
  }

  @override
  Future<bool> write(List<String> records) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setStringList(key, records);
  }
}

class TreeStorageException implements Exception {
  final String message;
  final Object? cause;

  TreeStorageException(this.message, [this.cause]);

  @override
  String toString() => message;
}

/// Serializa lecturas y escrituras de esta instancia en orden de solicitud.
/// Las pantallas futuras deberán compartir la misma instancia del repositorio.
class LocalTreeRepository extends TreeRepository {
  LocalTreeRepository({TreePreferencesStore? store})
    : _store = store ?? SharedPreferencesTreeStore();

  final TreePreferencesStore _store;
  Future<void> _pending = Future<void>.value();
  bool _loaded = false;
  List<WateringEvent> _events = [];

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    // Un fallo no bloquea los reintentos ni deja errores sin observar en la cola.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Compatibilidad de API para consumidores que solo necesitan plantas.
  Future<List<Tree>?> load() async {
    final snapshot = await loadSnapshot();
    return snapshot == null ? null : List.of(snapshot.trees);
  }

  /// null indica clave ausente; una instantánea vacía es distinta.
  @override
  Future<PlantSnapshot?> loadSnapshot() => _serialize(() async {
    _loaded = false;
    try {
      final records = await _store.read();
      PlantSnapshot? snapshot;
      if (records != null) {
        final decoded = records.map(jsonDecode).toList();
        if (decoded.length == 1 &&
            decoded.single is Map<String, dynamic> &&
            (decoded.single as Map<String, dynamic>).containsKey(
              'schemaVersion',
            )) {
          snapshot = PlantSnapshot.fromJson(
            decoded.single as Map<String, dynamic>,
          );
        } else {
          // Formato anterior: no crear eventos a partir de ultimoRiego.
          var needsUpgrade = false;
          final trees = decoded.map((record) {
            if (record is! Map<String, dynamic>) {
              throw const FormatException('Se esperaba una planta.');
            }
            needsUpgrade =
                needsUpgrade ||
                !record.containsKey('id') ||
                !record.containsKey('frecuenciaRiegoDias');
            return Tree.fromJson(record);
          }).toList();
          snapshot = PlantSnapshot(trees: trees);
          // Persistir IDs recién asignados una sola vez, después de validar todo.
          if (needsUpgrade) await _write(snapshot);
        }
      }
      _events = List.of(snapshot?.events ?? []);
      _loaded = true;
      return snapshot;
    } catch (error) {
      throw TreeStorageException(
        'No se pudieron cargar las plantas y su historial. Los datos guardados se conservan.',
        error,
      );
    }
  });

  Future<void> _write(PlantSnapshot snapshot) async {
    // Una única sustitución del valor de preferencias: nunca escribir las dos
    // listas por separado. Repetir la misma instantánea es idempotente.
    if (!await _store.write([jsonEncode(snapshot.toJson())])) {
      throw StateError('El almacenamiento rechazó la escritura.');
    }
  }

  @override
  Future<void> save(List<Tree> trees, {List<WateringEvent>? events}) {
    final treeCopy = List<Tree>.of(trees);
    final eventCopy = events == null ? null : List<WateringEvent>.of(events);
    return _serialize(() async {
      if (!_loaded) {
        throw TreeStorageException(
          'Debes cargar las plantas antes de guardar.',
        );
      }
      try {
        final snapshot = PlantSnapshot(
          trees: treeCopy,
          events: eventCopy ?? _events,
        );
        await _write(snapshot);
        _events = List.of(snapshot.events);
      } catch (error) {
        throw TreeStorageException(
          'No se pudieron guardar los cambios. Inténtalo de nuevo.',
          error,
        );
      }
    });
  }
}
