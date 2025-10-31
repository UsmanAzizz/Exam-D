// ignore_for_file: avoid_print, use_build_context_synchronously, empty_catches

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdipo/Accessibility.dart';
import 'package:webdipo/main.dart';
import 'package:webview_flutter/webview_flutter.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class RunTest extends StatefulWidget {
  final String ipAddress;
  final bool fromWifiSettings;
  const RunTest({
    super.key,
    required this.ipAddress,
    this.fromWifiSettings = false, // default false
  });

  @override
  State<RunTest> createState() => _RunTestState();
  
}

bool _wifiGracePeriod = false;
String? _pageTitle;
bool _isLoadingTitle = true;

class WindowModeHelper {
  static const MethodChannel _channel =
      MethodChannel('com.example.webdipo/window_mode');

  static Future<bool> isInMultiWindowMode() async {
    try {
      final bool result = await _channel.invokeMethod('isInMultiWindowMode');
      return result;
    } catch (e) {
      print('Error calling isInMultiWindowMode: $e');
      return false;
    }
  }

  static Future<bool> isInPiPMode() async {
    try {
      final bool result = await _channel.invokeMethod('isInPiPMode');
      return result;
    } catch (e) {
      print('Error calling isInPiPMode: $e');
      return false;
    }
  }

  static Future<bool> enterPictureInPictureMode() async {
    try {
      final bool result =
          await _channel.invokeMethod('enterPictureInPictureMode');
      return result;
    } catch (e) {
      print('Error calling enterPictureInPictureMode: $e');
      return false;
    }
  }
}

const MethodChannel _windowModeChannel =
    MethodChannel('com.example.webdipo/window_mode');
const String kTestStartTimeKey = 'test_start_time_epoch';
const String kTestDurationKey = 'test_time';

class _RunTestState extends State<RunTest> with WidgetsBindingObserver {
  late final WebViewController _controller;
  Timer? _penaltyTimer;
  int _secondsLeft = 0;
  bool _isInBackground = false;
  bool _isDisqualified = false;

  bool _isInWifiSettings = false;

  final TextEditingController _ipController = TextEditingController();
  final FocusNode _ipFocusNode = FocusNode();
  static const EventChannel _multiWindowEventChannel =
      EventChannel('com.example.webdipo/multi_window_event');
  static const EventChannel pipEventChannel =
      EventChannel('com.example.webdipo/pip_event');

  Stream<bool> get pipModeStream =>
      pipEventChannel.receiveBroadcastStream().map((event) => event as bool);
double _opacity = 0.0;

  @override
  void initState() {
    _saveTestStartTime();
    SharedPreferences.getInstance().then((prefs) {
      print('[INIT] test_time: ${prefs.getInt('test_time')}');
    });
    super.initState();
   
  Future.delayed(const Duration(milliseconds: 50), () {
    if (mounted) {
      setState(() {
        _opacity = 1.0;
      });
    }
  });


    _saveTestStartTime();
    _setupLockTaskHandler();
    WidgetsBinding.instance.addObserver(this);
    _setupWebView();
    _checkInitialWindowMode();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.fromWifiSettings) {
        print('[INFO] Kembali dari WiFi settings — tidak startLockTask lagi');
        return;
      }

      bool isFloating = await WindowMode.isInFloatingWindow();
      print('[Flutter] Cek awal: Apakah dalam Floating Window? => $isFloating');

      if (isFloating) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Penggunaan mode layar saat ini tidak diizinkan!'),
              duration: Duration(seconds: 3),
            ),
          );
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        }
        return;
      }
    });

    _ipFocusNode.addListener(() async {
      if (!_ipFocusNode.hasFocus) {
        if (mounted) {
          final title = await _controller.getTitle();
          setState(() {
            _isEditing = false;
            _ipController.text = title ?? '';
          });
        }
        _ipController.text = widget.ipAddress;
      }
    });

    _initializeNotifications();

    _multiWindowEventChannel.receiveBroadcastStream().listen((event) {
      if (event is bool) {
        if (event) {
          _handleFloatingModeDetected();
        } else {
          setState(() {
            _isDisqualified = false;
          });
        }
      }
    });

    // di State class

// di initState() atau di bagian setup WifiMonitor
    WifiMonitor.startMonitoring(
      onWifiSettingsOpened: () {
        setState(() {
          _isInWifiSettings = true;
          _wifiGracePeriod = true;
        });
        print('WiFi settings dibuka → grace period aktif');

        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            print('Grace period WiFi selesai');
            setState(() {
              _wifiGracePeriod = false;
            });
          }
        });
      },
      onWifiSettingsClosed: () {
        setState(() {
          _isInWifiSettings = false;
        });
        print('WiFi settings ditutup');

        if (!mounted) return;

        print('Navigasi ke RunTest');

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => RunTest(
              ipAddress: widget.ipAddress,
              fromWifiSettings: true, // ✅ Set true di sini
            ),
          ),
        );
      },
      onAppBackgrounded: () {
        print('App backgrounded (from native)');
        _isInBackground = true;
        // Jika tidak di grace period dan WiFi settings tidak aktif, mulai penalti
        if (!_wifiGracePeriod && !_isInWifiSettings) {
          _startPenaltyTimer();
        }
      },
      onAppResumed: () {
        print('App resumed (from native)');
        _isInBackground = false;
        // Bisa reset timer atau logika lain kalau perlu
      },
    );

    _ipController.text = widget.ipAddress;
  }



  void _setupLockTaskHandler() {
    _windowModeChannel.setMethodCallHandler((call) async {
      print('[Flutter] method call: ${call.method}');
      if (call.method == 'onLockTaskEnded') {
        print('[Flutter] ❌ Lock Task Mode dinonaktifkan!');
        // Reset _isPinningInProgress here if it's true, as pinning has failed
        if (mounted) {
          setState(() {
            print('[Flutter] _isPinningInProgress reset to false because lock task ended');
          });
        }
        print('[Flutter] _alreadyNavigated: $_alreadyNavigated');
        final isUserLoggedIn = await checkUserLoginStatus();
        print('[Flutter] isUserLoggedIn: $isUserLoggedIn');

        if (!_alreadyNavigated && !isUserLoggedIn) {
          print('[Flutter] Navigating to /login due to onLockTaskEnded and user not logged in.');
          setState(() {
            _alreadyNavigated = true;
          });
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        } else if (_alreadyNavigated) {
          print('[Flutter] Already navigated, skipping further navigation.');
        } else if (isUserLoggedIn) {
          print('[Flutter] User is logged in, skipping navigation to /login.');
        }
      }
    });
  }

  Future<bool> checkUserLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    // Misalnya kamu simpan 'isLoggedIn' boolean saat login berhasil
    return prefs.getBool('isLoggedIn') ?? false;
  }

  Future<void> _checkInitialWindowMode() async {
    print('🔥 Flutter: calling isInMultiWindowMode...');
    bool isFloatingWindow = await WindowModeHelper.isInMultiWindowMode();
    print('🔥 Flutter: isInMultiWindowMode returned $isFloatingWindow'); // <-- Tambahkan log ini

    if (isFloatingWindow && mounted) {
      print('❗ Detected multi-window mode saat halaman dimuat. Memicu penalti.'); // <-- Tambahkan log ini
      await _handleMultiWindowDetected(); // Peringatan + kembali ke MyApp
    } else {
      print('✅ Multi-window mode TIDAK terdeteksi saat halaman dimuat.'); // <-- Tambahkan log ini
    }
  }

  Future<void> _handleMultiWindowDetected({bool isPiP = false}) async {
    if (_alreadyNavigated) return;
    _alreadyNavigated = true;

    if (!mounted) return;

    String title = isPiP
        ? 'Peringatan Picture-in-Picture (PiP)'
        : 'Peringatan Multi-Window';
    String content = isPiP
        ? 'Penggunaan mode Picture-in-Picture (PiP) tidak diizinkan. Anda akan kembali ke halaman utama.'
        : 'Penggunaan multi-window mode tidak diizinkan. Anda akan kembali ke halaman utama.';

    bool? userAcknowledged = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    if (userAcknowledged == true) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  bool _isEditing = false;
  Future<void> _setupWebView() async {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) async {
            if (!_isEditing && mounted) {
              final title = await _controller.getTitle();
              setState(() {
                _ipController.text = title ?? '';
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('http://${widget.ipAddress}'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _penaltyTimer?.cancel();
    _ipController.dispose();
    _ipFocusNode.dispose();
    _ipFocusNode.removeListener(() {});
    super.dispose();
  }

  void _handleFloatingModeDetected() {
    if (!_alreadyNavigated && mounted) {
      _alreadyNavigated = true;
      setState(() {
        _isDisqualified = true;
      });
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    try {
      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {},
      );
    } catch (e) {}

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'channel_id',
      'Channel Notifikasi',
      description: 'Channel untuk peringatan aplikasi',
      importance: Importance.high,
    );

    try {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    } catch (e) {}
  }

  bool _penaltyStarted = false;
  bool _alreadyNavigated = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    print(
        '[Lifecycle] state changed: $state, wifiSettings: $_isInWifiSettings, grace: $_wifiGracePeriod');

    if (state == AppLifecycleState.resumed && _isInWifiSettings) {
      setState(() {
        _isInWifiSettings = false;
      });

      if (!_alreadyNavigated) {
        _alreadyNavigated = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => RunTest(
              ipAddress: widget.ipAddress,
              fromWifiSettings: true, // ✅ ini yang wajib
            ),
          ),
        );
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const penaltyDuration = 5;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // --- Tambahkan pengecekan Lock Task di sini ---
      final bool isLockTaskActive = await LockTaskHelper.checkLockTask();
      if (isLockTaskActive) {
        print('[Lifecycle] Lock Task Mode aktif, abaikan penalti saat layar mati/aplikasi di background.');
        return; // Abaikan penalti
      }
      // --- Akhir pengecekan Lock Task ---

      _isInBackground = true;

      // Jika di WiFi settings atau dalam grace period, abaikan penalti
      if (_isInWifiSettings || _wifiGracePeriod) {
        print('[Lifecycle] Abaikan penalti karena WiFi/grace period');
        return;
      }

      if (!_penaltyStarted) {
        _penaltyStarted = true;
        _isDisqualified = false;
        await prefs.setInt('last_background_time', now);

        _showNotification(
          'Terdeteksi Pelanggaran',
          'Memeriksa..',
        );

        _startPenaltyTimer();
      }
    } else if (state == AppLifecycleState.resumed) {
      _isInBackground = false;
      _penaltyTimer?.cancel();
      _penaltyStarted = false;

      setState(() {
        _secondsLeft = 0;
      });

      final lastBackground = prefs.getInt('last_background_time');
      if (lastBackground != null) {
        final diff = now - lastBackground;

        await prefs.remove('last_background_time');

        if (diff >= penaltyDuration) {
          if (!_alreadyNavigated && mounted) {
            _alreadyNavigated = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.pushNamedAndRemoveUntil(
                    context, '/login', (route) => false);
              }
            });
          }
          return;
        }
      }

      bool isFloatingWindow = await WindowModeHelper.isInMultiWindowMode();
      if (isFloatingWindow) {
        print('Floating window detected → langsung diskualifikasi');
        _penaltyTimer?.cancel();
        _penaltyStarted = true;
        _isDisqualified = true;

        if (!_alreadyNavigated && mounted) {
          _alreadyNavigated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(
                  context, '/login', (route) => false);
            }
          });
        }
        return;
      }

      if (_isInWifiSettings || _wifiGracePeriod) {
        print(
            '[Lifecycle] Resumed dari WiFi or grace period — OK, tidak logout');
        // reset flags
        _isInWifiSettings = false;
        _wifiGracePeriod = false;
      } else if (_isDisqualified && !_alreadyNavigated && mounted) {
        _alreadyNavigated = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacementNamed(context, '/login');
        });
      }
    }
  }

  void _startPenaltyTimer() {
    _penaltyTimer?.cancel();
    setState(() {
      _secondsLeft = 0;
    });

    _penaltyTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_secondsLeft == 0) {
        timer.cancel();

        if (_isInBackground) {
          _isDisqualified = true;

          final prefs = await SharedPreferences.getInstance();
          final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          await prefs.setInt('penalty_start_timestamp', now);

          await _showNotification(
            'Anda telah terdiskualifikasi',
            'Mohon untuk mematuhi aturan lain waktu.',
          );

          if (!mounted) return;
          Navigator.pushNamedAndRemoveUntil(
              context, '/login', (route) => false);
        }
      } else {
        setState(() {
          _secondsLeft--;
        });
      }
    });
  }

  Future<void> _showNotification(String title, String body) async {
    try {
      await flutterLocalNotificationsPlugin.show(
        0,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'channel_id',
            'Channel Notifikasi',
            channelDescription: 'Channel untuk peringatan aplikasi',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {}
  }
Future<void> checkPinVerified() async {
    final prefs = await SharedPreferences.getInstance();
    final pinVerified = prefs.getBool('pin_verified') ?? false;

    print('[checkPinVerified] Pin verified: $pinVerified');

    if (!pinVerified) {
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }
  Future<void> _confirmExit() async {
    bool canExit = false;
    Timer? timer;

    final prefs = await SharedPreferences.getInstance();

    // Print semua key dan value di SharedPreferences untuk debug
    print('SharedPreferences contents:');
    prefs.getKeys().forEach((key) {
      final value = prefs.get(key);
      print('  $key: $value');
    });

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final startTime = prefs.getInt(kTestStartTimeKey) ?? now;

    // ✅ Ambil test_time dari SharedPreferences secara dinamis
    final testDuration = await getSavedTestTime();

    print('now: $now');
    print('startTime: $startTime');
    print('testDuration (from prefs): $testDuration');

    int countdown = testDuration - (now - startTime);
    print('initial countdown: $countdown');

    if (countdown <= 0) {
      canExit = true;
      countdown = 0;
    }

    // Asumsi timer, countdown, dan canExit sudah dideklarasikan di parent widget/state
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            if (!canExit && (timer == null || !timer!.isActive)) {
              timer = Timer.periodic(const Duration(seconds: 1), (t) {
                if (!mounted) {
                  t.cancel();
                  return;
                }
                if (countdown > 1) {
                  setState(() {
                    countdown--;
                  });
                  print('countdown tick: $countdown');
                } else {
                  t.cancel();
                  setState(() {
                    canExit = true;
                  });
                  print('Countdown finished, canExit set to true');
                }
              });
            }

            final minutes = countdown ~/ 60;
            final seconds = countdown % 60;
            final countdownText =
                'Tunggu ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} sebelum keluar.';

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.exit_to_app_rounded,
                        color: Colors.redAccent,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      canExit ? 'Yakin ingin keluar?' : 'Waktu tersisa:',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[900],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      canExit
                          ? 'Semua progres ujian akan disimpan.'
                          : countdownText,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              timer?.cancel();
                              Navigator.of(context).pop(false);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey[700],
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Batal'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed: canExit
                                ? () async {
                                    timer?.cancel();
                                    final prefs = await SharedPreferences.getInstance();
                                    final existingTestTime = prefs.getInt('test_time');
                                    if (existingTestTime != null) {
                                      await prefs.setInt('test_time', existingTestTime);
                                      print('♻️ test_time disimpan ulang: $existingTestTime');
                                    } else {
                                      print('⚠️ test_time tidak ditemukan saat ingin disimpan ulang');
                                    }
                                    Navigator.of(context).pop(true);
                                    await checkPinVerified();
                                  }
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(canExit ? 'Keluar' : 'Tunggu..'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (shouldExit == true) {
      print('User confirmed exit, clearing only test start time');

      // HAPUS INI: await prefs.remove(kTestDurationKey); ❌

      await prefs.remove(kTestStartTimeKey); // ini boleh kalau memang harus

      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<int> getSavedTestTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('test_time') ?? 10; // default 600 detik (10 menit)
  }

    @override
    Widget build(BuildContext context) {
      return WillPopScope(
        onWillPop: () async {
          // Cek apakah WebView bisa kembali ke halaman sebelumnya
          final canGoBack = await _controller.canGoBack();
          if (canGoBack) {
            _controller.goBack();
            return false; // Jangan keluar dari halaman
          }

          return false;
        },
        child: Scaffold(
          appBar: AppBar(
  automaticallyImplyLeading: false,
elevation: 0,
  backgroundColor: Colors.white,
  title: Row(
    children: [
      Expanded(
        child: Text(
          _pageTitle ?? "Status : Running",
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      // Tombol reload
      IconButton(
        onPressed: () async {
          try {
            final currentUrl = await _controller.currentUrl();
            if (!mounted) return;
            if (currentUrl != null) {
              // Update title jika perlu
            }
            await _controller.reload();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal memuat ulang: $e')),
            );
          }
        },
        icon: const Icon(Icons.refresh, color: Colors.blueAccent),
        tooltip: 'Muat ulang',
      ),
      // Menu lebih modern
      PopupMenuButton<int>(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        icon: const Icon(Icons.more_vert, color: Colors.black87),
        onSelected: (value) async {
          if (value == 1) {
            setState(() {
              _isInWifiSettings = true;
            });
            await WifiSettings.openWifiSettings();
          } else if (value == 2) {
            _confirmExit();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 1,
            child: Row(
              children: const [
                Icon(Icons.wifi, color: Colors.blue),
                SizedBox(width: 12),
                Text('Pengaturan WiFi', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 2,
            child: Row(
              children: const [
                Icon(Icons.exit_to_app, color: Colors.redAccent),
                SizedBox(width: 12),
                Text('Selesai Tes', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    ],
  ),

          ),
        body: SafeArea(
  child: AnimatedOpacity(
    duration: const Duration(milliseconds: 500),
    curve: Curves.easeInOut,
    opacity: _opacity,
    child: WebViewWidget(controller: _controller),
  ),
),

        ),
      );
    }
  }

class WifiSettings {
  static const MethodChannel _channel = MethodChannel('webdipo/wifi');

  static Future<void> openWifiSettings() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('openWifiSettings');
      } on PlatformException catch (e) {
        print('Error membuka WiFi settings: ${e.message}');
      }
    } else {
      print('Fitur ini hanya tersedia di Android');
    }
  }
}

class LockTaskHelper {
  static const MethodChannel _channel =
      MethodChannel('com.example.webdipo/window_mode');

  static Future<bool> startLockTask() async {
    try {
      final bool result = await _channel.invokeMethod('startLockTask');
      return result;
    } catch (e) {
      print('Error starting lock task: $e');
      return false;
    }
  }

  static Future<bool> stopLockTask() async {
    try {
      final bool result = await _channel.invokeMethod('stopLockTask');
      return result;
    } catch (e) {
      print('Error stopping lock task: $e');
      return false;
    }
  }

  static Future<bool> checkLockTask() async {
    try {
      final bool result = await _channel.invokeMethod('checkLockTask');
      return result;
    } catch (e) {
      print('Error checking lock task: $e');
      return false;
    }
  }

  static Future<bool> isDeviceAdminActive() async {
    try {
      final bool result = await _channel.invokeMethod('isDeviceAdminActive');
      return result;
    } on PlatformException catch (e) {
      print('Error checking device admin status: ${e.message}');
      return false;
    }
  }
}

class WindowMode {
  static const MethodChannel _channel =
      MethodChannel('com.example.webdipo/window_mode');

  static Future<bool> isInFloatingWindow() async {
    try {
      print('[WindowMode] Memanggil native method isInFloatingWindow...');
      final bool result = await _channel.invokeMethod('isInFloatingWindow');
      print('[WindowMode] Native method isInFloatingWindow returned: $result');
      return result;
    } catch (e) {
      print('[WindowMode] Error checking floating window mode: $e');
      return false;
    }
  }
}

Future<void> _saveTestStartTime() async {
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  if (!prefs.containsKey(kTestStartTimeKey)) {
    await prefs.setInt(kTestStartTimeKey, now);
    print('[RunTest] Test start time saved: $now');
  }
}
