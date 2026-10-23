// [CUSTOM] Share favorite queries and global watch-later state across menus.
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/selection_text.dart';
import 'package:PiliPlus/common/widgets/video_favorite_action.dart';
import 'package:PiliPlus/models_new/fav/fav_folder/list.dart';
import 'package:PiliPlus/pages/common/publish/publish_route.dart';
import 'package:PiliPlus/services/later_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

const _iconSize = 20.0;

void showPgcCover({
  required String? title,
  required String? cover,
  dynamic aid,
  String? bvid,
}) => imageSaveDialog(
  title: title,
  cover: cover,
  aid: aid,
  bvid: bvid,
  orientation: .portrait,
  aspectRatio: Style.aspectRatio3x4,
);

void imageSaveDialog({
  required String? title,
  required String? cover,
  dynamic aid,
  String? bvid,
  Orientation orientation = .landscape,
  double aspectRatio = Style.aspectRatio16x9,
}) {
  // [CUSTOM] One favorite-state request per opened cover menu.
  final videoAid = VideoFavoriteAction.resolveAid(aid: aid, bvid: bvid);
  final currentBvid =
      bvid ?? (videoAid == null ? null : IdUtils.av2bv(videoAid));
  final prefetchedMid = Accounts.main.isLogin ? Accounts.main.mid : null;
  final foldersFuture = videoAid != null && prefetchedMid != null
      ? VideoFavoriteAction.requestFolders(aid: videoAid, mid: prefetchedMid)
      : null;
  Get.key.currentState!.push(
    PublishRoute(
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        final colorScheme = ColorScheme.of(context);
        final double width, height;
        switch (orientation) {
          case .portrait:
            height = MediaQuery.sizeOf(context).shortestSide * 0.8;
            width = height * aspectRatio;
          case .landscape:
            width = MediaQuery.sizeOf(context).shortestSide - 16;
            height = width / aspectRatio;
        }

        return Center(
          child: Container(
            width: width,
            margin: const .symmetric(horizontal: Style.safeSpace),
            decoration: _ImageDecoration(
              imageHeight: height,
              color: colorScheme.surface,
              borderRadius: const .all(Style.imgRadius),
            ),
            child: Column(
              mainAxisSize: .min,
              children: [
                IgnorePointer(
                  child: NetworkImgLayer(
                    src: cover,
                    quality: 100,
                    width: width,
                    height: height,
                    borderRadius: const .vertical(top: Style.imgRadius),
                  ),
                ),
                Padding(
                  padding: const .fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      if (title != null)
                        Expanded(
                          child: SelectionText(
                            title,
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      if (currentBvid != null) ...[
                        // [CUSTOM] Use LaterService for global watch later sync
                        Obx(() {
                          final bool isAdded = LaterService.to.isInLater(
                            currentBvid,
                          );
                          return iconButton(
                            iconSize: _iconSize,
                            tooltip: isAdded ? '移除稍后再看' : '稍后再看',
                            onPressed: () => {
                              Get.back(),
                              LaterService.to.toggleLater(
                                currentBvid,
                                aid: videoAid,
                              ),
                            },
                            icon: Icon(
                              isAdded
                                  ? Icons.watch_later
                                  : Icons.watch_later_outlined,
                            ),
                          );
                        }),
                        // [CUSTOM] Sync favorite state in save dialog
                        FutureBuilder<List<FavFolderInfo>?>(
                          future: foldersFuture,
                          builder: (context, snapshot) {
                            final isLoading =
                                foldersFuture != null &&
                                snapshot.connectionState !=
                                    ConnectionState.done;
                            final folders = snapshot.data;
                            final isFavorited =
                                folders?.any(
                                  (folder) => folder.favState == 1,
                                ) ==
                                true;
                            final tooltip = foldersFuture == null
                                ? '收藏'
                                : isLoading
                                ? '查询收藏状态'
                                : folders == null
                                ? '收藏状态未知'
                                : isFavorited
                                ? '已收藏'
                                : '收藏';

                            return iconButton(
                              iconSize: _iconSize,
                              tooltip: tooltip,
                              onPressed: () => VideoFavoriteAction.show(
                                context: context,
                                aid: videoAid,
                                prefetchedMid: prefetchedMid,
                                foldersFuture: foldersFuture,
                                popCurrentRoute: true,
                              ),
                              icon: isLoading
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      isFavorited
                                          ? Icons.star
                                          : Icons.star_outline,
                                    ),
                            );
                          },
                        ),
                      ],
                      if (cover != null && cover.isNotEmpty) ...[
                        if (PlatformUtils.isMobile)
                          iconButton(
                            iconSize: _iconSize,
                            tooltip: '分享',
                            onPressed: () {
                              Get.back();
                              ImageUtils.onShareImg(cover);
                            },
                            icon: const Icon(Icons.share),
                          )
                        else
                          iconButton(
                            iconSize: 18,
                            tooltip: '复制链接',
                            onPressed: () {
                              Get.back();
                              Utils.copyText(cover);
                            },
                            icon: const Icon(Icons.copy),
                          ),
                        iconButton(
                          iconSize: _iconSize,
                          tooltip: '保存封面图',
                          onPressed: () async {
                            bool saveStatus = await ImageUtils.downloadImg([
                              cover,
                            ]);
                            if (saveStatus) {
                              Get.back();
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
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          ScaleTransition(
            scale: animation,
            child: child,
          ),
    ),
  );
}

class _ImageDecoration extends Decoration {
  const _ImageDecoration({
    required this.color,
    required this.imageHeight,
    required this.borderRadius,
  });

  final Color color;
  final double imageHeight;
  final BorderRadius borderRadius;

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) {
    return Path()..addRRect(borderRadius.resolve(textDirection).toRRect(rect));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is _ImageDecoration &&
        other.color == color &&
        other.borderRadius == borderRadius &&
        imageHeight == other.imageHeight;
  }

  @override
  int get hashCode => Object.hash(color, borderRadius, imageHeight);

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) {
    return position.dy >= imageHeight;
  }

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    assert(onChanged != null);
    return _ImageDecorationPainter(this, onChanged);
  }
}

class _ImageDecorationPainter extends BoxPainter {
  _ImageDecorationPainter(this._decoration, super.onChanged);

  final _ImageDecoration _decoration;

  Paint? _cachedBackgroundPaint;
  Paint _getBackgroundPaint(Rect rect) {
    if (_cachedBackgroundPaint == null) {
      final paint = Paint()..color = _decoration.color;
      _cachedBackgroundPaint = paint;
    }

    return _cachedBackgroundPaint!;
  }

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    assert(configuration.size != null);
    final Rect rect = offset & configuration.size!;
    canvas.drawRRect(
      _decoration.borderRadius.toRRect(rect),
      _getBackgroundPaint(rect),
    );
  }

  @override
  String toString() {
    return '_ImagePainter for $_decoration';
  }
}
