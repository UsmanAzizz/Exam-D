import 'package:flutter/services.dart';

class WifiMonitor {
  static const MethodChannel _channel = MethodChannel('webdipo/accessibility');

  static void startMonitoring({
    required VoidCallback onWifiSettingsOpened,
    required VoidCallback onWifiSettingsClosed,
    required VoidCallback onAppResumed,
    required VoidCallback onAppBackgrounded,
    VoidCallback? onDisqualified,
    Function(Map<String, dynamic>)? onAccessibilityEvent,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onWifiSettingsOpened':
          onWifiSettingsOpened();
          break;
        case 'onWifiSettingsClosed':
          onWifiSettingsClosed();
          break;
        case 'onAppResumed':
          onAppResumed();
          break;
        case 'onAppBackgrounded':
          onAppBackgrounded();
          break;
        case 'onDisqualified':
          if (onDisqualified != null) onDisqualified();
          break;
        case 'onAccessibilityEvent':
          if (onAccessibilityEvent != null) {
            final args = call.arguments;
            if (args is Map) {
              onAccessibilityEvent(Map<String, dynamic>.from(args));
            }
          }
          break;
        default:
          print('Unknown method: ${call.method}');
      }
    });
  }
}

const MethodChannel _channel =
    MethodChannel('com.example.webdipo/accessibility');

void setupAccessibilityListener() {
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'onAccessibilityEvent') {
      final Map<dynamic, dynamic> eventData = call.arguments;
      print('Received accessibility event: $eventData');
    }
  });
}
