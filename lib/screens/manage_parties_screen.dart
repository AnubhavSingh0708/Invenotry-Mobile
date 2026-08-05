import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/storage_service.dart';

class ManagePartiesScreen extends StatefulWidget {
  const ManagePartiesScreen({super.key});

  @override
  State<ManagePartiesScreen> createState() => _ManagePartiesScreenState();
}

class _ManagePartiesScreenState extends State<ManagePartiesScreen> {
  final _inputController = TextEditingController();
  List<Map<String, dynamic>> _parties = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadParties();
  }

  Future<void> _loadParties() async {
    setState(() => _isLoading = true);
    final session = await StorageService.getSession();

    try {
      final res = await http.get(
        Uri.parse('${session['serverUrl']}/api/parties?user_id=${session['userId']}&auth_key=${session['authKey']}'),
      );
      if (res.statusCode == 200) {
        setState(() {
          _parties = List<Map<String, dynamic>>.from(jsonDecode(res.body));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error loading parties')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addParty() async {
    final name = _inputController.text.trim();
    if (name.isEmpty) return;

    final session = await StorageService.getSession();
    final res = await http.post(
      Uri.parse('${session['serverUrl']}/api/party/add'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': int.parse(session['userId']!),
        'auth_key': session['authKey'],
        'party': {'name': name},
      }),
    );

    if (res.statusCode == 200) {
      _inputController.clear();
      _loadParties();
    }
  }

  Future<void> _deleteParty(int id) async {
    final session = await StorageService.getSession();
    final res = await http.post(
      Uri.parse('${session['serverUrl']}/api/party/remove'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': int.parse(session['userId']!),
        'auth_key': session['authKey'],
        'id': id,
      }),
    );

    if (res.statusCode == 200) {
      _loadParties();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Parties')),
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
                      labelText: 'New Party Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _addParty,
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
                itemCount: _parties.length,
                itemBuilder: (context, index) {
                  final party = _parties[index];
                  return Card(
                    child: ListTile(
                      title: Text(party['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: IconButton(
                        icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                        onPressed: () => _deleteParty(party['id']),
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