import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:wifi_info_flutter/wifi_info_flutter.dart';
import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'run_test.dart';

class LocalServerPage extends StatefulWidget {
  const LocalServerPage({super.key});

  @override
  State<LocalServerPage> createState() => _LocalServerPageState();
}

class _LocalServerPageState extends State<LocalServerPage> {
  late Future<void> _initFuture;

  String? _ssid;
  String? _wifiError;
  bool _isLoadingWifi = true;

  Map<String, dynamic>? _firestoreData;
  String? _firestoreError;
  bool _isLoadingFirestore = true;

  bool _isSyncing = false;
  bool _isLocked = true;

  final String _prefsKey = 'local_data';
  final String _lastSyncKey = 'last_sync_date';

  @override
  void initState() {
    super.initState();
    _initFuture = _initializeApp();
  }

  Future<void> _initializeApp() async {
    await Firebase.initializeApp();
    await _checkPermissionsAndGetWifiName();
    await _loadFirestoreDataFromLocal();

    if (_firestoreData == null) {
      _isLocked = true;
    } else {
      _isLocked = false;
    }
  }

  Future<void> _refreshPage() async {
    setState(() {
      _initFuture = _initializeApp();
    });
  }

  PermissionStatus? _permissionStatus;

  Future<void> _checkPermissionsAndGetWifiName() async {
    setState(() {
      _isLoadingWifi = true;
      _wifiError = null;
      _ssid = null;
    });

    final location = loc.Location();

    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        setState(() {
          _wifiError = 'Layanan lokasi harus diaktifkan.';
          _isLoadingWifi = false;
        });
        return;
      }
    }

    var status = await Permission.location.status;
    _permissionStatus = status;

    if (!status.isGranted) {
      status = await Permission.location.request();
      _permissionStatus = status;
    }

    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        setState(() {
          _wifiError =
              'Izin lokasi ditolak. Silakan aktifkan melalui pengaturan.';
          _isLoadingWifi = false;
        });
        await openAppSettings();
      } else {
        setState(() {
          _wifiError = 'Izin lokasi ditolak.';
          _isLoadingWifi = false;
        });
      }
      return;
    }

    try {
      final wifiName = await WifiInfo().getWifiName();
      setState(() {
        _ssid = wifiName?.replaceAll('"', '') ?? 'Tidak Terhubung';
        _isLoadingWifi = false;
      });
    } catch (e) {
      setState(() {
        _wifiError = 'Gagal mengambil WiFi: $e';
        _isLoadingWifi = false;
      });
    }
  }

  Future<void> _loadFirestoreDataFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefsKey);

    if (jsonString != null) {
      try {
        final data = json.decode(jsonString) as Map<String, dynamic>;
        setState(() {
          _firestoreData = data;
          _isLoadingFirestore = false;
          _isLocked = false;
        });
      } catch (e) {
        setState(() {
          _firestoreError = 'Gagal membaca data lokal.';
          _isLoadingFirestore = false;
          _isLocked = true;
        });
      }
    } else {
      setState(() {
        _firestoreData = null;
        _isLoadingFirestore = false;
        _isLocked = true;
      });
    }
  }

  Future<bool> shouldAllowSync() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncString = prefs.getString(_lastSyncKey);

    if (lastSyncString == null) return true;

    final lastSync = DateTime.tryParse(lastSyncString);
    if (lastSync == null) return true;

    final now = DateTime.now();
    final diff = now.difference(lastSync);
    return diff.inDays >= 10;
  }

  Future<void> _syncFirestoreDataIfConnected() async {
    setState(() {
      _isSyncing = true;
      _firestoreError = null;
    });

    final hasConnection = await InternetConnectionChecker().hasConnection;

    if (!hasConnection) {
      setState(() {
        _firestoreError = 'Tidak ada koneksi internet.';
        _isLoadingFirestore = false;
        _isSyncing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Sinkronisasi gagal: tidak ada internet.'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }

      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('remote')
          .doc('local')
          .get();

      if (doc.exists) {
        final newData = doc.data();
        if (newData != null) {
          final prefs = await SharedPreferences.getInstance();
          final newDataString = json.encode(newData);

          await prefs.setString(_prefsKey, newDataString);
          await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());

          setState(() {
            _firestoreData = newData;
            _isLoadingFirestore = false;
            _isLocked = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Sinkronisasi data berhasil!'),
                backgroundColor: Colors.green.shade600,
              ),
            );
          }
        }
      } else {
        setState(() {
          _firestoreError = 'Dokumen tidak ditemukan.';
          _isLoadingFirestore = false;
        });
      }
    } catch (e) {
      setState(() {
        _firestoreError = 'Gagal mengambil data: $e';
        _isLoadingFirestore = false;
      });
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  bool get _isLanjutkanEnabled =>
      _ssid != null &&
      _firestoreData != null &&
      _firestoreData!.containsKey(_ssid);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                'Error inisialisasi Firebase: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (_isLocked) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Sinkronisasi Diperlukan'),
              backgroundColor: Colors.red.shade700,
              centerTitle: true,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Silakan lakukan sinkronisasi sebelum melanjutkan',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: _isSyncing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.sync),
                      label: const Text('Sinkronkan Sekarang'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 24),
                        backgroundColor: Colors.blue.shade800,
                      ),
                      onPressed: _isSyncing
                          ? null
                          : () async {
                              final canSync = await shouldAllowSync();
                              if (!canSync) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                          'Sinkronisasi hanya diperbolehkan setiap 2 bulan.'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                                return;
                              }

                              await _syncFirestoreDataIfConnected();

                              if (!_isLocked) {
                                await _refreshPage();
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    if (_firestoreError != null) ...[
                      Text(
                        _firestoreError!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      )
                    ]
                  ],
                ),
              ),
            ),
          );
        }

        // Jika tidak terkunci, tampilkan halaman utama seperti biasa
        return Scaffold(
          appBar: AppBar(
            title: const Text('Server Lokal'),
            backgroundColor: Colors.blue.shade800,
            centerTitle: true,
            elevation: 0,
            actions: [
              IconButton(
                icon: _isSyncing
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.sync),
                tooltip: 'Sinkronkan & Refresh',
                onPressed: _isSyncing
                    ? null
                    : () async {
                        // Langsung jalankan sinkronisasi tanpa cek waktu
                        await _syncFirestoreDataIfConnected();
                        await _refreshPage();
                      },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 2,
                        blurRadius: 10,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Status WiFi',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // === Loading WiFi ===
                      if (_isLoadingWifi) ...[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        const Text('Mengambil nama WiFi...'),
                      ]

                      // === Error WiFi ===
                      else if (_wifiError != null) ...[
                        Icon(Icons.error_outline,
                            size: 48, color: Colors.red.shade700),
                        const SizedBox(height: 12),
                        Text(
                          _wifiError!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        if (_permissionStatus == null ||
                            _permissionStatus!.isDenied) ...[
                          ElevatedButton.icon(
                            icon: const Icon(Icons.security),
                            label: const Text('Beri Izin'),
                            onPressed: _checkPermissionsAndGetWifiName,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade700,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 24),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('Coba Lagi'),
                            onPressed: _checkPermissionsAndGetWifiName,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 24),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ]
                      ]

                      // === Status WiFi Berhasil ===
                      else ...[
                        if (_ssid != null &&
                            _ssid!.isNotEmpty &&
                            _ssid != 'Tidak Terhubung') ...[
                          Text(
                            'Terhubung ke SSID:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],

                        // === SSID Container ===
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: _ssid == null ||
                                    _ssid!.isEmpty ||
                                    _ssid == 'Tidak Terhubung'
                                ? Colors.red.shade100
                                : _isLanjutkanEnabled
                                    ? Colors.green.shade100
                                    : Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              _ssid ?? 'Tidak ada SSID',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        // === Pesan WiFi tidak valid ===
                        if (_ssid != null &&
                            _ssid!.isNotEmpty &&
                            _ssid != 'Tidak Terhubung' &&
                            !_isLanjutkanEnabled) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'WiFi tidak valid',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.orange,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],

                      const SizedBox(height: 10),

                      // === Firestore & Tombol Lanjutkan ===
                      if (_isLoadingFirestore && !_isSyncing) ...[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        const Text('Mengambil data Firestore...'),
                      ] else if (_firestoreError != null) ...[
                        Icon(Icons.error_outline,
                            size: 48, color: Colors.red.shade700),
                        const SizedBox(height: 12),
                        Text(
                          _firestoreError!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.login, size: 20),
                            label: const Text(
                              'Lanjutkan',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            onPressed: _isLanjutkanEnabled
                                ? () {
                                    final ipAddress = _firestoreData![_ssid];
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            RunTest(ipAddress: ipAddress),
                                      ),
                                    );
                                  }
                                : null,
                            style: ButtonStyle(
                              backgroundColor:
                                  MaterialStateProperty.resolveWith<Color>(
                                (states) {
                                  if (!_isLanjutkanEnabled)
                                    return Colors.grey.shade300;
                                  return states.contains(MaterialState.pressed)
                                      ? Colors.white
                                      : Colors.green;
                                },
                              ),
                              foregroundColor:
                                  MaterialStateProperty.resolveWith<Color>(
                                (states) {
                                  if (!_isLanjutkanEnabled)
                                    return Colors.black45;
                                  return states.contains(MaterialState.pressed)
                                      ? Colors.green
                                      : Colors.white;
                                },
                              ),
                              minimumSize: MaterialStateProperty.all(
                                  const Size.fromHeight(48)),
                              shape: MaterialStateProperty.all(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              elevation:
                                  MaterialStateProperty.resolveWith<double>(
                                (states) =>
                                    states.contains(MaterialState.pressed)
                                        ? 0
                                        : 3,
                              ),
                              shadowColor: MaterialStateProperty.all(
                                Colors.green.withOpacity(0.1),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}
