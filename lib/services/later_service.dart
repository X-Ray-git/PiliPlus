import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/models_new/later/data.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

// [CUSTOM] Account-scoped cache shared by every watch-later entry point.
class LaterService extends GetxService {
  LaterService({this.loadPage = _loadPage});

  static LaterService get to => Get.find();
  final Future<LoadingState<LaterData>> Function(int, Account) loadPage;
  final RxSet<String> laterBvids = <String>{}.obs;
  final Map<String, bool> _changes = {};
  final Set<(Account, String)> _pending = {};
  Account? _account;
  Worker? _loginWorker;
  int _generation = 0;
  bool _syncing = false;

  static Future<LoadingState<LaterData>> _loadPage(int page, Account account) =>
      UserHttp.seeYouLater(page: page, ps: 100, account: account);

  @override
  void onInit() {
    super.onInit();
    _loginWorker = ever(Get.find<AccountService>().isLogin, (_) => syncList());
    syncList();
  }

  void _useAccount(Account account) {
    if (identical(_account, account)) return;
    _account = account;
    _generation++;
    _syncing = false;
    _changes.clear();
    laterBvids.clear();
  }

  Future<void> syncList() async {
    final account = Accounts.main;
    _useAccount(account);
    final generation = ++_generation;
    _changes.clear();
    _syncing = account.isLogin;
    if (!account.isLogin) return;
    final next = <String>{};
    bool isCurrent() =>
        generation == _generation && identical(account, Accounts.main);
    try {
      for (int page = 1; ; page++) {
        final res = await loadPage(page, account);
        if (!isCurrent()) return;
        if (res case Success(:final response)) {
          final list = response.list ?? const [];
          for (final item in list) {
            if (item.bvid case final bvid? when bvid.isNotEmpty) next.add(bvid);
          }
          if (list.length < 100) break;
        } else {
          // Failed/partial snapshots must not replace the last complete cache.
          return;
        }
      }
      if (!isCurrent()) return;
      for (final entry in _changes.entries) {
        if (entry.value) {
          next.add(entry.key);
        } else {
          next.remove(entry.key);
        }
      }
      // An empty successful result also replaces the previous snapshot.
      laterBvids
        ..clear()
        ..addAll(next);
    } catch (error) {
      if (kDebugMode) debugPrint('LaterService syncList error: $error');
    } finally {
      if (generation == _generation) {
        _syncing = false;
        _changes.clear();
      }
    }
  }

  // Called only after a successful mutation, with the request's captured account.
  void recordChange(Account account, Iterable<String> bvids, bool present) {
    if (!identical(account, Accounts.main)) return;
    _useAccount(account);
    for (final bvid in bvids) {
      if (_syncing) _changes[bvid] = present;
      if (present) {
        laterBvids.add(bvid);
      } else {
        laterBvids.remove(bvid);
      }
    }
  }

  void recordClear(Account account, int? cleanType) {
    if (!identical(account, Accounts.main)) return;
    _useAccount(account);
    if (cleanType == null) {
      _generation++;
      _syncing = false;
      _changes.clear();
      laterBvids.clear();
    } else {
      syncList();
    }
  }

  bool isInLater(String? bvid) {
    // Always subscribe Obx callers, including during an account transition.
    final contains = laterBvids.contains(bvid);
    return identical(_account, Accounts.main) && contains;
  }

  Future<void> toggleLater(String bvid, {int? aid}) =>
      _setLater(bvid, !isInLater(bvid), aid: aid);

  Future<void> addLater(String bvid, {int? aid}) =>
      _setLater(bvid, true, aid: aid);

  Future<void> removeLater(String bvid, {int? aid}) =>
      _setLater(bvid, false, aid: aid);

  Future<void> _setLater(String bvid, bool present, {int? aid}) async {
    final account = Accounts.main;
    if (!account.isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    final key = (account, bvid);
    if (!_pending.add(key)) return;
    try {
      if (present) {
        await UserHttp.toViewLater(bvid: bvid, aid: aid);
      } else {
        await UserHttp.toViewDel(aids: aid?.toString() ?? bvid);
      }
    } finally {
      _pending.remove(key);
    }
  }

  @override
  void onClose() {
    _loginWorker?.dispose();
    _generation++;
    super.onClose();
  }
}
