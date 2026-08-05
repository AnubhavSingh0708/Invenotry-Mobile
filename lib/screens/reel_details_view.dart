import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import '../models/reel.dart';
import '../services/storage_service.dart';
import 'map_screen.dart';

class ReelDetailsView extends StatefulWidget {
  final String monthCode;
  final String itemNumber;
  final String? rawQrUrl;

  const ReelDetailsView({
    Key? key,
    required this.monthCode,
    required this.itemNumber,
    this.rawQrUrl,
  }) : super(key: key);

  @override
  State<ReelDetailsView> createState() => _ReelDetailsViewState();
}

class _ReelDetailsViewState extends State<ReelDetailsView> {
  bool _isLoading = true;
  String? _errorMessage;
  Reel? _reel;
  dynamic _foundTableId; // Can be int or String depending on API

  String? _dispatchInfo;
  String? _billedInfo;

  String _serverUrl = '';
  int _userId = 0;
  String _authKey = '';

  @override
  void initState() {
    super.initState();
    _loadEnvAndFetchData();
  }

  Future<void> _loadEnvAndFetchData() async {
    final session = await StorageService.getSession();
    setState(() {
      _serverUrl = session['serverUrl']?.toString() ?? '';
      _userId = int.tryParse(session['userId']?.toString() ?? '0') ?? 0;
      _authKey = session['authKey']?.toString() ?? '';
    });

    await _fetchReelAndLocation();
  }

  Future<void> _fetchReelAndLocation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final int targetNumber = int.tryParse(widget.itemNumber) ?? 0;

      // 1. Primary API Search
      bool foundInApi = await _searchReelApi(targetNumber);

      // 2. Locate Table & Cell position (matches JS implementation logic)
      await _findTableAndCell(targetNumber, widget.monthCode.trim());

      // 3. Fallback to HTML lookup if not found in active Reels API
      if (!foundInApi) {
        await _fetchFromQrHtmlLookup();
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load reel details: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _searchReelApi(int targetId) async {
    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "user_id": _userId,
          "auth_key": _authKey,
          "target": "reels",
          "match": "all",
          "filters": [
            {"field": "id", "op": "eq", "value": targetId}
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['results'] != null && (data['results'] as List).isNotEmpty) {
          setState(() {
            _reel = Reel.fromJson(data['results'][0]);
          });
          return true;
        }
      }
    } catch (e) {
      debugPrint('Search API Error: $e');
    }
    return false;
  }

  Future<void> _findTableAndCell(int targetNumber, String searchMonth) async {
    try {
      final tablesUri = Uri.parse('$_serverUrl/api/tables?user_id=$_userId&auth_key=$_authKey');
      final tablesRes = await http.get(tablesUri);

      if (tablesRes.statusCode != 200) return;

      final tablesData = jsonDecode(tablesRes.body);
      final List tables = tablesData is List ? tablesData : (tablesData['results'] ?? []);

      if (tables.isEmpty) return;

      for (var table in tables) {
        final tableId = table['id'];
        final cellsUri = Uri.parse('$_serverUrl/api/table?user_id=$_userId&auth_key=$_authKey&table_id=$tableId');
        final cellsRes = await http.get(cellsUri);

        if (cellsRes.statusCode == 200) {
          final cellsData = jsonDecode(cellsRes.body);
          final List cells = cellsData is List ? cellsData : (cellsData['results'] ?? []);

          for (var cell in cells) {
            dynamic itemsRaw = cell['items'];
            List items = [];

            if (itemsRaw is String) {
              try {
                items = jsonDecode(itemsRaw);
              } catch (_) {}
            } else if (itemsRaw is List) {
              items = itemsRaw;
            }

            if (items.isNotEmpty) {
              bool hasMatch = items.any((item) {
                if (item is! Map) return false;

                final itemNum = int.tryParse(item['number']?.toString() ?? '');
                final monthCode = item['month_code']?.toString().trim();

                return itemNum == targetNumber &&
                    monthCode?.toUpperCase() == searchMonth.toUpperCase();
              });

              if (hasMatch) {
                setState(() {
                  _foundTableId = tableId;
                });
                return; // Stop searching once found
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error performing table location search: $e');
    }
  }

  Future<void> _fetchFromQrHtmlLookup() async {
    final String targetUrl = widget.rawQrUrl ??
        '$_serverUrl/lookupqr?id=${widget.monthCode}-${widget.itemNumber}';

    try {
      final res = await http.get(Uri.parse(targetUrl));
      if (res.statusCode == 200) {
        final document = parse(res.body);

        String extractVal(String labelName) {
          final labels = document.querySelectorAll('.label');
          for (var label in labels) {
            if (label.text.toLowerCase().contains(labelName.toLowerCase())) {
              final parent = label.parent;
              final valElem = parent?.querySelector('.value');
              if (valElem != null) return valElem.text.trim();
            }
          }
          return '';
        }

        double parseCleanDouble(String raw) {
          final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
          return double.tryParse(cleaned) ?? 0.0;
        }

        int parseCleanInt(String raw) {
          final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
          return double.tryParse(cleaned)?.toInt() ?? 0;
        }

        final String fullReelId = '${widget.monthCode}-${widget.itemNumber}';

        setState(() {
          _reel = Reel(
            id: int.tryParse(widget.itemNumber),
            reelId: fullReelId,
            sizeCm: parseCleanDouble(extractVal('Size')),
            weightKg: parseCleanDouble(extractVal('Weight')),
            gsm: parseCleanInt(extractVal('GSM')), // Properly handles floats or formatted GSM strings
            bf: extractVal('BF'),
            colour: extractVal('Colour'),
            quality: extractVal('Quality'),
            party: extractVal('Party'),
            date: extractVal('Mfg Date'),
            time: '',
          );

          _dispatchInfo = extractVal('Dispatch Info');
          _billedInfo = extractVal('Billed Info');
        });
      } else {
        setState(() {
          _errorMessage = 'Reel not found in active records or archives.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error looking up QR details: $e';
      });
    }
  }
  bool get _isDispatchedOrBilled {
    final hasDispatchInfo = _dispatchInfo != null && _dispatchInfo!.isNotEmpty;
    final hasBilledInfo = _billedInfo != null && _billedInfo!.isNotEmpty;
    final hasDispatchDate = _reel?.dispatchDate != null && _reel!.dispatchDate!.isNotEmpty;

    return hasDispatchInfo || hasBilledInfo || hasDispatchDate;
  }
  Future<void> _dispatchReel() async {
    if (_reel == null || _reel!.reelId.isEmpty) {
      _showAlert('Error', 'Reel ID not found for dispatch.');
      return;
    }

    final now = DateTime.now();
    final String dispatchDate =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final String dispatchTime =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    try {
      final res = await http.post(
        Uri.parse('$_serverUrl/api/dispatch/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "user_id": _userId,
          "auth_key": _authKey,
          "reel_id": _reel!.reelId,
          "dispatch_date": dispatchDate,
          "dispatch_time": dispatchTime,
        }),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        _showAlert('Success', 'Reel successfully dispatched!');
        _fetchReelAndLocation();
      } else {
        _showAlert('Failed', 'Failed to dispatch reel. Status: ${res.statusCode}');
      }
    } catch (e) {
      _showAlert('Error', 'Error connecting to dispatch API: $e');
    }
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            title: Text('Reel #${widget.monthCode}-${widget.itemNumber}'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            )
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            )
          else if (_reel != null) ...[
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Card(
                        color: Colors.blue.shade50,
                        child: ListTile(
                          leading: const Icon(Icons.pin_drop, color: Colors.blue),
                          title: const Text('Current Storage Location'),
                          subtitle: Text(
                            _foundTableId != null
                                ? 'Found in Table ID: $_foundTableId'
                                : 'Location not assigned to any active table',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        childAspectRatio: 2.5,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildDetailItem('Size (CM)', _reel!.sizeCm.toStringAsFixed(2)),
                          _buildDetailItem('Weight (KG)', _reel!.weightKg.toStringAsFixed(2)),
                          _buildDetailItem('GSM', _reel!.gsm.toString()),
                          _buildDetailItem('BF', _reel!.bf),
                          _buildDetailItem('Colour', _reel!.colour),
                          _buildDetailItem('Quality', _reel!.quality),
                          _buildDetailItem('Party', _reel!.party ?? 'N/A'),
                          _buildDetailItem('Mfg Date', '${_reel!.date} ${_reel!.time}'),
                        ],
                      ),
                      if (_dispatchInfo != null && _dispatchInfo!.isNotEmpty)
                        _buildInfoBanner('Dispatch Info', _dispatchInfo!, Colors.orange),
                      if (_billedInfo != null && _billedInfo!.isNotEmpty)
                        _buildInfoBanner('Billed Info', _billedInfo!, Colors.green),
                    ],
                  ),
                ),
              ),

              // Show bottom action bar ONLY if the reel is NOT dispatched or billed
              if (!_isDispatchedOrBilled)
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _dispatchReel,
                            icon: const Icon(Icons.local_shipping, color: Colors.white),
                            label: const Text('Dispatch Reel', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => MapScreen(
                                    searchItem:int.tryParse(widget.itemNumber),
                                    searchMonth: widget.monthCode,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.map, color: Colors.white),
                            label: const Text('View Location', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ]
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildInfoBanner(String label, String value, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}