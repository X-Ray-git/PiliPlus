package com.example.piliplus

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * 桌面快捷方式帮助类
 * 用于创建和管理应用快捷方式
 */
class ShortcutHelper(private val context: Context) {

    /**
     * 创建收藏夹桌面快捷方式
     *
     * @param mediaId 收藏夹ID
     * @param title 收藏夹标题
     * @param customIconPath 自定义图标的本地文件路径(可选,为null则使用应用图标)
     * @return true表示请求成功发送,false表示失败
     */
    suspend fun createFavShortcut(
        mediaId: String,
        title: String,
        customIconPath: String?
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            // 创建Deep Link Intent,点击快捷方式时打开指定收藏夹
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = android.net.Uri.parse("bilibili://medialist/detail/$mediaId")
                setClass(context, MainActivity::class.java)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }

            // 默认使用应用图标,如果提供了自定义图标路径则使用自定义图标
            val icon = if (!customIconPath.isNullOrEmpty()) {
                loadIconFromFile(customIconPath)
            } else {
                IconCompat.createWithResource(context, R.mipmap.ic_launcher)
            }

            // 创建快捷方式
            val shortcut = ShortcutInfoCompat.Builder(context, "fav_$mediaId")
                .setShortLabel(title) // 短标签(桌面显示)
                .setLongLabel(title) // 长标签(长按显示)
                .setIcon(icon)
                .setIntent(intent)
                .build()

            // 请求添加快捷方式到桌面(Android 8.0+会弹出授权对话框)
            ShortcutManagerCompat.requestPinShortcut(context, shortcut, null)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    /**
     * 从本地文件加载图标
     * 
     * @param filePath 图片文件路径
     * @return 图标,加载失败时返回默认应用图标
     */
    private fun loadIconFromFile(filePath: String): IconCompat {
        return try {
            val file = File(filePath)
            if (file.exists()) {
                val bitmap = BitmapFactory.decodeFile(filePath)
                if (bitmap != null) {
                    // 调整图标大小以适应快捷方式 (192x192 dp)
                    val scaledBitmap = Bitmap.createScaledBitmap(bitmap, 192, 192, true)
                    IconCompat.createWithBitmap(scaledBitmap)
                } else {
                    IconCompat.createWithResource(context, R.mipmap.ic_launcher)
                }
            } else {
                IconCompat.createWithResource(context, R.mipmap.ic_launcher)
            }
        } catch (e: Exception) {
            e.printStackTrace()
            IconCompat.createWithResource(context, R.mipmap.ic_launcher)
        }
    }
}
