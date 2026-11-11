// [CUSTOM] Diagnostic I/O must not block the playback event loop.
// ignore_for_file: avoid_slow_async_io

import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/diagnostics/bounded_event_log.dart';

// Ordinary events rotate; incident files are never overwritten until cleared.
class IncidentStore {
  IncidentStore(
    this.recent,
    this.directory, {
    this.capacity = 20,
    DateTime Function()? now,
  }) : assert(capacity > 0 && capacity <= 99),
       assert(recent.maxBytes <= 128 * 1024),
       _now = now ?? DateTime.now;

  final BoundedEventLog recent;
  final Directory directory;
  final int capacity;
  final DateTime Function() _now;
  static const maxIncidentBytes = 256 * 1024;
  Future<void> _pending = Future.value();
  File? _active;
  DateTime? _until;
  int _remaining = 0;
  int _activeBytes = 0;
  int saved = 0;
  bool failed = false;
  bool get full => saved >= capacity;

  Future<void> _run(Future<void> Function() action) =>
      _pending = _pending.then((_) async {
        try {
          await action();
          failed = false;
        } catch (_) {
          _active = null;
          failed = true;
        }
      });

  Future<List<File>> _files() async {
    if (!await directory.exists()) {
      saved = 0;
      return [];
    }
    final files = await directory
        .list()
        .where(
          (entry) =>
              entry is File &&
              RegExp(r'^\d{2}\.jsonl$').hasMatch(entry.uri.pathSegments.last),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    saved = files.length;
    return files;
  }

  Future<void> refresh() => _run(() async {
    await _files();
  });

  Future<void> append(Map<String, Object?> event, {String? incident}) => _run(
    () async {
      await recent.append(event);
      final recentFailed = recent.storageFailed;
      final time = _now();
      final line = '${jsonEncode(event)}\n';
      final bytes = utf8.encode(line).length;
      if (_active != null &&
          time.isBefore(_until!) &&
          _remaining > 0 &&
          _activeBytes + bytes <= maxIncidentBytes) {
        await _active!.writeAsString(line, mode: FileMode.append, flush: true);
        _activeBytes += bytes;
        _remaining--;
        // Nearby failures belong to the same incident, including repeated presses.
        if (recentFailed) {
          throw const FileSystemException('Recent log write failed');
        }
        return;
      }
      _active = null;
      if (incident != null) {
        final files = await _files();
        if (!full) {
          await directory.create(recursive: true);
          // Reuse a vacant slot without replacing surviving files after a partial clear.
          final names = files.map((file) => file.uri.pathSegments.last).toSet();
          var slot = 1;
          while (names.contains('${slot.toString().padLeft(2, '0')}.jsonl')) {
            slot++;
          }
          final id = slot.toString().padLeft(2, '0');
          final header = jsonEncode({
            'event': 'incident.start',
            'id': id,
            'reason': incident,
            'time': event['time'],
          });
          final content = '$header\n${await recent.read()}';
          final pending = File('${directory.path}/pending.tmp');
          await pending.writeAsString(content, flush: true);
          final file = await pending.rename('${directory.path}/$id.jsonl');
          _active = file;
          _activeBytes = utf8.encode(content).length;
          _until = time.add(const Duration(seconds: 30));
          _remaining = 64;
          saved++;
        }
      }
      if (recentFailed) {
        throw const FileSystemException('Recent log write failed');
      }
    },
  );

  Future<String> export() async {
    var result = '';
    await _run(() async {
      final files = await _files();
      final output = StringBuffer()
        ..writeln(
          jsonEncode({
            'event': 'archive.summary',
            'saved': saved,
            'capacity': capacity,
            'full': full,
            'storageFailedBeforeExport': failed || recent.storageFailed,
          }),
        );
      for (final file in files) {
        output.write(await file.readAsString());
      }
      output
        ..writeln(jsonEncode({'event': 'recent.start'}))
        ..write(await recent.read());
      result = output.toString();
    });
    if (failed) throw const FileSystemException('Export failed');
    return result;
  }

  Future<void> clear() async {
    await _run(() async {
      _active = null;
      await recent.clear();
      if (await directory.exists()) await directory.delete(recursive: true);
      saved = 0;
      if (recent.storageFailed) throw const FileSystemException('Clear failed');
    });
    if (failed) throw const FileSystemException('Clear failed');
  }
}
