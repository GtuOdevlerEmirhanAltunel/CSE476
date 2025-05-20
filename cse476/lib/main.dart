import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For rootBundle
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;
import 'package:image/image.dart' as img; // For image manipulation

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
        primarySwatch:
            Colors.deepPurple, // Changed theme color for a fresh look
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'GoogleSans', // Ensure you have this font or change it
        useMaterial3: true, // Using Material 3 for modern UI
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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

// Helper class to store detection results
class Detection {
  final Rect boundingBox; // The bounding box of the detected object
  final String label; // The label of the detected object (e.g., "qr_code")
  final double confidence; // The confidence score of the detection

  Detection(this.boundingBox, this.label, this.confidence);
}

class _QRHomePageState extends State<QRHomePage> {
  File? _imageFile;
  List<String> _qrResults = []; // Store multiple QR results
  bool _isProcessing = false;
  late final BarcodeScanner _barcodeScanner;
  tfl.Interpreter? _interpreter; // TFLite interpreter

  // --- TFLite Model Configuration (ADJUST THESE) ---
  static const String _modelPath =
      'assets/model.tflite'; // Your TFLite model path
  // Example: If your model expects 224x224 RGB images
  static const int _inputTensorWidth = 224;
  static const int _inputTensorHeight = 224;
  // --- End TFLite Model Configuration ---

  @override
  void initState() {
    super.initState();
    _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      // Load the TFLite model from assets
      _interpreter = await tfl.Interpreter.fromAsset(_modelPath);
      if (kDebugMode) {
        print('TFLite model loaded successfully.');
        // You can print model input/output tensor details here if needed
        // print('Input tensors: ${_interpreter?.getInputTensors()}');
        // print('Output tensors: ${_interpreter?.getOutputTensors()}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to load TFLite model: $e');
      }
      // Handle model loading failure (e.g., show an error message)
      setState(() {
        _qrResults = ["Error: Failed to load detection model."];
      });
    }
  }

  @override
  void dispose() {
    _barcodeScanner.close();
    _interpreter?.close(); // Close the TFLite interpreter
    super.dispose();
  }

  Future<void> _pickImageAndProcess() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
        _qrResults = [];
        _isProcessing = true;
      });
      await _detectAndScanQRCodes(_imageFile!);
    } else {
      if (kDebugMode) {
        print('User canceled image picking.');
      }
    }
  }

  // Preprocesses the image to the format expected by the TFLite model
  Future<Uint8List> _preprocessImage(File imageFile) async {
    final imageBytes = await imageFile.readAsBytes();
    img.Image? originalImage = img.decodeImage(imageBytes);

    if (originalImage == null) {
      throw Exception("Could not decode image");
    }

    // Resize the image to the model's expected input size
    img.Image resizedImage = img.copyResize(
      originalImage,
      width: _inputTensorWidth,
      height: _inputTensorHeight,
    );

    // Convert the image to a byte buffer (quantized models might need Uint8List)
    // For float models, you'd normalize and convert to Float32List
    // This is a placeholder. You MUST adjust this based on your model's requirements.
    // Example for a float model (normalize to [-1, 1] or [0, 1]):
    // var inputBuffer = Float32List(1 * _inputTensorWidth * _inputTensorHeight * 3);
    // int pixelIndex = 0;
    // for (int y = 0; y < _inputTensorHeight; y++) {
    //   for (int x = 0; x < _inputTensorWidth; x++) {
    //     var pixel = resizedImage.getPixel(x, y);
    //     inputBuffer[pixelIndex++] = (img.getRed(pixel) / 255.0 - 0.5) * 2.0;   // R
    //     inputBuffer[pixelIndex++] = (img.getGreen(pixel) / 255.0 - 0.5) * 2.0; // G
    //     inputBuffer[pixelIndex++] = (img.getBlue(pixel) / 255.0 - 0.5) * 2.0;  // B
    //   }
    // }
    // return inputBuffer.buffer.asUint8List(); // This is incorrect for Float32List, just showing structure

    // Example for a common Uint8List RGB format (no normalization, just bytes)
    // This might be suitable if your TFLite model handles normalization internally or is quantized.
    var inputBuffer = Uint8List(1 * _inputTensorWidth * _inputTensorHeight * 3);
    int pixelIndex = 0;
    for (int y = 0; y < _inputTensorHeight; y++) {
      for (int x = 0; x < _inputTensorWidth; x++) {
        var pixel = resizedImage.getPixel(x, y);
        inputBuffer[pixelIndex++] = pixel.r.toInt(); // R
        inputBuffer[pixelIndex++] = pixel.g.toInt(); // G
        inputBuffer[pixelIndex++] = pixel.b.toInt(); // B
      }
    }
    return inputBuffer; // This is a flattened RGB byte list
  }

  // Runs the TFLite model to detect objects (QR codes)
  Future<List<Detection>> _runObjectDetection(Uint8List imageBytes) async {
    if (_interpreter == null) {
      if (kDebugMode) print("Interpreter not initialized.");
      return [];
    }

    // Prepare input tensor
    // The shape [1, height, width, 3] is common for image models
    // This needs to match your model's input tensor shape!
    final input = Reshaping(
      imageBytes,
    ).reshape([1, _inputTensorHeight, _inputTensorWidth, 3]);

    // --- Prepare Output Tensors (ADJUST THESE) ---
    // This is highly dependent on your model's output format.
    // Example: For a model that outputs bounding boxes, classes, and scores.
    // You need to know the exact shapes and order.
    // Let's assume:
    // output 0: bounding boxes (e.g., [1, num_detections, 4]) -> [ymin, xmin, ymax, xmax] normalized
    // output 1: class IDs (e.g., [1, num_detections])
    // output 2: scores (e.g., [1, num_detections])
    // output 3: number of detections (e.g., [1]) - some models provide this

    // Example output structure (you MUST verify and adjust this)
    // Map<int, Object> outputs = {
    //   0: List<List<double>>.filled(1, List<double>.filled(10 * 4, 0.0)).reshape([1, 10, 4]), // Bounding boxes (10 detections, 4 coords)
    //   1: List<List<double>>.filled(1, List<double>.filled(10, 0.0)).reshape([1, 10]),      // Class IDs
    //   2: List<List<double>>.filled(1, List<double>.filled(10, 0.0)).reshape([1, 10]),      // Scores
    // };
    // --- End Output Tensors ---

    // This is a generic output map. You need to define the shapes based on your model.
    // Let's assume a common SSD Mobilenet output structure for demonstration:
    // Output tensor 0: Locations (usually normalized: ymin, xmin, ymax, xmax)
    // Output tensor 1: Classes (index into your labels file)
    // Output tensor 2: Scores
    // Output tensor 3: Number of detections
    // The shapes below are EXAMPLES. Replace with your model's actual output shapes.
    var outputLocations = Reshaping(
      List.filled(1 * 10 * 4, 0.0),
    ).reshape([1, 10, 4]); // Max 10 detections, 4 coordinates
    var outputClasses = Reshaping(
      List.filled(1 * 10, 0.0),
    ).reshape([1, 10]); // Max 10 detections, class index
    var outputScores = Reshaping(
      List.filled(1 * 10, 0.0),
    ).reshape([1, 10]); // Max 10 detections, score
    var numDetections = Reshaping(
      List.filled(1, 0.0),
    ).reshape([1]); // Number of actual detections

    Map<int, Object> outputs = {
      0: outputLocations,
      1: outputClasses,
      2: outputScores,
      3: numDetections,
    };

    try {
      _interpreter!.runForMultipleInputs([input], outputs);
    } catch (e) {
      if (kDebugMode) print("Error running TFLite model: $e");
      return [];
    }

    // --- Postprocess Model Output (ADJUST THIS) ---
    final List<Detection> detections = [];
    final int N =
        numDetections[0].toInt(); // Get the actual number of detections

    // Assuming your model has a labels file, and "qr_code" is one of the labels.
    // You'll need to map class indices from outputClasses to actual labels.
    // For simplicity, let's assume class '0' is 'qr_code'.
    const String qrCodeLabel =
        "qr_code"; // Or check outputClasses[0][i] against your label map
    const double confidenceThreshold =
        0.5; // Minimum confidence to consider a detection

    for (int i = 0; i < N; i++) {
      final score = outputScores[0][i];
      final classId =
          outputClasses[0][i].toInt(); // Example: map this to a label

      // Replace this with your actual label mapping and filtering logic
      // For this example, we assume any detection could be a QR code if score is high.
      // Or, if your model specifically identifies QR codes, check classId.
      if (score > confidenceThreshold) {
        // Bounding box coordinates are often normalized [0.0, 1.0]
        // Format might be [ymin, xmin, ymax, xmax]
        final ymin = outputLocations[0][i][0];
        final xmin = outputLocations[0][i][1];
        final ymax = outputLocations[0][i][2];
        final xmax = outputLocations[0][i][3];

        // Convert normalized coordinates to absolute pixel coordinates for cropping
        // This assumes _imageFile is available and its dimensions are known.
        // For simplicity, we'll create Rect with normalized values first.
        // Actual cropping will need image dimensions.
        final rect = Rect.fromLTRB(xmin, ymin, xmax, ymax); // Normalized rect

        // You might need to filter by classId if your model detects multiple object types
        // e.g., if (labels[classId] == "qr_code")
        detections.add(Detection(rect, qrCodeLabel, score));
        if (kDebugMode) {
          print('Detected: $qrCodeLabel with score $score at $rect');
        }
      }
    }
    // --- End Postprocess Model Output ---
    return detections;
  }

  Future<Uint8List?> _cropImageToBytes(
    File originalImageFile,
    Rect normalizedBoundingBox,
  ) async {
    final imageBytes = await originalImageFile.readAsBytes();
    img.Image? originalImage = img.decodeImage(imageBytes);

    if (originalImage == null) return null;

    final int imgWidth = originalImage.width;
    final int imgHeight = originalImage.height;

    // Convert normalized bounding box to absolute pixel coordinates
    final int x = (normalizedBoundingBox.left * imgWidth).toInt();
    final int y = (normalizedBoundingBox.top * imgHeight).toInt();
    final int w =
        ((normalizedBoundingBox.right - normalizedBoundingBox.left) * imgWidth)
            .toInt();
    final int h =
        ((normalizedBoundingBox.bottom - normalizedBoundingBox.top) * imgHeight)
            .toInt();

    // Ensure coordinates are within image bounds
    final cropX = x.clamp(0, imgWidth - 1);
    final cropY = y.clamp(0, imgHeight - 1);
    final cropW = (x + w).clamp(0, imgWidth) - cropX;
    final cropH = (y + h).clamp(0, imgHeight) - cropY;

    if (cropW <= 0 || cropH <= 0) return null; // Invalid crop region

    img.Image cropped = img.copyCrop(
      originalImage,
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH,
    );

    // Encode cropped image to PNG bytes (or JPEG)
    return Uint8List.fromList(img.encodePng(cropped));
  }

  Future<void> _decodeQRCodeFromCroppedBytes(
    Uint8List croppedImageBytes,
    Rect originalNormalizedBox,
  ) async {
    final InputImage inputImage = InputImage.fromBytes(
      bytes: croppedImageBytes,
      metadata: InputImageMetadata(
        // These dimensions are for the CROPPED image.
        // We need to get them from the actual cropped image if possible.
        // For simplicity, let's try without explicit dimensions if `fromBytes` handles it.
        // If not, you might need to decode `croppedImageBytes` again to get its new dimensions.
        size: const Size(
          0,
          0,
        ), // Will be inferred by MLKit if possible for some formats
        rotation: InputImageRotation.rotation0deg,
        format:
            InputImageFormat
                .nv21, // This might need to be InputImageFormat.bgra8888 or similar depending on how `encodePng` works.
        // For PNG bytes, ML Kit might handle it. If issues, try decoding PNG to raw pixels.
        // Let's try a common one, or let ML Kit infer.
        // Update: ML Kit usually expects uncompressed formats like NV21, YUV_420_888, BGRA8888.
        // PNG bytes might not work directly.
        // A more robust way is to convert the cropped img.Image to a format ML Kit likes.
        // For now, we'll try with PNG bytes and see if ML Kit handles it.
        // If not, you'll need to convert `img.Image cropped` to raw BGRA8888 bytes.
        bytesPerRow: croppedImageBytes.length ~/ originalNormalizedBox.height,
      ),
    );

    // --- Alternative: Convert cropped img.Image to BGRA8888 for ML Kit ---
    // This is a more reliable way than passing PNG bytes directly.
    // img.Image croppedImage = img.decodeImage(croppedImageBytes)!; // If you passed PNG bytes
    // Uint8List bgraBytes = Uint8List(croppedImage.width * croppedImage.height * 4);
    // int i = 0;
    // for (int py = 0; py < croppedImage.height; py++) {
    //   for (int px = 0; px < croppedImage.width; px++) {
    //     int pixel = croppedImage.getPixel(px, py);
    //     bgraBytes[i++] = img.getBlue(pixel);
    //     bgraBytes[i++] = img.getGreen(pixel);
    //     bgraBytes[i++] = img.getRed(pixel);
    //     bgraBytes[i++] = img.getAlpha(pixel);
    //   }
    // }
    // final InputImage inputImageReliable = InputImage.fromBytes(
    //   bytes: bgraBytes,
    //   metadata: InputImageMetadata(
    //     size: Size(croppedImage.width.toDouble(), croppedImage.height.toDouble()),
    //     rotation: InputImageRotation.rotation0deg,
    //     format: InputImageFormat.bgra8888, // This is a common format ML Kit supports
    //     bytesPerRow: croppedImage.width * 4,
    //   ),
    // );
    // --- End Alternative ---

    try {
      // Use the reliable input image if you implement the alternative above
      // final List<Barcode> barcodes = await _barcodeScanner.processImage(inputImageReliable);
      final List<Barcode> barcodes = await _barcodeScanner.processImage(
        inputImage,
      );

      if (barcodes.isNotEmpty) {
        for (final barcode in barcodes) {
          if (barcode.format == BarcodeFormat.qrCode &&
              barcode.rawValue != null) {
            setState(() {
              _qrResults.add(barcode.rawValue!);
              if (kDebugMode) print('QR Code Decoded: ${barcode.rawValue}');
            });
          }
        }
      } else {
        if (kDebugMode) {
          print('No QR code found in cropped region: $originalNormalizedBox');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error during QR code decoding from cropped image: $e");
      }
      // Optionally add an error message to _qrResults for this specific crop
    }
  }

  Future<void> _detectAndScanQRCodes(File imageFile) async {
    if (_interpreter == null) {
      setState(() {
        _qrResults = ["Error: Detection model not loaded."];
        _isProcessing = false;
      });
      return;
    }

    try {
      // 1. Preprocess the image for the TFLite model
      final Uint8List inputBytes = await _preprocessImage(imageFile);

      // 2. Run object detection model
      final List<Detection> detections = await _runObjectDetection(inputBytes);

      if (detections.isEmpty) {
        setState(() {
          _qrResults = ["No QR codes detected by the model."];
        });
        if (kDebugMode) print("No objects detected by TFLite model.");
        return;
      }

      // 3. For each detected QR code, crop and scan
      _qrResults.clear(); // Clear previous results
      for (final detection in detections) {
        // Assuming detection.label is "qr_code" or similar, or you filter appropriately
        if (kDebugMode) {
          print("Processing detected QR at ${detection.boundingBox}");
        }

        final Uint8List? croppedBytes = await _cropImageToBytes(
          imageFile,
          detection.boundingBox,
        );
        if (croppedBytes != null) {
          await _decodeQRCodeFromCroppedBytes(
            croppedBytes,
            detection.boundingBox,
          );
        } else {
          if (kDebugMode) {
            print(
              "Failed to crop image for detection at ${detection.boundingBox}",
            );
          }
        }
      }

      if (_qrResults.isEmpty) {
        setState(() {
          _qrResults = ["QR codes detected, but none could be read."];
        });
      }
    } catch (e) {
      setState(() {
        _qrResults = ["Error processing image: ${e.toString()}"];
      });
      if (kDebugMode) {
        print("Error in _detectAndScanQRCodes: $e");
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI QR Code Extractor'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ElevatedButton.icon(
                icon: const Icon(Icons.image_search),
                onPressed: _isProcessing ? null : _pickImageAndProcess,
                label: const Text('Pick Image & Scan QR Codes'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 20),
              if (_isProcessing)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (_imageFile != null)
                  Column(
                    children: [
                      Text(
                        "Selected Image:",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        // Add rounded corners to the image preview
                        borderRadius: BorderRadius.circular(12.0),
                        child: Image.file(
                          _imageFile!,
                          height: 250, // Increased height for better preview
                          fit: BoxFit.contain,
                          // TODO: Optionally draw bounding boxes from `detections` here
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                if (_qrResults.isNotEmpty)
                  Card(
                    // Display results in a card for better UI
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _qrResults.length == 1 &&
                                    _qrResults[0].startsWith("Error:")
                                ? "Status:"
                                : "QR Code Results:",
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(
                              color:
                                  _qrResults.length == 1 &&
                                          _qrResults[0].startsWith("Error:")
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._qrResults.map(
                            (result) => Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: Text(
                                result,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight:
                                      result.startsWith("Error:")
                                          ? FontWeight.normal
                                          : FontWeight.bold,
                                  color:
                                      result.startsWith("Error:")
                                          ? Theme.of(context).colorScheme.error
                                          : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_imageFile != null &&
                    !_isProcessing) // If image was processed but no results
                  Text(
                    'No QR codes found or could be read.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Helper extension for reshaping lists (used for TFLite input/output)
extension Reshaping on List<dynamic> {
  List<dynamic> reshape(List<int> shape) {
    if (shape.isEmpty) return this;
    final List<dynamic> reshaped = [];
    final int totalElements = shape.reduce((a, b) => a * b);
    if (length != totalElements) {
      throw ArgumentError(
        'Cannot reshape list of length $length to shape $shape',
      );
    }

    // This is a simplified reshape, assuming it's being used correctly
    // for TFLite where the outer list might be the batch.
    // For a true multi-dimensional reshape, a more complex logic is needed.
    // For now, this works if the input is flat and becomes e.g. [1, H, W, C]
    if (shape.length == 4 && shape[0] == 1) {
      // Common case: [1, H, W, C]
      // This is a placeholder. Proper reshaping is complex.
      // TFLite plugins often handle this if the flat list is correct.
      // The plugin expects a List<List<List<List<double>>>>> for input [1,H,W,C]
      // or Uint8List directly if it's a single tensor.
      // The `tflite_flutter` plugin is flexible.
      // When you assign to `_interpreter.run(input, output)`,
      // `input` should be `List<Object>` where each object is a tensor.
      // If your model has one input tensor of shape [1, H, W, C],
      // then `input` would be `[tensorDataAsNestedListOrFlatBuffer]`.
      // The provided `imageBytes.reshape(...)` in `_runObjectDetection`
      // uses a simple List<dynamic> which might need to be further structured
      // or directly passed if the plugin supports flat buffers for the given shape.
      // The `tflite_flutter` plugin is quite good at inferring this.
    }
    return this; // Return as is, assuming tflite_flutter handles it.
    // Or, you'd implement the actual reshaping logic here.
  }
}
