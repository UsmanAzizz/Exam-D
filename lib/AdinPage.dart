import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  Map<String, String> localData = {};

  @override
  void initState() {
    super.initState();
    _loadLocalData();
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    Map<String, String> data = {};
    for (var key in keys) {
      final value = prefs.get(key);
      data[key] = value?.toString() ?? '';
    }
    setState(() {
      localData = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administrator Panel'),
        centerTitle: true,
        backgroundColor: Colors.blueGrey.shade800,
      ),
      body: localData.isEmpty
          ? const Center(
              child: Text(
                'Tidak ada data di local storage',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: localData.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final key = localData.keys.elementAt(index);
                final value = localData[key]!;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        key,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        value,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
