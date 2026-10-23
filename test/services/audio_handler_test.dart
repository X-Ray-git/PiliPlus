import 'dart:io';

import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/services/audio_handler.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late VideoPlayerServiceHandler handler;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-media-test-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });
  setUp(() {
    handler = VideoPlayerServiceHandler()
      ..onVideoDetailChange(Part(part: 'test', duration: 30), 1, 'test');
  });
  tearDown(() => handler.clear());

  void update(PlayerStatus status, {int seconds = 10, String? label}) {
    handler.onUpdateState(
      status,
      false,
      false,
      position: Duration(seconds: seconds),
      speed: 1,
      debugLabel: label,
    );
  }

  test('audio-only playback publishes state without a video controller', () {
    update(.playing);
    expect(handler.playbackState.value.playing, isTrue);
    expect(
      handler.playbackState.value.controls.map((e) => e.action),
      contains(MediaAction.pause),
    );
    update(.paused);
    expect(handler.playbackState.value.playing, isFalse);
    expect(
      handler.playbackState.value.controls.map((e) => e.action),
      contains(MediaAction.play),
    );
  });

  test('transient video buffering retains the pause control', () {
    update(.playing);
    handler.onUpdateState(
      PlayerStatus.paused,
      true,
      false,
      position: const Duration(seconds: 10),
      speed: 1,
    );
    expect(handler.playbackState.value.playing, isTrue);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.buffering,
    );
    expect(
      handler.playbackState.value.controls.map((e) => e.action),
      contains(MediaAction.pause),
    );
    update(.paused);
    expect(handler.playbackState.value.playing, isFalse);
  });

  test(
    'headset toggle dispatches pause while playing and play while paused',
    () async {
      final calls = <String>[];
      handler
        ..onPlay = () {
          calls.add('play');
          return null;
        }
        ..onPause = () {
          calls.add('pause');
          return null;
        };
      update(.playing);
      await handler.click();
      update(.paused);
      await handler.click();
      expect(calls, ['pause', 'play']);
    },
  );

  test('notification commands dispatch directly to the audio owner', () async {
    final calls = <String>[];
    handler
      ..onPlay = () {
        calls.add('play');
        return null;
      }
      ..onPause = () {
        calls.add('pause');
        return null;
      };
    await handler.pause();
    await handler.play();
    expect(calls, ['pause', 'play']);
  });

  test('a delayed video pause cannot overwrite active audio playback', () {
    handler.onPlay = () => null;
    update(.playing);
    update(.paused, label: 'onVideoPaused');
    expect(handler.playbackState.value.playing, isTrue);
    update(.paused);
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('identical nonzero-position events do not republish media state', () {
    update(.playing);
    final published = handler.playbackState.value;
    update(.playing);
    expect(identical(handler.playbackState.value, published), isTrue);
    update(.paused);
    expect(handler.playbackState.value.playing, isFalse);
    update(.paused, seconds: 20);
    expect(
      handler.playbackState.value.updatePosition,
      const Duration(seconds: 20),
    );
  });

  test('clearing the session permits the same state in a new session', () {
    update(.playing);
    handler
      ..clear()
      ..onVideoDetailChange(Part(part: 'next', duration: 30), 2, 'next');
    update(.playing);
    expect(handler.playbackState.value.playing, isTrue);
  });

  test(
    'restoring a previous item does not reuse its old deduplication state',
    () {
      handler.onVideoDetailChange(Part(part: 'next', duration: 30), 2, 'next');
      update(.playing);
      handler.onVideoDetailDispose('next');
      expect(handler.playbackState.value.playing, isFalse);
      update(.playing);
      expect(handler.playbackState.value.playing, isTrue);
    },
  );
}
