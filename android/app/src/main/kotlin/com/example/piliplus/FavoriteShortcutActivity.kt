package com.example.piliplus

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** The launcher's CLEAR_TASK applies to this task, separate from the video player. */
class FavoriteShortcutActivity : Activity() {
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
