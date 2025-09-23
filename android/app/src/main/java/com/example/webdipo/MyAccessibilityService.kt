package com.example.webdipo
import com.example.webdipo.MyAccessibilityService
import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MyAccessibilityService : AccessibilityService() {

    companion object {
        // Akan diisi dari MainActivity agar bisa kirim event ke Flutter
        lateinit var methodChannel: MethodChannel
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val eventType = event.eventType
        val packageName = event.packageName?.toString() ?: "unknown"
        val className = event.className?.toString() ?: "unknown"
        val text = event.text?.joinToString(", ") ?: ""

        Log.d("MyAccessibilityService", "Event received: type=$eventType, package=$packageName, class=$className, text=$text")

        try {
            val eventData = mapOf(
                "eventType" to eventType,
                "packageName" to packageName,
                "className" to className,
                "text" to text
            )
            methodChannel.invokeMethod("onAccessibilityEvent", eventData)
        } catch (e: Exception) {
            Log.e("MyAccessibilityService", "Failed to send accessibility event: ${e.message}")
        }
    }

    override fun onInterrupt() {
        Log.d("MyAccessibilityService", "Accessibility service interrupted")
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("MyAccessibilityService", "Accessibility service connected")
    }
}
