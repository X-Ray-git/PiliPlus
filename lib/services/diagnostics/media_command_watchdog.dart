import 'dart:async';

// [CUSTOM] A suspicion detector, not a playback recovery mechanism.
typedef MediaControlSnapshot = ({
  bool hasPlayer,
  bool playing,
  bool sessionPlaying,
});

class MediaCommandWatchdog {
  MediaCommandWatchdog(this.report);
  final void Function(String reason, Map<String, Object?> data) report;
  Timer? _timer;
  bool? _expected;

  void watch(bool expectedPlaying, MediaControlSnapshot? Function() snapshot) {
    cancel();
    _expected = expectedPlaying;
    final elapsed = Stopwatch()..start();
    _timer = Timer(const Duration(seconds: 5), () {
      _timer = null;
      // Null means the playback owner changed; that command is no longer relevant.
      MediaControlSnapshot? state;
      try {
        state = snapshot();
      } catch (_) {
        // A disposed player must not make the diagnostic timer throw.
        return;
      }
      if (state == null) return;
      final reason = !state.hasPlayer
          ? 'missing_player'
          : state.playing != expectedPlaying
          ? 'playback_mismatch'
          : state.sessionPlaying != state.playing
          ? 'session_mismatch'
          : null;
      if (reason != null) {
        report(reason, {
          'elapsedMs': elapsed.elapsedMilliseconds,
          'expectedPlaying': expectedPlaying,
          'hasPlayer': state.hasPlayer,
          'nativePlaying': state.playing,
          'sessionPlaying': state.sessionPlaying,
        });
      }
    });
  }

  void supersedeIfDifferent(bool playing) {
    if (_expected != playing) cancel();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _expected = null;
  }
}
