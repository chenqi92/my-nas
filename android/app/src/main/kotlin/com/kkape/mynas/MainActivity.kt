package com.kkape.mynas

import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import com.kkape.mynas.widgets.WidgetDataChannel
import com.kkape.mynas.dynamicisland.DynamicIslandChannel
import com.kkape.mynas.transcoding.MediaCodecTranscodingPlugin

class MainActivity : AudioServiceFragmentActivity() {
    private var videoSystemBarsHidden = false
    private var previousSystemUiVisibility: Int? = null
    private var previousSystemBarsBehavior: Int? = null
    private var videoDisplayChannel: MethodChannel? = null

    @Suppress("DEPRECATION")
    private fun updateVideoSystemBars() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.apply {
                if (videoSystemBarsHidden) {
                    systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    hide(WindowInsets.Type.systemBars())
                } else {
                    previousSystemBarsBehavior?.let { systemBarsBehavior = it }
                    previousSystemBarsBehavior = null
                    show(WindowInsets.Type.systemBars())
                }
            }
        } else {
            window.decorView.systemUiVisibility = if (videoSystemBarsHidden) {
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            } else {
                previousSystemUiVisibility ?: View.SYSTEM_UI_FLAG_VISIBLE
            }
            if (!videoSystemBarsHidden) previousSystemUiVisibility = null
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        videoDisplayChannel?.setMethodCallHandler(null)
        videoDisplayChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && videoSystemBarsHidden) updateVideoSystemBars()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        videoDisplayChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "my_nas/video_display")
        videoDisplayChannel?.setMethodCallHandler { call, result ->
            if (call.method == "setSystemBarsHidden") {
                val hidden = call.arguments as? Boolean ?: false
                if (hidden != videoSystemBarsHidden) {
                    if (hidden) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            previousSystemBarsBehavior = window.insetsController?.systemBarsBehavior
                        } else {
                            @Suppress("DEPRECATION")
                            val visibility = window.decorView.systemUiVisibility
                            previousSystemUiVisibility = visibility
                        }
                    }
                    videoSystemBarsHidden = hidden
                    updateVideoSystemBars()
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        // 注册 Chromaprint 指纹插件
        flutterEngine.plugins.add(ChromaprintPlugin())

        // 注册小组件数据通道
        flutterEngine.plugins.add(WidgetDataChannel())

        // 注册灵动岛通道
        flutterEngine.plugins.add(DynamicIslandChannel())

        // 注册显示能力检测插件 (HDR)
        flutterEngine.plugins.add(DisplayCapabilityPlugin())

        // 注册音频能力检测插件 (直通)
        flutterEngine.plugins.add(AudioCapabilityPlugin())

        // 注册 MediaCodec 转码插件
        flutterEngine.plugins.add(MediaCodecTranscodingPlugin())
    }
}
