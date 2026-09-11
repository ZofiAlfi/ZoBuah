package com.fruitpos.fruit_pos

import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL_NAME = "com.fruitpos/locktask"
    private val TAG = "FruitPosKiosk"
    private var locked = false
    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val dpm = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(this, FruitPosAdminReceiver::class.java)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startLockTask" -> {
                    Log.i(TAG, "startLockTask requested")
                    try {
                        if (dpm.isDeviceOwnerApp(packageName)) {
                            Log.i(TAG, "device owner; setLockTaskFeatures NONE")
                            dpm.setLockTaskPackages(admin, arrayOf(packageName))
                            dpm.setLockTaskFeatures(
                                admin,
                                DevicePolicyManager.LOCK_TASK_FEATURE_NONE
                            )
                        }
                        startLockTask()
                        locked = true
                        Log.i(TAG, "startLockTask ok")
                        val main = android.os.Handler(android.os.Looper.getMainLooper())
                        val attempt = object : Runnable {
                            var remaining = 3
                            override fun run() {
                                if (remaining-- > 0 && locked && !isFinishing) {
                                    try {
                                        startLockTask()
                                    } catch (_: Exception) {
                                    }
                                    main.postDelayed(this, 400)
                                }
                            }
                        }
                        main.postDelayed(attempt, 400)
                        result.success(true)
                    } catch (e: Exception) {
                        locked = false
                        Log.e(TAG, "startLockTask failed", e)
                        result.success(false)
                    }
                }
                "stopLockTask" -> {
                    try {
                        locked = false
                        stopLockTask()
                    } catch (_: Exception) {
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        if (locked) {
            try {
                startLockTask()
            } catch (_: Exception) {
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && locked) {
            try {
                startLockTask()
            } catch (_: Exception) {
            }
        }
    }

    override fun onUserLeaveHint() {
        Log.i(TAG, "onUserLeaveHint locked=$locked")
        if (locked) {
            try {
                channel.invokeMethod("leaveAttempted", null)
            } catch (_: Exception) {
            }
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                try {
                    val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
                    val ok = am.moveTaskToFront(taskId, 0)
                    Log.i(TAG, "moveTaskToFront ok=$ok")
                } catch (e: Exception) {
                    Log.e(TAG, "moveTaskToFront failed", e)
                }
            }, 150)
        }
        super.onUserLeaveHint()
    }
}