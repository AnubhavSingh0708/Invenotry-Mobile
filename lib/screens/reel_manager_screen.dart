import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/reel.dart';
import '../services/storage_service.dart';
import 'edit_reel_screen.dart';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:async';
import '../services/event_service.dart';


class ReelManagerScreen extends StatefulWidget {
  const ReelManagerScreen({Key? key}) : super(key: key);

  @override
  _ReelManagerScreenState createState() => _ReelManagerScreenState();
}

class _ReelManagerScreenState extends State<ReelManagerScreen> {
  //refresh





  List<Reel> reels = [];
  bool isLoading = true;
  int currentStart = 0;
  final int limit = 20;

  String serverUrl = '';
  String userId = '';
  String authKey = '';



  StreamSubscription<void>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _initSession();

    // Listen for any server changes and reload screen data automatically
    _eventSubscription = EventService().onServerChange.listen((_) {
      if (mounted) {
        _initSession();
      }
    });
  }

  @override
  void dispose() {
    // Cancel subscription when navigating away to prevent memory leaks
    _eventSubscription?.cancel();
    super.dispose();
  }


  Future<void> _initSession() async {
    final session = await StorageService.getSession();
    setState(() {
      serverUrl = session['serverUrl'] ?? '';
      userId = session['userId'] ?? '';
      authKey = session['authKey'] ?? '';
    });
    _fetchReels();
  }

  Future<void> _fetchReels({bool loadMore = false}) async {
    if (serverUrl.isEmpty) return;

    if (!loadMore) {
      setState(() {
        isLoading = true;
        currentStart = 0;
        reels.clear();
      });
    }



    final end = currentStart + limit - 1;
    final url = '$serverUrl/api/reels?user_id=$userId&auth_key=$authKey&start=$currentStart&end=$end';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          reels.addAll(data.map((json) => Reel.fromJson(json)).toList());
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load reels: $e')),
      );
    }
  }



  Future<void> _deleteReel(Reel reel) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reel'),
        content: Text('Delete Reel ${reel.reelId}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    // Using reelId as the identifier based on the model provided
    final url = '$serverUrl/api/reel/remove';
    try {
      await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': int.parse(userId),
          'auth_key': authKey,
          'id': reel.id
        }),
      );
      _fetchReels();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  /// Generates the PDF layout and opens the system print dialog for a specific Reel
  Future<void> _printReelDetails(Reel reel) async {
    try {
      // Build QR Code endpoint URL
      final qrText = '$serverUrl/lookupqr?id=${Uri.encodeComponent(reel.reelId)}';
      final qrUrl = '$serverUrl/api/qrcode?user_id=$userId&auth_key=${Uri.encodeComponent(authKey)}&text=${Uri.encodeComponent(qrText)}&size=512';

      // Fetch QR Code image bytes
      final response = await http.get(Uri.parse(qrUrl));
      if (response.statusCode != 200) throw Exception("Failed to fetch QR Code");
      final Uint8List qrBytes = response.bodyBytes;

      final doc = pw.Document();
      final qrImage = pw.MemoryImage(qrBytes);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(24),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 2),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Image(qrImage, width: 200, height: 200),
                    pw.SizedBox(height: 12),
                    pw.Text(
                      reel.reelId,
                      style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Party: ${reel.party ?? "N/A"}',
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Text(
                      'Weight: ${reel.weightKg} kg  |  GSM: ${reel.gsm}',
                      style: const pw.TextStyle(fontSize: 16),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Colour: ${reel.colour}  |  Size: ${reel.sizeCm} cm',
                      style: const pw.TextStyle(fontSize: 16),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Quality: ${reel.quality}  |  BF: ${reel.bf}',
                      style: const pw.TextStyle(fontSize: 16),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Text(
                      'Date: ${reel.date} ${reel.time}',
                      style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      // Trigger standard system printer print job
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Reel_Label_${reel.reelId}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print label: $e')),
        );
      }
    }
  }

  /// Displays the view dialog and includes a print action button
  void _showReelDetails(Reel reel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reel Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID: ${reel.reelId}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Weight: ${reel.weightKg} kg'),
              Text('Size: ${reel.sizeCm} cm'),
              Text('GSM: ${reel.gsm}'),
              Text('BF: ${reel.bf}'),
              Text('Colour: ${reel.colour}'),
              Text('Quality: ${reel.quality}'),
              Text('Party: ${reel.party ?? "N/A"}'),
              Text('Date: ${reel.date} ${reel.time}'),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            onPressed: () {
              Navigator.pop(context); // Optional: close dialog before printing
              _printReelDetails(reel);
            },
            icon: const Icon(Icons.print, color: Colors.white, size: 18),
            label: const Text('Print Label', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reel Labeling'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // Handle Logout logic
            },
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Wrap(
              spacing: 12.0,
              runSpacing: 12.0,
              children: reels.map((reel) {
                return SizedBox(
                  width: MediaQuery.of(context).size.width * 0.43, // Responsive wrap width
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: InkWell(
                      onTap: () => _showReelDetails(reel),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    reel.reelId,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'View') _showReelDetails(reel);
                                    if (value == 'Edit') {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => EditReelScreen(reel: reel)),
                                      ).then((_) => _fetchReels());
                                    }
                                    if (value == 'Delete') _deleteReel(reel);
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(value: 'View', child: Text('View')),
                                    const PopupMenuItem(value: 'Edit', child: Text('Edit')),
                                    const PopupMenuItem(value: 'Delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                                  ],
                                )
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('${reel.weightKg} kg'),
                            Text(reel.party ?? 'No Party', overflow: TextOverflow.ellipsis),
                            Text(reel.date, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                setState(() => currentStart += limit);
                _fetchReels(loadMore: true);
              },
              child: const Text('Load More'),
            )
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EditReelScreen()), // Null passed by default for adding
          ).then((_) => _fetchReels());
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}