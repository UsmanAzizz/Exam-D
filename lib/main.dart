import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdipo/localserver.dart';
import 'run_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'remote.dart'; // Import halaman baru
import 'fetch_config.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'dart:io'; // untuk SocketException

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
    ),
  );

  runApp(const MyApp());
}

 const MethodChannel _windowModeChannel =
    MethodChannel('com.example.webdipo/window_mode');

const correctPin = '532563'; // PIN yang harus dimasukkan
final GlobalKey _fieldKey = GlobalKey();
final GlobalKey _buttonKey = GlobalKey();
String _formatDuration(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  final secondsStr = seconds.toString().padLeft(2, '0'); // agar selalu 2 digit
  return '$minutes menit $secondsStr detik';
}

bool _showFab = true;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Login CBT',
      debugShowCheckedModeBanner: false,
      home: const SplashDecider(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/runTest': (context) => const RunTest(ipAddress: '192.168.0.1'),
        '/remoteaccess': (context) => const RemoteAccess(),
        '/localserver': (context) => const LocalServerPage(),
        '/config': (context) => const ConfigPage(), // Tambahkan ini
      },
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
      ),
    );
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Halaman pembuka untuk cek status PIN verified
class SplashDecider extends StatefulWidget {
  const SplashDecider({super.key});

  @override
  State<SplashDecider> createState() => _SplashDeciderState();
}

class _SplashDeciderState extends State<SplashDecider> {
  Timer? _deviceAdminCheckTimer;

  @override
  void initState() {
    super.initState();
    _checkPinVerified();
    _fetchLocalData();
    _fetchPenaltyDurationFromFirestore();
     _fetchTestTimeAndSave();
  }

  Future<void> _checkPinVerified() async {
    final prefs = await SharedPreferences.getInstance();
       final pinVerified = prefs.getBool('pin_verified') ?? false;
   print('DEBUG: pin_verified = $pinVerified');
   
       // --- Tambahkan pengecekan Device Admin di sini ---
       final bool isDeviceAdmin = await LockTaskHelper.isDeviceAdminActive();
       print('DEBUG: isDeviceAdminActive = $isDeviceAdmin'); // <-- Tambahkan log ini
   
       if (!isDeviceAdmin) {
      print('DEBUG: Device Admin belum aktif. Membuka pengaturan...');
      await _windowModeChannel.invokeMethod('openLockTaskSettings');
      _startDeviceAdminMonitoring(); // <-- Pindahkan pemanggilan ke sini
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            print('DEBUG: Menampilkan dialog peringatan Device Admin.');
            return AlertDialog(
              title: const Text('Peringatan'),
              content: const Text('Untuk mengaktifkan mode ujian aman, aplikasi memerlukan izin Device Admin. Mohon aktifkan izin tersebut.'),
              actions: <Widget>[
                TextButton(
                  child: const Text('OK'),
                  onPressed: () {
                    Navigator.of(context).pop(); // Tutup dialog
                    // Pemantauan sudah dimulai di luar dialog
                  },
                ),
              ],
            );
          },
        );
      }
      print('DEBUG: _checkPinVerified() berhenti karena Device Admin belum aktif.');
      return;
       }
   
                      print('DEBUG: Device Admin sudah aktif. Melanjutkan ke login.'); // <-- Tambahkan log ini
           
                      // Setelah Device Admin aktif, navigasi ke LoginPage
                      if (mounted) {
                        Navigator.pushReplacementNamed(context, '/login');
                      }
  }

  Future<void> _fetchLocalData() async {
  try {
    // Cek koneksi internet langsung di sini
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult != ConnectivityResult.mobile &&
        connectivityResult != ConnectivityResult.wifi) {
      throw Exception('Tidak ada koneksi internet');
    }

    await Firebase.initializeApp();

    final prefs = await SharedPreferences.getInstance();

    final localDoc = await FirebaseFirestore.instance
        .collection('remote')
        .doc('local')
        .get();

    // Fetch online_test_link from remote/remote_access
    final remoteAccessDoc = await FirebaseFirestore.instance
        .collection('remote')
        .doc('remote_access')
        .get();

    if (remoteAccessDoc.exists) {
      final remoteAccessData = remoteAccessDoc.data();
      if (remoteAccessData != null && remoteAccessData.containsKey('link')) {
        final onlineTestLink = remoteAccessData['link'].toString();
        await prefs.setString('online_test_link', onlineTestLink);
        print('✅ online_test_link dari remote/remote_access disimpan: $onlineTestLink');
      } else {
        print('⚠️ Link ujian online tidak ditemukan di remote/remote_access');
      }
    } else {
      print('⚠️ Dokumen remote/remote_access tidak ditemukan');
    }

    if (localDoc.metadata.isFromCache) {
      throw Exception(
          'Data hanya dari cache, kemungkinan tidak ada koneksi internet');
    }

    if (localDoc.exists) {
      final localData = localDoc.data();
      if (localData != null) {
        print('📦 Data di remote/local:');
        localData.forEach((key, value) {
          print(' - $key : $value');
        });

        final localDataString = json.encode(localData);
        await prefs.setString('local_data', localDataString);
        print('✅ Data local dari remote/local disimpan ke SharedPreferences');

        if (localData.containsKey('local_setting')) {
          final localSetting = localData['local_setting'].toString();
          await prefs.setString('local_setting', localSetting);
          print('✅ local_setting dari local disimpan: $localSetting');
        }
      }
    } else {
      print('⚠️ Dokumen remote/local tidak ditemukan');
      throw Exception('Dokumen remote/local tidak ditemukan');
    }
  } catch (e) {
    print('❌ Gagal fetch data remote/local: $e');
    throw e; // Lempar error supaya bisa ditangkap di luar
  }
}

Future<void> _fetchPenaltyDurationFromFirestore() async {
  try {
    await Firebase.initializeApp();

    final docSnap = await FirebaseFirestore.instance
        .collection('remote')
        .doc('global')
        .get();

    if (docSnap.exists) {
      final data = docSnap.data();
      if (data != null && data.containsKey('int_penalty')) {
        final dynamic penaltyValue = data['int_penalty'];
        int penaltyInt;

        if (penaltyValue is int) {
          penaltyInt = penaltyValue;
        } else if (penaltyValue is String) {
          penaltyInt = int.tryParse(penaltyValue) ?? 1800; // default 1800 detik
        } else {
          penaltyInt = 1800;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('int_penalty', penaltyInt);
        print('✅ int_penalty disimpan ke SharedPreferences: $penaltyInt');
      } else {
        print('⚠️ int_penalty tidak ditemukan di dokumen remote/global');
      }
    } else {
      print('⚠️ Dokumen global di koleksi remote tidak ada');
    }
  } catch (e) {
    print('❌ Gagal fetch int_penalty dari Firestore: $e');
  }
}

Future<void> _fetchTestTimeAndSave() async {
  try {
    // Cek apakah Firebase sudah diinisialisasi
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
      print('Firebase berhasil diinisialisasi');
    }

    // Ambil dokumen 'global' dari koleksi 'remote'
    final docSnap = await FirebaseFirestore.instance
        .collection('remote')
        .doc('global')
        .get();

    if (docSnap.exists) {
      final data = docSnap.data();
      int testTimeInt = 0; // default kalau data tidak ada

      if (data != null && data.containsKey('test_time')) {
        final dynamic testTimeValue = data['test_time'];

        if (testTimeValue is int) {
          testTimeInt = testTimeValue;
        } else if (testTimeValue is String) {
          testTimeInt = int.tryParse(testTimeValue) ?? 0;
        } else {
          print('⚠️ Tipe data test_time tidak dikenali, gunakan default 0');
        }
      } else {
        print(
            '⚠️ test_time tidak ditemukan di dokumen remote/global, simpan default 0');
      }

      // Simpan nilai testTimeInt ke SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('test_time', testTimeInt);
      print('✅ test_time disimpan ke SharedPreferences: $testTimeInt');
    } else {
      print('⚠️ Dokumen global di koleksi remote tidak ada');
    }
  } catch (e) {
    print('❌ Gagal fetch test_time dari Firestore: $e');
  }
}

  void _startDeviceAdminMonitoring() {
    _deviceAdminCheckTimer?.cancel(); // Pastikan tidak ada timer yang berjalan
    _deviceAdminCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final bool isDeviceAdmin = await LockTaskHelper.isDeviceAdminActive();
      print('DEBUG: Memantau Device Admin - isDeviceAdminActive = $isDeviceAdmin');

      if (isDeviceAdmin) {
        timer.cancel(); // Hentikan timer
        _checkPinVerified(); // Panggil ulang untuk melanjutkan alur aplikasi
      }
    });
  }

  @override
  void dispose() {
    _deviceAdminCheckTimer?.cancel(); // Batalkan timer saat widget dibuang
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// Halaman Login dengan pengecekan masa penalty dan tombol minta hak akses
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

bool _isAccessButtonEnabled = false;
Timer? _accessButtonTimer;

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _ipController = TextEditingController();
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkPenaltyStatus();
    _loadSavedIp(); // Tambahkan ini
  }

  // Tambahkan method baru untuk memuat IP yang tersimpan
  Future<void> _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    final String? lastEnteredKey = prefs.getString('last_entered_key');

    if (lastEnteredKey != null && lastEnteredKey.isNotEmpty) {
      if (mounted) {
        setState(() {
          _ipController.text = lastEnteredKey;
        });
      }
    }
  }

  void showBottomMenu(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Bottom Menu',
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, animation1, animation2) {
        return Align(
          alignment: Alignment.bottomCenter,
          
          child: Material(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            color: Colors.white,
            child: Container(
              height: 320,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Garis kecil di atas
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),

                  _buildMenuItem(
                    icon: Icons.sync,
                    title: 'Sinkronkan Konfigurasi',
                    color: Colors.green.shade600,
                    onTap: () async {
                      if (Navigator.canPop(navigatorKey.currentContext!)) {
                        Navigator.pop(navigatorKey.currentContext!);
                        print('Drawer ditutup');
                      }

                      try {
                        print('Mulai sinkronisasi konfigurasi...');

                        bool adaPerubahan = false;

                        // Ambil data lama dari prefs
                        final prefs = await SharedPreferences.getInstance();
                        final dataLama = prefs.getString('local_data') ?? '';

                        // Misal _fetchLocalData simpan data terbaru ke variabel global atau langsung ke prefs
                        // Jadi kita perlu ambil data terbaru dari sumber lain,
                        // misal kamu punya variabel _latestLocalData di class kamu yang diupdate oleh _fetchLocalData
                        await _fetchLocalData();

                        // Ambil data terbaru dari prefs lagi atau variabel lokal yang kamu simpan di _fetchLocalData
                        final dataBaru = prefs.getString('local_data_temp') ??
                            ''; // Contoh simpan sementara di prefs atau variabel

                        if (dataBaru != dataLama) {
                          adaPerubahan = true;
                          await prefs.setString('local_data', dataBaru);
                        }

                        await _fetchPenaltyDurationFromFirestore();
                        print(
                            'Durasi penalti berhasil diambil dari Firestore.');

                        await _fetchTestTimeAndSave();
                        print('Waktu tes berhasil diambil dan disimpan.');

                        print('Status perubahan data: $adaPerubahan');

                        ScaffoldMessenger.of(navigatorKey.currentContext!)
                            .showSnackBar(
                          SnackBar(
                            content: Text(
                              adaPerubahan
                                  ? 'Konfigurasi berhasil diperbarui'
                                  : 'Tidak ada perubahan data',
                            ),
                            backgroundColor: adaPerubahan
                                ? Colors.green
                                : Colors.yellow.shade700,
                          ),
                        );

                        // Hapus Navigator.pop supaya drawer tidak ditutup di sini
                      } catch (e) {
                        print('Terjadi error saat sinkronisasi: $e');

                        String pesanError = 'Gagal memperbarui konfigurasi: $e';
                        if (e is SocketException) {
                          pesanError = 'Tidak ada koneksi internet.';
                          print('Error koneksi internet terdeteksi.');
                        }

                        ScaffoldMessenger.of(navigatorKey.currentContext!)
                            .showSnackBar(
                          SnackBar(
                            content: Text(pesanError),
                            backgroundColor: Colors.red.shade700,
                          ),
                        );
                      }
                    },
                  ),

                  _buildMenuItem(
                    icon: Icons.cloud_outlined,
                    title: 'Test Online',
                    color: Colors.blue.shade600,
                   onTap: () => _closeDialogAndNavigate(context, '/remoteaccess'),
 ),
                  _buildMenuItem(
                    icon: Icons.sd_storage,
                    title: 'Server Lokal',
                    color: Colors.orange.shade600,
                    onTap: () => Navigator.pushNamed(context, '/localserver'),
                  ),
                  _buildMenuItem(
                    icon: Icons.power_settings_new,
                    title: 'Keluar Aplikasi',
                    color: Colors.red.shade600,
                    onTap: () async {
                      Navigator.pop(context);
                      bool success = await stopLockTask();
                      if (success) {
                        SystemNavigator.pop();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Gagal mematikan lock task'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
     transitionBuilder: (context, animation, secondaryAnimation, child) {
  final curvedValue = Curves.fastEaseInToSlowEaseOut.transform(animation.value) - 1.0;

  return Transform.translate(
    offset: Offset(0.0, curvedValue * -300),
    child: child,
  );
},

    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color color = Colors.blue,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.1),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }

  Future<void> _checkPenaltyStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final int? penaltyDurationFromPrefs = prefs.getInt('int_penalty');
    final int penaltyDuration =
        penaltyDurationFromPrefs ?? 1800; // fallback 30 menit

    // Periksa apakah sebelumnya aplikasi sempat masuk background
    final int? lastBackground = prefs.getInt('last_background_time');

    if (lastBackground != null) {
      if (now - lastBackground >= penaltyDuration) {
        final int penaltyStart = now;
        await prefs.setInt('penalty_start_timestamp', penaltyStart);
        await prefs.remove('last_background_time');

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
          return;
        }
      } else {
        await prefs.remove('last_background_time');
      }
    }

    final int? penaltyStartTimestamp = prefs.getInt('penalty_start_timestamp');

    if (penaltyStartTimestamp != null) {
      final int elapsed = now - penaltyStartTimestamp;
      final int remaining = penaltyDuration - elapsed;

      if (remaining > 0) {
        setState(() {
          _secondsLeft = remaining;
        });
        _startTimer();
        return;
      } else {
        await prefs.remove('penalty_start_timestamp');
      }
    }

    setState(() {
      _secondsLeft = 0;
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_secondsLeft <= 1) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('penalty_start_timestamp');
        timer.cancel();
        if (!mounted) return;
        setState(() {
          _secondsLeft = 0;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _secondsLeft--;
        });
      }
    });
  }

  void _login() async {
    String enteredKey = _ipController.text.trim();

    if (enteredKey.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      // Use the entered key to retrieve the actual IP address from SharedPreferences
      final String? ipAddress = prefs.getString(enteredKey);

      if (ipAddress != null && ipAddress.isNotEmpty) {
        await prefs.setString('last_entered_key', enteredKey); // Simpan key yang dimasukkan

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RemoteAccess(), // Navigate to RemoteAccess
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunci "$enteredKey" tidak ditemukan atau alamat ujian kosong.')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kunci tidak boleh kosong')), // Ubah pesan error
      );
    }
  }

  Future<void> _requestAccess() async {
    String? inputPin = await showDialog<String>(
      context: context,
      builder: (context) {
        final TextEditingController pinDialogController =
            TextEditingController();
        String? dialogErrorText;

        return StatefulBuilder(
          builder: (context, setState) {
            void verifyPin() {
              if (pinDialogController.text.trim() == correctPin) {
                Navigator.pop(context, pinDialogController.text.trim());
              } else {
                setState(() {
                  dialogErrorText = 'PIN salah, coba lagi.';
                });
              }
            }

           return AlertDialog(
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  title: const Center(
    child: Text(
      'Masukkan PIN',
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 22,
        color: Colors.black87,
      ),
    ),
  ),
  content: SizedBox(
    width: double.maxFinite,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
       
        TextField(
          controller: pinDialogController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center, // input PIN di tengah
          decoration: InputDecoration(
            hintText: '••••••',
            errorText: dialogErrorText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blue, width: 2),
            ),
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          style: const TextStyle(
            fontSize: 24,
            letterSpacing: 16, // spacing agar tiap digit lebih jelas
            fontWeight: FontWeight.w500,
          ),
          onSubmitted: (_) => verifyPin(),
        ),
        const SizedBox(height: 20),
      ],
    ),
  ),
  actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  actions: [
    TextButton(
      onPressed: () => Navigator.pop(context),
      child: const Text(
        'Batal',
        style: TextStyle(fontSize: 16, color: Colors.grey),
      ),
    ),
    ElevatedButton(
      onPressed: verifyPin,
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      ),
      child: const Text(
        'Verifikasi',
        style: TextStyle(fontSize: 16),
      ),
    ),
  ],
);

          },
        );
      },
    );

    if (inputPin == correctPin) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('penalty_start_timestamp');
      await prefs.remove('penalty_remaining');

      if (!mounted) return;
      setState(() {
        _secondsLeft = 0;
      });

     ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(
    content: Text('Akses diterima'),
    backgroundColor: Colors.green,  // Tambah warna hijau
  ),
);

    }
  }

  static const MethodChannel _channel =
      MethodChannel('com.example.webdipo/window_mode');

  Future<bool> stopLockTask() async {
    try {
      final bool result = await _channel.invokeMethod('stopLockTask');
      return result;
    } catch (e) {
      print('Error calling stopLockTask: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_secondsLeft > 0) return false;
        return true;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: Curves.easeInOutCubic,
          switchOutCurve: Curves.easeInOutCirc,
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
        child: (_showFab && _secondsLeft == 0) // tombol cuma muncul kalau _secondsLeft = 0 (tidak penalti)
    ? SizedBox(
        key: const ValueKey('fab-arrow-up'),
        height: 46,
        width: 100,
        child: TextButton(
          onPressed: () => showBottomMenu(context),
          style: TextButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            elevation: 0,
          ),
          child: const Icon(
            Icons.keyboard_arrow_up,
            size: 28,
            color: Colors.white,
          ),
        ),
      )
    : const SizedBox.shrink(key: ValueKey('fab-empty')),
        ),

        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                     _secondsLeft > 0 
  ? Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 80,
          color: Colors.redAccent,
        ),
       
      ],
    )
  : Column(
      children: [
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              fontFamily: 'Montserrat',
              color: Colors.blueAccent,
            ),
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.top,
                child: Padding(
                  padding: const EdgeInsets.only(right: 2, bottom: 0),
                  child: Icon(
                    Icons.language,
                    size: 44,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
              TextSpan(text: 'Exam-D'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Platform Ujian Digital',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
            fontFamily: 'OpenSans',
          ),
        ),
      ],
    ),

                      if (_secondsLeft > 0) ...[
                        const Text(
                          'Anda dalam masa penalti',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Sisa waktu: ${_formatDuration(_secondsLeft)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.deepOrange,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _requestAccess,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                              elevation: 0,
                              shadowColor:
                                  Colors.blue.shade700.withOpacity(0.5),
                            ),
                            child: const Text(
                              'Minta Hak Akses',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                      final offsetAnimation = Tween<Offset>(
                        begin: const Offset(0.0, 0.2),
                        end: Offset.zero,
                      ).animate(animation);

                      return SlideTransition(
                        position: offsetAnimation,
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      );
                    },
                    child: _secondsLeft == 0
                        ? Column(
                            key: const ValueKey('visible_form'),
                            children: [
                              const SizedBox(height: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // TextField dengan label & style modern
                                  TextField(
                                    key: const ValueKey('ip_text_field'),
                                    controller: _ipController,
                                    keyboardType: TextInputType.url,
                                    textAlign: TextAlign.left,
                                    decoration: InputDecoration(
                                      labelText: 'Masukkan key Ujian',
                                      labelStyle:
                                          TextStyle(color: Colors.grey[700]),
                                      filled: true,
                                      fillColor: Colors.grey.shade100,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                            color: Colors.blue.shade700,
                                            width: 2),
                                      ),
                                      suffixIcon: Container(
                                        margin: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade700,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          highlightColor: Colors.white24,
                                          splashColor: Colors.blue.shade300,
                                          onTap: _login,
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Start </>',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                // SizedBox(width: 4),
                                                // Icon(Icons.arrow_forward,
                                                //     color: Colors.white),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 18,
                                      ),
                                    ),
                                    style: const TextStyle(
                                        color: Colors.black, fontSize: 16),
                                    onSubmitted: (_) => _login(),
                                  ),
                                  const SizedBox(height: 20),

                                  // Row tombol connected style
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 500),
                                    transitionBuilder: (Widget child,
                                        Animation<double> animation) {
                                      final offsetAnimation = Tween<Offset>(
                                        begin: const Offset(0.0, 0.2),
                                        end: Offset.zero,
                                      ).animate(animation);

                                      return SlideTransition(
                                        position: offsetAnimation,
                                        child: FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        ),
                                      );
                                    },
                                    // child: Row(
                                    //   key: const ValueKey(
                                    //       'buttonRow'), // key statis supaya AnimatedSwitcher tahu ini widget yang sama
                                    //   children: [
                                    //     Expanded(
                                    //       child: ElevatedButton.icon(
                                    //         onPressed: () {
                                    //           Navigator.pushNamed(
                                    //               context, '/remoteaccess');
                                    //         },
                                    //         icon: const Icon(
                                    //             Icons.cloud_outlined,
                                    //             size: 20),
                                    //         label: const Text(
                                    //           'Online',
                                    //           style: TextStyle(
                                    //               fontSize: 16,
                                    //               fontWeight: FontWeight.w600),
                                    //         ),
                                    //         style: ElevatedButton.styleFrom(
                                    //           backgroundColor:
                                    //               Colors.blue.shade700,
                                    //           padding:
                                    //               const EdgeInsets.symmetric(
                                    //                   vertical: 14),
                                    //           shape:
                                    //               const RoundedRectangleBorder(
                                    //             borderRadius: BorderRadius.only(
                                    //               topLeft: Radius.circular(16),
                                    //               bottomLeft:
                                    //                   Radius.circular(16),
                                    //             ),
                                    //           ),
                                    //           elevation: 5,
                                    //           shadowColor: Colors.blue.shade700
                                    //               .withOpacity(0.3),
                                    //         ),
                                    //       ),
                                    //     ),
                                    //     Expanded(
                                    //       child: ElevatedButton.icon(
                                    //         onPressed: () {
                                    //           Navigator.pushNamed(
                                    //               context, '/localserver');
                                    //         },
                                    //         icon: const Icon(Icons.sd_storage,
                                    //             size: 20),
                                    //         label: const Text(
                                    //           'Lokal',
                                    //           style: TextStyle(
                                    //               fontSize: 16,
                                    //               fontWeight: FontWeight.w600),
                                    //         ),
                                    //         style: ElevatedButton.styleFrom(
                                    //           backgroundColor:
                                    //               Colors.blue.shade700,
                                    //           padding:
                                    //               const EdgeInsets.symmetric(
                                    //                   vertical: 14),
                                    //           shape:
                                    //               const RoundedRectangleBorder(
                                    //             borderRadius: BorderRadius.only(
                                    //               topRight: Radius.circular(16),
                                    //               bottomRight:
                                    //                   Radius.circular(16),
                                    //             ),
                                    //           ),
                                    //           elevation: 5,
                                    //           shadowColor: Colors.blue.shade700
                                    //               .withOpacity(0.3),
                                    //         ),
                                    //       ),
                                    //     ),
                                    //   ],
                                    // ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 32),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
        // floatingActionButton: Align(
        //   alignment: Alignment.bottomRight,
        //   child: Padding(
        //     padding: const EdgeInsets.only(
        //         right: 10, bottom: 1), // Atur posisi di sini
        //     child: Container(
        //       decoration: const BoxDecoration(
        //         shape: BoxShape.circle,
        //       ),
        //       child: IconButton(
        //         icon: const Icon(Icons.power_settings_new,
        //             size: 30, color: Colors.red),
        //         onPressed: () async {
        //           bool success = await stopLockTask();
        //           if (success) {
        //             SystemNavigator.pop();
        //           } else {
        //             ScaffoldMessenger.of(context).showSnackBar(
        //               const SnackBar(
        //                   content: Text('Gagal mematikan lock task')),
        //             );
        //           }
        //         },
        //       ),
        //     ),
        //   ),
        // ),s
        // floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }
}

Future<void> _fetchLocalData() async {
  try {
    // Cek koneksi internet langsung di sini
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult != ConnectivityResult.mobile &&
        connectivityResult != ConnectivityResult.wifi) {
      throw Exception('Tidak ada koneksi internet');
    }

    await Firebase.initializeApp();

    final prefs = await SharedPreferences.getInstance();

    final localDoc = await FirebaseFirestore.instance
        .collection('remote')
        .doc('local')
        .get();

    // Fetch online_test_link from remote/remote_access
    final remoteAccessDoc = await FirebaseFirestore.instance
        .collection('remote')
        .doc('remote_access')
        .get();

    if (remoteAccessDoc.exists) {
      final remoteAccessData = remoteAccessDoc.data();
      if (remoteAccessData != null && remoteAccessData.containsKey('link')) {
        final onlineTestLink = remoteAccessData['link'].toString();
        await prefs.setString('online_test_link', onlineTestLink);
        print('✅ online_test_link dari remote/remote_access disimpan: $onlineTestLink');
      } else {
        print('⚠️ Link ujian online tidak ditemukan di remote/remote_access');
      }
    } else {
      print('⚠️ Dokumen remote/remote_access tidak ditemukan');
    }

    if (localDoc.metadata.isFromCache) {
      throw Exception(
          'Data hanya dari cache, kemungkinan tidak ada koneksi internet');
    }

    if (localDoc.exists) {
      final localData = localDoc.data();
      if (localData != null) {
        print('📦 Data di remote/local:');
        localData.forEach((key, value) {
          print(' - $key : $value');
        });

        final localDataString = json.encode(localData);
        await prefs.setString('local_data', localDataString);
        print('✅ Data local dari remote/local disimpan ke SharedPreferences');

        if (localData.containsKey('local_setting')) {
          final localSetting = localData['local_setting'].toString();
          await prefs.setString('local_setting', localSetting);
          print('✅ local_setting dari local disimpan: $localSetting');
        }
      }
    } else {
      print('⚠️ Dokumen remote/local tidak ditemukan');
      throw Exception('Dokumen remote/local tidak ditemukan');
    }
  } catch (e) {
    print('❌ Gagal fetch data remote/local: $e');
    throw e; // Lempar error supaya bisa ditangkap di luar
  }
}

Future<void> _fetchPenaltyDurationFromFirestore() async {
  try {
    await Firebase.initializeApp();

    final docSnap = await FirebaseFirestore.instance
        .collection('remote')
        .doc('global')
        .get();

    if (docSnap.exists) {
      final data = docSnap.data();
      if (data != null && data.containsKey('int_penalty')) {
        final dynamic penaltyValue = data['int_penalty'];
        int penaltyInt;

        if (penaltyValue is int) {
          penaltyInt = penaltyValue;
        } else if (penaltyValue is String) {
          penaltyInt = int.tryParse(penaltyValue) ?? 1800; // default 1800 detik
        } else {
          penaltyInt = 1800;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('int_penalty', penaltyInt);
        print('✅ int_penalty disimpan ke SharedPreferences: $penaltyInt');
      } else {
        print('⚠️ int_penalty tidak ditemukan di dokumen remote/global');
      }
    } else {
      print('⚠️ Dokumen global di koleksi remote tidak ada');
    }
  } catch (e) {
    print('❌ Gagal fetch int_penalty dari Firestore: $e');
  }
}

Future<void> _fetchTestTimeAndSave() async {
  try {
    // Cek apakah Firebase sudah diinisialisasi
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
      print('Firebase berhasil diinisialisasi');
    }

    // Ambil dokumen 'global' dari koleksi 'remote'
    final docSnap = await FirebaseFirestore.instance
        .collection('remote')
        .doc('global')
        .get();

    if (docSnap.exists) {
      final data = docSnap.data();
      int testTimeInt = 0; // default kalau data tidak ada

      if (data != null && data.containsKey('test_time')) {
        final dynamic testTimeValue = data['test_time'];

        if (testTimeValue is int) {
          testTimeInt = testTimeValue;
        } else if (testTimeValue is String) {
          testTimeInt = int.tryParse(testTimeValue) ?? 0;
        } else {
          print('⚠️ Tipe data test_time tidak dikenali, gunakan default 0');
        }
      } else {
        print(
            '⚠️ test_time tidak ditemukan di dokumen remote/global, simpan default 0');
      }

      // Simpan nilai testTimeInt ke SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('test_time', testTimeInt);
      print('✅ test_time disimpan ke SharedPreferences: $testTimeInt');
    } else {
      print('⚠️ Dokumen global di koleksi remote tidak ada');
    }
  } catch (e) {
    print('❌ Gagal fetch test_time dari Firestore: $e');
  }
}
void _closeDialogAndNavigate(BuildContext context, String routeName) {
  print('[main] _closeDialogAndNavigate: Popping current route.');
  Navigator.pop(context);
  // Delay sedikit supaya animasi pop selesai dulu
  Future.delayed(const Duration(milliseconds: 300), () {
    print('[main] _closeDialogAndNavigate: Pushing route: $routeName');
    Navigator.pushNamed(context, routeName);
  });
}
