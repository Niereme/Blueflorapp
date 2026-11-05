import 'dart:async';
import 'package:blueflora/data/settings_repository.dart';
import 'package:blueflora/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

class MemoryJsonStore implements JsonPreferencesStore {
  String? value;
  bool writeResult = true;
  Object? readError;
  Object? writeError;
  Completer<void>? readGate;
  Completer<void>? writeGate;
  final writes = <String>[];
  @override
  Future<String?> read() async {
    await readGate?.future;
    if (readError != null) throw readError!;
    return value;
  }

  @override
  Future<bool> write(String next) async {
    writes.add(next);
    await writeGate?.future;
    if (writeError != null) throw writeError!;
    if (writeResult) value = next;
    return writeResult;
  }
}

class FakeReminder {
  FakeReminder(this.id, this.at, this.payload, this.body);
  final int id;
  final tz.TZDateTime at;
  final String payload;
  final String body;
}

class FakeNotificationGateway implements NotificationGateway {
  bool granted = true;
  bool requestResult = true;
  int requests = 0;
  Object? initializeError;
  Object? scheduleError;
  Object? cancelError;
  Completer<void>? scheduleGate;
  final jobs = <int, FakeReminder>{};
  final scheduled = <FakeReminder>[];
  final cancelled = <int>[];
  tz.Location zone = tz.UTC;
  @override
  Future<void> initialize() async {
    if (initializeError != null) throw initializeError!;
  }

  @override
  Future<bool> hasPermission() async => granted;
  @override
  Future<bool> requestPermission() async {
    requests++;
    granted = requestResult;
    return granted;
  }

  @override
  Future<tz.Location> localZone() async => zone;
  @override
  Future<List<PendingReminder>> pending() async =>
      jobs.values.map((job) => PendingReminder(job.id, job.payload)).toList();
  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
    required String payload,
  }) async {
    await scheduleGate?.future;
    if (scheduleError != null) throw scheduleError!;
    final job = FakeReminder(id, at, payload, body);
    scheduled.add(job);
    jobs[id] = job;
  }

  @override
  Future<void> cancel(int id) async {
    if (cancelError != null) throw cancelError!;
    cancelled.add(id);
    jobs.remove(id);
  }
}
