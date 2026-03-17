package com.amble.app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.amble.app/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "requestPinWidget") {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val appWidgetManager = AppWidgetManager.getInstance(this)
                        val provider = ComponentName(this, RambleWidgetProvider::class.java)
                        if (appWidgetManager.isRequestPinAppWidgetSupported) {
                            val requested = appWidgetManager.requestPinAppWidget(provider, null, null)
                            // Returns true if request was initiated (user may still decline)
                            result.success(requested)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
