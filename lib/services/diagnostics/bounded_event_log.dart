// [CUSTOM] Keep filesystem checks asynchronous on the playback event loop.
// ignore_for_file: avoid_slow_async_io

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

// [CUSTOM] Local flight recorder. I/O failures never reach playback callers.
class BoundedEventLog {
  BoundedEventLog(
    this.file, {
    this.maxEntries = 400,
    this.maxBytes = 128 * 1024,
  });

  final File file;
  final int maxEntries;
  final int maxBytes;
  final Queue<String> _lines = Queue();
  int _bytes = 0;
  bool _loaded = false;
  Future<void> _pending = Future.value();
  bool storageFailed = false;

  Future<void> _run(Future<void> Function() action) {
    return _pending = _pending.then((_) async {
      try {
        await action();
        storageFailed = false;
      } catch (_) {
        storageFailed = true;
      }
    });
  }

  void _retain(String line) {
    final size = utf8.encode('$line\n').length;
    if (size > maxBytes) return;
    _lines.add(line);
    _bytes += size;
    while (_lines.length > maxEntries || _bytes > maxBytes) {
      _bytes -= utf8.encode('${_lines.removeFirst()}\n').length;
    }
  }

  Future<void> _load() async {
    if (_loaded) return;
    if (await file.exists()) {
      // Bound reads too, including after an interrupted/corrupt previous write.
      final handle = await file.open();
      try {
        final length = await handle.length();
        final start = length > maxBytes ? length - maxBytes : 0;
        await handle.setPosition(start);
        final lines = utf8
            .decode(await handle.read(maxBytes), allowMalformed: true)
            .split('\n');
        for (final line in start == 0 ? lines : lines.skip(1)) {
          try {
            if (jsonDecode(line) is Map<String, dynamic>) _retain(line);
          } catch (_) {
            // Keep valid events on either side of a partial line.
          }
        }
      } finally {
        await handle.close();
      }
    }
    _loaded = true;
  }

  String get _contents => _lines.isEmpty ? '' : '${_lines.join('\n')}\n';

  Future<void> append(Map<String, Object?> event) {
    final line = jsonEncode(event);
    return _run(() async {
      await _load();
      _retain(line);
      await file.parent.create(recursive: true);
      await file.writeAsString(_contents, flush: true);
    });
  }

  Future<String> read() async {
    await _run(_load);
    return _contents;
  }

  Future<void> clear() => _run(() async {
    _lines.clear();
    _bytes = 0;
    _loaded = true;
    if (await file.exists()) await file.delete();
  });
}
