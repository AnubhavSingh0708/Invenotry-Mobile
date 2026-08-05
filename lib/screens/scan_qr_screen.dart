import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/storage_service.dart';
import 'reel_details_view.dart';

class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({Key? key}) : super(key: key);

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawUrl = barcodes.first.rawValue;
    if (rawUrl == null || rawUrl.isEmpty) return;

    // Load session asynchronously from StorageService
    final session = await StorageService.getSession();
    final serverUrl = session['serverUrl']?.toString() ?? '';

    try {
      final Uri uri = Uri.parse(rawUrl);

      // Optional check: ensure URL path contains '/lookupqr'
      if (!uri.path.contains('lookupqr')) {
        _showErrorSnackBar('Invalid QR Code format.');
        return;
      }

      final String? idParam = uri.queryParameters['id']; // e.g., "26AU-5"
      if (idParam == null || !idParam.contains('-')) {
        _showErrorSnackBar('QR Code missing valid reel parameters.');
        return;
      }

      final parts = idParam.split('-');
      final String monthCode = parts[0];
      final String itemNumber = parts[1];

      setState(() => _isProcessing = true);
      _scannerController.stop();

      // Open Reel Details Sheet
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => ReelDetailsView(
          monthCode: monthCode,
          itemNumber: itemNumber,
          rawQrUrl: rawUrl,
        ),
      ).then((_) {
        // Resume scanning when bottom sheet is dismissed
        if (mounted) {
          setState(() => _isProcessing = false);
          _scannerController.start();
        }
      });
    } catch (e) {
      _showErrorSnackBar('Error parsing QR Code URL');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Reel QR Code'),
        actions: [
          // Torch toggle
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _scannerController,
            builder: (context, state, child) {
              final isTorchOn = state.torchState == TorchState.on;
              return IconButton(
                icon: Icon(isTorchOn ? Icons.flash_on : Icons.flash_off),
                onPressed: () => _scannerController.toggleTorch(),
              );
            },
          ),
          // Switch camera toggle
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _scannerController,
            builder: (context, state, child) {
              return IconButton(
                icon: const Icon(Icons.cameraswitch),
                onPressed: () => _scannerController.switchCamera(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _handleBarcode,
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              'Align QR code within the frame',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                backgroundColor: Colors.black54,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}