import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/fav_select_dialog.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/models_new/fav/fav_folder/data.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

void imageSaveDialog({
  required String? title,
  required String? cover,
  dynamic aid,
  String? bvid,
}) {
  final double imgWidth = MediaQuery.sizeOf(Get.context!).shortestSide - 16;
  SmartDialog.show(
    animationType: SmartAnimationType.centerScale_otherSlide,
    builder: (context) {
      const iconSize = 20.0;
      final theme = Theme.of(context);
      return Container(
        width: imgWidth,
        margin: const .symmetric(horizontal: StyleString.safeSpace),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: StyleString.mdRadius,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: SmartDialog.dismiss,
                  child: NetworkImgLayer(
                    src: cover,
                    quality: 100,
                    width: imgWidth,
                    height: imgWidth / StyleString.aspectRatio16x9,
                    borderRadius: const .vertical(top: StyleString.imgRadius),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  width: 30,
                  height: 30,
                  child: IconButton(
                    tooltip: '关闭',
                    style: IconButton.styleFrom(
                      padding: .zero,
                      backgroundColor: Colors.black.withValues(alpha: 0.3),
                    ),
                    onPressed: SmartDialog.dismiss,
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  if (title != null)
                    Expanded(
                      child: SelectableText(
                        title,
                        style: theme.textTheme.titleSmall,
                      ),
                    )
                  else
                    const Spacer(),
                  if (aid != null || bvid != null) ...[
                    iconButton(
                      iconSize: iconSize,
                      tooltip: '稍后再看',
                      onPressed: () => {
                        SmartDialog.dismiss(),
                        UserHttp.toViewLater(aid: aid, bvid: bvid),
                      },
                      icon: const Icon(Icons.watch_later_outlined),
                    ),
                    iconButton(
                      iconSize: iconSize,
                      tooltip: '收藏',
                      onPressed: () async {
                        SmartDialog.dismiss();
                        
                        if (!Accounts.main.isLogin) {
                          SmartDialog.showToast('账号未登录');
                          return;
                        }
                        
                        // 获取aid，如果只有bvid，则通过bvid转换
                        int? videoAid = aid;
                        if (videoAid == null && bvid != null) {
                          SmartDialog.showLoading(msg: '获取视频信息');
                          try {
                            // 通过bvid获取aid的方法：先获取cid（会同时返回aid信息）
                            // 使用SearchHttp.ab2c来获取，虽然它返回cid，但我们可以用其他方式
                            // 实际上我们需要从bvid提取aid
                            // bvid是base58编码的aid，但解码比较复杂
                            // 更简单的方法：调用视频详情API
                            final res = await Request().get(
                              '/x/web-interface/view',
                              queryParameters: {'bvid': bvid},
                            );
                            SmartDialog.dismiss();
                            if (res.data['code'] == 0) {
                              videoAid = res.data['data']?['aid'];
                            }
                          } catch (e) {
                            SmartDialog.dismiss();
                            SmartDialog.showToast('获取视频信息失败');
                            return;
                          }
                        }
                        
                        if (videoAid == null) {
                          SmartDialog.showToast('无法获取视频ID');
                          return;
                        }
                        
                        SmartDialog.showLoading(msg: '加载中');
                        
                        // 获取用户收藏夹列表
                        final foldersRes = await FavHttp.videoInFolder(
                          mid: Accounts.main.mid,
                          rid: videoAid,
                          type: 2,
                        );
                        
                        SmartDialog.dismiss();
                        
                        if (!foldersRes.isSuccess) {
                          SmartDialog.showToast('获取收藏夹失败');
                          return;
                        }
                        
                        final folders = foldersRes.data.list ?? [];
                        if (folders.isEmpty) {
                          SmartDialog.showToast('暂无收藏夹，请先创建');
                          return;
                        }
                        
                        final initialSelected = folders
                            .where((f) => f.favState == 1)
                            .map((f) => f.id)
                            .toSet();
                        
                        if (!Get.context!.mounted) return;
                        
                        final result = await FavSelectDialog.show(
                          Get.context!,
                          folders,
                          initialSelected,
                        );
                        
                        if (result == null) return;
                        
                        if (result.add.isEmpty && result.del.isEmpty) {
                          SmartDialog.showToast('未做任何修改');
                          return;
                        }
                        
                        SmartDialog.showLoading(msg: '处理中');
                        
                        final favRes = await FavHttp.favVideo(
                          resources: '$videoAid:2',
                          addIds: result.add.isNotEmpty
                              ? result.add.join(',')
                              : null,
                          delIds: result.del.isNotEmpty
                              ? result.del.join(',')
                              : null,
                        );
                        
                        SmartDialog.dismiss();
                        
                        if (favRes.isSuccess) {
                          SmartDialog.showToast('操作成功');
                        } else {
                          SmartDialog.showToast('操作失败：$favRes');
                        }
                      },
                      icon: const Icon(Icons.star_outline),
                    ),
                  ],
                  if (cover != null && cover.isNotEmpty) ...[
                    if (PlatformUtils.isMobile)
                      iconButton(
                        iconSize: iconSize,
                        tooltip: '分享',
                        onPressed: () {
                          SmartDialog.dismiss();
                          ImageUtils.onShareImg(cover);
                        },
                        icon: const Icon(Icons.share),
                      ),
                    iconButton(
                      iconSize: iconSize,
                      tooltip: '保存封面图',
                      onPressed: () async {
                        bool saveStatus = await ImageUtils.downloadImg([cover]);
                        if (saveStatus) {
                          SmartDialog.dismiss();
                        }
                      },
                      icon: const Icon(Icons.download),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
