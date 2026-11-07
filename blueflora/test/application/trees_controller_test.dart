import 'dart:async';
import 'dart:convert';

import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_tree_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestTreeStore store;
  late TreesController controller;
  late DateTime now;
  setUp(() {
    now = DateTime(2026, 11, 4, 12);
    store = TestTreeStore()..records = [];
    controller = TreesController(
      repository: LocalTreeRepository(store: store),
      clock: () => now,
      autoRefresh: false,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'Centraliza agregar, editar, regar y eliminar y actualiza el resumen',
    () async {
      expect(controller.canModify, isFalse);
      await controller.load();
      final tree = Tree(
        nombre: 'Pino',
        frecuenciaRiegoDias: 1,
        ultimoRiego: now.subtract(const Duration(days: 2)),
      );
      expect(await controller.add(tree), isTrue);
      expect(controller.summary.total, 1);
      expect(controller.summary.overdue, 1);
      expect(
        await controller.edit(tree.copyWith(frecuenciaRiegoDias: 3)),
        isTrue,
      );
      expect(controller.summary.overdue, 0);
      expect(controller.summary.tomorrow, 1);
      expect(await controller.edit(tree), isTrue);
      expect(await controller.water(tree.id), isTrue);
      expect(controller.summary.pending, 0);
      expect(controller.trees.single.ultimoRiego, now);
      expect(await controller.delete(tree.id), isTrue);
      expect(controller.summary.total, 0);
      expect(store.treeRecords, isEmpty);
    },
  );

  test('No duplica cargas ni permite modificar durante la carga', () async {
    store.readGate = Completer<void>();
    final load = controller.load();
    expect(controller.loading, isTrue);
    expect(await controller.load(), isFalse);
    expect(
      await controller.add(Tree(nombre: 'Pino', frecuenciaRiegoDias: 1)),
      isFalse,
    );
    await Future<void>.delayed(Duration.zero);
    expect(store.reads, 1);
    expect(store.writes, isEmpty);
    store.readGate!.complete();
    expect(await load, isTrue);
    expect(controller.loading, isFalse);
  });

  test(
    'Mientras guarda mantiene el estado confirmado y bloquea operaciones concurrentes',
    () async {
      await controller.load();
      store.writeGate = Completer<void>();
      final tree = Tree(nombre: 'Pino', frecuenciaRiegoDias: 1);
      final add = controller.add(tree);
      expect(controller.saving, isTrue);
      expect(controller.summary.total, 0);
      expect(
        await controller.add(Tree(nombre: 'Roble', frecuenciaRiegoDias: 2)),
        isFalse,
      );
      expect(await controller.load(), isFalse);
      store.writeGate!.complete();
      expect(await add, isTrue);
      expect(controller.saving, isFalse);
      expect(controller.summary.total, 1);
      expect(store.writes, hasLength(1));
    },
  );

  test(
    'Un fallo de escritura no cambia el resumen y conserva el reintento',
    () async {
      await controller.load();
      final tree = Tree(nombre: 'Pino', frecuenciaRiegoDias: 1);
      store.writeResult = false;
      expect(await controller.add(tree), isFalse);
      expect(controller.saveError, isNotNull);
      expect(controller.canRetrySave, isTrue);
      expect(controller.summary.total, 0);
      store.writeResult = true;
      expect(await controller.retrySave(), isTrue);
      expect(controller.summary.total, 1);
      expect(controller.saveError, isNull);
      expect(controller.canRetrySave, isFalse);
    },
  );

  test(
    'Una intención incierta bloquea acciones nuevas hasta reconciliarla',
    () async {
      await controller.load();
      store.writeResult = false;
      await controller.add(Tree(nombre: 'Fallido', frecuenciaRiegoDias: 1));
      store.writeResult = true;
      expect(
        await controller.add(
          Tree(nombre: 'Confirmado', frecuenciaRiegoDias: 1),
        ),
        isFalse,
      );
      expect(await controller.retrySave(), isTrue);
      expect(controller.trees.single.nombre, 'Fallido');
      expect(
        await controller.add(
          Tree(nombre: 'Confirmado', frecuenciaRiegoDias: 1),
        ),
        isTrue,
      );
      expect(controller.trees.map((tree) => tree.nombre), [
        'Fallido',
        'Confirmado',
      ]);
    },
  );

  test('Errores de carga se notifican y permiten reintentar', () async {
    store.readError = StateError('lectura fallida');
    expect(await controller.load(), isFalse);
    expect(controller.loadError, isNotNull);
    expect(controller.loading, isFalse);
    expect(controller.canModify, isFalse);
    store.readError = null;
    expect(await controller.load(), isTrue);
    expect(controller.loadError, isNull);
    expect(controller.canModify, isTrue);
  });

  test(
    'Lista publicada es inmutable e IDs duplicados o inexistentes no se guardan',
    () async {
      await controller.load();
      final tree = Tree(nombre: 'Pino', frecuenciaRiegoDias: 1);
      await controller.add(tree);
      expect(() => controller.trees.clear(), throwsUnsupportedError);
      expect(await controller.add(tree), isFalse);
      expect(
        await controller.edit(Tree(nombre: 'Otro', frecuenciaRiegoDias: 1)),
        isFalse,
      );
      expect(await controller.water('inexistente'), isFalse);
      expect(await controller.delete('inexistente'), isFalse);
      expect(store.writes, hasLength(1));
    },
  );

  test('Reanudar recalcula fechas sin cargar ni guardar datos', () async {
    final tree = Tree(
      nombre: 'Pino',
      frecuenciaRiegoDias: 1,
      ultimoRiego: DateTime(2026, 11, 4, 8),
    );
    store.treeRecords = [jsonEncode(tree.toJson())];
    await controller.load();
    expect(controller.summary.tomorrow, 1);
    now = DateTime(2026, 11, 5, 7);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(controller.summary.today, 1);
    now = DateTime(2026, 11, 5, 9);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(controller.summary.overdue, 1);
    expect(store.reads, 1);
    expect(store.writes, isEmpty);
  });

  test('Un guardado fallido de riego conserva fechas y pendientes', () async {
    final tree = Tree(
      nombre: 'Pino',
      frecuenciaRiegoDias: 1,
      ultimoRiego: now.subtract(const Duration(days: 2)),
    );
    store.treeRecords = [jsonEncode(tree.toJson())];
    await controller.load();
    store.writeError = StateError('sin espacio');
    expect(await controller.water(tree.id), isFalse);
    expect(controller.trees.single.ultimoRiego, tree.ultimoRiego);
    expect(controller.summary.overdue, 1);
  });

  test(
    'Los cambios confirmados se recuperan con un controlador nuevo',
    () async {
      await controller.load();
      final tree = Tree(nombre: 'Pino', frecuenciaRiegoDias: 1);
      await controller.add(tree);
      final other = TreesController(
        repository: LocalTreeRepository(store: store),
        clock: () => now,
        autoRefresh: false,
      );
      addTearDown(other.dispose);
      await other.load();
      expect(other.trees.single.toJson(), tree.toJson());
    },
  );

  test(
    'Notifica comienzo y final del guardado sin publicar una planta antes de tiempo',
    () async {
      await controller.load();
      final states = <(bool, int)>[];
      controller.addListener(
        () => states.add((controller.saving, controller.summary.total)),
      );
      await controller.add(Tree(nombre: 'Pino', frecuenciaRiegoDias: 1));
      expect(states, [(true, 0), (false, 1)]);
    },
  );

  testWidgets('Temporizador actualiza mañana al cambiar de día', (
    tester,
  ) async {
    now = DateTime(2026, 11, 4, 23, 59);
    store.treeRecords = [
      jsonEncode(
        Tree(
          nombre: 'Pino',
          frecuenciaRiegoDias: 1,
          ultimoRiego: DateTime(2026, 11, 4, 8),
        ).toJson(),
      ),
    ];
    final timed = TreesController(
      repository: LocalTreeRepository(store: store),
      clock: () => now,
    );
    try {
      await timed.load();
      expect(timed.summary.tomorrow, 1);
      now = DateTime(2026, 11, 5);
      await tester.pump(const Duration(minutes: 1));
      expect(timed.summary.today, 1);
      expect(timed.summary.tomorrow, 0);
      expect(store.writes, isEmpty);
    } finally {
      timed.dispose();
    }
  });

  testWidgets(
    'Temporizador actualiza el vencimiento sin esperar a medianoche',
    (tester) async {
      now = DateTime(2026, 11, 4, 12);
      final due = now.add(const Duration(minutes: 1));
      store.treeRecords = [
        jsonEncode(
          Tree(
            nombre: 'Pino',
            frecuenciaRiegoDias: 1,
            ultimoRiego: due.subtract(const Duration(days: 1)),
          ).toJson(),
        ),
      ];
      final timed = TreesController(
        repository: LocalTreeRepository(store: store),
        clock: () => now,
      );
      try {
        await timed.load();
        now = due;
        await tester.pump(const Duration(minutes: 1));
        expect(timed.summary.today, 1);
        now = due.add(const Duration(microseconds: 1));
        await tester.pump(const Duration(microseconds: 1));
        expect(timed.summary.overdue, 1);
        expect(timed.summary.today, 0);
      } finally {
        timed.dispose();
      }
    },
  );

  testWidgets(
    'Temporizador actualiza también el contador de periodos de 24 horas',
    (tester) async {
      now = DateTime(2026, 11, 4, 12);
      final due = now.add(const Duration(days: 2, minutes: 1));
      final tree = Tree(
        nombre: 'Pino',
        frecuenciaRiegoDias: 3,
        ultimoRiego: due.subtract(const Duration(days: 3)),
      );
      store.treeRecords = [jsonEncode(tree.toJson())];
      final timed = TreesController(
        repository: LocalTreeRepository(store: store),
        clock: () => now,
      );
      try {
        await timed.load();
        expect(tree.diasRestantes(ahora: timed.now), 3);
        now = now.add(const Duration(minutes: 1));
        await tester.pump(const Duration(minutes: 1));
        expect(tree.diasRestantes(ahora: timed.now), 2);
      } finally {
        timed.dispose();
      }
    },
  );

  testWidgets(
    'Destruir durante carga o guardado no notifica después de dispose',
    (tester) async {
      final isolated = TreesController(
        repository: LocalTreeRepository(store: store),
        clock: () => now,
      );
      store.readGate = Completer<void>();
      final load = isolated.load();
      isolated.dispose();
      store.readGate!.complete();
      expect(await load, isFalse);
      expect(store.writes, isEmpty);
      final saving = TreesController(
        repository: LocalTreeRepository(store: store),
        clock: () => now,
      );
      await saving.load();
      store.writeGate = Completer<void>();
      final add = saving.add(Tree(nombre: 'Pino', frecuenciaRiegoDias: 1));
      saving.dispose();
      store.writeGate!.complete();
      expect(await add, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
