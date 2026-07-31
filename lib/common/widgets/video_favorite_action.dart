import 'package:PiliPlus/common/widgets/fav_select_dialog.dart';
import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/fav/fav_folder/list.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

abstract final class VideoFavoriteAction {
  static int? resolveAid({Object? aid, String? bvid}) {
    final parsedAid = switch (aid) {
      int value => value,
      null => null,
      _ => int.tryParse(aid.toString()),
    };
    if (parsedAid != null && parsedAid > 0) {
      return parsedAid;
    }
    if (bvid == null || !IdUtils.bvRegexExact.hasMatch(bvid)) {
      return null;
    }
    try {
      return IdUtils.bv2av(bvid);
    } catch (_) {
      return null;
    }
  }

  static Future<List<FavFolderInfo>?> requestFolders({
    required int aid,
    required int mid,
  }) async {
    try {
      final result = await FavHttp.videoInFolder(mid: mid, rid: aid, type: 2);
      if (!Accounts.main.isLogin || Accounts.main.mid != mid) {
        return null;
      }
      return switch (result) {
        Success(:final response) => response.list ?? <FavFolderInfo>[],
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> show({
    required BuildContext context,
    required int? aid,
    required int? prefetchedMid,
    required Future<List<FavFolderInfo>?>? foldersFuture,
    bool dismissCurrentDialog = false,
  }) async {
    if (dismissCurrentDialog) {
      SmartDialog.dismiss();
    }
    if (!Accounts.main.isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    if (aid == null) {
      SmartDialog.showToast('无法获取视频ID');
      return;
    }

    final mid = Accounts.main.mid;
    final reusableFuture = prefetchedMid == mid ? foldersFuture : null;

    SmartDialog.showLoading(msg: '加载中');
    List<FavFolderInfo>? folders;
    try {
      folders = await reusableFuture;
      if (folders == null &&
          Accounts.main.isLogin &&
          Accounts.main.mid == mid) {
        folders = await requestFolders(aid: aid, mid: mid);
      }
    } finally {
      SmartDialog.dismiss();
    }

    if (folders == null) {
      SmartDialog.showToast('获取收藏夹失败');
      return;
    }
    if (folders.isEmpty) {
      SmartDialog.showToast('暂无收藏夹，请先创建');
      return;
    }

    final initialSelected = folders
        .where((folder) => folder.favState == 1)
        .map((folder) => folder.id)
        .toSet();
    final dialogContext = dismissCurrentDialog ? Get.context : context;
    if (dialogContext == null || !dialogContext.mounted) return;

    final result = await FavSelectDialog.show(
      dialogContext,
      folders,
      initialSelected,
    );
    if (result == null) return;
    if (result.add.isEmpty && result.del.isEmpty) {
      SmartDialog.showToast('未做任何修改');
      return;
    }
    if (!Accounts.main.isLogin || Accounts.main.mid != mid) {
      SmartDialog.showToast('账号已切换，请重新操作');
      return;
    }

    SmartDialog.showLoading(msg: '处理中');
    LoadingState<void>? favResult;
    try {
      favResult = await FavHttp.favVideo(
        resources: '$aid:2',
        addIds: result.add.isNotEmpty ? result.add.join(',') : null,
        delIds: result.del.isNotEmpty ? result.del.join(',') : null,
      );
    } catch (_) {
      favResult = null;
    } finally {
      SmartDialog.dismiss();
    }

    if (favResult?.isSuccess == true) {
      SmartDialog.showToast('操作成功');
    } else {
      SmartDialog.showToast(
        favResult == null ? '操作失败，请稍后重试' : '操作失败：$favResult',
      );
    }
  }
}
