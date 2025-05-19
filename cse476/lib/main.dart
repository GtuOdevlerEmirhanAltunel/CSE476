import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:flutter/foundation.dart';

void main() {
  runApp(const QRApp());
}

class QRApp extends StatelessWidget {
  const QRApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI QR Extractor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'GoogleSans',
      ),
      home: const QRHomePage(),
    );
  }
}

class QRHomePage extends StatefulWidget {
  const QRHomePage({super.key});

  @override
  _QRHomePageState createState() => _QRHomePageState();
}

class _QRHomePageState extends State<QRHomePage> {
  File? _image;
  String? _qrResult;
  bool _isScanning = false;
  late final BarcodeScanner _barcodeScanner; // Declare it here

  @override
  void initState() {
    super.initState();
    _barcodeScanner = BarcodeScanner(); // Initialize it here
  }

  @override
  void dispose() {
    // Dispose the barcode scanner to prevent memory leaks.
    _barcodeScanner.close();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _qrResult = null;
        _isScanning = true;
      });
      _scanQRCode(_image!);
    } else {
      if (kDebugMode) {
        print('User canceled image picking.');
      }
    }
  }

  Future<void> _scanQRCode(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);

    try {
      final List<Barcode> barcodes = await _barcodeScanner.processImage(
        inputImage,
      );

      if (barcodes.isNotEmpty) {
        for (final barcode in barcodes) {
          if (barcode.format == BarcodeFormat.qrCode) {
            setState(() {
              _qrResult = barcode.rawValue;
              _isScanning = false;
            });
            return;
          }
        }
      }

      setState(() {
        _qrResult = "No QR code found.";
        _isScanning = false;
      });
    } catch (e) {
      setState(() {
        _qrResult = "Error: ${e.toString()}";
        _isScanning = false;
      });
      if (kDebugMode) {
        print("Error during QR code scanning: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI QR Code Extractor'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ElevatedButton(
                onPressed: _pickImage,
                child: const Text('Pick Image to Scan QR Code'),
              ),
              const SizedBox(height: 20),
              if (_image != null)
                Column(
                  children: [
                    Image.file(_image!, height: 200, fit: BoxFit.contain),
                    const SizedBox(height: 20),
                  ],
                ),
              if (_isScanning)
                const CircularProgressIndicator()
              else if (_qrResult != null)
                Text(
                  'Result: $_qrResult',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
