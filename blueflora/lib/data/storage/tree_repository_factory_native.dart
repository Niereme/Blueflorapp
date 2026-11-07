import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../local_tree_repository.dart';
import '../tree_repository.dart';
import 'file_migration_backup.dart';
import 'migration_backup.dart';
import 'sqlite_tree_repository.dart';
import 'storage_platform_policy.dart';

StoragePlatform get currentStoragePlatform {
  if (Platform.isAndroid) return StoragePlatform.android;
  if (Platform.isIOS) return StoragePlatform.ios;
  if (Platform.isMacOS) return StoragePlatform.macos;
  if (Platform.isLinux) return StoragePlatform.linux;
  if (Platform.isWindows) return StoragePlatform.windows;
  return StoragePlatform.other;
}

/// Adaptador disponible para todos los sistemas nativos. La política de activación
/// es independiente: soporte del paquete no equivale a validación en dispositivo.
Future<native.Database> openNativePlantDatabase(String path) {
  final nativePlugin = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  if (!nativePlugin) ffi.sqfliteFfiInit();
  final factory = nativePlugin
      ? native.databaseFactory
      : ffi.databaseFactoryFfi;
  return factory.openDatabase(
    path,
    options: native.OpenDatabaseOptions(
      version: 1,
      onConfigure: SqliteTreeRepository.configure,
      onCreate: SqliteTreeRepository.createSchema,
    ),
  );
}

TreeRepository createTreeRepository() {
  if (!sqliteEnabledFor(currentStoragePlatform)) return LocalTreeRepository();
  // Resolver rutas solo al cargar. No usar caché, almacenamiento externo ni red.
  Future<Directory> directory() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      return Directory(await native.getDatabasesPath());
    }
    return getApplicationSupportDirectory();
  }

  final backups = _LazyBackups(
    () async => FileMigrationBackup(
      Directory(
        p.join((await directory()).path, 'blueflora_migration_backups'),
      ),
    ),
  );
  return SqliteTreeRepository(
    openDatabase: () async {
      final dir = await directory();
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'blueflora_anonymous_v1.sqlite'));
      final receipt = File('${file.path}.activation-guard');
      // Si el sistema restauró únicamente una parte de la base activa, fallar
      // cerrado en vez de migrar silenciosamente las preferencias obsoletas.
      if (await receipt.exists() && !await file.exists()) {
        throw StateError(
          'Falta la base SQLite de una instalación ya preparada.',
        );
      }
      final db = await openNativePlantDatabase(file.path);
      try {
        final identity =
            (await db.query('storage_state')).single['database_id'] as String;
        if (await receipt.exists()) {
          if (await receipt.readAsString() != identity) {
            throw StateError(
              'La base no corresponde al comprobante de esta instalación.',
            );
          }
        } else {
          await receipt.writeAsString(identity, flush: true);
        }
      } catch (_) {
        await db.close();
        rethrow;
      }
      return db;
    },
    source: SharedPreferencesTreeStore(),
    backups: backups,
  );
}

class _LazyBackups implements MigrationBackupStore {
  _LazyBackups(this.open);
  final Future<FileMigrationBackup> Function() open;
  @override
  Future<void> capture(String hash, String envelope) async =>
      (await open()).capture(hash, envelope);
  @override
  Future<String> read(String hash) async => (await open()).read(hash);
}
