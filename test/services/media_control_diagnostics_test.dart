import 'dart:convert';
import 'dart:io';

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

  test(
    'disabled recorder creates no event file and explicit export marks report',
    () async {
      expect(MediaControlDiagnostics.enabled, isFalse);
      MediaControlDiagnostics.record('ignored');
      expect(
        File('${directory.path}/.media_control_diagnostics.jsonl').existsSync(),
        isFalse,
      );
      final result = events(await MediaControlDiagnostics.export());
      expect(result.single['event'], 'user.report');
      expect(result.single['recordingEnabled'], isFalse);
    },
  );

  test('export drains preceding commands and preserves callback errors without text', () async {
    await MediaControlDiagnostics.setEnabled(true);
    final handler = VideoPlayerServiceHandler()
      ..onPlay = () async => throw StateError('private video URL');
    await expectLater(handler.play(), throwsStateError);
    final output = await MediaControlDiagnostics.export();
    final result = events(output);
    expect(result.map((e) => e['event']), [
      'diagnostics.enabled',
      'media.play.received',
      'media.play.error',
      'user.report',
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
    final result = events(await MediaControlDiagnostics.export());
    expect(result.map((e) => e['event']), [
      'diagnostics.enabled',
      'media.play.received',
      'video.play.dispatch',
      'media.play.returned',
      'user.report',
    ]);
    expect(result[1]['audioOwner'], isFalse);
    expect(result[2]['hasController'], isFalse);
    handler.clear();
  });

  test(
    'disabling stops capture and clear removes queued old records',
    () async {
      await MediaControlDiagnostics.setEnabled(true);
      MediaControlDiagnostics.record('before.clear');
      await MediaControlDiagnostics.clear();
      MediaControlDiagnostics.record('after.clear');
      await MediaControlDiagnostics.setEnabled(false);
      MediaControlDiagnostics.record('after.disable');
      final result = events(await MediaControlDiagnostics.export());
      expect(result.map((e) => e['event']), ['after.clear', 'user.report']);
      expect(result.last['recordingEnabled'], isFalse);
    },
  );
}
