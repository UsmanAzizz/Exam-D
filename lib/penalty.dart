import 'package:flutter/material.dart';
import 'accessibility.dart'; // pastikan ini path yang benar ke WifiMonitor

class PenaltyPage extends StatefulWidget {
  const PenaltyPage({super.key});

  @override
  State<PenaltyPage> createState() => _PenaltyPageState();
}

class _PenaltyPageState extends State<PenaltyPage> {
  bool _isPenaltyActive = false;
  DateTime? _penaltyEndTime;

  @override
  void initState() {
    super.initState();

    WifiMonitor.startMonitoring(
      onWifiSettingsOpened: () => print('WiFi settings dibuka'),
      onWifiSettingsClosed: () => print('WiFi settings ditutup'),
      onAppResumed: () => print('App resumed'),
      onAppBackgrounded: () => print('App backgrounded'),
      onDisqualified: () => print('User diskualifikasi'),
      onAccessibilityEvent: (event) => print('Accessibility event: $event'),
    );

    // Kalau mau bisa cek state penalty dari shared prefs atau backend disini
  }

  void _startPenaltyTimer() {
    setState(() {
      _isPenaltyActive = true;
      _penaltyEndTime = DateTime.now().add(const Duration(seconds: 5));
    });
  }

  void _cancelPenalty() {
    setState(() {
      _isPenaltyActive = false;
      _penaltyEndTime = null;
    });
  }

  void _showDisqualificationDialog() {
    if (!_isPenaltyActive) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Diskualifikasi'),
        content: const Text(
          'Anda diskualifikasi karena meninggalkan aplikasi saat pengaturan WiFi.\nSilakan login kembali.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacementNamed('/login');
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Halaman Penalty'),
      ),
      body: Center(
        child: _isPenaltyActive
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                      'Anda akan didiskualifikasi jika tidak kembali dalam 5 detik'),
                  const SizedBox(height: 12),
                  _penaltyEndTime != null
                      ? Text(
                          'Waktu tersisa: ${_penaltyEndTime!.difference(DateTime.now()).inSeconds} detik',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        )
                      : Container(),
                ],
              )
            : const Text('Silakan gunakan menu WiFi'),
      ),
    );
  }
}
