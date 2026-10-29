import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/diagnostics/bounded_event_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('piliplus-diagnostics-');
    file = File('${directory.path}/events.jsonl');
  });
  tearDown(() => directory.delete(recursive: true));

  List<Map<String, dynamic>> events(String text) => const LineSplitter()
      .convert(text)
      .map((line) => jsonDecode(line) as Map<String, dynamic>)
      .toList();

  test('concurrent calls persist in order and evict oldest entries', () async {
    final log = BoundedEventLog(file, maxEntries: 3);
    await Future.wait(List.generate(20, (i) => log.append({'sequence': i})));
    expect(events(await log.read()).map((e) => e['sequence']), [17, 18, 19]);
    expect(await file.readAsString(), await log.read());
  });

  test(
    'UTF-8 byte bound includes newlines and rejects oversized records',
    () async {
      final log = BoundedEventLog(file, maxBytes: 70);
      for (var i = 0; i < 10; i++) {
        await log.append({'sequence': i, 'value': '播放'});
      }
      final before = await log.read();
      expect(utf8.encode(before).length, lessThanOrEqualTo(70));
      expect(events(before).last['sequence'], 9);
      await log.append({'value': List.filled(100, '长').join()});
      expect(await log.read(), before);
      expect(await file.length(), lessThanOrEqualTo(70));
    },
  );

  test(
    'restart preserves valid events around a corrupt trailing record',
    () async {
      await file.writeAsString(
        '{"sequence":1}\ninvalid\n{"sequence":2}\n{"partial":',
      );
      final log = BoundedEventLog(file);
      await log.append({'sequence': 3});
      expect(events(await log.read()).map((e) => e['sequence']), [1, 2, 3]);
      expect(await BoundedEventLog(file).read(), await log.read());
    },
  );

  test('oversized existing file is read from a bounded tail', () async {
    await file.writeAsString(
      List.generate(1000, (i) => jsonEncode({'sequence': i})).join('\n'),
    );
    final log = BoundedEventLog(file, maxBytes: 80);
    await log.append({'sequence': 1000});
    final content = await log.read();
    expect(utf8.encode(content).length, lessThanOrEqualTo(80));
    expect(events(content).last['sequence'], 1000);
    expect(await file.length(), lessThanOrEqualTo(80));
  });

  test('clear is ordered with writes and removes persisted records', () async {
    final log = BoundedEventLog(file);
    final beforeClear = log.append({'sequence': 1});
    final clearing = log.clear();
    await Future.wait([beforeClear, clearing]);
    expect(file.existsSync(), isFalse);
    expect(await log.read(), isEmpty);
    await log.append({'sequence': 2});
    expect(events(await BoundedEventLog(file).read()).single['sequence'], 2);
  });

  test(
    'disk failure does not reject writes and later writes can recover',
    () async {
      final blockedParent = File('${directory.path}/blocked');
      await blockedParent.writeAsString('not a directory');
      final log = BoundedEventLog(File('${blockedParent.path}/events.jsonl'));
      await expectLater(log.append({'sequence': 1}), completes);
      expect(log.storageFailed, isTrue);
      await blockedParent.delete();
      await log.append({'sequence': 2});
      expect(log.storageFailed, isFalse);
      expect(events(await log.read()).last['sequence'], 2);
      expect(log.file.existsSync(), isTrue);
    },
  );
}
