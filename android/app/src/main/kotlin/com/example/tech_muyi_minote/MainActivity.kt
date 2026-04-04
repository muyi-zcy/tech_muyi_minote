package com.example.tech_muyi_minote

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : FlutterActivity() {
    private val clipboardChannel = "com.example.tech_muyi_minote/clipboard_image"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, clipboardChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "writeImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val mime = call.argument<String>("mime") ?: "image/png"
                if (path.isNullOrEmpty()) {
                    result.error("bad_args", "missing path", null)
                    return@setMethodCallHandler
                }
                try {
                    val file = File(path)
                    if (!file.exists() || !file.canRead()) {
                        result.error("no_file", "not found or unreadable", null)
                        return@setMethodCallHandler
                    }
                    val authority = "${applicationContext.packageName}.fileprovider"
                    val uri = FileProvider.getUriForFile(this, authority, file)
                    val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip = ClipData.newUri(contentResolver, "MiNote image", uri)
                    cm.setPrimaryClip(clip)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("clipboard", e.message, null)
                }
            }
    }
}
