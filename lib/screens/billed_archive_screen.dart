import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/reel.dart';
import '../services/storage_service.dart';

class BilledArchiveScreen extends StatefulWidget {
  const BilledArchiveScreen({super.key});

  @override
  State<BilledArchiveScreen> createState() => _BilledArchiveScreenState();
}

class _BilledArchiveScreenState extends State<BilledArchiveScreen> {
  List<Reel> _reels = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  int _offset = 0;
  final int _limit = 100;

  @override
  void initState() {
    super.initState();
    _fetchBilledArchive();
  }

  Future<void> _fetchBilledArchive({bool isLoadMore = false}) async {
    if (isLoadMore) {
      if (_isLoadingMore || !_hasMore) return;
      setState(() {
        _isLoadingMore = true;
      });
    } else {
      setState(() {
        _isLoading = true;
        _error = null;
        _offset = 0;
        _reels.clear();
        _hasMore = true;
      });
    }

    try {
      final session = await StorageService.getSession();
      final serverUrl = session['serverUrl'];

      final uri = Uri.parse(
        '$serverUrl/api/billed_archive?limit=$_limit&offset=$_offset',
      );

      final res = await http.get(uri,headers: {
            'Content-Type': 'application/json',
            'X-User-ID': '${session['userId']}',
            'X-Auth-Key': '${session['authKey']}',
  });

      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        final fetchedReels = list.map((e) => Reel.fromJson(e)).toList();

        setState(() {
          // If fetched items are fewer than limit, we've reached the end of the data
          if (fetchedReels.length < _limit) {
            _hasMore = false;
          }

          _reels.addAll(fetchedReels);
          _offset += fetchedReels.length;
        });
      } else {
        throw Exception("Failed to load archive");
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _showDetailsModal(Reel reel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archived Reel #${reel.reelId}'),
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
              _infoRow('Billed Info', '${reel.billedDate} at ${reel.billedTime}', color: Colors.green),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Billed Reels Archive')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _reels.isEmpty
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : _reels.isEmpty
          ? const Center(child: Text('No archived reels found.'))
          : ListView.builder(
        itemCount: _reels.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          // Render the Load More button / Loader at the end of the list
          if (index == _reels.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
              child: Center(
                child: _isLoadingMore
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                  onPressed: () => _fetchBilledArchive(isLoadMore: true),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Load More'),
                ),
              ),
            );
          }

          final reel = _reels[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              onTap: () => _showDetailsModal(reel),
              title: Text('Reel #${reel.reelId}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${reel.sizeCm} CM | ${reel.weightKg} KG\nBilled: ${reel.billedDate}'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'ARCHIVED',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
