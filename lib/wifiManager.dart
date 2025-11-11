import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WifiManagerPage extends StatefulWidget {
  const WifiManagerPage({super.key});

  @override
  State<WifiManagerPage> createState() => _WifiManagerPageState();
}

class _WifiManagerPageState extends State<WifiManagerPage> {
  List<WifiNetwork?> _wifiList = [];
  bool _isLoading = false;
  String? _errorMessage;

  String? _connectedSSID;
  String? _connectingSSID;

  late SharedPreferences _prefs;
  bool _prefsReady = false;

  @override
  void initState() {
    super.initState();
    _initPrefsAndScan();
  }

  Future<void> _initPrefsAndScan() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _prefsReady = true;
    });
    await _checkPermissionAndScan();
  }

  Future<void> _checkPermissionAndScan() async {
    setState(() {
      _errorMessage = null;
    });

    var status = await Permission.location.status;
    if (!status.isGranted) {
      status = await Permission.location.request();
    }

    if (status.isGranted) {
      await _scanWifi();
      await _checkCurrentConnection();
    } else {
      setState(() {
        _errorMessage = 'Permission lokasi ditolak. Tidak bisa memindai WiFi.';
      });
    }
  }

  Future<void> _checkCurrentConnection() async {
    try {
      final connectedSSID = await WiFiForIoTPlugin.getSSID();
      if (!mounted) return;
      setState(() {
        _connectedSSID = connectedSSID;
      });
    } catch (_) {}
  }

  Future<void> _scanWifi() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await WiFiForIoTPlugin.loadWifiList().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Timeout memindai jaringan WiFi'),
      );

      if (!mounted) return;

      setState(() {
        _wifiList = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Gagal memindai WiFi: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _connectToNetwork(String ssid) async {
    if (!_prefsReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('SharedPreferences belum siap. Coba lagi.')),
      );
      return;
    }

    if (ssid.isEmpty) return;

    final passwordKey = 'wifi_password_$ssid';
    String? savedPassword = _prefs.getString(passwordKey);
    String password = savedPassword ?? '';

    final passwordController = TextEditingController(text: password);

    final shouldConnect = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sambungkan ke $ssid'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password WiFi'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: const Text('Batal'),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            child: const Text('Sambungkan'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (shouldConnect != true) return;
    password = passwordController.text;

    setState(() {
      _connectingSSID = ssid;
    });

    bool connected = false;
    String message = 'Mencoba sambungkan ke $ssid...';

    try {
      print("Mencoba menyambungkan ke SSID: $ssid dengan password: $password");

      connected = await WiFiForIoTPlugin.connect(
        ssid,
        password: password,
        security: NetworkSecurity.WPA,
        joinOnce: false, // Ganti ke false untuk mencegah buka pengaturan
      );

      print("Hasil koneksi ke $ssid: $connected");

      message = connected
          ? 'Berhasil tersambung ke $ssid'
          : 'Gagal tersambung ke $ssid';

      if (connected) {
        await _prefs.setString(passwordKey, password);
        setState(() {
          _connectedSSID = ssid;
        });
      }
    } catch (e) {
      message = 'Terjadi kesalahan saat menyambung: $e';
    } finally {
      if (mounted) {
        setState(() {
          _connectingSSID = null;
        });
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _forgetNetwork(String ssid) async {
    if (!_prefsReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('SharedPreferences belum siap. Coba lagi.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Lupakan jaringan $ssid?'),
        content: const Text('Anda yakin ingin melupakan jaringan ini?'),
        actions: [
          TextButton(
            child: const Text('Batal'),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            child: const Text('Lupakan'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      String message;
      try {
        final result = await WiFiForIoTPlugin.removeWifiNetwork(ssid);
        message = result
            ? 'Berhasil melupakan jaringan $ssid'
            : 'Gagal melupakan jaringan $ssid';

        final passwordKey = 'wifi_password_$ssid';
        await _prefs.remove(passwordKey);

        if (_connectedSSID == ssid) {
          setState(() {
            _connectedSSID = null;
          });
        }
      } catch (e) {
        message = 'Terjadi kesalahan saat melupakan jaringan: $e';
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      _scanWifi();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    List<WifiNetwork?> connectedList = [];
    List<WifiNetwork?> otherList = [];

    for (var network in _wifiList) {
      if (network?.ssid == _connectedSSID) {
        connectedList.add(network);
      } else {
        otherList.add(network);
      }
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Manajer WiFi'),
        backgroundColor: Colors.blue.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _checkPermissionAndScan();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Daftar WiFi diperbarui')),
              );
            },
            tooltip: 'Segarkan daftar WiFi',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _wifiList.isEmpty
                  ? const Center(
                      child: Text('Tidak ada jaringan WiFi ditemukan.'))
                  : RefreshIndicator(
                      onRefresh: _scanWifi,
                      child: ListView(
                        children: [
                          if (connectedList.isNotEmpty) ...[
                            _buildWifiTile(connectedList.first!, true),
                            const SizedBox(height: 20),
                            const Divider(),
                          ],
                          ...otherList
                              .map((network) => _buildWifiTile(network!, false))
                              ,
                        ],
                      ),
                    ),
    );
  }

  Widget _buildWifiTile(WifiNetwork network, bool isConnected) {
    final ssid = network.ssid ?? 'Unknown';
    final level = network.level;
    final isConnecting = _connectingSSID == ssid;

    String subtitleText;
    if (isConnecting) {
      subtitleText = 'Menyambungkan...';
    } else if (isConnected) {
      subtitleText = 'Tersambung';
    } else {
      subtitleText = 'Level sinyal: ${level ?? 'Tidak diketahui'}';
    }

    return ListTile(
      title: Text(ssid),
      subtitle: Text(subtitleText),
      trailing: isConnected
          ? const Icon(Icons.check_circle, color: Colors.green)
          : IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              tooltip: 'Lupakan jaringan',
              onPressed: () => _forgetNetwork(ssid),
            ),
      onTap: () => _connectToNetwork(ssid),
    );
  }
}
