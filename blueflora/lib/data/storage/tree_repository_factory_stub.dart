import '../local_tree_repository.dart';
import '../tree_repository.dart';

// Web conserva su almacenamiento; no importa dart:io ni dart:ffi.
TreeRepository createTreeRepository() => LocalTreeRepository();
