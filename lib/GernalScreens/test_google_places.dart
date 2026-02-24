import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/google_places_service.dart';

/// Test widget to verify Google Places API key is working
class TestGooglePlacesScreen extends StatefulWidget {
  const TestGooglePlacesScreen({super.key});

  @override
  State<TestGooglePlacesScreen> createState() => _TestGooglePlacesScreenState();
}

class _TestGooglePlacesScreenState extends State<TestGooglePlacesScreen> {
  late GooglePlacesService _service;
  String _testResult = 'Not tested yet';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    try {
      _service = GooglePlacesService();
    } catch (e) {
      _testResult = 'Error: $e';
    }
  }

  Future<void> _testSearch() async {
    setState(() {
      _isLoading = true;
      _testResult = 'Testing...';
    });

    try {
      final results = await _service.autocompleteSearch('lilongwe');
      setState(() {
        _testResult = 'Success! Found ${results.length} results:\n\n'
            '${results.take(3).map((r) => '- ${r.mainText} (${r.secondaryText})').join('\n')}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _testResult = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Google Places API')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _testResult,
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _testSearch,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Test API'),
            ),
          ],
        ),
      ),
    );
  }
}
