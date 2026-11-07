import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'migration_backup.dart';

class FileMigrationBackup implements MigrationBackupStore {
  FileMigrationBackup(this.directory);
  final Directory directory;

  File _file(String hash) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Hash de respaldo inválido.');
    }
    return File(p.join(directory.path, '$hash.json'));
  }

  @override
  Future<void> capture(String hash, String envelope) async {
    await directory.create(recursive: true);
    final file = _file(hash);
    if (!await file.exists()) {
      // El archivo parcial es reanudable; jamás reemplazar un respaldo completo.
      final partial = File('${file.path}.partial');
      await partial.writeAsString(envelope, flush: true);
      if (await partial.readAsString() != envelope) {
        throw StateError('No se pudo verificar el respaldo temporal.');
      }
      await partial.rename(file.path);
    }
    if (await read(hash) != envelope) {
      throw StateError('El respaldo no coincide con el origen.');
    }
  }

  @override
  Future<String> read(String hash) async {
    final text = await _file(hash).readAsString();
    if (sha256.convert(utf8.encode(text)).toString() != hash) {
      throw StateError('El respaldo no supera la verificación SHA-256.');
    }
    return text;
  }
}
