import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/storage_service.dart';
import 'reel_details_view.dart';

class AdvancedReelSearchScreen extends StatefulWidget {
  const AdvancedReelSearchScreen({super.key});

  @override
  State<AdvancedReelSearchScreen> createState() => _AdvancedReelSearchScreenState();
}

class _AdvancedReelSearchScreenState extends State<AdvancedReelSearchScreen> {
  Map<String, dynamic> _meta = {};
  bool _isLoadingMeta = true;

  String? _selectedTarget;
  String _matchType = 'all';

  String? _filterField;
  String? _filterOp;
  final _filterValueController = TextEditingController();
  final _filterValue2Controller = TextEditingController();

  final List<Map<String, dynamic>> _activeFilters = [];

  String? _sortField;
  final String _sortOrder = 'asc';
  final _limitController = TextEditingController(text: '100');

  List<dynamic> _results = [];
  Map<String, dynamic>? _resultsMeta;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _fetchMeta();
  }

  Future<void> _fetchMeta() async {
    final session = await StorageService.getSession();
    try {
      final res = await http.get(
        Uri.parse('${session['serverUrl']}/api/search/meta?user_id=${session['userId']}&auth_key=${session['authKey']}'),
      );
      if (res.statusCode == 200) {
        setState(() {
          _meta = jsonDecode(res.body);

          // Lock target specifically to reels/reel category
          if (_meta.containsKey('reels')) {
            _selectedTarget = 'reels';
          } else if (_meta.containsKey('reel')) {
            _selectedTarget = 'reel';
          } else if (_meta.isNotEmpty) {
            _selectedTarget = _meta.keys.first;
          }

          _updateFieldsForTarget();
          _isLoadingMeta = false;
        });
      }
    } catch (e) {
      setState(() => _isLoadingMeta = false);
    }
  }

  void _updateFieldsForTarget() {
    if (_selectedTarget == null || !_meta.containsKey(_selectedTarget)) return;

    final fields = List<String>.from(_meta[_selectedTarget]['fields']);
    final ops = List<String>.from(_meta[_selectedTarget]['ops']);

    setState(() {
      _activeFilters.clear();
      _filterField = fields.isNotEmpty ? fields.first : null;
      _filterOp = ops.isNotEmpty ? ops.first : null;
      _sortField = null;
    });
  }

  dynamic _parseValue(String val, String operator) {
    if (operator == 'in') {
      return val.split(',').map((e) => e.trim()).toList();
    }
    return int.tryParse(val) ?? double.tryParse(val) ?? val;
  }

  void _addFilter() {
    if (_filterField == null || _filterOp == null || _filterValueController.text.isEmpty) return;

    final filter = {
      'field': _filterField,
      'op': _filterOp,
      'value': _parseValue(_filterValueController.text.trim(), _filterOp!),
    };

    if (_filterOp == 'between') {
      if (_filterValue2Controller.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Provide Value 2 for "between"')));
        return;
      }
      filter['value2'] = _parseValue(_filterValue2Controller.text.trim(), 'between');
    }

    setState(() {
      _activeFilters.add(filter);
      _filterValueController.clear();
      _filterValue2Controller.clear();
    });
  }

  Future<void> _runSearch() async {
    setState(() => _isSearching = true);
    final session = await StorageService.getSession();

    final payload = {
      'user_id': int.parse(session['userId']!),
      'auth_key': session['authKey'],
      'target': _selectedTarget,
      'match': _matchType,
      'filters': _activeFilters,
      'sort_order': _sortOrder,
      'limit': int.tryParse(_limitController.text) ?? 100,
      'offset': 0,
    };

    if (_sortField != null) {
      payload['sort_field'] = _sortField;
    }

    try {
      final res = await http.post(
        Uri.parse('${session['serverUrl']}/api/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        setState(() {
          _results = data['results'] ?? [];
          _resultsMeta = {'count': data['count'], 'total': data['total'], 'target': data['target']};
        });
      } else {
        throw Exception(data['error'] ?? 'Search failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _openReelDetails(Map<String, dynamic> row) async {
    final session = await StorageService.getSession();
    final serverUrl = session['serverUrl'] ?? '';

    final reelRid = row['reel_id'];
    final monthCode = row['month_code'] ?? row['monthCode'] ?? row['month'] ?? '';
    final itemNumber = row['item_number'] ?? row['itemNumber'] ?? row['item_no'] ?? '';
    final rawUrl = '$serverUrl/lookupqr?id=$reelRid';

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ReelDetailsView(
        monthCode: monthCode.toString(),
        itemNumber: itemNumber.toString(),
        rawQrUrl: rawUrl,
      ),
    ).then((_) {
      // Action callback when details view closes
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingMeta) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Advanced Reel Search')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- 1. Filter Builder Panel ---
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Display target info badge instead of editable dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Target Category: ${_selectedTarget?.toUpperCase() ?? "REELS"}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Match Type', border: OutlineInputBorder()),
                      value: _matchType,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Match ALL Filters (AND)')),
                        DropdownMenuItem(value: 'any', child: Text('Match ANY Filter (OR)')),
                      ],
                      onChanged: (v) => setState(() => _matchType = v!),
                    ),
                    const Divider(height: 32),

                    Text('Add Filter', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Field', border: OutlineInputBorder()),
                      value: _filterField,
                      items: (_meta[_selectedTarget]?['fields'] as List?)
                          ?.map((f) => DropdownMenuItem<String>(value: f, child: Text(f)))
                          .toList(),
                      onChanged: (v) => setState(() => _filterField = v),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Operator', border: OutlineInputBorder()),
                      value: _filterOp,
                      items: (_meta[_selectedTarget]?['ops'] as List?)
                          ?.map((o) => DropdownMenuItem<String>(value: o, child: Text(o)))
                          .toList(),
                      onChanged: (v) => setState(() => _filterOp = v),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _filterValueController,
                      decoration: const InputDecoration(labelText: 'Value', border: OutlineInputBorder()),
                    ),
                    if (_filterOp == 'between') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _filterValue2Controller,
                        decoration: const InputDecoration(labelText: 'Value 2 (Upper Bound)', border: OutlineInputBorder()),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _addFilter,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Filter'),
                    ),

                    const SizedBox(height: 16),
                    // Active Filters Chips
                    if (_activeFilters.isNotEmpty) ...[
                      const Text('Active Filters:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: _activeFilters.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final f = entry.value;
                          final txt = '${f['field']} ${f['op']} ${f['value']}' +
                              (f['op'] == 'between' ? ' and ${f['value2']}' : '');
                          return Chip(
                            label: Text(txt, style: const TextStyle(fontSize: 12)),
                            onDeleted: () => setState(() => _activeFilters.removeAt(idx)),
                          );
                        }).toList(),
                      ),
                    ] else ...[
                      const Text('No active filters. Search will return all reel records.', style: TextStyle(fontStyle: FontStyle.italic)),
                    ],

                    const Divider(height: 32),

                    TextField(
                      controller: _limitController,
                      decoration: const InputDecoration(labelText: 'Limit', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _isSearching ? null : _runSearch,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSearching
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Run Search', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // --- 2. Results Table ---
              if (_resultsMeta != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    'Results: ${_resultsMeta!['count']} of ${_resultsMeta!['total']} total matching records in ${_resultsMeta!['target']} (Tap any row to view details)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),

              if (_resultsMeta != null && _results.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: Text('No results found.', style: TextStyle(fontSize: 16))),
                  ),
                )
              else if (_results.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(Theme.of(context).colorScheme.primaryContainer),
                      columns: (_results.first as Map<String, dynamic>).keys.map(
                            (k) => DataColumn(label: Text(k, style: const TextStyle(fontWeight: FontWeight.bold))),
                      ).toList(),
                      rows: _results.map((row) {
                        final rowMap = row as Map<String, dynamic>;
                        return DataRow(
                          onSelectChanged: (_) => _openReelDetails(rowMap),
                          cells: rowMap.values.map((v) {
                            final displayVal = (v is Map || v is List) ? jsonEncode(v) : v?.toString() ?? '';
                            return DataCell(Text(displayVal));
                          }).toList(),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}