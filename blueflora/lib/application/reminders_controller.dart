import 'dart:async';
import 'dart:convert';
import 'package:blueflora/data/reminder_registry.dart';
import 'package:blueflora/domain/reminder_plan.dart';
import 'package:blueflora/services/notification_service.dart';
import 'package:flutter/widgets.dart';
import 'settings_controller.dart';
import 'trees_controller.dart';

/// Reconciliación serializada de avisos con los datos confirmados. Los fallos
/// de Android nunca revierten ni simulan un guardado de plantas.
class RemindersController extends ChangeNotifier with WidgetsBindingObserver {
  RemindersController({
    required this.trees,
    required this.settings,
    required this.gateway,
    ReminderRegistry? registry,
    DateTime Function()? clock,
  }) : _registry = registry ?? ReminderRegistry(),
       _clock = clock ?? DateTime.now {
    trees.addListener(_changed);
    settings.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }
  final TreesController trees;
  final SettingsController settings;
  final NotificationGateway gateway;
  final ReminderRegistry _registry;
  final DateTime Function() _clock;
  Future<void>? _active;
  bool _dirty = false;
  bool _force = false;
  bool _disposed = false;
  bool working = false;
  bool changingPermission = false;
  bool permissionDenied = false;
  String? error;
  String? _lastSuccessful;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _changed() {
    sync();
  }

  Future<void> sync({bool force = false}) {
    if (_disposed) return Future.value();
    _dirty = true;
    _force = _force || force;
    if (_active != null) return _active!;
    final done = Completer<void>();
    _active = done.future;
    working = true;
    _emit();
    _drain().then((_) {
      _active = null;
      working = false;
      _emit();
      done.complete();
      if (_dirty && !_disposed) sync();
    });
    return done.future;
  }

  Future<void> _drain() async {
    while (_dirty && !_disposed) {
      _dirty = false;
      final force = _force;
      _force = false;
      if (!settings.ready ||
          settings.loading ||
          settings.saving ||
          trees.loading ||
          trees.saving ||
          trees.loadError != null) {
        continue;
      }
      final plants = trees.trees;
      final preferences = settings.value;
      final input = jsonEncode([
        plants.map((tree) => tree.toJson()).toList(),
        preferences.remindersEnabled,
        preferences.hour,
        preferences.minute,
      ]);
      if (!force && input == _lastSuccessful) continue;
      try {
        await gateway.initialize();
        final pending = await gateway.pending();
        // Desactivar debe poder cancelar aun si el registro de IDs está dañado.
        if (!preferences.remindersEnabled) {
          for (final request in pending) {
            await gateway.cancel(request.id);
          }
        }
        final records = await _registry.load();
        if (_disposed) return;
        if (!preferences.remindersEnabled) {
          for (final request in pending) {
            for (final entry in records.entries.toList()) {
              if (entry.value.id == request.id) {
                records[entry.key] = ReminderRecord(id: request.id);
              }
            }
          }
          if (pending.isNotEmpty) await _registry.save(records);
          permissionDenied = false;
        } else if (!await gateway.hasPermission()) {
          for (final request in pending) {
            await gateway.cancel(request.id);
          }
          for (final entry in records.entries.toList()) {
            if (pending.any((request) => request.id == entry.value.id)) {
              records[entry.key] = ReminderRecord(id: entry.value.id);
            }
          }
          if (pending.isNotEmpty) await _registry.save(records);
          permissionDenied = true;
          throw StateError(
            'Permiso de notificaciones denegado. Puedes autorizarlo en los ajustes de Android.',
          );
        } else {
          permissionDenied = false;
          final zone = await gateway.localZone();
          final now = _clock();
          final plans = plants
              .map((plant) => planReminder(plant, preferences, now, zone))
              .whereType<ReminderPlan>()
              .toList();
          var nextId =
              records.values.fold<int>(
                0,
                (max, record) => record.id > max ? record.id : max,
              ) +
              1;
          var allocated = false;
          for (final plan in plans) {
            if (!records.containsKey(plan.plant.id)) {
              if (nextId > 2147483647) {
                throw StateError(
                  'No hay identificadores de aviso disponibles.',
                );
              }
              records[plan.plant.id] = ReminderRecord(id: nextId++);
              allocated = true;
            }
          }
          // Los IDs se guardan antes de llamar a Android y nunca se reutilizan.
          if (allocated) await _registry.save(records);
          final wantedIds = plans
              .map((plan) => records[plan.plant.id]!.id)
              .toSet();
          for (final request in pending) {
            if (!wantedIds.contains(request.id)) {
              await gateway.cancel(request.id);
              for (final entry in records.entries.toList()) {
                if (entry.value.id == request.id) {
                  records[entry.key] = ReminderRecord(id: request.id);
                }
              }
              await _registry.save(records);
            }
          }
          for (final plan in plans) {
            if (_disposed) return;
            final old = records[plan.plant.id]!;
            final requests = pending.where((request) => request.id == old.id);
            final request = requests.isEmpty ? null : requests.first;
            if (request?.payload == plan.signature) continue;
            // Ya se emitió el intento de este ciclo: no repetir un vencido cada
            // vez que se abre la app. Una cancelación pendiente limpia la marca.
            if (request == null &&
                old.cycle == plan.cycle &&
                old.at != null &&
                !old.at!.isAfter(now)) {
              continue;
            }
            // Android sustituye el aviso del mismo ID; no cancelar primero.
            final record = ReminderRecord(
              id: old.id,
              cycle: plan.cycle,
              at: plan.at,
              signature: plan.signature,
            );
            records[plan.plant.id] = record;
            // Marcar el intento antes de programar evita repetirlo tras reinicio.
            await _registry.save(records);
            try {
              await gateway.schedule(
                id: record.id,
                title: 'Recordatorio de riego',
                body:
                    'Revisa el riego de ${plan.plant.nombre}. Aviso basado en calendario.',
                at: plan.at,
                payload: plan.signature,
              );
            } catch (_) {
              // Si Android guardó la alarma pero se perdió la respuesta,
              // conservar su marca y no volver a crear el ciclo al reabrir.
              final after = await gateway.pending();
              final accepted = after.any(
                (request) =>
                    request.id == old.id && request.payload == plan.signature,
              );
              records[plan.plant.id] = accepted ? record : old;
              await _registry.save(records);
              rethrow;
            }
          }
        }
        _lastSuccessful = input;
        error = null;
      } catch (_) {
        _lastSuccessful = null;
        error = permissionDenied
            ? 'Permiso de notificaciones denegado. Puedes autorizarlo en los ajustes de Android.'
            : 'No se pudieron actualizar los recordatorios. Reintenta; tus plantas y riegos están guardados.';
      }
    }
  }

  Future<bool> setEnabled(bool enabled) async {
    if (changingPermission || !settings.canModify || _disposed) return false;
    changingPermission = true;
    _emit();
    try {
      await sync();
      if (_disposed) return false;
      if (enabled && !await gateway.requestPermission()) {
        permissionDenied = true;
        error = 'Permiso rechazado. Los recordatorios no se han activado.';
        return false;
      }
      if (_disposed) return false;
      final saved = await settings.save(
        settings.value.copyWith(remindersEnabled: enabled),
      );
      if (saved) await sync(force: true);
      return saved;
    } catch (_) {
      error =
          'No se pudo solicitar el permiso. Reintenta desde Configuraciones.';
      return false;
    } finally {
      changingPermission = false;
      _emit();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sync(force: true);
  }

  @override
  void dispose() {
    _disposed = true;
    trees.removeListener(_changed);
    settings.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
