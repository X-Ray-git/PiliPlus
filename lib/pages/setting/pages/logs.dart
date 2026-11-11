import 'dart:async' show Timer;
import 'dart:convert' show jsonDecode;
import 'dart:io';

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/selection_text.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/services/media_control_diagnostics.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:catcher_2/catcher_2.dart';
import 'package:catcher_2/utils/log_printer.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const _snackBarDisplayDuration = Duration(seconds: 1);

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  List<_ExpandedItem<Report>> logsContent = [];
  _ExpandedItem<_DeviceInfo>? _deviceInfo;
  late bool enableLog = Pref.enableLog;
  bool _diagnosticsBusy = false;

  @override
  void initState() {
    _initDeviceInfo();
    getLog();
    MediaControlDiagnostics.refreshArchiveStatus();
    super.initState();
  }

  void _initDeviceInfo() {
    if (Catcher2.instance case final c?) {
      _deviceInfo = _ExpandedItem((
        c.deviceParameters,
        c.applicationParameters,
        c.customParameters,
      ));
    }
  }

  Future<void> getLog() async {
    final logsPath = await LoggerUtils.getLogsPath();
    logsContent = (await logsPath.readAsLines()).reversed.map((i) {
      try {
        final log = Report.fromJson(jsonDecode(i));
        return _ExpandedItem(log);
      } catch (e, s) {
        return _ExpandedItem(
          Report(
            'Parse log failed: $e\n\n\n$i',
            s,
            DateTime.now(),
            const {},
            const {},
            const {},
            null,
          ),
        );
      }
    }).toList();
    if (mounted) {
      setState(() {});
    }
  }

  void copyLogs() {
    Utils.copyText(
      '```\n${logsContent.join('\n\n')}```',
      needToast: false,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('复制成功'),
          duration: _snackBarDisplayDuration,
        ),
      );
    }
  }

  Future<void> clearLogs() async {
    if (await LoggerUtils.clearLogs()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已清空'),
            duration: _snackBarDisplayDuration,
          ),
        );
        logsContent.clear();
        setState(() {});
      }
    }
  }

  // [CUSTOM] Separate opt-in media diagnostics from crash reports.
  Future<File> _diagnosticExportFile() async {
    final directory = await getTemporaryDirectory();
    return File('${directory.path}/piliplus-media-diagnostics.jsonl');
  }

  Future<void> _runDiagnosticAction(Future<void> Function() action) async {
    if (_diagnosticsBusy) return;
    setState(() => _diagnosticsBusy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请稍后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _diagnosticsBusy = false);
    }
  }

  Future<void> _markMediaIncident() async {
    await MediaControlDiagnostics.markIncident();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            MediaControlDiagnostics.archiveStatus.value.full
                ? '故障存档已满，请先导出再清空；已有存档不会被覆盖'
                : '已保存故障现场，可稍后导出',
          ),
        ),
      );
    }
  }

  Future<void> _exportMediaDiagnostics() async {
    final content = await MediaControlDiagnostics.export();
    final file = await _diagnosticExportFile();
    await file.writeAsString(content, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        sharePositionOrigin: await ShareUtils.sharePositionOrigin,
      ),
    );
  }

  Future<void> _clearMediaDiagnostics() async {
    await MediaControlDiagnostics.clear();
    final file = await _diagnosticExportFile();
    // Keep diagnostic file operations off the UI event loop.
    // ignore: avoid_slow_async_io
    if (await file.exists()) await file.delete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空媒体控制诊断记录')),
      );
    }
  }

  Widget _mediaDiagnosticsCard() => Card(
    child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text('媒体控制诊断'),
            subtitle: const Text('记录后台视频播放、暂停及音频焦点状态，立即生效'),
            value: MediaControlDiagnostics.enabled,
            onChanged: _diagnosticsBusy
                ? null
                : (value) => _runDiagnosticAction(
                    () => MediaControlDiagnostics.setEnabled(value),
                  ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '开启后，控制指令 5 秒后状态仍不符、命令异常或获取音频焦点失败时，'
              '自动保存疑似故障及前后记录。系统未传入耳机按键时无法自动发现，'
              '请尽快手动标记，之后可稍后导出。\n'
              '日常记录循环保留 400 条、128 KiB；故障单独保存至手动清空，'
              '最多 20 份、每份 256 KiB。存满后停止新增，不覆盖已有故障。\n'
              '仅保存在本机，不记录视频内容、地址或账号，不会自动上传。',
            ),
          ),
          ValueListenableBuilder(
            valueListenable: MediaControlDiagnostics.archiveStatus,
            builder: (context, status, _) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                status.failed
                    ? '诊断存储出现错误，请尝试导出并检查存储空间'
                    : status.full
                    ? '已保存 ${status.saved}/20 份，存档已满，请先导出再清空'
                    : '已保存 ${status.saved}/20 份故障现场',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _diagnosticsBusy
                      ? null
                      : () => _runDiagnosticAction(_markMediaIncident),
                  child: const Text('标记刚才的故障'),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.ios_share),
                  label: const Text('导出诊断记录'),
                  onPressed: _diagnosticsBusy
                      ? null
                      : () => _runDiagnosticAction(_exportMediaDiagnostics),
                ),
                TextButton(
                  onPressed: _diagnosticsBusy
                      ? null
                      : () => _runDiagnosticAction(_clearMediaDiagnostics),
                  child: const Text('清空诊断记录'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          PopupMenuButton(
            itemBuilder: (_) => [
              if (kDebugMode)
                PopupMenuItem(
                  onTap: () => Timer.periodic(
                    const Duration(milliseconds: 3500),
                    (timer) {
                      Utils.reportError('Manual', StackTrace.current);
                      if (timer.tick > 3) {
                        timer.cancel();
                        if (mounted) getLog();
                      }
                    },
                  ),
                  child: const Text('引发错误'),
                ),
              PopupMenuItem(
                onTap: () {
                  enableLog = !enableLog;
                  GStorage.setting.put(SettingBoxKey.enableLog, enableLog);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已${enableLog ? '开启' : '关闭'}，重启生效'),
                      duration: _snackBarDisplayDuration,
                    ),
                  );
                },
                child: Text('${enableLog ? '关闭' : '开启'}日志'),
              ),
              PopupMenuItem(
                onTap: copyLogs,
                child: const Text('复制日志'),
              ),
              PopupMenuItem(
                onTap: () =>
                    PageUtils.launchURL('${Constants.sourceCodeUrl}/issues'),
                child: const Text('错误反馈'),
              ),
              PopupMenuItem(
                onTap: clearLogs,
                child: const Text('清空日志'),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.only(
          left: padding.left + 12,
          right: padding.right + 12,
        ),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _mediaDiagnosticsCard()),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            if (_deviceInfo != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const .only(bottom: 12),
                  child: _InfoCard(info: _deviceInfo!),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.only(bottom: padding.bottom + 100),
              sliver: SliverList.separated(
                itemCount: logsContent.length,
                itemBuilder: (context, index) =>
                    _ReportCard(report: logsContent[index]),
                separatorBuilder: (_, _) => const SizedBox(height: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _DeviceInfo = (
  Map<String, dynamic>,
  Map<String, dynamic>,
  Map<String, dynamic>,
);

class _InfoCard extends StatelessWidget {
  final _ExpandedItem<_DeviceInfo> info;

  const _InfoCard({required this.info});

  Widget _buildMapSection(
    Color color,
    String title,
    Map<String, dynamic> map,
  ) {
    if (map.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      spacing: 4,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(fontWeight: .bold, color: color, fontSize: 15),
        ),
        ...map.entries.map(
          (entry) => Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '• ${entry.key}: ',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                TextSpan(
                  text: entry.value.toString(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return _card([
      Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 22,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '相关信息',
              style: TextStyle(fontWeight: .bold, fontSize: 15),
              maxLines: 1,
              overflow: .ellipsis,
            ),
          ),
          iconButton(
            size: 34,
            iconSize: 22,
            tooltip: '复制',
            onPressed: () {
              final report = Report(
                '',
                null,
                DateTime(1970),
                info.item.$1,
                info.item.$2,
                info.item.$3,
                null,
              ).formatInfo();
              Utils.copyText('```\n$report```', needToast: false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已将相关信息复制至剪贴板'),
                  duration: _snackBarDisplayDuration,
                ),
              );
            },
            icon: const Icon(Icons.copy_outlined, size: 16),
          ),
          iconButton(
            size: 34,
            iconSize: 22,
            tooltip: info.isExpanded ? '收起' : '展开',
            icon: Icon(
              info.isExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onPressed: () {
              info.isExpanded = !info.isExpanded;
              (context as Element).markNeedsBuild();
            },
          ),
        ],
      ),
      if (info.isExpanded) ...[
        _buildMapSection(colorScheme.primary, '设备信息', info.item.$1),
        _buildMapSection(colorScheme.primary, '应用信息', info.item.$2),
        _buildMapSection(colorScheme.primary, '编译信息', info.item.$3),
      ],
    ]);
  }
}

class _ReportCard extends StatelessWidget {
  final _ExpandedItem<Report> report;

  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    late final stackTrace = PrettyLogPrinter.formatStackString(
      report.item.stackTrace?.toString(),
      -1,
    );
    final dateTime = DateFormatUtils.longFormatDs.format(report.item.dateTime);
    return _card([
      Row(
        crossAxisAlignment: .start,
        children: [
          Expanded(
            child: Column(
              spacing: 6,
              crossAxisAlignment: .start,
              children: [
                Text(
                  report.item.error.toString(),
                  style: const TextStyle(fontWeight: .bold, fontSize: 15),
                  maxLines: 2,
                  overflow: .ellipsis,
                ),
                Text(
                  dateTime,
                  style: TextStyle(
                    height: 1.2,
                    color: colorScheme.outline,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          iconButton(
            size: 34,
            iconSize: 22,
            tooltip: '复制',
            onPressed: () {
              Utils.copyText('```\n$report```', needToast: false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已将 $dateTime 复制至剪贴板'),
                  duration: _snackBarDisplayDuration,
                ),
              );
            },
            icon: const Icon(Icons.copy_outlined, size: 16),
          ),
          iconButton(
            size: 34,
            iconSize: 22,
            tooltip: report.isExpanded ? '收起' : '展开',
            icon: Icon(
              report.isExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onPressed: () {
              report.isExpanded = !report.isExpanded;
              (context as Element).markNeedsBuild();
            },
          ),
        ],
      ),
      if (report.isExpanded) ...[
        const SizedBox(height: 16),
        Text(
          '错误详情',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colorScheme.error,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const .all(12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const .all(.circular(8)),
            border: .all(color: colorScheme.outline.withValues(alpha: 0.5)),
          ),
          child: SelectionText(
            report.item.error.toString(),
            style: TextStyle(
              fontFamily: 'Monospace',
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // stackTrace may be null or String("null") or blank
        if (stackTrace != null && stackTrace.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '堆栈跟踪',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colorScheme.error,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const .all(12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const .all(.circular(8)),
              border: .all(color: colorScheme.outline.withValues(alpha: 0.5)),
            ),
            child: SelectionText.rich(
              TextSpan(
                children: stackTrace
                    .map(
                      (i) => TextSpan(
                        text: '$i\n',
                        style: i.contains('(package:${Constants.appName}')
                            ? TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: .w600,
                              )
                            : TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                    .toList(),
              ),
              style: const TextStyle(fontFamily: 'Monospace', fontSize: 13),
            ),
          ),
        ],
      ],
    ]);
  }
}

Widget _card(List<Widget> contents) {
  return Card(
    child: Padding(
      padding: const .all(12),
      child: Column(
        crossAxisAlignment: .stretch,
        children: contents,
      ),
    ),
  );
}

class _ExpandedItem<T> {
  bool isExpanded = false;
  final T item;

  _ExpandedItem(this.item);

  @override
  String toString() => item.toString();
}
