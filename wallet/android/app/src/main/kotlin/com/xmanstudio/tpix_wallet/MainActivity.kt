package com.xmanstudio.tpix_wallet

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // เว็บบนมือถือเปิดกระเป๋าด้วย tpixwallet://wc → ผู้ใช้ตอบเสร็จแล้วพากลับเบราว์เซอร์
        // moveTaskToBack = ถอย task ของกระเป๋าไปข้างหลัง (ไม่ปิดแอป) task ของเบราว์เซอร์ที่อยู่ใต้กลับขึ้นมาเอง
        // ฝั่ง Dart: lib/services/app_return.dart
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tpix_wallet/app_return")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveToBack" -> result.success(moveTaskToBack(true))
                    else -> result.notImplemented()
                }
            }
    }
}
