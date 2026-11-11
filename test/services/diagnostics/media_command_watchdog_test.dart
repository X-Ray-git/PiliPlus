import 'package:PiliPlus/services/diagnostics/media_command_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('detects failed play and pause even without thrown errors', (
    tester,
  ) async {
    final reports = <String>[];
    final watchdog = MediaCommandWatchdog((reason, _) => reports.add(reason))
      ..watch(
        true,
        () => (hasPlayer: true, playing: false, sessionPlaying: false),
      );
    await tester.pump(const Duration(seconds: 5));
    watchdog.watch(
      false,
      () => (hasPlayer: true, playing: true, sessionPlaying: true),
    );
    await tester.pump(const Duration(seconds: 5));
    expect(reports, ['playback_mismatch', 'playback_mismatch']);
  });

  testWidgets('latest command wins and successful playback is not flagged', (
    tester,
  ) async {
    final reports = <String>[];
    MediaCommandWatchdog((reason, _) => reports.add(reason))
      ..watch(
        true,
        () => (hasPlayer: true, playing: false, sessionPlaying: false),
      )
      ..watch(
        false,
        () => (hasPlayer: true, playing: false, sessionPlaying: false),
      );
    await tester.pump(const Duration(seconds: 5));
    expect(reports, isEmpty);
  });

  testWidgets(
    'owner changes, direct opposite commands and disable cancel old checks',
    (tester) async {
      final reports = <String>[];
      final watchdog = MediaCommandWatchdog((reason, _) => reports.add(reason))
        ..watch(true, () => null);
      await tester.pump(const Duration(seconds: 5));
      watchdog
        ..watch(
          true,
          () => (hasPlayer: false, playing: false, sessionPlaying: false),
        )
        ..supersedeIfDifferent(false);
      await tester.pump(const Duration(seconds: 5));
      watchdog
        ..watch(
          true,
          () => (hasPlayer: false, playing: false, sessionPlaying: false),
        )
        ..cancel();
      await tester.pump(const Duration(seconds: 5));
      expect(reports, isEmpty);
    },
  );

  testWidgets('detects missing player and stale media-session state', (
    tester,
  ) async {
    final reports = <String>[];
    final watchdog = MediaCommandWatchdog((reason, _) => reports.add(reason))
      ..watch(
        true,
        () => (hasPlayer: false, playing: false, sessionPlaying: false),
      );
    await tester.pump(const Duration(seconds: 5));
    watchdog.watch(
      false,
      () => (hasPlayer: true, playing: false, sessionPlaying: true),
    );
    await tester.pump(const Duration(seconds: 5));
    expect(reports, ['missing_player', 'session_mismatch']);
  });
  testWidgets('a disposed player snapshot cannot throw out of the timer', (
    tester,
  ) async {
    final reports = <String>[];
    MediaCommandWatchdog((reason, _) => reports.add(reason))
        .watch(true, () => throw StateError('disposed'));
    await tester.pump(const Duration(seconds: 5));
    expect(reports, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
