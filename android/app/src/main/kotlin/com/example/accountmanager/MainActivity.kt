package com.example.accountmanager

import android.content.pm.ActivityInfo
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 原生层平板判断逻辑
        val resource = resources
        val config = resource.configuration
        // 最小宽度>=600dp视为平板
        if (config.smallestScreenWidthDp >= 600) {
            // 平板强制设置为可根据传感器全向旋转
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR
        } else {
            // 手机强制锁定竖屏
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
    }
}
