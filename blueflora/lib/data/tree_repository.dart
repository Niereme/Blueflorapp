import '../domain/plant_snapshot.dart';
import '../domain/local_mutation.dart';
import '../domain/tree.dart';
import '../domain/watering_event.dart';

/// Contrato local, sin red ni identidad de cuentas.
abstract class TreeRepository {
  String? get storageNotice => null;
  bool get writable => true;
  Future<PlantSnapshot?> loadSnapshot();
  String get spaceId => 'anonymous';
  int get revision => 0;
  int versionOf(String id) => 0;

  Future<PlantSnapshot> applyMutation(LocalMutation mutation);

  Future<void> save(List<Tree> trees, {List<WateringEvent>? events});
}
