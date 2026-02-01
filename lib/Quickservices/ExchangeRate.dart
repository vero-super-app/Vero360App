import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ExchangeRateScreen extends StatefulWidget {
  const ExchangeRateScreen({Key? key}) : super(key: key);

  @override
  _ExchangeRateScreenState createState() => _ExchangeRateScreenState();
}

class _ExchangeRateScreenState extends State<ExchangeRateScreen> {
  Map<String, dynamic>? exchangeRates;
  bool isLoading = true;
  final TextEditingController inputController = TextEditingController();
  String baseCurrency = "USD";
  double inputAmount = 0.0;

  final List<String> currencies = ['MWK', 'GBP', 'USD', 'CNY', 'ZAR', 'TZS'];

  @override
  void initState() {
    super.initState();
    fetchExchangeRates();
  }

  Future<void> fetchExchangeRates() async {
    final String apiUrl =
        "https://api.exchangerate-api.com/v4/latest/$baseCurrency";

    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        setState(() {
          exchangeRates = jsonDecode(response.body)['rates'];
          isLoading = false;
        });
      } else {
        showError(
            "Failed to load exchange rates. Error code: ${response.statusCode}");
      }
    } catch (error) {
      showError("An error occurred while fetching exchange rates: $error");
    }
  }

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    setState(() {
      isLoading = false;
    });
  }

  void updateConversion() {
    setState(() {
      inputAmount = double.tryParse(inputController.text) ?? 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // title: const Text("Exchange Rates"),
        backgroundColor: Colors.orange,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : exchangeRates == null
              ? const Center(child: Text("Failed to load exchange rates"))
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      // Header Section
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20.0),
                        color: Colors.orange,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "Currency Converter",
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              "Exchange rates are for reference only",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Input Section
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: inputController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: "Enter amount",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                ),
                                onChanged: (value) => updateConversion(),
                              ),
                            ),
                            const SizedBox(width: 16),
                            DropdownButton<String>(
                              value: baseCurrency,
                              items: currencies.map((String currency) {
                                return DropdownMenuItem<String>(
                                  value: currency,
                                  child: Text(currency),
                                );
                              }).toList(),
                              onChanged: (newValue) async {
                                if (newValue != null) {
                                  setState(() {
                                    baseCurrency = newValue;
                                    isLoading = true;
                                  });
                                  await fetchExchangeRates();
                                  updateConversion();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Conversion Results
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: currencies.length,
                          itemBuilder: (context, index) {
                            final currency = currencies[index];
                            if (currency == baseCurrency) return Container();

                            final rate = exchangeRates![currency];
                            final convertedAmount =
                                rate != null ? (inputAmount * rate) : 0.0;

                            return Card(
                              elevation: 3,
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              child: ListTile(
                                leading: Text(
                                  _getFlag(currency),
                                  style: const TextStyle(fontSize: 30),
                                ),
                                title: Text(
                                  currency,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                trailing: Text(
                                  convertedAmount.toStringAsFixed(2),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  String _getFlag(String currency) {
    const flagMap = {
      'MWK': '🇲🇼',
      'GBP': '🇬🇧',
      'USD': '🇺🇸',
      'CNY': '🇨🇳',
      'ZAR': '🇿🇦',
      'TZS': '🇹🇿',
    };
    return flagMap[currency] ?? '🏳️';
  }
}
