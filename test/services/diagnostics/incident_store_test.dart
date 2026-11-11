import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/diagnostics/bounded_event_log.dart';
import 'package:PiliPlus/services/diagnostics/incident_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late DateTime now;
  IncidentStore makeStore({int capacity = 20}) => IncidentStore(
    BoundedEventLog(File('${dir.path}/recent.jsonl'), maxEntries: 3),
    Directory('${dir.path}/incidents'),
    capacity: capacity,
    now: () => now,
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('piliplus-incidents-');
    now = DateTime.utc(2026, 11, 11);
  });
  tearDown(() => dir.delete(recursive: true));

  test(
    'incident survives routine rotation and restart, with following context',
    () async {
      final store = makeStore();
      await store.append({'event': 'before'});
      await store.append({'event': 'failure'}, incident: 'failure');
      await store.append({'event': 'recovered'});
      now = now.add(const Duration(minutes: 1));
      for (var i = 0; i < 10; i++) {
        await store.append({'event': 'routine', 'i': i});
      }
      final restart = makeStore();
      final exported = await restart.export();
      expect(exported, contains('before'));
      expect(exported, contains('failure'));
      expect(exported, contains('recovered'));
      expect(await restart.recent.read(), isNot(contains('failure')));
      expect(restart.saved, 1);
    },
  );

  test(
    'nearby failures are grouped and full archives never overwrite evidence',
    () async {
      final store = makeStore(capacity: 1);
      await store.append({'event': 'first'}, incident: 'first');
      await store.append({'event': 'second'}, incident: 'second');
      expect(store.saved, 1);
      final file = File('${dir.path}/incidents/01.jsonl');
      final original = await file.readAsString();
      expect(original, contains('second'));
      now = now.add(const Duration(minutes: 1));
      await store.append({'event': 'later'}, incident: 'later');
      expect(store.full, isTrue);
      expect(await file.readAsString(), original);
      await store.clear();
      await store.append({'event': 'new'}, incident: 'new');
      expect(await file.readAsString(), contains('new'));
      expect(await file.readAsString(), isNot(contains('first')));
    },
  );

  test('post-context is bounded and retains the original trigger', () async {
    final store = makeStore();
    await store.append({'event': 'trigger'}, incident: 'trigger');
    for (var i = 0; i < 100; i++) {
      await store.append({'event': 'after', 'i': i});
    }
    final file = File('${dir.path}/incidents/01.jsonl');
    final records = const LineSplitter().convert(await file.readAsString());
    expect(
      records.length,
      66,
    ); // Header, trigger and at most 64 following events.
    expect(records[1], contains('trigger'));
    expect(
      file.lengthSync(),
      lessThanOrEqualTo(IncidentStore.maxIncidentBytes),
    );
  });

  test(
    'archive I/O failures cannot break playback callers and are visible',
    () async {
      final store = makeStore();
      await File('${dir.path}/incidents').writeAsString('blocked');
      await expectLater(
        store.append({'event': 'failure'}, incident: 'failure'),
        completes,
      );
      expect(store.failed, isTrue);
      expect(await store.recent.read(), contains('failure'));
    },
  );
  test('gaps left by external deletion never cause another archive to be overwritten', () async {
    final store = makeStore();
    await store.append({'event': 'first'}, incident: 'first');
    now = now.add(const Duration(minutes: 1));
    await store.append({'event': 'second'}, incident: 'second');
    final second = File('${dir.path}/incidents/02.jsonl');
    final original = await second.readAsString();
    await File('${dir.path}/incidents/01.jsonl').delete();
    final restart = makeStore();
    await restart.append({'event': 'third'}, incident: 'third');
    expect(await second.readAsString(), original);
    expect(restart.saved, 2);
  });
}
