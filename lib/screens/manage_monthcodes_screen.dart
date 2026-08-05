import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/storage_service.dart';

class ManageMonthcodesScreen extends StatefulWidget {
  const ManageMonthcodesScreen({super.key});

  @override
  State<ManageMonthcodesScreen> createState() => _ManageMonthcodesScreenState();
}

class _ManageMonthcodesScreenState extends State<ManageMonthcodesScreen> {
  final _inputController = TextEditingController();
  List<Map<String, dynamic>> _monthcodes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMonthcodes();
  }

  Future<void> _loadMonthcodes() async {
    setState(() => _isLoading = true);
    final session = await StorageService.getSession();

    try {
      final res = await http.get(
        Uri.parse('${session['serverUrl']}/api/monthcodes?user_id=${session['userId']}&auth_key=${session['authKey']}'),
      );
      if (res.statusCode == 200) {
        setState(() {
          _monthcodes = List<Map<String, dynamic>>.from(jsonDecode(res.body));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error loading monthcodes')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addMonthcode() async {
    final code = _inputController.text.trim();
    if (code.isEmpty) return;

    final session = await StorageService.getSession();
    final res = await http.post(
      Uri.parse('${session['serverUrl']}/api/monthcode/add'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': int.parse(session['userId']!),
        'auth_key': session['authKey'],
        'code': code,
      }),
    );

    if (res.statusCode == 200) {
      _inputController.clear();
      _loadMonthcodes();
    }
  }

  Future<void> _deleteMonthcode(int id) async {
    final session = await StorageService.getSession();
    final res = await http.post(
      Uri.parse('${session['serverUrl']}/api/monthcode/remove'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': int.parse(session['userId']!),
        'auth_key': session['authKey'],
        'id': id,
      }),
    );

    if (res.statusCode == 200) {
      _loadMonthcodes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Monthcodes')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    decoration: const InputDecoration(
                      labelText: 'New Monthcode',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _addMonthcode,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                itemCount: _monthcodes.length,
                itemBuilder: (context, index) {
                  final code = _monthcodes[index];
                  return Card(
                    child: ListTile(
                      title: Text(code['code'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: IconButton(
                        icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                        onPressed: () => _deleteMonthcode(code['id']),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}