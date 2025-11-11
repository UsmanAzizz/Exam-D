import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  bool _loading = false;
  bool _configExists = false;
  bool _pinVerified = false;

  String _statusText = "Masukkan PIN untuk melanjutkan.";
  String _buttonText = "Verifikasi PIN";

  final TextEditingController _pinController = TextEditingController();
  String? _pinErrorText;

  @override
  void initState() {
    super.initState();
    _checkConfig();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _checkConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final config = prefs.getString('local_data');

    if (config != null && config.isNotEmpty) {
      setState(() {
        _configExists = true;
        _statusText = "Konfigurasi sudah tersedia.";
        _buttonText = "Lanjutkan";
        _pinVerified = true;
      });
    } else {
      setState(() {
        _configExists = false;
        _statusText = "Masukkan PIN untuk melanjutkan.";
        _buttonText = "Verifikasi PIN";
        _pinVerified = false;
      });
    }
  }

  Future<String?> _fetchPinFromFirestore() async {
    try {
      await Firebase.initializeApp();
      final doc = await FirebaseFirestore.instance
          .collection('remote')
          .doc('global')
          .get();

      if (doc.exists) {
        final data = doc.data();
        return data?['PIN_start']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _verifyPin() async {
    setState(() {
      _pinErrorText = null;
      _loading = true;
      _statusText = '';
    });

    final enteredPin = _pinController.text.trim();

    if (enteredPin.isEmpty) {
      _showStatus('PIN tidak boleh kosong', false);
      setState(() {
        _pinErrorText = 'PIN tidak boleh kosong';
        _loading = false;
      });
      return;
    }

    final correctPin = await _fetchPinFromFirestore();

    if (correctPin == null) {
      _showStatus('Gagal mengambil PIN dari server.', false);
      setState(() {
        _pinErrorText = 'Gagal mengambil PIN dari server.';
        _loading = false;
      });
      return;
    }

    if (enteredPin == correctPin) {
      print('PIN benar.');
        final prefs = await SharedPreferences.getInstance();
       await prefs.setBool('pin_verified', true);
      _showStatus('PIN benar! Silakan unduh konfigurasi.',
          true); // sukses = true -> warna hijau
      setState(() {
        _pinVerified = true;
        _buttonText = "Unduh Konfigurasi";
        _pinErrorText = null;
        _loading = false;
      });
    } else {
      print('PIN salah.');
      _showStatus(
          'PIN salah. Coba lagi.', false); // gagal = false -> warna merah
      setState(() {
        _pinErrorText = "PIN salah. Coba lagi.";
        _loading = false;
      });
    }
  }

  Future<void> _downloadConfig() async {
    _showStatus('Mengunduh konfigurasi...', true);

    setState(() {
      _loading = true;
      _pinErrorText = null;
    });

    try {
      await Firebase.initializeApp();

      await Future.wait([
        _fetchLocalData(),
        _fetchPenaltyDurationFromFirestore(),
        _fetchTestTimeAndSave(),
      ]);

      _showStatus('Berhasil mengunduh konfigurasi!', true);
      setState(() {
        _buttonText = "Lanjutkan";
        _configExists = true;
      });
    } catch (_) {
      _showStatus('Gagal mengunduh konfigurasi', false);
      setState(() {
        _buttonText = "Coba Lagi";
        _configExists = false;
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  void _handleButton() {
    if (!_pinVerified) {
      _verifyPin();
    } else if (_configExists) {
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      _downloadConfig();
    }
  }

  bool _isSuccessStatus = false; // tambahkan ini di class _ConfigPageState

  void _showStatus(String message, bool isSuccess) {
    setState(() {
      _isSuccessStatus = isSuccess; // simpan status sukses/gagal

      if (isSuccess) {
        _statusText = message;
        _pinErrorText = null;
      } else {
        _pinErrorText = message;
        _statusText = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Colors.blue.shade700;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: SizedBox(
            width: 360, // fixed width
            height: 300, // fixed height
            child: Column(
              mainAxisSize: MainAxisSize.min, // supaya ukurannya sesuai isi
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.settings, size: 90, color: Colors.blueAccent),
                const SizedBox(height: 24),
                if (!_pinVerified) ...[
                  TextField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 10,
                    ),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                      counterText: "",
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: TextButton(
                    onPressed: _loading ? null : _handleButton,
                    style: TextButton.styleFrom(
                      backgroundColor: _loading ? Colors.white : primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ).copyWith(
                      overlayColor:
                          WidgetStateProperty.all(Colors.transparent),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.blueAccent,
                              ),
                            ),
                          )
                        : Text(
                            _buttonText,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 40),
                if (_statusText.isNotEmpty && _pinErrorText == null)
                  Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: _isSuccessStatus
                          ? Colors.green
                          : Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (_pinErrorText != null)
                  Text(
                    _pinErrorText!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =================== 🔽 FETCH FUNCTIONS 🔽 ===================

  Future<void> _fetchLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final localDoc = await FirebaseFirestore.instance
        .collection('remote')
        .doc('local')
        .get();

    if (localDoc.exists) {
      final localData = localDoc.data();
      print('Fetched local data: $localData'); // <-- print data
      if (localData != null) {
        final localDataString = json.encode(localData);
        await prefs.setString('local_data', localDataString);
        if (localData.containsKey('local_setting')) {
          await prefs.setString(
              'local_setting', localData['local_setting'].toString());
        }
      }
    } else {
      throw Exception("Dokumen remote/local tidak ditemukan");
    }
  }

  Future<void> _fetchPenaltyDurationFromFirestore() async {
    final docSnap = await FirebaseFirestore.instance
        .collection('remote')
        .doc('global')
        .get();

    if (docSnap.exists) {
      final data = docSnap.data();
      print('Fetched penalty duration data: $data'); // <-- print data
      if (data != null && data.containsKey('int_penalty')) {
        int penaltyInt;
        final dynamic value = data['int_penalty'];
        if (value is int) {
          penaltyInt = value;
        } else if (value is String) {
          penaltyInt = int.tryParse(value) ?? 1800;
        } else {
          penaltyInt = 1800;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('int_penalty', penaltyInt);
      }
    } else {
      throw Exception("Dokumen remote/global tidak ditemukan");
    }
  }

  Future<void> _fetchTestTimeAndSave() async {
    try {
      // Pastikan Firebase sudah diinisialisasi
      await Firebase.initializeApp();

      final docSnap = await FirebaseFirestore.instance
          .collection('remote')
          .doc('global')
          .get();

      if (docSnap.exists) {
        final data = docSnap.data();
        if (data != null && data.containsKey('test_time')) {
          // Misalkan test_time disimpan sebagai int (jumlah detik atau epoch dll)
          // Sesuaikan tipe sesuai DB kamu
          final dynamic testTimeValue = data['test_time'];
          int testTimeInt;

          if (testTimeValue is int) {
            testTimeInt = testTimeValue;
          } else if (testTimeValue is String) {
            testTimeInt = int.tryParse(testTimeValue) ?? 0;
          } else {
            // handle tipe lain kalau perlu
            testTimeInt = 0;
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('test_time', testTimeInt);
          print('✅ test_time disimpan ke SharedPreferences: $testTimeInt');
        } else {
          print('⚠️ test_time tidak ditemukan di dokumen remote/global');
        }
      } else {
        print('⚠️ Dokumen global di koleksi remote tidak ada');
      }
    } catch (e) {
      print('❌ Gagal fetch test_time dari Firestore: $e');
    }
  }
}
