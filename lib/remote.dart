import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'run_test.dart';

class RemoteAccess extends StatefulWidget {
  const RemoteAccess({Key? key}) : super(key: key);

  @override
  State<RemoteAccess> createState() => _RemoteAccessState();
}

class _RemoteAccessState extends State<RemoteAccess> {
  @override
  void initState() {
    super.initState();
    _navigateToTest();
  }

  Future<void> _navigateToTest() async {
    final prefs = await SharedPreferences.getInstance();
    final link = prefs.getString('online_test_link');

    // Ensure the widget is still mounted before navigating
    if (!mounted) return;

    if (link != null && link.isNotEmpty) {
      // Replace the current page with RunTest
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => RunTest(ipAddress: link)),
      );
    } else {
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

  @override
  Widget build(BuildContext context) {
    // Show a loading indicator while we check for the link and navigate
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}