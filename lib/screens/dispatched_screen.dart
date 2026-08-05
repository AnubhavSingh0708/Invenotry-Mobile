import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/reel.dart';
import '../services/storage_service.dart';
import '../services/event_service.dart';

class DispatchedScreen extends StatefulWidget {
  const DispatchedScreen({super.key});

  @override
  State<DispatchedScreen> createState() => _DispatchedScreenState();
}

class _DispatchedScreenState extends State<DispatchedScreen> {
  List<Reel> _reels = [];
  bool _isLoading = true;
  String? _error;
  bool _isFetching = false; // Prevents overlapping concurrent requests

  StreamSubscription<void>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _fetchDispatchedReels();

    // Listen for any server changes and reload screen data automatically
    _eventSubscription = EventService().onServerChange.listen((_) {
      if (mounted) {
        _fetchDispatchedReels();
      }
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchDispatchedReels() async {
    // Avoid launching parallel fetch operations from rapid SSE events
    if (_isFetching) return;
    _isFetching = true;

    try {
      final session = await StorageService.getSession();
      final serverUrl = session['serverUrl'];
      final userId = session['userId'];
      final authKey = session['authKey'];

      final res = await http.get(
        Uri.parse('$serverUrl/api/billing?user_id=$userId&auth_key=$authKey'),
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        final fetchedReels = list.map((e) => Reel.fromJson(e)).toList();

        setState(() {
          _reels = fetchedReels;
          _error = null; // Clear any previous error state
          _isLoading = false;
        });
      } else {
        throw Exception("Server Error ${res.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    } finally {
      _isFetching = false;
    }
  }

  void _showDetailsModal(Reel reel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reel #${reel.reelId}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow('Size (CM)', '${reel.sizeCm}'),
              _infoRow('Weight (KG)', '${reel.weightKg}'),
              _infoRow('GSM', '${reel.gsm}'),
              _infoRow('BF', reel.bf),
              _infoRow('Colour', reel.colour),
              _infoRow('Quality', reel.quality),
              _infoRow('Party', reel.party ?? 'N/A'),
              _infoRow('Mfg Date', '${reel.date} ${reel.time}'),
              const Divider(),
              _infoRow('Dispatch Info', '${reel.dispatchDate} at ${reel.dispatchTime}', color: Colors.orange),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color ?? Colors.grey[700])),
          const SizedBox(width: 16.0),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markBilled(String reelId) async {
    final session = await StorageService.getSession();
    final now = DateTime.now();
    final dateStr = now.toIso8601String().split('T')[0];
    final timeStr = "${now.hour}:${now.minute}:${now.second}";

    final res = await http.post(
      Uri.parse('${session['serverUrl']}/api/billing/archive'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': int.parse(session['userId']!),
        'auth_key': session['authKey'],
        'reel_id': reelId,
        'billed_date': dateStr,
        'billed_time': timeStr,
      }),
    );

    if (res.statusCode == 200) {
      _fetchDispatchedReels();
    }
  }

  Future<void> _undispatch(String reelId) async {
    final session = await StorageService.getSession();
    final res = await http.post(
      Uri.parse('${session['serverUrl']}/api/dispatch/undo'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': int.parse(session['userId']!),
        'auth_key': session['authKey'],
        'reel_id': reelId,
      }),
    );

    if (res.statusCode == 200) {
      _fetchDispatchedReels();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dispatched Reels')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _fetchDispatchedReels,
              child: const Text('Retry'),
            )
          ],
        ),
      )
          : ListView.builder(
        itemCount: _reels.length,
        itemBuilder: (context, index) {
          final reel = _reels[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 6),
            child: ListTile(
              onTap: () => _showDetailsModal(reel),
              title: Text('Reel #${reel.reelId}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${reel.sizeCm} CM | ${reel.weightKg} KG\n${reel.dispatchDate} ${reel.dispatchTime}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    onPressed: () => _markBilled(reel.reelId),
                    tooltip: 'Mark Billed',
                  ),
                  IconButton(
                    icon: const Icon(Icons.undo, color: Colors.red),
                    onPressed: () => _undispatch(reel.reelId),
                    tooltip: 'Undispatch',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}