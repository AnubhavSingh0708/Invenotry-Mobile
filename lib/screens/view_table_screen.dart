import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/reel.dart';
import '../services/storage_service.dart';
import '../services/event_service.dart';
import 'add_using_qr_view.dart';

class ViewTableScreen extends StatefulWidget {
  final String tableId;
  final int? searchItem;
  final String? searchMonth;

  const ViewTableScreen({
    Key? key,
    required this.tableId,
    this.searchItem,
    this.searchMonth,
  }) : super(key: key);

  @override
  State<ViewTableScreen> createState() => _ViewTableScreenState();
}

class _ViewTableScreenState extends State<ViewTableScreen> with SingleTickerProviderStateMixin {
  String serverUrl = '';
  String userId = '';
  String authKey = '';

  bool _isLoading = true;
  bool _isFetching = false;
  bool _isModalOpen = false; // Flag to prevent SSE reloads during active modal sessions

  List<dynamic> _cellsData = [];

  int _maxRows = 4;
  int _maxCols = 6;
  bool _isVertical = false;

  int? _activeSearchItem;
  String? _activeSearchMonth;

  late AnimationController _pulseController;
  StreamSubscription<void>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _activeSearchItem = widget.searchItem;
    _activeSearchMonth = widget.searchMonth;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _loadSessionAndData();

    // Listen for server changes; auto-reload ONLY if no modal/dialog is currently active
    _eventSubscription = EventService().onServerChange.listen((_) {
      if (mounted && !_isModalOpen) {
        _fetchTableDetails();
      }
    });

    if (_activeSearchItem != null) {
      Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _activeSearchItem = null;
            _activeSearchMonth = null;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadSessionAndData() async {
    final session = await StorageService.getSession();
    if (!mounted) return;
    setState(() {
      serverUrl = session['serverUrl'] ?? '';
      userId = session['userId'] ?? '';
      authKey = session['authKey'] ?? '';
    });

    await _fetchTableDetails();
  }

  Future<void> _fetchTableDetails() async {
    if (_isFetching) return;
    _isFetching = true;

    // Show full-screen loader only on initial load to avoid UI flickering during live SSE updates
    if (_cellsData.isEmpty && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final cellSizeUri = Uri.parse('$serverUrl/api/cellsize?user_id=$userId&auth_key=$authKey&table_id=${widget.tableId}');
      final cellRes = await http.get(cellSizeUri);

      if (cellRes.statusCode == 200) {
        final sz = jsonDecode(cellRes.body);
        _maxRows = sz['rows'] ?? _maxRows;
        _maxCols = sz['cols'] ?? sz['columns'] ?? _maxCols;
        _isVertical = (sz['stack_type'] ?? '') == 'vertical';
      }

      final tableUri = Uri.parse('$serverUrl/api/table?user_id=$userId&auth_key=$authKey&table_id=${widget.tableId}');
      final tableRes = await http.get(tableUri);

      if (!mounted) return;

      if (tableRes.statusCode == 200) {
        setState(() {
          _cellsData = jsonDecode(tableRes.body);
        });
      }
    } catch (e) {
      debugPrint("Error loading table details: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _isFetching = false;
    }
  }

  Color _parseColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return const Color(0xFF34495E);
    try {
      final hex = colorStr.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF34495E);
    }
  }

  /// Checks if a position (x, y) can support a reel based on current stack rules (0-indexed)
  bool _isSlotSupported(Set<String> filledSet, int x, int y) {
    if (y == 0) return true; // Base level is always valid

    if (_isVertical) {
      // Vertical Stacking: Requires reel directly below it at (x, y - 1)
      return filledSet.contains('$x-${y - 1}');
    } else {
      // Horizontal Pyramid Stacking: Requires two supporting reels at (x, y - 1) and (x + 1, y - 1)
      return filledSet.contains('$x-${y - 1}') && filledSet.contains('${x + 1}-${y - 1}');
    }
  }

  // View Reel Metadata Modal
  void _viewReel(int itemNumber, String monthCode, int row, int col) async {
    try {
      final res = await http.post(
        Uri.parse('$serverUrl/api/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': int.tryParse(userId) ?? 0,
          'auth_key': authKey,
          'target': 'reels',
          'match': 'all',
          'filters': [
            {'field': 'item_number', 'op': 'eq', 'value': itemNumber},
            {'field': 'month_code', 'op': 'eq', 'value': monthCode}
          ]
        }),
      );

      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        if (data['count'] > 0) {
          final reel = Reel.fromJson(data['results'][0]);
          _showReelDetailsDialog(reel, row, col, itemNumber);
        }
      }
    } catch (e) {
      debugPrint("Error viewing reel: $e");
    }
  }

  Future<void> _showReelDetailsDialog(Reel reel, int row, int col, int itemNumber) async {
    _isModalOpen = true;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Reel ID: ${reel.reelId}'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                Text('Party: ${reel.party ?? "N/A"}'),
                Text('Quality: ${reel.quality}'),
                Text('Colour: ${reel.colour}'),
                Text('GSM: ${reel.gsm}'),
                Text('BF: ${reel.bf}'),
                Text('Size: ${reel.sizeCm} cm'),
                Text('Weight: ${reel.weightKg} kg'),
                Text('Date: ${reel.date} ${reel.time}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(context);
                await _removeReelFromCell(row, col, itemNumber);
              },
              child: const Text('Remove from Cell'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                Navigator.pop(context);
                await _dispatchReel(reel.reelId, row, col, itemNumber);
              },
              child: const Text('Dispatch Reel'),
            ),
          ],
        );
      },
    );

    _isModalOpen = false;
    _fetchTableDetails(); // Refresh after modal dismisses
  }

  // Add Reel to Blank Slot Modal
  Future<void> _openAddModal(int r, int c, int x, int y) async {
    _isModalOpen = true;
    List<dynamic> unassignedReels = [];

    try {
      final res = await http.get(
        Uri.parse('$serverUrl/api/reels/unassigned?user_id=$userId&auth_key=$authKey'),
      );

      if (res.statusCode == 200) {
        unassignedReels = jsonDecode(res.body) as List;
      } else {
        debugPrint("Failed to load unassigned reels: ${res.statusCode}");
      }
    } catch (e) {
      debugPrint("Error fetching unassigned reels: $e");
    }

    String? selectedReelJson;

    if (!mounted) {
      _isModalOpen = false;
      return;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF4A90D9)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Scan QR Code',
                    onPressed: () async {
                      Navigator.pop(context);
                      final qrResult = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AddUsingQrView(serverUrl: serverUrl),
                        ),
                      );

                      if (qrResult != null && qrResult is Map) {
                        final String? monthCode = qrResult['monthCode'];
                        final int? itemNum = qrResult['itemNumber'];
                        final bool isDispatchedOrBilled = qrResult['isDispatchedOrBilled'] ?? false;

                        if (monthCode != null && itemNum != null) {
                          await _processQrAddReel(
                            itemNum,
                            monthCode,
                            r,
                            c,
                            x,
                            y,
                            isDispatchedOrBilled,
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  const Text('Add Reel to Slot', style: TextStyle(fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Grid Position: [$r, $c] -> Layer $y, Slot $x',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  DropdownButton<String>(
                    isExpanded: true,
                    hint: Text(
                      unassignedReels.isEmpty
                          ? '-- No Unassigned Reels Available --'
                          : '-- Select Unassigned Reel --',
                    ),
                    value: selectedReelJson,
                    items: unassignedReels.map((reel) {
                      final val = jsonEncode({
                        'number': reel['item_number'],
                        'month_code': reel['month_code'],
                      });
                      return DropdownMenuItem<String>(
                        value: val,
                        child: Text(
                          'ID: ${reel['reel_id']} (${reel['item_number']}, ${reel['month_code']})',
                        ),
                      );
                    }).toList(),
                    onChanged: unassignedReels.isEmpty
                        ? null
                        : (val) {
                      setModalState(() => selectedReelJson = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: selectedReelJson == null
                      ? null
                      : () async {
                    Navigator.pop(context);
                    final data = jsonDecode(selectedReelJson!);
                    await _confirmAddReel(
                      data['number'],
                      data['month_code'],
                      r,
                      c,
                      x,
                      y,
                    );
                  },
                  child: const Text('Snap to Position'),
                ),
              ],
            );
          },
        );
      },
    );

    _isModalOpen = false;
    _fetchTableDetails(); // Refresh after modal closes
  }

  Future<void> _confirmAddReel(int item, String monthCode, int r, int c, int x, int y) async {
    try {
      final res = await http.post(
        Uri.parse('$serverUrl/api/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': int.tryParse(userId) ?? 0,
          'auth_key': authKey,
          'table_id': widget.tableId,
          'item': item,
          'month_code': monthCode,
          'row': r,
          'col': c,
          'x': x,
          'y': y,
        }),
      );

      if (res.statusCode == 200) {
        _fetchTableDetails();
      }
    } catch (e) {
      debugPrint("Error adding reel: $e");
    }
  }

  // Compact & Scaled Rearrange Modal
  Future<void> _openRearrangeModal(Map<String, dynamic> cell) async {
    _isModalOpen = true;

    await showDialog(
      context: context,
      builder: (context) {
        final items = cell['items'] as List? ?? [];
        final filledSet = items.map((i) => '${i['x']}-${i['y']}').toSet();
        final r = cell['row'];
        final c = cell['col'];
        final reelAssetPath = _isVertical ? 'assets/reelv.png' : 'assets/reel.png';

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Rearrange Cell ${cell['number']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Drag and drop reels to snap them to a valid position.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const Divider(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(_maxRows, (rIdx) {
                          final y = _maxRows - 1 - rIdx; // 0-indexed Y (goes from _maxRows - 1 down to 0)
                          final slotsInRow = _isVertical ? _maxCols : (_maxCols - y);

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(slotsInRow, (cIdx) {
                              final x = cIdx; // 0-indexed X (goes from 0 to slotsInRow - 1)
                              final item = items.firstWhere(
                                    (i) => i['x'] == x && i['y'] == y,
                                orElse: () => null,
                              );

                              if (item != null) {
                                return Draggable<Map<String, dynamic>>(
                                  data: {
                                    'item': item['number'],
                                    'fromX': x,
                                    'fromY': y,
                                    'fromRow': r,
                                    'fromCol': c,
                                  },
                                  feedback: Material(
                                    color: Colors.transparent,
                                    child: Image.asset(reelAssetPath, width: 38, height: 38),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: 0.3,
                                    child: Container(
                                      margin: const EdgeInsets.all(2),
                                      width: 38,
                                      height: 38,
                                      child: Image.asset(reelAssetPath, fit: BoxFit.contain),
                                    ),
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.all(2),
                                    width: 38,
                                    height: 38,
                                    child: Image.asset(reelAssetPath, fit: BoxFit.contain),
                                  ),
                                );
                              } else {
                                final isSupported = _isSlotSupported(filledSet, x, y);

                                return DragTarget<Map<String, dynamic>>(
                                  onAccept: (draggedData) async {
                                    if (!isSupported) return;
                                    Navigator.pop(context);
                                    await _executeReelMove(
                                      draggedData['fromRow'],
                                      draggedData['fromCol'],
                                      r,
                                      c,
                                      draggedData['item'],
                                      draggedData['fromX'],
                                      draggedData['fromY'],
                                      x,
                                      y,
                                    );
                                  },
                                  builder: (context, candidateData, rejectedData) {
                                    return Container(
                                      margin: const EdgeInsets.all(2),
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSupported
                                              ? (candidateData.isNotEmpty ? Colors.green : Colors.grey.shade400)
                                              : Colors.red.shade300,
                                          style: BorderStyle.solid,
                                          width: 1.5,
                                        ),
                                        color: isSupported
                                            ? (candidateData.isNotEmpty ? Colors.green.shade100 : Colors.transparent)
                                            : Colors.red.shade50.withOpacity(0.4),
                                      ),
                                    );
                                  },
                                );
                              }
                            }),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );

    _isModalOpen = false;
    _fetchTableDetails(); // Refresh after rearrange modal closes
  }

  // Process add using QR request
  Future<void> _processQrAddReel(
      int targetNumber,
      String searchMonth,
      int r,
      int c,
      int x,
      int y,
      bool isDispatchedOrBilled,
      ) async {
    setState(() => _isLoading = true);

    try {
      // 1. Check if reel is in unassigned reels list
      final unassignedUri = Uri.parse('$serverUrl/api/reels/unassigned?user_id=$userId&auth_key=$authKey');
      final unassignedRes = await http.get(unassignedUri);
      bool isUnassigned = false;

      if (unassignedRes.statusCode == 200) {
        final List unassigned = jsonDecode(unassignedRes.body) as List;
        isUnassigned = unassigned.any((item) {
          final itemNum = int.tryParse(item['item_number']?.toString() ?? '');
          final monthCode = item['month_code']?.toString().trim();
          return itemNum == targetNumber && monthCode?.toUpperCase() == searchMonth.toUpperCase();
        });
      }

      if (isUnassigned) {
        await _confirmAddReel(targetNumber, searchMonth, r, c, x, y);
        return;
      }

      // 2. Check if reel belongs to this table
      Map<String, dynamic>? currentTableLoc;
      for (var cell in _cellsData) {
        final items = cell['items'] as List? ?? [];
        for (var item in items) {
          final itemNum = int.tryParse(item['number']?.toString() ?? '');
          final monthCode = item['month_code']?.toString().trim();

          if (itemNum == targetNumber && monthCode?.toUpperCase() == searchMonth.toUpperCase()) {
            currentTableLoc = {
              'fromRow': cell['row'],
              'fromCol': cell['col'],
              'fromX': item['x'],
              'fromY': item['y'],
            };
            break;
          }
        }
        if (currentTableLoc != null) break;
      }

      if (currentTableLoc != null) {
        await _executeReelMove(
          currentTableLoc['fromRow'],
          currentTableLoc['fromCol'],
          r,
          c,
          targetNumber,
          currentTableLoc['fromX'],
          currentTableLoc['fromY'],
          x,
          y,
        );
        return;
      }

      // 3. Search for table & cell presence across all other tables
      Map<String, dynamic>? otherTableLoc;
      final tablesUri = Uri.parse('$serverUrl/api/tables?user_id=$userId&auth_key=$authKey');
      final tablesRes = await http.get(tablesUri);

      if (tablesRes.statusCode == 200) {
        final tablesData = jsonDecode(tablesRes.body);
        final List tables = tablesData is List ? tablesData : (tablesData['results'] ?? []);

        for (var table in tables) {
          final tableId = table['id']?.toString();
          if (tableId == widget.tableId.toString()) continue;

          final cellsUri = Uri.parse('$serverUrl/api/table?user_id=$userId&auth_key=$authKey&table_id=$tableId');
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
                  return itemNum == targetNumber && monthCode?.toUpperCase() == searchMonth.toUpperCase();
                });

                if (hasMatch) {
                  otherTableLoc = {
                    'tableId': tableId,
                    'row': cell['row'],
                    'col': cell['col'],
                  };
                  break;
                }
              }
            }
          }
          if (otherTableLoc != null) break;
        }
      }

      if (otherTableLoc != null) {
        // Remove from original location
        await http.post(
          Uri.parse('$serverUrl/api/remove'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': int.tryParse(userId) ?? 0,
            'auth_key': authKey,
            'table_id': otherTableLoc['tableId'],
            'row': otherTableLoc['row'],
            'col': otherTableLoc['col'],
            'item': targetNumber,
          }),
        );

        // Add to desired space
        await _confirmAddReel(targetNumber, searchMonth, r, c, x, y);
        return;
      }

      // 4. Check if dispatched/billed before final addition
      if (isDispatchedOrBilled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reel is Dispatched or Billed and cannot be added.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Add fresh reel
      await _confirmAddReel(targetNumber, searchMonth, r, c, x, y);
    } catch (e) {
      debugPrint("Error handling QR reel processing: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _executeReelMove(
      int fromRow, int fromCol, int toRow, int toCol, int itemNum, int fromX, int fromY, int toX, int toY,
      ) async {
    try {
      final res = await http.post(
        Uri.parse('$serverUrl/api/move'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': int.tryParse(userId) ?? 0,
          'auth_key': authKey,
          'item': itemNum,
          'from_table_id': widget.tableId,
          'from_row': fromRow,
          'from_col': fromCol,
          'to_table_id': widget.tableId,
          'to_row': toRow,
          'to_col': toCol,
          'to_x': toX,
          'to_y': toY,
        }),
      );

      if (res.statusCode == 200) {
        _fetchTableDetails();
      }
    } catch (e) {
      debugPrint("Error moving reel: $e");
    }
  }

  Future<void> _removeReelFromCell(int r, int c, int item) async {
    try {
      final res = await http.post(
        Uri.parse('$serverUrl/api/remove'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': int.tryParse(userId) ?? 0,
          'auth_key': authKey,
          'table_id': widget.tableId,
          'row': r,
          'col': c,
          'item': item,
        }),
      );

      if (res.statusCode == 200) {
        _fetchTableDetails();
      }
    } catch (e) {
      debugPrint("Error removing reel: $e");
    }
  }

  Future<void> _dispatchReel(String reelId, int r, int c, int item) async {
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    try {
      final res = await http.post(
        Uri.parse('$serverUrl/api/dispatch/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': int.tryParse(userId) ?? 0,
          'auth_key': authKey,
          'reel_id': reelId,
          'dispatch_date': dateStr,
          'dispatch_time': timeStr
        }),
      );

      if (res.statusCode == 200) {
        await _removeReelFromCell(r, c, item);
      }
    } catch (e) {
      debugPrint("Error dispatching reel: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final reelAssetPath = _isVertical ? 'assets/reelv.png' : 'assets/reel.png';

    int maxGridRow = 0;
    int maxGridCol = 0;
    for (var cell in _cellsData) {
      if ((cell['row'] ?? 0) > maxGridRow) maxGridRow = cell['row'];
      if ((cell['col'] ?? 0) > maxGridCol) maxGridCol = cell['col'];
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Table ${widget.tableId}'),
        backgroundColor: const Color(0xFF4A90D9),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : InteractiveViewer(
        constrained: false,
        boundaryMargin: const EdgeInsets.all(200),
        minScale: 0.3,
        maxScale: 2.5,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: List.generate(maxGridRow + 1, (r) {
              return Row(
                children: List.generate(maxGridCol + 1, (c) {
                  final cell = _cellsData.firstWhere(
                        (x) => x['row'] == r && x['col'] == c,
                    orElse: () => null,
                  );

                  if (cell == null) {
                    return const SizedBox(width: 240, height: 200);
                  }

                  final items = cell['items'] as List? ?? [];
                  final filledSet = items.map((i) => '${i['x']}-${i['y']}').toSet();

                  return Container(
                    constraints: const BoxConstraints(minWidth: 240),
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _parseColor(cell['color']),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Cell ${cell['number']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 12.0),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white24,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _openRearrangeModal(cell),
                                child: const Text('Rearrange', style: TextStyle(color: Colors.white, fontSize: 11)),
                              ),
                            )
                          ],
                        ),
                        const Divider(color: Colors.white38),
                        const SizedBox(height: 6),

                        // Pyramid / Stack Rows (0-indexed)
                        Column(
                          children: List.generate(_maxRows, (rIdx) {
                            final y = _maxRows - 1 - rIdx; // 0-indexed Y (goes from _maxRows - 1 down to 0)
                            final slotsInRow = _isVertical ? _maxCols : (_maxCols - y);

                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(slotsInRow, (cIdx) {
                                final x = cIdx; // 0-indexed X (goes from 0 to slotsInRow - 1)
                                final item = items.firstWhere(
                                      (i) => i['x'] == x && i['y'] == y,
                                  orElse: () => null,
                                );

                                if (item != null) {
                                  final isTarget = item['number'] == _activeSearchItem &&
                                      item['month_code'] == _activeSearchMonth;

                                  return GestureDetector(
                                    onTap: () => _viewReel(item['number'], item['month_code'], r, c),
                                    child: ScaleTransition(
                                      scale: isTarget
                                          ? Tween<double>(begin: 1.0, end: 1.35).animate(_pulseController)
                                          : const AlwaysStoppedAnimation(1.0),
                                      child: Container(
                                        margin: const EdgeInsets.all(3),
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isTarget ? Colors.yellow : Colors.white24,
                                            width: isTarget ? 2 : 1,
                                          ),
                                        ),
                                        child: Image.asset(reelAssetPath, fit: BoxFit.contain),
                                      ),
                                    ),
                                  );
                                } else {
                                  final isVisible = _isSlotSupported(filledSet, x, y);

                                  if (isVisible) {
                                    return GestureDetector(
                                      onTap: () => _openAddModal(r, c, x, y),
                                      child: Container(
                                        margin: const EdgeInsets.all(3),
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white38,
                                            style: BorderStyle.solid,
                                          ),
                                        ),
                                      ),
                                    );
                                  } else {
                                    return const SizedBox(width: 42, height: 42);
                                  }
                                }
                              }),
                            );
                          }),
                        ),
                      ],
                    ),
                  );
                }),
              );
            }),
          ),
        ),
      ),
    );
  }
}