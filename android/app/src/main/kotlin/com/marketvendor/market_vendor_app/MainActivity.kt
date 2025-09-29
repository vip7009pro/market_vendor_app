package com.marketvendor.market_vendor_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Đăng ký plugin FileStoragePlugin
        flutterEngine.plugins.add(FileStoragePlugin())
    }
}
