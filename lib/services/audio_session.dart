import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/services/media_control_diagnostics.dart';
import 'package:audio_session/audio_session.dart';

class AudioSessionHandler {
  late AudioSession _session;
  bool _shouldResume = false;

  // [CUSTOM] Observe focus requests/results without changing focus policy.
  Future<bool> setActive(bool active) async {
    MediaControlDiagnostics.record('focus.request', {'active': active});
    try {
      final granted = await _session.setActive(active);
      MediaControlDiagnostics.record('focus.result', {
        'active': active,
        'granted': granted,
      });
      return granted;
    } catch (error) {
      MediaControlDiagnostics.record('focus.error', {
        'active': active,
        'errorType': error.runtimeType.toString(),
      });
      rethrow;
    }
  }

  AudioSessionHandler() {
    initSession();
  }

  Future<void> initSession() async {
    _session = await AudioSession.instance;
    _session.configure(const AudioSessionConfiguration.music());

    _session.interruptionEventStream.listen(_onInterrupted);

    // 耳机拔出暂停
    _session.becomingNoisyEventStream.listen((_) {
      MediaControlDiagnostics.record('audio.becomingNoisy');
      final pause = videoPlayerServiceHandler?.onPause;
      if (pause != null) {
        pause();
      } else {
        PlPlayerController.pauseIfExists();
      }
    });
  }

  void _onInterrupted(AudioInterruptionEvent event) {
    MediaControlDiagnostics.record('focus.interruption', {
      'begin': event.begin,
      'type': event.type.name,
    });
    if (event.begin) {
      final player = PlPlayerController.instance;
      switch (event.type) {
        case .duck:
          if (player != null && player.playerStatus.isPlaying) {
            player.setVolume(player.volume.value * 0.5, showIndicator: false);
          }
        case .pause:
        case .unknown:
          final isAudioPlaying = videoPlayerServiceHandler?.isPlaying;
          if (isAudioPlaying != null) {
            if (isAudioPlaying()) {
              _shouldResume = true;
              videoPlayerServiceHandler?.onPause?.call();
            }
          } else if (player != null && player.playerStatus.isPlaying) {
            _shouldResume = true;
            player.pause(isInterrupt: true);
          }
      }
    } else {
      switch (event.type) {
        case .duck:
          final player = PlPlayerController.instance;
          player?.setVolume(player.volume.value * 2, showIndicator: false);
        case .pause:
          if (_shouldResume) {
            _shouldResume = false;
            final play = videoPlayerServiceHandler?.onPlay;
            if (play != null) {
              play();
            } else {
              PlPlayerController.playIfExists();
            }
          }
        case .unknown:
      }
    }
  }
}
