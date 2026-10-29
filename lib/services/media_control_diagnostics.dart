import 'dart:io';

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/services/diagnostics/bounded_event_log.dart';
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
  final String _session = DateTime.now().toUtc().toIso8601String();
  Future<BoundedEventLog>? _store;

  Future<BoundedEventLog> get _log => _store ??= () async {
    final dir = await getApplicationDocumentsDirectory();
    return BoundedEventLog(
      File('${dir.path}/.media_control_diagnostics.jsonl'),
    );
  }();

  static void init() {
    instance._enabled = GStorage.setting.get(_settingKey, defaultValue: false);
    WidgetsBinding.instance.addObserver(instance);
    record('session.start');
  }

  static Future<void> setEnabled(bool value) async {
    await GStorage.setting.put(_settingKey, value);
    instance._enabled = value;
    if (value) record('diagnostics.enabled');
  }

  // Call sites pass only booleans, numbers, and fixed enum/event names.
  static void record(String event, [Map<String, Object?> data = const {}]) {
    if (!enabled) return;
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
    // Keep errors contained and do not make the player await disk writes.
    instance._append(entry);
  }

  Future<void> _append(Map<String, Object?> entry) async {
    try {
      await (await _log).append(entry);
    } catch (_) {
      // Path/plugin availability must not affect the media command.
      _store = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    record('app.lifecycle', {'state': state.name});
  }

  static Future<String> export() async {
    final log = await instance._log;
    // The marker is explicit, even if recording has since been switched off.
    await log.append({
      'time': DateTime.now().toUtc().toIso8601String(),
      'event': 'user.report',
      'recordingEnabled': enabled,
      'storageFailedBeforeExport': log.storageFailed,
    });
    return log.read();
  }

  static Future<void> clear() async {
    final log = await instance._log;
    await log.clear();
    if (log.storageFailed) throw const FileSystemException('Clear failed');
  }
}
