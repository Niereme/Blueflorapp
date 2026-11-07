/// Respaldo del valor lógico íntegro, fuera de las tablas de trabajo.
abstract class MigrationBackupStore {
  Future<void> capture(String hash, String envelope);
  Future<String> read(String hash);
}
