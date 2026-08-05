import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import '../services/storage_service.dart';
import 'view_table_screen.dart';

class MapScreen extends StatefulWidget {
  final int? searchItem;
  final String? searchMonth;

  const MapScreen({
    Key? key,
    this.searchItem,
    this.searchMonth,
  }) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class TableShapeData {
  final String id;
  final Rect bounds;
  final Color fillColor;

  TableShapeData({
    required this.id,
    required this.bounds,
    required this.fillColor,
  });
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  String serverUrl = '';
  String userId = '';
  String authKey = '';

  bool _isLoading = true;
  List<dynamic> _tablesList = [];
  List<TableShapeData> _shapes = [];

  double _svgWidth = 1000;
  double _svgHeight = 800;

  TableShapeData? _targetShape;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadSessionAndInit();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadSessionAndInit() async {
    final session = await StorageService.getSession();
    setState(() {
      serverUrl = session['serverUrl'] ?? '';
      userId = session['userId'] ?? '';
      authKey = session['authKey'] ?? '';
    });

    await _fetchMapAndTables();

    if (widget.searchItem != null && widget.searchMonth != null) {
      await _handleSearchAndHighlight();
    }
  }

  Future<void> _fetchMapAndTables() async {
    try {
      final mapUri = Uri.parse('$serverUrl/api/map?user_id=$userId&auth_key=$authKey');
      final tablesUri = Uri.parse('$serverUrl/api/tables?user_id=$userId&auth_key=$authKey');

      final results = await Future.wait([
        http.get(mapUri),
        http.get(tablesUri),
      ]);

      if (results[0].statusCode == 200 && results[1].statusCode == 200) {
        final svgString = results[0].body;
        final tablesData = jsonDecode(results[1].body);

        _parseSvgShapes(svgString);

        setState(() {
          _tablesList = tablesData is List ? tablesData : (tablesData['results'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading map or tables: $e");
      setState(() => _isLoading = false);
    }
  }

  Color _parseColor(String? colorStr, {Color fallback = const Color(0xFF4A90D9)}) {
    if (colorStr == null || colorStr.isEmpty || colorStr == 'none') return fallback;
    try {
      if (colorStr.startsWith('#')) {
        final hex = colorStr.replaceAll('#', '');
        return Color(int.parse(hex.length == 3 ? 'FF${hex.split('').map((c) => '$c$c').join()}' : 'FF$hex', radix: 16));
      }
    } catch (_) {}
    return fallback;
  }

  Color _extractFillColor(xml.XmlElement element) {
    String? fill = element.getAttribute('fill');
    if (fill != null && fill != 'none') {
      return _parseColor(fill);
    }

    final style = element.getAttribute('style');
    if (style != null) {
      final fillMatch = RegExp(r'fill\s*:\s*([^;]+)').firstMatch(style);
      if (fillMatch != null) {
        return _parseColor(fillMatch.group(1)?.trim());
      }
    }
    return const Color(0xFF4A90D9);
  }

  void _parseSvgShapes(String svgContent) {
    try {
      final document = xml.XmlDocument.parse(svgContent);
      final svgElement = document.findAllElements('svg').firstOrNull;

      if (svgElement != null) {
        final viewBox = svgElement.getAttribute('viewBox');
        if (viewBox != null) {
          final parts = viewBox.trim().split(RegExp(r'[\s,]+'));
          if (parts.length >= 4) {
            _svgWidth = double.tryParse(parts[2]) ?? 1000;
            _svgHeight = double.tryParse(parts[3]) ?? 800;
          }
        }
      }

      final parsedShapes = <TableShapeData>[];
      final elements = document.findAllElements('*');

      for (var element in elements) {
        final id = element.getAttribute('id');
        if (id != null && id.isNotEmpty && id != 'refpoint1' && id != 'refpoint2') {
          Rect? bounds;
          final name = element.name.local.toLowerCase();
          final fillColor = _extractFillColor(element);

          if (name == 'rect') {
            final x = double.tryParse(element.getAttribute('x') ?? '0') ?? 0;
            final y = double.tryParse(element.getAttribute('y') ?? '0') ?? 0;
            final w = double.tryParse(element.getAttribute('width') ?? '0') ?? 60;
            final h = double.tryParse(element.getAttribute('height') ?? '0') ?? 60;
            bounds = Rect.fromLTWH(x, y, w, h);
          } else if (name == 'polygon' || name == 'polyline') {
            final pointsAttr = element.getAttribute('points') ?? '';
            final coords = pointsAttr
                .trim()
                .split(RegExp(r'[\s,]+'))
                .where((s) => s.isNotEmpty)
                .map((s) => double.tryParse(s) ?? 0.0)
                .toList();

            double minX = double.infinity, minY = double.infinity;
            double maxX = -double.infinity, maxY = -double.infinity;

            for (int i = 0; i < coords.length - 1; i += 2) {
              final x = coords[i];
              final y = coords[i + 1];
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
            }

            if (minX != double.infinity) {
              bounds = Rect.fromLTRB(minX, minY, maxX, maxY);
            }
          }

          if (bounds != null) {
            parsedShapes.add(TableShapeData(id: id, bounds: bounds, fillColor: fillColor));
          }
        }
      }

      _shapes = parsedShapes;
    } catch (e) {
      debugPrint("Error parsing SVG shapes: $e");
    }
  }

  Future<void> _handleSearchAndHighlight() async {
    String? foundTableId;

    for (var table in _tablesList) {
      final tId = table['id'].toString();
      final cellUri = Uri.parse('$serverUrl/api/table?user_id=$userId&auth_key=$authKey&table_id=$tId');

      try {
        final res = await http.get(cellUri);
        if (res.statusCode == 200) {
          final cellsData = jsonDecode(res.body);
          final cells = cellsData is List ? cellsData : (cellsData['results'] ?? []);

          for (var cell in cells) {
            final items = cell['items'] as List? ?? [];
            final matches = items.any((i) =>
            i['number'].toString() == widget.searchItem.toString() &&
                i['month_code'].toString() == widget.searchMonth.toString());

            if (matches) {
              foundTableId = tId;
              break;
            }
          }
        }
      } catch (e) {
        debugPrint("Search error: $e");
      }

      if (foundTableId != null) break;
    }

    if (foundTableId != null) {
      final target = _shapes.firstWhere(
            (s) => s.id == foundTableId,
        orElse: () => TableShapeData(id: foundTableId!, bounds: Rect.zero, fillColor: const Color(0xFF4A90D9)),
      );

      setState(() {
        _targetShape = target;
      });

      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          _navigateToTable(
            foundTableId!,
            highlightItem: widget.searchItem,
            highlightMonth: widget.searchMonth,
          );
        }
      });
    }
  }

  void _navigateToTable(String tableId, {int? highlightItem, String? highlightMonth}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewTableScreen(
          tableId: tableId,
          searchItem: highlightItem,
          searchMonth: highlightMonth,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Warehouse Map'),
        backgroundColor: const Color(0xFF4A90D9),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : InteractiveViewer(
        constrained: false, // Ensures full SVG canvas dimensions are scrollable
        boundaryMargin: const EdgeInsets.all(300),
        minScale: 0.2,
        maxScale: 3.5,
        child: SizedBox(
          width: _svgWidth,
          height: _svgHeight,
          child: Stack(
            children: [
              // Render Map Zones using parsed SVG Colors
              ..._shapes.map((shape) {
                return Positioned(
                  left: shape.bounds.left,
                  top: shape.bounds.top,
                  width: shape.bounds.width,
                  height: shape.bounds.height,
                  child: GestureDetector(
                    onTap: () => _navigateToTable(shape.id),
                    child: Container(
                      decoration: BoxDecoration(
                        color: shape.fillColor,
                        border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 3,
                            offset: Offset(0, 2),
                          )
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        shape.id,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                );
              }).toList(),

              // Pulsing Marker
              if (_targetShape != null && _targetShape!.bounds != Rect.zero)
                Positioned(
                  left: _targetShape!.bounds.center.dx - 20,
                  top: _targetShape!.bounds.center.dy - 40,
                  child: ScaleTransition(
                    scale: _pulseAnimation,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.redAccent,
                      size: 40,
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