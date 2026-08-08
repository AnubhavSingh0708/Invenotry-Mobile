import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/reel.dart';
import '../services/storage_service.dart';

class EditReelScreen extends StatefulWidget {
  final Reel? reel;

  const EditReelScreen({Key? key, this.reel}) : super(key: key);

  @override
  _EditReelScreenState createState() => _EditReelScreenState();
}

class _EditReelScreenState extends State<EditReelScreen> {
  final _formKey = GlobalKey<FormState>();

  String serverUrl = '';
  String userId = '';
  String authKey = '';

  // Track if saving succeeded to dynamically reveal print button
  bool isSaved = false;
  bool isPrinting = false;

  // Controllers
  final TextEditingController monthCodeCtrl = TextEditingController();
  final TextEditingController itemNumCtrl = TextEditingController();
  final TextEditingController reelIdCtrl = TextEditingController();
  final TextEditingController sizeCtrl = TextEditingController();
  final TextEditingController weightCtrl = TextEditingController();
  final TextEditingController gsmCtrl = TextEditingController();
  final TextEditingController bfCtrl = TextEditingController();
  final TextEditingController colourCtrl = TextEditingController();
  final TextEditingController qualityCtrl = TextEditingController();
  final TextEditingController dateCtrl = TextEditingController();
  final TextEditingController timeCtrl = TextEditingController();

  String? selectedParty;
  List<String> monthCodes = [];
  List<String> parties = [];

  final List<String> bfSuggestions = ["18", "20", "22", "24", "26", "28", "30"];
  final List<String> colourSuggestions = ["Natural", "Golden Yellow"];
  final List<String> qualitySuggestions = [
    "Craftboard",
    "Liner Paper",
    "Fluting paper",
    "Fluting/Liner"
  ];

  @override
  void initState() {
    super.initState();
    _initSession();
    _setupForm();
  }

  void _setupForm() {
    if (widget.reel != null) {
      final r = widget.reel!;
      reelIdCtrl.text = r.reelId;
      sizeCtrl.text = r.sizeCm.toString();
      weightCtrl.text = r.weightKg.toString();
      gsmCtrl.text = r.gsm.toString();
      bfCtrl.text = r.bf;
      colourCtrl.text = r.colour;
      qualityCtrl.text = r.quality;
      selectedParty = r.party;
      dateCtrl.text = r.date;
      timeCtrl.text = r.time;

      if (r.reelId.contains('-')) {
        final parts = r.reelId.split('-');
        monthCodeCtrl.text = parts[0];
        itemNumCtrl.text = parts[1];
      }
    } else {
      final now = DateTime.now();
      dateCtrl.text = DateFormat('yyyy-MM-dd').format(now);
      timeCtrl.text = DateFormat('HH:mm:ss').format(now);
    }
  }

  Future<void> _initSession() async {
    final session = await StorageService.getSession();
    setState(() {
      serverUrl = session['serverUrl'] ?? '';
      userId = session['userId'] ?? '';
      authKey = session['authKey'] ?? '';
    });
    _loadDropdowns();
  }

  Future<void> _loadDropdowns() async {
    if (serverUrl.isEmpty) return;

    try {
      final resCode = await http.get(Uri.parse(
          '$serverUrl/api/monthcodes'),
          headers: {
            'Content-Type': 'application/json',
            'X-User-ID': userId,
            'X-Auth-Key': authKey,
  });
      if (resCode.statusCode == 200) {
        final List<dynamic> data = json.decode(resCode.body);
        setState(() {
          monthCodes = data.map((e) => e['code'].toString()).toList();
        });
      }

      final resParty = await http.get(Uri.parse(
          '$serverUrl/api/parties'),
          headers: {
            'Content-Type': 'application/json',
            'X-User-ID': userId,
            'X-Auth-Key': authKey,
  });
      if (resParty.statusCode == 200) {
        final List<dynamic> data = json.decode(resParty.body);
        setState(() {
          parties = data.map((e) => e['name'].toString()).toList();
        });
      }
    } catch (e) {
      debugPrint("Dropdown load failed: $e");
    }
  }

  void _updateReelId() {
    if (monthCodeCtrl.text.isNotEmpty && itemNumCtrl.text.isNotEmpty) {
      setState(() {
        reelIdCtrl.text = '${monthCodeCtrl.text}-${itemNumCtrl.text}';
      });
    }
  }

  Future<void> _saveReel() async {
    if (!_formKey.currentState!.validate()) return;

    final isEdit = widget.reel != null;
    final endpoint = isEdit ? '/api/reel/modify' : '/api/reel/add';

    final Map<String, dynamic> reelData = {
      'reel_id': reelIdCtrl.text,
      'month_code': monthCodeCtrl.text,
      'item_number': int.tryParse(itemNumCtrl.text) ?? 0,
      'size_cm': double.tryParse(sizeCtrl.text) ?? 0.0,
      'weight_kg': double.tryParse(weightCtrl.text) ?? 0.0,
      'gsm': int.tryParse(gsmCtrl.text) ?? 0,
      'bf': bfCtrl.text,
      'colour': colourCtrl.text,
      'quality': qualityCtrl.text,
      'party': selectedParty,
      'date': dateCtrl.text,
      'time': timeCtrl.text,
    };

    // Attach internal database primary key when editing
    if (isEdit && widget.reel?.id != null) {
      reelData['id'] = widget.reel!.id;
    }

    final payload = {
      'reel': reelData,
    };

    try {
      final response = await http.post(
        Uri.parse('$serverUrl$endpoint'),
        headers: {
            'Content-Type': 'application/json',
            'X-User-ID': userId,
            'X-Auth-Key': authKey,
  },
        body: json.encode(payload),
      );

      final result = json.decode(response.body);
      if (result['success'] == true) {
        setState(() {
          isSaved = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved Successfully! You can now print the label.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error saving reel')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Network Error: $e')),
      );
    }
  }

  /// Print Label Method using `pdf` and `printing` packages
  Future<void> _printSavedReel() async {
    setState(() => isPrinting = true);

    try {
      final reelId = reelIdCtrl.text;
      final party = selectedParty ?? '';
      final weightKg = weightCtrl.text;
      final gsm = gsmCtrl.text;
      final colour = colourCtrl.text;
      final sizeCm = sizeCtrl.text;
      final quality = qualityCtrl.text;
      final bf = bfCtrl.text;
      final date = dateCtrl.text;
      final time = timeCtrl.text;

      // Build QR Code endpoint URL
      final qrText = '$serverUrl/lookupqr?id=${Uri.encodeComponent(reelId)}';
      final qrUrl =
          '$serverUrl/api/qrcode?text=${Uri.encodeComponent(qrText)}&size=512';

      // Fetch QR Code image bytes
      final response = await http.get(Uri.parse(qrUrl),
      headers: {
            'X-User-ID': userId,
            'X-Auth-Key': authKey,
  });
      if (response.statusCode != 200)
        throw Exception("Failed to fetch QR Code");
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
                      reelId,
                      style: pw.TextStyle(
                          fontSize: 28, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Party: $party',
                      style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey800),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Text(
                      'Weight: $weightKg kg  |  GSM: $gsm',
                      style: const pw.TextStyle(fontSize: 16),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Colour: $colour  |  Size: $sizeCm cm',
                      style: const pw.TextStyle(fontSize: 16),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Quality: $quality  |  BF: $bf',
                      style: const pw.TextStyle(fontSize: 16),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Text(
                      'Date: $date $time',
                      style: const pw.TextStyle(
                          fontSize: 12, color: PdfColors.grey600),
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
        name: 'Reel_Label_$reelId',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to print label: $e')),
      );
    } finally {
      setState(() => isPrinting = false);
    }
  }

  Widget _buildAutocomplete(
      String label, TextEditingController controller, List<String> suggestions) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Autocomplete<String>(
        initialValue: TextEditingValue(text: controller.text),
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) return suggestions;
          return suggestions.where((option) =>
              option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
        },
        onSelected: (String selection) {
          controller.text = selection;
        },
        fieldViewBuilder:
            (context, textEditingController, focusNode, onFieldSubmitted) {
          textEditingController.addListener(() {
            controller.text = textEditingController.text;
          });
          return TextFormField(
            controller: textEditingController,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.reel != null;
    final canPrint = isEdit || isSaved;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Reel' : 'Add New Reel'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: monthCodes.contains(monthCodeCtrl.text)
                    ? monthCodeCtrl.text
                    : null,
                decoration: const InputDecoration(
                    labelText: 'Month Code', border: OutlineInputBorder()),
                items: monthCodes
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) {
                  monthCodeCtrl.text = val ?? '';
                  _updateReelId();
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: itemNumCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Item Number', border: OutlineInputBorder()),
                onChanged: (_) => _updateReelId(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: reelIdCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Reel ID (Auto-generated)',
                  border: const OutlineInputBorder(),
                  fillColor: Colors.grey.shade200,
                  filled: true,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: sizeCtrl,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Size (cm)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: weightCtrl,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Weight (kg)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: gsmCtrl,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'GSM', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              _buildAutocomplete('BF', bfCtrl, bfSuggestions),
              _buildAutocomplete('Colour', colourCtrl, colourSuggestions),
              _buildAutocomplete('Quality', qualityCtrl, qualitySuggestions),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: parties.contains(selectedParty)
                          ? selectedParty
                          : null,
                      decoration: const InputDecoration(
                          labelText: 'Party', border: OutlineInputBorder()),
                      items: parties
                          .map(
                              (p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (val) => setState(() => selectedParty = val),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle,
                        color: Colors.green, size: 36),
                    onPressed: () {
                      // Add Party Logic
                    },
                  )
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: dateCtrl,
                decoration: const InputDecoration(
                    labelText: 'Date', border: OutlineInputBorder()),
                readOnly: true,
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (date != null) {
                    dateCtrl.text = DateFormat('yyyy-MM-dd').format(date);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: timeCtrl,
                decoration: const InputDecoration(
                    labelText: 'Time', border: OutlineInputBorder()),
                readOnly: true,
                onTap: () async {
                  final time = await showTimePicker(
                      context: context, initialTime: TimeOfDay.now());
                  if (time != null) {
                    timeCtrl.text =
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
                  }
                },
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                ),
                onPressed: _saveReel,
                child: const Text('Save Reel',
                    style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
              const SizedBox(height: 16),
              if (canPrint)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.purple,
                  ),
                  onPressed: isPrinting ? null : _printSavedReel,
                  child: isPrinting
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                      : const Text('Print Label',
                      style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
