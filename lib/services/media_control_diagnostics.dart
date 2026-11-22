import 'dart:io';

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/services/diagnostics/bounded_event_log.dart';
import 'package:PiliPlus/services/diagnostics/incident_store.dart';
import 'package:PiliPlus/services/diagnostics/media_command_watchdog.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

// [CUSTOM] Opt-in diagnostics; no identifiers, URLs, titles or exception text.
class MediaControlDiagnostics with WidgetsBindingObserver {
  static final instance = MediaControlDiagnostics._();
  MediaControlDiagnostics._();
  static const _settingKey = 'mediaControlDiagnostics';
  static bool get enabled => instance._enabled;
  bool _enabled = false;
  int _sequence = 0;
  // Keep the last release available if routine events rotate out before a press.
  Map<String, Object?>? _lastRelease;
  final String _session = DateTime.now().toUtc().toIso8601String();
  Future<IncidentStore>? _store;
  static final archiveStatus = ValueNotifier((
    saved: 0,
    full: false,
    failed: false,
  ));
  final _watchdog = MediaCommandWatchdog((reason, data) {
    record('media.command.suspect', {'reason': reason, ...data});
  });

  Future<IncidentStore> get _log => _store ??= () async {
    final dir = await getApplicationDocumentsDirectory();
    return IncidentStore(
      BoundedEventLog(File('${dir.path}/.media_control_diagnostics.jsonl')),
      Directory('${dir.path}/.media_control_incidents'),
    );
  }();

  static void init() {
    instance._enabled = GStorage.setting.get(_settingKey, defaultValue: false);
    WidgetsBinding.instance.addObserver(instance);
    record('session.start');
  }

  static Future<void> setEnabled(bool value) async {
    await GStorage.setting.put(_settingKey, value);
    instance._watchdog.cancel();
    instance._lastRelease = null;
    instance._enabled = value;
    if (value) record('diagnostics.enabled');
  }

  // Call sites pass only booleans, numbers, and fixed enum/event names.
  static void record(String event, [Map<String, Object?> data = const {}]) {
    if (!enabled) return;
    if (event == 'video.play.begin' || event == 'video.pause.begin') {
      instance._watchdog.supersedeIfDifferent(event == 'video.play.begin');
    }
    final entry = <String, Object?>{
      'time': DateTime.now().toUtc().toIso8601String(),
      'session': instance._session,
      'sequence': ++instance._sequence,
      'event': event,
      'version': BuildConfig.versionName,
      'commit': BuildConfig.commitHash,
      'platform': Platform.operatingSystem,
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      ...data,
    };
    if (event == 'video.controller.release') {
      instance._lastRelease = entry;
    } else if (event == 'video.controller.created') {
      instance._lastRelease = null;
    } else if (event == 'media.command.suspect' &&
        data['reason'] == 'missing_player') {
      entry['lastRelease'] = instance._lastRelease;
    }
    // Keep errors contained and do not make the player await disk writes.
    instance._append(entry);
  }

  Future<void> _append(Map<String, Object?> entry) async {
    try {
      final log = await _log;
      final event = entry['event'] as String;
      final incident =
          event.endsWith('.error') ||
          event == 'media.command.suspect' ||
          (event == 'focus.result' &&
              entry['active'] == true &&
              entry['granted'] == false);
      await log.append(entry, incident: incident ? event : null);
      _publish(log);
    } catch (_) {
      // Path/plugin availability must not affect the media command.
      _store = null;
      archiveStatus.value = (
        saved: archiveStatus.value.saved,
        full: archiveStatus.value.full,
        failed: true,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    record('app.lifecycle', {'state': state.name});
  }

  static void _publish(IncidentStore log) {
    archiveStatus.value = (
      saved: log.saved,
      full: log.full,
      failed: log.failed,
    );
  }

  static void cancelCommandCheck() => instance._watchdog.cancel();

  static void watchCommand(
    bool playing,
    MediaControlSnapshot? Function() snapshot,
  ) {
    if (enabled) instance._watchdog.watch(playing, snapshot);
  }

  static Future<void> refreshArchiveStatus() async {
    try {
      final log = await instance._log;
      await log.refresh();
      _publish(log);
    } catch (_) {
      archiveStatus.value = (saved: 0, full: false, failed: true);
    }
  }

  // Explicit marking also covers hardware presses that never reached Dart.
  static Future<void> markIncident() async {
    final log = await instance._log;
    await log.append({
      'time': DateTime.now().toUtc().toIso8601String(),
      'event': 'user.report',
      'recordingEnabled': enabled,
      'version': BuildConfig.versionName,
      'commit': BuildConfig.commitHash,
    }, incident: 'user.report');
    _publish(log);
    if (log.failed) throw const FileSystemException('Incident write failed');
  }

  static Future<String> export() async {
    final log = await instance._log;
    final result = await log.export();
    _publish(log);
    return result;
  }

  static Future<void> clear() async {
    instance._lastRelease = null;
    instance._watchdog.cancel();
    final log = await instance._log;
    await log.clear();
    _publish(log);
  }
}
