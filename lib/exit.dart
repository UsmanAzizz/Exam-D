import 'package:flutter/material.dart';

class ExitSuccessPage extends StatefulWidget {
  const ExitSuccessPage({super.key});

  @override
  State<ExitSuccessPage> createState() => _ExitSuccessPageState();
}

class _ExitSuccessPageState extends State<ExitSuccessPage> {
  @override
  void initState() {
    super.initState();
    // Otomatis navigasi ke login setelah 2 detik
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 120,
              ),
              const SizedBox(height: 24),
              const Text(
                'Tes Selesai!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Terima kasih sudah menyelesaikan tes.\nAnda akan diarahkan ke halaman login.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 30),
              const CircularProgressIndicator(
                color: Colors.green,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
