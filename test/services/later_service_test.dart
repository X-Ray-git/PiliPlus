import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models_new/later/data.dart';
import 'package:PiliPlus/models_new/later/list.dart';
import 'package:PiliPlus/services/later_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

LoginAccount account(int mid) => LoginAccount(
  BiliCookieJar.fromJson({'DedeUserID': '$mid', 'bili_jct': 'test'}),
  null,
  null,
);

LoadingState<LaterData> snapshot(List<String> ids) => Success(
  LaterData(list: ids.map((bvid) => LaterItemModel(bvid: bvid)).toList()),
);

void main() {
  late Account first;
  setUp(() {
    first = account(1);
    Accounts.accountMode[AccountType.main.index] = first;
  });

  test('successful empty snapshot removes old entries', () async {
    final service = LaterService(loadPage: (_, _) async => snapshot([]))
      ..recordChange(first, ['old'], true);
    await service.syncList();
    expect(service.laterBvids, isEmpty);
  });

  test(
    'partial pagination failure preserves the previous complete cache',
    () async {
      final service = LaterService(
        loadPage: (page, _) async => page == 1
            ? snapshot(List.generate(100, (index) => 'page-$index'))
            : const Error('offline'),
      )..recordChange(first, ['old'], true);
      await service.syncList();
      expect(service.laterBvids, {'old'});
    },
  );

  test('mutations during loading win over stale snapshot contents', () async {
    final response = Completer<LoadingState<LaterData>>();
    final service = LaterService(loadPage: (_, _) => response.future);
    final sync = service.syncList();
    service
      ..recordChange(first, ['new'], true)
      ..recordChange(first, ['removed'], false);
    response.complete(snapshot(['removed', 'unchanged']));
    await sync;
    expect(service.laterBvids, {'new', 'unchanged'});
  });

  test('late response and mutation from another account are ignored', () async {
    final oldResponse = Completer<LoadingState<LaterData>>();
    final second = account(2);
    final service = LaterService(
      loadPage: (_, owner) => identical(owner, first)
          ? oldResponse.future
          : Future.value(snapshot([])),
    )..recordChange(first, ['old'], true);
    final oldSync = service.syncList();
    Accounts.accountMode[AccountType.main.index] = second;
    expect(service.isInLater('old'), isFalse);
    await service.syncList();
    oldResponse.complete(snapshot(['stale']));
    await oldSync;
    service.recordChange(first, ['late-add'], true);
    expect(service.laterBvids, isEmpty);
  });

  test('a newer refresh wins when responses arrive out of order', () async {
    final firstResponse = Completer<LoadingState<LaterData>>();
    final nextResponse = Completer<LoadingState<LaterData>>();
    int calls = 0;
    final service = LaterService(
      loadPage: (_, _) =>
          ++calls == 1 ? firstResponse.future : nextResponse.future,
    );
    final oldSync = service.syncList();
    final newSync = service.syncList();
    nextResponse.complete(snapshot(['new']));
    await newSync;
    firstResponse.complete(snapshot(['old']));
    await oldSync;
    expect(service.laterBvids, {'new'});
  });

  testWidgets('account transition keeps menu state reactive', (tester) async {
    final service = LaterService(loadPage: (_, _) async => snapshot([]))
      ..recordChange(first, ['old'], true);
    final second = account(2);
    Accounts.accountMode[AccountType.main.index] = second;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Obx(() => Text('${service.isInLater('new')}')),
      ),
    );
    expect(find.text('false'), findsOneWidget);
    service.recordChange(second, ['new'], true);
    await tester.pump();
    expect(find.text('true'), findsOneWidget);
  });

  test('full clear invalidates an in-flight refresh', () async {
    final response = Completer<LoadingState<LaterData>>();
    final service = LaterService(loadPage: (_, _) => response.future);
    final sync = service.syncList();
    service.recordClear(first, null);
    response.complete(snapshot(['old']));
    await sync;
    expect(service.laterBvids, isEmpty);
  });

  test(
    'logout clears cache and ignores the previous account response',
    () async {
      final response = Completer<LoadingState<LaterData>>();
      final service = LaterService(loadPage: (_, _) => response.future)
        ..recordChange(first, ['old'], true);
      final sync = service.syncList();
      Accounts.accountMode[AccountType.main.index] = AnonymousAccount();
      await service.syncList();
      response.complete(snapshot(['old']));
      await sync;
      expect(service.laterBvids, isEmpty);
    },
  );
}
