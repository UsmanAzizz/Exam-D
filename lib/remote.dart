import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'run_test.dart';
import 'package:webdipo/run_test.dart' show LockTaskHelper; // Import LockTaskHelper

class RemoteAccess extends StatefulWidget {
  // Placeholder for PopupMenuButton, as it was not found in the original file.
  // The original search string was looking for an existing PopupMenuItem within an itemBuilder,
  // but no such structure exists in this file. To proceed with the instruction
  // to add a PopupMenuItem, a suitable anchor point needs to be identified.
  // This corrected search targets the class definition as a general insertion point.

  const RemoteAccess({Key? key}) : super(key: key);

  @override
  State<RemoteAccess> createState() => _RemoteAccessState();
}

class _RemoteAccessState extends State<RemoteAccess> {
  static const MethodChannel _windowModeChannel =
      MethodChannel('com.example.webdipo/window_mode');
  bool _pinningAttempted = false;
  bool _alreadyNavigated = false;
  bool _isLoadingPinning = true; // New state to show loading for pinning
  String? _onlineTestLink;
  String _pinningStatusMessage = 'Memulai mode ujian aman...'; // Default message
  IconData? _pinningStatusIcon; // Icon for status
  Timer? _lockTaskCheckTimer; // Tambahkan ini

  @override
  void initState() {
    super.initState();
    print('[RemoteAccess] initState called.');
    _navigateToTest();
  }

  Future<void> _navigateToTest() async {
    final prefs = await SharedPreferences.getInstance();
    final link = prefs.getString('online_test_link');

    print('[RemoteAccess] online_test_link: $link'); // Log the link

    // Ensure the widget is still mounted before navigating
    if (!mounted) return;

    if (link != null && link.isNotEmpty) {
      setState(() {
        _onlineTestLink = link;
        _isLoadingPinning = true; // Start loading for pinning
      });
      _startPinningProcess(); // Call the new pinning process
    } else {
      print('[RemoteAccess] Link ujian online tidak ditemukan atau kosong.');
      // If the link is not found, show an error and pop the page
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link ujian online tidak ditemukan. Silakan sinkronkan konfigurasi.'),
          backgroundColor: Colors.red,
        ),
      );
      // Pop back to the previous screen (LoginPage)
      Navigator.pop(context);
    }
  }



  Future<void> _startPinningProcess() async {
    if (_pinningAttempted) return;
    _pinningAttempted = true;

    // Panggil startLockTask() untuk memicu dialog Pin Layar dari Android
    print('[RemoteAccess] Memanggil LockTaskHelper.startLockTask() untuk memicu Pin Layar...');
    bool started = await LockTaskHelper.startLockTask();
    print('[RemoteAccess] LockTaskHelper.startLockTask() returned: $started');

    if (!started) {
      // Jika startLockTask() gagal, tampilkan pesan error dan hentikan pemantauan
      if (mounted) {
        setState(() {
          _pinningStatusMessage = 'Gagal memicu Pin Layar. Pastikan Device Admin aktif.';
          _pinningStatusIcon = Icons.error;
          _isLoadingPinning = false;
        });
      }
      return;
    }

    // Tampilkan UI loading dan pesan
    if (mounted) {
      setState(() {
        _pinningStatusMessage = 'Pin Layar sedang diaktifkan. Mohon konfirmasi jika diminta.';
        _pinningStatusIcon = null; // Kembali ke CircularProgressIndicator
        _isLoadingPinning = true;
      });
    }

    // Mulai memantau status Lock Task
    _lockTaskCheckTimer?.cancel();
    _lockTaskCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final bool isLockTaskActive = await LockTaskHelper.checkLockTask();
      print('[RemoteAccess] Memantau Lock Task - isLockTaskActive = $isLockTaskActive');

      if (isLockTaskActive) {
        timer.cancel(); // Hentikan timer
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => RunTest(ipAddress: _onlineTestLink!),
            ),
          );
        }
      } else {
        // Jika Lock Task belum aktif, bisa tampilkan pesan atau instruksi ulang
        if (mounted) {
          setState(() {
            _pinningStatusMessage = 'Pin Layar belum aktif. Mohon konfirmasi jika diminta.';
            _pinningStatusIcon = Icons.warning;
            _isLoadingPinning = false; // Selesai loading, siap untuk interaksi pengguna
          });
        }
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _pinningStatusIcon != null
                ? Icon(_pinningStatusIcon, size: 48, color: _pinningStatusIcon == Icons.check_circle ? Colors.green : Colors.red)
                : const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              _pinningStatusMessage,
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            if (_pinningStatusIcon == null) // Only show this hint if still loading
              const Text(
                '(Mohon konfirmasi pin layar jika diminta)',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
  }