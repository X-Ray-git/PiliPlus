import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class LaterService extends GetxService {
  static LaterService get to => Get.find();

  final RxSet<String> laterBvids = <String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    // Listen to login state changes
    ever(Get.find<AccountService>().isLogin, (bool isLogin) {
      if (isLogin) {
        syncList();
      } else {
        laterBvids.clear();
      }
    });

    if (Get.find<AccountService>().isLogin.value) {
      syncList();
    }
  }

  Future<void> syncList() async {
    if (!Get.find<AccountService>().isLogin.value) return;

    int page = 1;
    bool hasMore = true;
    final Set<String> newBvids = {};

    while (hasMore) {
      // 100 per page to reduce requests
      final res = await UserHttp.seeYouLater(page: page, ps: 100);
      if (res case Success(:final response)) {
        final list = response.list;
        if (list == null || list.isEmpty) {
          hasMore = false;
        } else {
          for (var item in list) {
            if (item.bvid != null) {
              newBvids.add(item.bvid!);
            }
          }
          // If we received fewer than requested, we're done
          if (list.length < 100) {
            hasMore = false;
          } else {
            page++;
          }
        }
      } else {
        // Stop on error to prevent infinite loop
        if (kDebugMode) debugPrint('LaterService syncList error: $res');
        hasMore = false;
      }
    }

    if (newBvids.isNotEmpty) {
      laterBvids
        ..clear()
        ..addAll(newBvids);
    }
  }

  bool isInLater(String? bvid) {
    if (bvid == null) return false;
    return laterBvids.contains(bvid);
  }

  Future<void> toggleLater(String bvid, {int? aid}) async {
    if (!Get.find<AccountService>().isLogin.value) {
      SmartDialog.showToast('账号未登录');
      return;
    }

    if (isInLater(bvid)) {
      final res = await UserHttp.toViewDel(aids: aid?.toString() ?? bvid);
      if (res.isSuccess) {
        laterBvids.remove(bvid);
      }
    } else {
      final res = await UserHttp.toViewLater(bvid: bvid, aid: aid);
      if (res.isSuccess) {
        laterBvids.add(bvid);
      }
    }
  }

  Future<void> addLater(String bvid, {int? aid}) async {
    if (isInLater(bvid)) return;
    await toggleLater(bvid, aid: aid);
  }

  Future<void> removeLater(String bvid, {int? aid}) async {
    if (!isInLater(bvid)) return;
    await toggleLater(bvid, aid: aid);
  }
}
