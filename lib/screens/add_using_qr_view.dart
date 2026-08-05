import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/reel.dart';

class AddUsingQrView extends StatefulWidget {
  final String serverUrl;

  const AddUsingQrView({
    Key? key,
    required this.serverUrl,
  }) : super(key: key);

  @override
  State<AddUsingQrView> createState() => _AddUsingQrViewState();
}

class _AddUsingQrViewState extends State<AddUsingQrView> {
  final MobileScannerController _scannerController = MobileScannerController();

  bool _isScanning = true;
  bool _isLoading = false;
  String? _errorMessage;

  String? _monthCode;
  String? _itemNumber;
  String? _rawQrUrl;

  Reel? _reel;
  String? _dispatchInfo;
  String? _billedInfo;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        setState(() {
          _isScanning = false;
        });
        _processQrCode(rawValue);
        break;
      }
    }
  }

  void _processQrCode(String raw) {
    _rawQrUrl = raw;
    String idParam = '';

    try {
      final uri = Uri.parse(raw);
      if (uri.queryParameters.containsKey('id')) {
        idParam = uri.queryParameters['id']!;
      } else {
        idParam = raw.trim();
      }
    } catch (_) {
      idParam = raw.trim();
    }

    if (idParam.contains('-')) {
      final parts = idParam.split('-');
      _monthCode = parts[0].trim();
      _itemNumber = parts.sublist(1).join('-').trim();
    } else {
      setState(() {
        _errorMessage = 'Invalid QR format. Expected MONTHCODE-NUMBER format.';
      });
      return;
    }

    _fetchFromQrHtmlLookup();
  }

  Future<void> _fetchFromQrHtmlLookup() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final String targetUrl = _rawQrUrl != null && _rawQrUrl!.startsWith('http')
        ? _rawQrUrl!
        : '${widget.serverUrl}/lookupqr?id=$_monthCode-$_itemNumber';

    try {
      final res = await http.get(Uri.parse(targetUrl));
      if (res.statusCode == 200) {
        final document = html_parser.parse(res.body);

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

        final String fullReelId = '$_monthCode-$_itemNumber';

        setState(() {
          _reel = Reel(
            id: int.tryParse(_itemNumber ?? ''),
            reelId: fullReelId,
            sizeCm: parseCleanDouble(extractVal('Size')),
            weightKg: parseCleanDouble(extractVal('Weight')),
            gsm: parseCleanInt(extractVal('GSM')),
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
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool get _isDispatchedOrBilled {
    final hasDispatchInfo = _dispatchInfo != null && _dispatchInfo!.isNotEmpty;
    final hasBilledInfo = _billedInfo != null && _billedInfo!.isNotEmpty;
    final hasDispatchDate = _reel?.dispatchDate != null && _reel!.dispatchDate!.isNotEmpty;

    return hasDispatchInfo || hasBilledInfo || hasDispatchDate;
  }

  void _resetScanner() {
    setState(() {
      _isScanning = true;
      _reel = null;
      _errorMessage = null;
      _dispatchInfo = null;
      _billedInfo = null;
      _monthCode = null;
      _itemNumber = null;
    });
  }

  void _confirmSelection() {
    if (_monthCode == null || _itemNumber == null) return;
    Navigator.pop(context, {
      'monthCode': _monthCode,
      'itemNumber': int.tryParse(_itemNumber!),
      'isDispatchedOrBilled': _isDispatchedOrBilled,
      'reel': _reel,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: const Color(0xFF4A90D9),
        actions: [
          if (!_isScanning)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetScanner,
              tooltip: 'Scan Again',
            )
        ],
      ),
      body: _isScanning
          ? MobileScanner(
        controller: _scannerController,
        onDetect: _onDetect,
      )
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _resetScanner,
                child: const Text('Try Again'),
              )
            ],
          ),
        )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reel ID: ${_reel?.reelId ?? "$_monthCode-$_itemNumber"}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const Divider(),
                    Text('Party: ${_reel?.party ?? "N/A"}'),
                    Text('Quality: ${_reel?.quality ?? "N/A"}'),
                    Text('Colour: ${_reel?.colour ?? "N/A"}'),
                    Text('GSM: ${_reel?.gsm ?? "N/A"}'),
                    Text('BF: ${_reel?.bf ?? "N/A"}'),
                    Text('Size: ${_reel?.sizeCm ?? 0} cm'),
                    Text('Weight: ${_reel?.weightKg ?? 0} kg'),
                    Text('Date: ${_reel?.date ?? "N/A"}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isDispatchedOrBilled)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: const Text(
                  'This reel is Dispatched or Billed and cannot be added.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            const Spacer(),
            Padding(
            padding: const EdgeInsets.only(bottom: 35.0), // Pushes content below away by 20 pixels
            child :Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _resetScanner,
                    child: const Text('Rescan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDispatchedOrBilled ? Colors.grey : Colors.green,
                    ),
                    onPressed: _isDispatchedOrBilled ? null : _confirmSelection,
                    child: const Text('Snap to Position'),
                  ),
                ),
              ],
            )
            )

          ],
        ),
      ),
    );
  }
}