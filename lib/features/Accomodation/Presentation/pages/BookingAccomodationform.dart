import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:vero360_app/GeneralPages/payment_webview.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_booking_model.dart' show BookingRequest;
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/booking_service.dart';

class BookingFormPage extends StatefulWidget {
  final  hostel;

  BookingFormPage({required this.hostel});

  @override
  _BookingFormPageState createState() => _BookingFormPageState();
}

class _BookingFormPageState extends State<BookingFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  late DateTime _bookingDate;
  bool _isLoading = false;
  final FToast _fToast = FToast();

  @override
  void initState() {
    super.initState();
    _bookingDate = DateTime.now();
    _fToast.init(context); // Initialize toast notifications
  }

  Future<void> _submitBooking() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _isLoading = true);

      try {
        // Step 1: Create a booking
        final bookingRequest = BookingRequest(
          boardingHouseId: widget.hostel.id,
          studentName: _nameController.text,
          emailAddress: _emailController.text,
          phoneNumber: _phoneController.text,
          bookingDate: _bookingDate.toIso8601String(),
          price: widget.hostel.bookingFee,
        );

        final bookingResult = await BookingService().createBooking(bookingRequest);

        if (bookingResult['status'] == 'success') {
          final paymentResult = await BookingService().initiatePayment(
            amount: widget.hostel.bookingFee,
            currency: 'MWK',
            email: _emailController.text,
            txRef: 'tx_${DateTime.now().millisecondsSinceEpoch}',
            phoneNumber: _phoneController.text,
            name: _nameController.text,
          );

          if (paymentResult['status'] == 'success' && paymentResult['checkout_url'] != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => PaymentWebView(checkoutUrl: paymentResult['checkout_url']),
              ),
            );
          } else {
            showCustomToast('Failed to initiate payment.', Icons.error, Colors.red);
          }
        } else {
          showCustomToast('Booking failed.', Icons.error, Colors.red);
        }
      } catch (error) {
        showCustomToast('Error: $error', Icons.error, Colors.red);
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  void showCustomToast(String message, IconData icon, Color color) {
    Widget toast = Container(
      padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
        color: color,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6.0,
            offset: Offset(2, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          SizedBox(width: 12.0),
          Flexible(
            child: Text(
              message,
              style: TextStyle(color: Colors.white, fontSize: 16),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );

    _fToast.showToast(
      child: toast,
      gravity: ToastGravity.CENTER,
      toastDuration: Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Book ${widget.hostel.houseName}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Secure Your Stay at ${widget.hostel.houseName} room number ${widget.hostel.roomNumber}',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal[700]),
            ),
            SizedBox(height: 16),

            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      buildTextField(_nameController, 'Your Name', Icons.person, 'Please enter your name'),
                      SizedBox(height: 12),
                      buildTextField(_emailController, 'Your Email', Icons.email, 'Please enter your email'),
                      SizedBox(height: 12),
                      buildTextField(_phoneController, 'Your Phone', Icons.phone, 'Please enter your phone number'),
                      SizedBox(height: 20),
                      Text(
                        'Booking Fee: MWK ${widget.hostel.bookingFee}',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green[700]),
                      ),
                      SizedBox(height: 20),
                      _isLoading
                          ? Center(child: CircularProgressIndicator())
                          :ElevatedButton.icon(
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.orange,
    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    minimumSize: Size(double.infinity, 50), // Ensures full width
  ),
  onPressed: _submitBooking,
  icon: Icon(Icons.payment, color: Colors.white),
  label: FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      'Pay Now MWK ${widget.hostel.bookingFee}',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
    ),
  ),
),

                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTextField(TextEditingController controller, String label, IconData icon, String validationMsg) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
        prefixIcon: Icon(icon),
      ),
      validator: (value) => value == null || value.isEmpty ? validationMsg : null,
    );
  }
}
