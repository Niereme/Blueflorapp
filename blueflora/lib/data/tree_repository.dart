import '../domain/plant_snapshot.dart';
import '../domain/tree.dart';
import '../domain/watering_event.dart';

/// Contrato local, sin red ni identidad de cuentas.
abstract class TreeRepository {
  String? get storageNotice => null;
  bool get writable => true;
  Future<PlantSnapshot?> loadSnapshot();
  Future<void> save(List<Tree> trees, {List<WateringEvent>? events});
}
