import 'dart:async';
import 'dart:convert';

import 'package:blueflora/data/local_tree_repository.dart';

class TestTreeStore implements TreePreferencesStore {
  List<String>? records;
  List<String>? get treeRecords {
    final raw = records;
    if (raw == null || raw.length != 1) return raw;
    try {
      final value = jsonDecode(raw.single);
      if (value is Map<String, dynamic> && value.containsKey('schemaVersion')) {
        return (value['trees'] as List).map(jsonEncode).toList();
      }
    } catch (_) {
      // Los tests de corrupción necesitan observar el contenido sin repararlo.
    }
    return raw;
  }

  set treeRecords(List<String>? value) => records = value;
  Object? readError;
  Object? writeError;
  bool writeResult = true;
  bool persistBeforeFailure = false;
  Completer<void>? readGate;
  Completer<void>? writeGate;
  int reads = 0;
  final writes = <List<String>>[];

  @override
  Future<List<String>?> read() async {
    reads++;
    await readGate?.future;
    if (readError != null) throw readError!;
    return records == null ? null : List.of(records!);
  }

  @override
  Future<bool> write(List<String> value) async {
    writes.add(List.of(value));
    await writeGate?.future;
    if (persistBeforeFailure) records = List.of(value);
    if (writeError != null) throw writeError!;
    if (writeResult) records = List.of(value);
    return writeResult;
  }
}
