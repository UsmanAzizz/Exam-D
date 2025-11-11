import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'run_test.dart';

class RemoteAccess extends StatefulWidget {
  const RemoteAccess({super.key});

  @override
  State<RemoteAccess> createState() => _RemoteAccessState();
}

class _RemoteAccessState extends State<RemoteAccess> {
  static const MethodChannel _windowModeChannel =
      MethodChannel('com.example.webdipo/window_mode');

  bool _pinningAttempted = false;
  bool _alreadyNavigated = false;
  bool _isLoadingPinning = true;
  String? _onlineTestLink;
  String _pinningStatusMessage = 'Menyiapkan mode ujian aman...';
  IconData? _pinningStatusIcon;
  Timer? _lockTaskCheckTimer;
  int _countdown = 3;

  @override
  void initState() {
    super.initState();
    debugPrint('[RemoteAccess] initState');
    _navigateToTest();
  }

  Future<void> _navigateToTest() async {
    final prefs = await SharedPreferences.getInstance();
    final link = prefs.getString('online_test_link');

    debugPrint('[RemoteAccess] online_test_link: $link');

    if (!mounted) return;

    if (link != null && link.isNotEmpty) {
      setState(() {
        _onlineTestLink = link;
        _isLoadingPinning = true;
      });
      _startPinningProcess();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Link ujian online tidak ditemukan. Silakan sinkronkan konfigurasi.'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _startPinningProcess() async {
    if (_pinningAttempted) return;
    _pinningAttempted = true;

    debugPrint('[RemoteAccess] Memulai proses LockTask...');
    final started = await LockTaskHelper.startLockTask();
    debugPrint('[RemoteAccess] LockTask start result: $started');

    if (!started) {
      if (mounted) {
        setState(() {
          _pinningStatusMessage =
              'Gagal memulai mode aman.\nPastikan izin Device Admin aktif.';
          _pinningStatusIcon = Icons.error_outline_rounded;
          _isLoadingPinning = false;
        });
      }
      return;
    }

    setState(() {
      _pinningStatusMessage = 'Mengaktifkan mode ujian aman';
      _pinningStatusIcon = null;
      _isLoadingPinning = true;
    });

    _lockTaskCheckTimer?.cancel();
    _lockTaskCheckTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) async {
      final isLockTaskActive = await LockTaskHelper.checkLockTask();
      debugPrint('[RemoteAccess] Monitoring: isLockTaskActive = $isLockTaskActive');

      if (isLockTaskActive) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _pinningStatusIcon = Icons.check_circle_rounded;
            _pinningStatusMessage =
                'Mengaktifkan mode aman..\nMemulai tes dalam $_countdown...';
            _isLoadingPinning = false;
          });

          // Countdown 3-2-1 sebelum navigasi
          Timer.periodic(const Duration(seconds: 1), (countdownTimer) {
            if (!mounted) {
              countdownTimer.cancel();
              return;
            }

            if (_countdown == 1) {
              countdownTimer.cancel();
              if (!_alreadyNavigated) {
                _alreadyNavigated = true;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RunTest(ipAddress: _onlineTestLink!),
                  ),
                );
              }
            } else {
              setState(() {
                _countdown--;
                _pinningStatusMessage =
                    'Mengaktifkan mode aman..\nMemulai tes dalam $_countdown...';
              });
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _pinningStatusMessage =
                'Mode aman belum aktif.\nMohon konfirmasi jika diminta.';
            _pinningStatusIcon = Icons.warning_amber_rounded;
            _isLoadingPinning = false;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _lockTaskCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Column(
                key: ValueKey(_pinningStatusMessage),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _pinningStatusIcon == Icons.error_outline_rounded
                          ? Colors.red.shade50
                          : _pinningStatusIcon == Icons.warning_amber_rounded
                              ? Colors.amber.shade50
                              : _pinningStatusIcon == Icons.check_circle_rounded
                                  ? Colors.green.shade50
                                  : accent.withOpacity(0.12),
                      border: Border.all(
                        color: _pinningStatusIcon == Icons.error_outline_rounded
                            ? Colors.red.shade400
                            : _pinningStatusIcon == Icons.warning_amber_rounded
                                ? Colors.amber.shade400
                                : _pinningStatusIcon == Icons.check_circle_rounded
                                    ? Colors.green.shade400
                                    : accent.withOpacity(0.25),
                        width: 1.5,
                      ),
                    ),
                    child: _pinningStatusIcon != null
                        ? Icon(
                            _pinningStatusIcon,
                            size: 60,
                            color: _pinningStatusIcon == Icons.error_outline_rounded
                                ? Colors.red.shade700
                                : _pinningStatusIcon == Icons.warning_amber_rounded
                                    ? Colors.amber.shade700
                                    : Colors.green.shade700,
                          )
                        : SizedBox(
                            width: 48,
                            height: 48,
                            child: CircularProgressIndicator(
                              color: accent,
                              strokeWidth: 3,
                            ),
                          ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _pinningStatusMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_pinningStatusIcon == null)
                    Text(
                      '(Mohon konfirmasi pin layar jika diminta)',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 40),
                  if (!_isLoadingPinning &&
                      _pinningStatusIcon != Icons.check_circle_rounded)
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Coba Lagi'),
                      onPressed: () {
                        setState(() {
                          _pinningAttempted = false;
                          _startPinningProcess();
                        });
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
