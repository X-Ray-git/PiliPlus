package com.example.piliplus

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.annotation.RequiresApi
import kotlin.concurrent.thread

/** The launcher's CLEAR_TASK applies to this task, separate from the video player. */
class FavoriteShortcutActivity : Activity() {
    companion object {
        @RequiresApi(Build.VERSION_CODES.O)
        fun migratePinnedFavorites(context: Context) {
            // Older launchers can store an explicit MainActivity target that bypasses URI resolution.
            thread(name = "PiliPlus-favorite-shortcuts") {
                try {
                    val manager = context.getSystemService(ShortcutManager::class.java) ?: return@thread
                    val target = ComponentName(context, FavoriteShortcutActivity::class.java)
                    val updates = manager.pinnedShortcuts.mapNotNull { shortcut ->
                        if (shortcut.isImmutable || !shortcut.id.startsWith("fav_")) return@mapNotNull null
                        val intent = shortcut.intent ?: return@mapNotNull null
                        val uri = intent.data ?: return@mapNotNull null
                        if (intent.action != Intent.ACTION_VIEW || intent.component == target ||
                            uri.scheme != "bilibili" || uri.host != "medialist" ||
                            uri.path != "/detail/${shortcut.id.removePrefix("fav_")}"
                        ) return@mapNotNull null

                        if (uri.getQueryParameter("pili_entry") == null) {
                            intent.data = uri.buildUpon().appendQueryParameter("pili_entry", "pinned_favorite").build()
                        }
                        // Only update the launch intent. The system retains the pin, label and custom icon.
                        ShortcutInfo.Builder(context, shortcut.id).setIntent(intent.setComponent(target)).build()
                    }
                    if (updates.isNotEmpty()) manager.updateShortcuts(updates)
                } catch (e: RuntimeException) {
                    Log.w("FavoriteShortcut", "Could not update pinned favorites on this start", e)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = intent.data
        if (intent.action == Intent.ACTION_VIEW && uri?.scheme == "bilibili" &&
            uri.host == "medialist" && uri.path?.startsWith("/detail/") == true
        ) {
            startActivity(Intent(Intent.ACTION_VIEW, uri, this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        }
        finish()
    }
}
