import 'package:flutter/material.dart';
import 'reel_details_view.dart';

class SearchReelScreen extends StatefulWidget {
  const SearchReelScreen({Key? key}) : super(key: key);

  @override
  State<SearchReelScreen> createState() => _SearchReelScreenState();
}

class _SearchReelScreenState extends State<SearchReelScreen> {
  final _monthCodeController = TextEditingController();
  final _itemNumberController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  void _onSearch() {
    if (_formKey.currentState!.validate()) {
      FocusScope.of(context).unfocus();

      final String monthCode = _monthCodeController.text.trim();
      final String itemNumber = _itemNumberController.text.trim();

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => ReelDetailsView(
          monthCode: monthCode,
          itemNumber: itemNumber,
        ),
      );
    }
  }

  @override
  void dispose() {
    _monthCodeController.dispose();
    _itemNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Reel'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, // Fixed CrossAxisAlignment
            children: [
              TextFormField(
                controller: _monthCodeController,
                decoration: const InputDecoration(
                  labelText: 'Month Code',
                  hintText: 'e.g. 26AU',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Enter month code' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _itemNumberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Item / Reel Number',
                  hintText: 'e.g. 5',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.numbers),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Enter item number' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _onSearch,
                icon: const Icon(Icons.search),
                label: const Text('Search Reel'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}