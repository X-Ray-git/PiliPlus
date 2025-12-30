import 'package:flutter/services.dart';

/// 桌面快捷方式工具类
/// 仅支持Android平台
abstract final class ShortcutHelper {
  static const MethodChannel _channel = MethodChannel('piliplus/shortcut');

  /// 创建收藏夹桌面快捷方式
  /// 
  /// [mediaId] 收藏夹ID
  /// [title] 收藏夹标题
  /// [customIconPath] 自定义图标的本地文件路径(可选,为null则使用应用图标)
  /// 
  /// 返回true表示请求成功发送,false表示失败
  /// 注意:返回true不代表快捷方式已创建,用户可能拒绝授权
  static Future<bool> createFavShortcut({
    required String mediaId,
    required String title,
    String? customIconPath,
  }) async {
    try {
      final result = await _channel.invokeMethod('createFavShortcut', {
        'mediaId': mediaId,
        'title': title,
        'customIconPath': customIconPath,
      });
      return result == true;
    } catch (e) {
      return false;
    }
  }
}
