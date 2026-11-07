import 'dart:async';

import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/data/tree_repository.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/domain/local_mutation.dart';
import 'package:blueflora/domain/watering_event.dart';
import 'package:blueflora/domain/watering_summary.dart';
import 'package:flutter/widgets.dart';

/// Una instancia compartida por MainScreen; confirma cambios solo tras guardar.
class TreesController extends ChangeNotifier with WidgetsBindingObserver {
  TreesController({
    required TreeRepository repository,
    DateTime Function()? clock,
    this.autoRefresh = true,
  }) : _repository = repository,
       _clock = clock ?? DateTime.now {
    _now = _clock();
    if (autoRefresh) WidgetsBinding.instance.addObserver(this);
  }

  final TreeRepository _repository;
  String? get storageNotice => _repository.storageNotice;
  bool get storageReadOnly => !_repository.writable;
  final DateTime Function() _clock;
  final bool autoRefresh;
  late DateTime _now;
  Timer? _timer;
  bool _disposed = false;
  bool _loaded = false;
  bool _foreground = true;
  bool _loading = false;
  bool _saving = false;
  String? _loadError;
  String? _saveError;
  List<Tree> _trees = [];
  LocalMutation? _failedMutation;
  LocalMutation? _initialMutation;
  List<WateringEvent> _events = [];

  List<Tree> get trees => List.unmodifiable(_trees);
  Tree? plantById(String id) {
    for (final tree in _trees) {
      if (tree.id == id) return tree;
    }
    return null;
  }

  List<WateringEvent> eventsFor([String? plantId]) {
    final result = _events
        .where((event) => plantId == null || event.plantId == plantId)
        .toList();
    result.sort((a, b) {
      final byDate = b.occurredAt.compareTo(a.occurredAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return List.unmodifiable(result);
  }

  DateTime get now => _now;
  bool get loading => _loading || !_loaded && _loadError == null;
  bool get saving => _saving;
  String? get loadError => _loadError;
  String? get saveError => _saveError;
  bool get canModify =>
      !_disposed &&
      _loaded &&
      !_loading &&
      !_saving &&
      _loadError == null &&
      _repository.writable;

  /// Conservada sin reajustar revisiones para reconciliación explícita.
  LocalMutation? get pendingMutation => _failedMutation ?? _initialMutation;
  bool get canRetrySave => canModify && _failedMutation != null;
  WateringSummary get summary => WateringSummary(_trees, _now);

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> load() async {
    if (_disposed || _loading || _saving) return false;
    _loading = true;
    _loadError = null;
    _saveError = null;

    _emit();
    try {
      var snapshot = await _repository.loadSnapshot();
      var trees = snapshot?.trees;
      if (_disposed) return false;
      if (trees == null || _initialMutation != null) {
        _initialMutation ??= () {
          final demo = Tree(
            nombre: 'Árbol de prueba',
            especie: 'Pino de Bosque',
            altura: 4,
            frecuenciaRiegoDias: 3,
          );
          return _intent('plant.create', demo.id, demo.toJson());
        }();
        snapshot = await _repository.applyMutation(_initialMutation!);
        trees = snapshot.trees;
        _initialMutation = null;
      }
      if (_disposed) return false;
      _trees = List.of(trees);
      _events = List.of(snapshot?.events ?? []);
      _loaded = true;
      _now = _clock();
      return true;
    } on TreeStorageException catch (error) {
      if (!_disposed) _loadError = error.message;
      return false;
    } finally {
      if (!_disposed) {
        _loading = false;
        _scheduleRefresh();
        _emit();
      }
    }
  }

  LocalMutation _intent(
    String action,
    String id,
    Map<String, Object?> payload,
  ) => LocalMutation(
    spaceId: _repository.spaceId,
    action: action,
    entityId: id,
    expectedRevision: _repository.revision,
    expectedVersion: _repository.versionOf(id),
    payload: payload,
  );

  Future<bool> _save(LocalMutation mutation) async {
    if (!canModify) return false;
    _saving = true;
    _saveError = null;
    _emit();
    try {
      final snapshot = await _repository.applyMutation(mutation);
      if (_disposed) return false;
      _trees = List.of(snapshot.trees);
      _events = List.of(snapshot.events);
      _failedMutation = null;
      _now = _clock();
      return true;
    } on TreeStorageException catch (error) {
      if (!_disposed) {
        _saveError = error.message;
        _failedMutation = mutation;
      }
      return false;
    } finally {
      if (!_disposed) {
        _saving = false;
        _scheduleRefresh();
        _emit();
      }
    }
  }

  Future<bool> add(Tree tree) {
    if (!canModify ||
        _failedMutation != null ||
        _trees.any((item) => item.id == tree.id)) {
      return Future.value(false);
    }
    return _save(_intent('plant.create', tree.id, tree.toJson()));
  }

  Future<bool> edit(Tree tree) {
    final old = plantById(tree.id);
    if (!canModify || _failedMutation != null || old == null) {
      return Future.value(false);
    }
    final before = old.toJson();
    final after = tree.toJson();
    final patch = <String, Object?>{};
    for (final key in ['nombre', 'especie', 'altura', 'frecuenciaRiegoDias']) {
      if (before[key] != after[key]) patch[key] = after[key];
    }
    return _save(_intent('plant.update', tree.id, patch));
  }

  Future<bool> delete(String id) {
    if (!canModify || _failedMutation != null || plantById(id) == null) {
      return Future.value(false);
    }
    return _save(_intent('plant.delete', id, {}));
  }

  Future<bool> water(String id) {
    if (!canModify) return Future.value(false);
    final pending = _failedMutation;
    if (pending != null) {
      return pending.action == 'watering_event.append' && pending.entityId == id
          ? retrySave()
          : Future.value(false);
    }
    final tree = plantById(id);
    if (tree == null) return Future.value(false);
    final timestamp = _clock();
    final event = WateringEvent(
      plantId: id,
      plantName: tree.nombre,
      occurredAt: timestamp,
    );
    return _save(
      _intent('watering_event.append', id, {
        ...event.toJson(),
        'declarationText': timestamp.toIso8601String(),
      }),
    );
  }

  Future<bool> retrySave() =>
      canRetrySave ? _save(_failedMutation!) : Future.value(false);

  /// No relee preferencias ni escribe datos: solo recalcula el estado temporal.
  void refreshTime() {
    if (_disposed) return;
    _now = _clock();
    _scheduleRefresh();
    _emit();
  }

  void _scheduleRefresh() {
    _timer?.cancel();
    if (!autoRefresh || _disposed || !_loaded || !_foreground) return;
    final current = _clock();
    _now = current;
    final local = current.toLocal();
    var next = DateTime(local.year, local.month, local.day + 1);
    for (final tree in _trees) {
      final last = tree.ultimoRiego;
      if (last == null) continue;
      final due = last.add(Duration(days: tree.frecuenciaRiegoDias));
      // Además de medianoche y vencimientos, actualizar el contador de periodos
      // de 24 horas de las tarjetas exactamente al cruzar cada límite.
      final remaining = due.difference(current).inMicroseconds;
      final DateTime boundary;
      if (remaining > 0) {
        final fullDays = (remaining - 1) ~/ Duration.microsecondsPerDay;
        boundary = due.subtract(Duration(days: fullDays));
      } else if (remaining == 0) {
        boundary = due.add(const Duration(microseconds: 1));
      } else {
        final elapsedDays = (-remaining) ~/ Duration.microsecondsPerDay;
        boundary = due.add(Duration(days: elapsedDays + 1));
      }
      if (boundary.isAfter(current) && boundary.isBefore(next)) next = boundary;
    }
    _timer = Timer(next.difference(current), refreshTime);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      refreshTime();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (autoRefresh) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
