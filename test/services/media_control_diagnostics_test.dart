import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/services/audio_handler.dart';
import 'package:PiliPlus/services/media_control_diagnostics.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final originalPaths = PathProviderPlatform.instance;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'piliplus-media-diagnostics-',
    );
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
    PathProviderPlatform.instance = _Paths(directory.path);
    MediaControlDiagnostics.init();
  });
  tearDownAll(() async {
    await MediaControlDiagnostics.setEnabled(false);
    await MediaControlDiagnostics.clear();
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    await directory.delete(recursive: true);
  });
  setUp(() async {
    await MediaControlDiagnostics.setEnabled(false);
    await MediaControlDiagnostics.clear();
  });

  List<Map<String, dynamic>> events(String text) => const LineSplitter()
      .convert(text)
      .map((line) => jsonDecode(line) as Map<String, dynamic>)
      .toList();

  List<Map<String, dynamic>> recentEvents(String text) {
    final all = events(text);
    return all
        .skip(all.lastIndexWhere((e) => e['event'] == 'recent.start') + 1)
        .toList();
  }

  test(
    'disabled recorder creates no events and export does not create a false incident',
    () async {
      expect(MediaControlDiagnostics.enabled, isFalse);
      MediaControlDiagnostics.record('ignored');
      expect(
        File('${directory.path}/.media_control_diagnostics.jsonl').existsSync(),
        isFalse,
      );
      final result = events(await MediaControlDiagnostics.export());
      expect(result.first['event'], 'archive.summary');
      expect(result.first['saved'], 0);
      expect(result.last['event'], 'recent.start');
    },
  );

  test('export drains preceding commands and preserves callback errors without text', () async {
    await MediaControlDiagnostics.setEnabled(true);
    final handler = VideoPlayerServiceHandler()
      ..onPlay = () async => throw StateError('private video URL');
    await expectLater(handler.play(), throwsStateError);
    final output = await MediaControlDiagnostics.export();
    final result = recentEvents(output);
    expect(events(output).first['saved'], 1);
    expect(result.map((e) => e['event']), [
      'diagnostics.enabled',
      'media.play.received',
      'media.play.error',
    ]);
    expect(result[2]['errorType'], 'StateError');
    expect(output, isNot(contains('private video URL')));
    expect(result[1]['audioOwner'], isTrue);
    handler.clear();
  });

  test('video dispatch records a missing controller instead of reporting playback success', () async {
    await MediaControlDiagnostics.setEnabled(true);
    final handler = VideoPlayerServiceHandler();
    await handler.play();
    final result = recentEvents(await MediaControlDiagnostics.export());
    expect(result.map((e) => e['event']), [
      'diagnostics.enabled',
      'media.play.received',
      'video.play.dispatch',
      'media.play.returned',
    ]);
    expect(result[1]['audioOwner'], isFalse);
    expect(result[2]['hasController'], isFalse);
    handler.clear();
  });

  test(
    'headset toggle still dispatches video pause after the old page closes',
    () async {
      await MediaControlDiagnostics.setEnabled(true);
      final handler = VideoPlayerServiceHandler();
      addTearDown(handler.clear);
      handler
        ..onVideoDetailChange(Part(part: 'old'), 1, 'old')
        ..onVideoDetailChange(Part(part: 'current'), 2, 'current')
        ..onUpdateState(
          .playing,
          false,
          false,
          position: const Duration(seconds: 8),
          speed: 1,
        )
        ..onVideoDetailDispose('old');
      await handler.click();
      final result = recentEvents(await MediaControlDiagnostics.export());
      expect(
        result.map((event) => event['event']),
        contains('video.pause.dispatch'),
      );
      expect(
        result.map((event) => event['event']),
        isNot(contains('video.play.dispatch')),
      );
    },
  );

  test(
    'disabling stops capture and clear removes queued old records',
    () async {
      await MediaControlDiagnostics.setEnabled(true);
      MediaControlDiagnostics.record('before.clear');
      await MediaControlDiagnostics.clear();
      MediaControlDiagnostics.record('after.clear');
      await MediaControlDiagnostics.setEnabled(false);
      MediaControlDiagnostics.record('after.disable');
      final result = recentEvents(await MediaControlDiagnostics.export());
      expect(result.map((e) => e['event']), ['after.clear']);
    },
  );
  test(
    'manual marking persists separately from normal records and export',
    () async {
      await MediaControlDiagnostics.setEnabled(true);
      MediaControlDiagnostics.record('manual.context');
      await MediaControlDiagnostics.markIncident();
      await MediaControlDiagnostics.setEnabled(false);
      final output = await MediaControlDiagnostics.export();
      expect(events(output).first['saved'], 1);
      expect(output, contains('manual.context'));
      expect(output, contains('user.report'));
      await MediaControlDiagnostics.clear();
      expect(events(await MediaControlDiagnostics.export()).first['saved'], 0);
    },
  );
  test(
    'only denied focus acquisition is archived, not focus release',
    () async {
      await MediaControlDiagnostics.setEnabled(true);
      MediaControlDiagnostics.record('focus.result', {
        'active': false,
        'granted': false,
      });
      expect(events(await MediaControlDiagnostics.export()).first['saved'], 0);
      MediaControlDiagnostics.record('focus.result', {
        'active': true,
        'granted': false,
      });
      expect(events(await MediaControlDiagnostics.export()).first['saved'], 1);
    },
  );
  test(
    'a missing-player incident identifies only the latest controller lifetime',
    () async {
      await MediaControlDiagnostics.setEnabled(true);
      MediaControlDiagnostics.record('video.controller.release', {
        'source': 'videoPage',
      });
      MediaControlDiagnostics.record('media.command.suspect', {
        'reason': 'missing_player',
      });
      MediaControlDiagnostics.record('video.controller.created');
      MediaControlDiagnostics.record('media.command.suspect', {
        'reason': 'missing_player',
      });
      final suspects = recentEvents(await MediaControlDiagnostics.export())
          .where((e) => e['event'] == 'media.command.suspect');
      expect(suspects.first['lastRelease']['source'], 'videoPage');
      expect(suspects.first['lastRelease']['time'], isNotNull);
      expect(suspects.last['lastRelease'], isNull);
    },
  );
}
