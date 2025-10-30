package com.example.webdipo
import android.content.res.Resources    
import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.util.Rational
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val ACCESSIBILITY_CHANNEL = "webdipo/accessibility"
    private val WIFI_CHANNEL = "webdipo/wifi"
    private val OVERLAY_CHANNEL = "webdipo/overlay"
    private val WINDOW_MODE_CHANNEL = "com.example.webdipo/window_mode"
    private val MULTI_WINDOW_EVENT_CHANNEL = "com.example.webdipo/multi_window_event"
    private val PIP_EVENT_CHANNEL = "com.example.webdipo/pip_event"

    companion object {
        lateinit var accessibilityMethodChannel: MethodChannel
    }

    private lateinit var wifiMethodChannel: MethodChannel
    private lateinit var windowModeMethodChannel: MethodChannel
    private var multiWindowEventSink: EventChannel.EventSink? = null
    private var pipEventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var isLockTaskPending = false // Re-introduce flag
    private var _isLockTaskInitiated = false // Re-introduce flag

    private val CHANNEL_ID = "window_mode_channel"
    private val NOTIFICATION_ID = 1001

    private val wifiBroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                "com.example.webdipo.WIFI_SETTINGS_OPENED" -> {
                    accessibilityMethodChannel.invokeMethod("onWifiSettingsOpened", null)
                }
                "com.example.webdipo.WIFI_SETTINGS_CLOSED" -> {
                    accessibilityMethodChannel.invokeMethod("onWifiSettingsClosed", null)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        accessibilityMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACCESSIBILITY_CHANNEL)
        wifiMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_CHANNEL)
        val overlayMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
        windowModeMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WINDOW_MODE_CHANNEL)

        // EventChannel untuk multi-window mode
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MULTI_WINDOW_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    multiWindowEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    multiWindowEventSink = null
                }
            })

        // EventChannel untuk PiP mode
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    pipEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    pipEventSink = null
                }
            })

        // Method channel wifi
        wifiMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openWifiSettings" -> openWifiSettings(result)
                else -> result.notImplemented()
            }
        }

        // Method channel accessibility
        accessibilityMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openAccessibilitySettings" -> openAccessibilitySettings(result)
                else -> result.notImplemented()
            }
        }

        // Method channel overlay permission
        overlayMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasOverlayPermission" -> result.success(hasOverlayPermission())
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Method channel window mode
             windowModeMethodChannel.setMethodCallHandler { call, result ->
    when (call.method) {

        "isInMultiWindowMode" -> {
            val isMulti = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                isInMultiWindowMode
            } else false
            Log.d("MainActivity", "isInMultiWindowMode -> $isMulti")
            result.success(isMulti)
        }

        "isInFloatingWindow" -> {
            val isFloating = checkIfInFloatingWindowMode()
            Log.d("MainActivity", "isInFloatingWindow -> $isFloating")
            result.success(isFloating)
        }

        "enterPictureInPictureMode" -> {
            val entered = enterPiPMode()
            result.success(entered)
        }

                        "startLockTask" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                try {
                                    Log.d("MainActivity", "Attempting to start Lock Task Mode")
                                    isLockTaskPending = true
                            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                                                                val componentName = ComponentName(this@MainActivity, MyDeviceAdminReceiver::class.java)
                            
                                                                // --- Tambahkan log ini ---
                                                                val isDeviceOwner = dpm.isDeviceOwnerApp(packageName)
                                                                Log.d("MainActivity", "Is app Device Owner? $isDeviceOwner")
                                                                // --- Akhir log ---
                            
                                                                if (hasWindowFocus()) {
                                                                    startLockTask()
                                                                    Log.d("MainActivity", "Lock Task started immediately")
                                                                    // Callback ke Flutter
                                                                    windowModeMethodChannel.invokeMethod("onLockTaskStarted", true)
                                                                } else {
                                                                    Log.d("MainActivity", "Waiting for window focus to start Lock Task")
                                                                }        
                                    result.success(true)
                                } catch (e: Exception) {
                                    Log.e("MainActivity", "Failed to start Lock Task Mode", e)
                                    windowModeMethodChannel.invokeMethod("onLockTaskError", e.message)
                                    result.error("LOCKTASK_FAILED", e.message, null)
                                }
                            } else result.success(false)
                        }
        "stopLockTask" -> {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                try {
                    Log.d("MainActivity", "Stopping Lock Task Mode")
                    stopLockTask()
                    // Callback ke Flutter
                    windowModeMethodChannel.invokeMethod("onLockTaskStopped", true)
                    result.success(true)
                } catch (e: Exception) {
                    Log.e("MainActivity", "Failed to stop Lock Task Mode", e)
                    windowModeMethodChannel.invokeMethod("onLockTaskError", e.message)
                    result.error("LOCKTASK_FAILED", "Failed to stop Lock Task Mode: ${e.message}", null)
                }
            } else result.success(false)
        }

                        "openLockTaskSettings" -> {
                            try {
                                val componentName = ComponentName(this@MainActivity, MyDeviceAdminReceiver::class.java)
                                val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                                    putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, componentName)
                                    putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                        "Aktifkan agar aplikasi dapat menggunakan Lock Task Mode.")
                                }
                                startActivity(intent)
                                result.success(null)
                            } catch (e: Exception) {
                                Log.e("MainActivity", "Failed to open Lock Task settings", e)
                                windowModeMethodChannel.invokeMethod("onLockTaskError", e.message)
                                result.error("ERROR", "Gagal membuka pengaturan Lock Task: ${e.message}", null)
                            }
                        }
        
                                        "checkLockTask" -> {
                                            val isLocked = isLockTaskActive()
                                            Log.d("MainActivity", "checkLockTask -> $isLocked")
                                            result.success(isLocked)
                                        }
                        
                                        "isDeviceAdminActive" -> {
                                            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                                            val componentName = ComponentName(this@MainActivity, MyDeviceAdminReceiver::class.java)
                                            val isActive = dpm.isAdminActive(componentName)
                                            Log.d("MainActivity", "isDeviceAdminActive -> $isActive")
                                            result.success(isActive)
                                        }        else -> result.notImplemented()
    }
}


        MyAccessibilityService.methodChannel = accessibilityMethodChannel

        // Daftarkan receiver untuk WiFi settings
        val filter = IntentFilter().apply {
            addAction("com.example.webdipo.WIFI_SETTINGS_OPENED")
            addAction("com.example.webdipo.WIFI_SETTINGS_CLOSED")
        }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    registerReceiver(
        wifiBroadcastReceiver,
        filter,
        Context.RECEIVER_NOT_EXPORTED
    )
} else {
    registerReceiver(wifiBroadcastReceiver, filter)
}

    }

  private fun isInFloatingWindowMode(): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        if (isInMultiWindowMode) {
            Log.d("FloatingCheck", "Mode multi-window terdeteksi (floating window).")
            return true
        }
    }

    val screenHeight = Resources.getSystem().displayMetrics.heightPixels
    val windowHeight = window.decorView.height

    val isFloating = windowHeight < (screenHeight * 0.9)

    Log.d("FloatingCheck", "screenHeight: $screenHeight")
    Log.d("FloatingCheck", "windowHeight: $windowHeight")
    Log.d("FloatingCheck", "Apakah floating: $isFloating")

    return isFloating
}
    @RequiresApi(Build.VERSION_CODES.N)
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        Log.d("MainActivity", "onPictureInPictureModeChanged: isInPiP=$isInPictureInPictureMode")

        pipEventSink?.let { sink ->
            mainHandler.post {
                sink.success(isInPictureInPictureMode)
            }
        }

        if (isInPictureInPictureMode) {
            showWindowModeNotification("Picture-in-Picture mode aktif")
        } else {
            cancelWindowModeNotification()
        }
    }
    private fun checkIfInFloatingWindowMode(): Boolean {
        val metrics = Resources.getSystem().displayMetrics
        val screenHeight = metrics.heightPixels
        val screenWidth = metrics.widthPixels

        val windowHeight = window.decorView.height
        val windowWidth = window.decorView.width

        val isFloating = windowHeight < screenHeight || windowWidth < screenWidth

       if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
    if (isInMultiWindowMode) {
        Log.d("MainActivity", "Detected multi-window mode.")
        return true
    }
}


    Log.d("MainActivity", "Floating check -> screen: ${screenWidth}x$screenHeight, window: ${windowWidth}x$windowHeight, isFloating: $isFloating")

    return isFloating
}


    private fun showWindowModeNotification(contentText: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Window Mode Notifications",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Mode Window Aktif")
            .setContentText(contentText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun cancelWindowModeNotification() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)
    }

    private fun openWifiSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
            startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            result.error("UNAVAILABLE", "Cannot open WiFi settings: ${e.message}", null)
        }
    }

    private fun openAccessibilitySettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            result.error("UNAVAILABLE", "Cannot open Accessibility settings: ${e.message}", null)
        }
    }

    private fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        }
    }

    private fun enterPiPMode(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Log.d("MainActivity", "🧪 [Native] Trying to enter PiP mode")
            Log.d("MainActivity", "Has window focus? ${hasWindowFocus()}")
            Log.d("MainActivity", "Is in lock task mode? ${isInLockTaskMode()}")

            if (!hasWindowFocus()) {
                Log.w("MainActivity", "❌ Tidak bisa masuk PiP: Tidak punya fokus")
                return false
            }

            if (isInLockTaskMode()) {
                Log.w("MainActivity", "❌ Tidak bisa masuk PiP: Lock Task aktif, stopLockTask dipanggil")
                stopLockTask()
                // Berikan delay kecil untuk pastikan stopLockTask selesai
                mainHandler.postDelayed({
                    val aspectRatio = Rational(16, 9)
                    val params = PictureInPictureParams.Builder()
                        .setAspectRatio(aspectRatio)
                        .build()
                    val entered = enterPictureInPictureMode(params)
                    Log.d("MainActivity", "✅ enterPictureInPictureMode() after stopLockTask: $entered")
                }, 1000) // delay 1 detik
                return true // sementara return true, tapi PiP sebenarnya belum pasti aktif
            }

            val aspectRatio = Rational(16, 9)
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(aspectRatio)
                .build()

            val entered = enterPictureInPictureMode(params)
            Log.d("MainActivity", "✅ enterPictureInPictureMode() returned: $entered")
            return entered
        }

        Log.w("MainActivity", "❌ PiP tidak didukung di SDK ini")
        return false
    }

    private fun isInLockTaskMode(): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            false
        }
    }

    private fun isLockTaskActive(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            return activityManager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        }
        return false
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(wifiBroadcastReceiver)
    }


private var isLockTaskInitiated = false

override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    Log.d("MainActivity", "onCreate: isLockTaskInitiated = $isLockTaskInitiated")
}

        override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        Log.d("MainActivity", "onWindowFocusChanged: hasFocus=$hasFocus, isLockTaskPending=$isLockTaskPending, _isLockTaskInitiated=$_isLockTaskInitiated")

        if (!hasFocus) return

        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val currentLockTaskMode = activityManager.lockTaskModeState

            if (isLockTaskPending) {
                // Sedang menunggu lock task mode
                if (currentLockTaskMode == ActivityManager.LOCK_TASK_MODE_LOCKED) {
                    Log.d("MainActivity", "Lock Task Mode successfully entered")
                    isLockTaskPending = false
                    windowModeMethodChannel.invokeMethod("onLockTaskActivated", null)
                } else if (currentLockTaskMode == ActivityManager.LOCK_TASK_MODE_NONE) {
                    Log.d("MainActivity", "Lock Task Mode failed (user declined)")
                    isLockTaskPending = false
                    windowModeMethodChannel.invokeMethod("onLockTaskEnded", "User declined Lock Task Mode")
                }
            } else {
                // Deteksi jika Lock Task berakhir tiba-tiba
                if (_isLockTaskInitiated && currentLockTaskMode == ActivityManager.LOCK_TASK_MODE_NONE) {
                    Log.d("MainActivity", "Lock Task Mode OFF unexpectedly")
                    windowModeMethodChannel.invokeMethod("onLockTaskEnded", "Lock Task Mode exited unexpectedly")
                }
            }
        }
    }
}
