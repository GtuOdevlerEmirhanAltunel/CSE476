import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter QR Scanner',
      theme: ThemeData(
        primarySwatch: Colors.cyan,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const QRScannerScreen(),
    );
  }
}

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _scannerController = MobileScannerController(
    // For mobile_scanner v5.x, consider using arguments like:
    // formats: [BarcodeFormat.qrCode], // To scan only QR codes
    // autoStart: true, // Default is true
    // cameraResolution: Size(640, 480), // Optional: to request a specific resolution
    facing: CameraFacing.back,
    // initialTorchState: TorchState.off, // Optional: if you want to set initial torch state
  );

  StreamSubscription<BarcodeCapture>? _subscription; // Corrected type
  List<Barcode> _barcodes = [];
  ui.Size? _previewSize;
  Size? _widgetSize;
  bool _isPermissionGranted = false;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  ValueNotifier<TorchState> _torchState = ValueNotifier<TorchState>(
    TorchState.off,
  );
  ValueNotifier<CameraFacing> _cameraFacing = ValueNotifier<CameraFacing>(
    CameraFacing.back,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() {
        _isPermissionGranted = status == PermissionStatus.granted;
      });
      if (_isPermissionGranted) {
        _initializeScanner();
      } else {
        _showPermissionDeniedDialog();
      }
    }
  }

  void _showPermissionDeniedDialog() {
    if (mounted &&
        context.findRenderObject() != null &&
        context.findRenderObject()!.attached) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Camera Permission Denied'),
            content: const Text(
              'This app needs camera access to scan QR codes. Please grant camera permission in app settings.',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Open Settings'),
                onPressed: () {
                  openAppSettings();
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }

  void _initializeScanner() {
    // Ensure controller is not already started or disposed
    if (_scannerController.value.isRunning ||
        _scannerController.value.isInitialized) {
      // It seems mobile_scanner v5 automatically starts based on its lifecycle with the widget
      // explicit _scannerController.start() might not be needed or could cause issues if called redundantly.
      // The controller starts when the MobileScanner widget is built and visible.
    }

    // Subscribe to barcode stream
    // The stream type is BarcodeCapture
    _subscription = _scannerController.barcodes.listen(
      _handleBarcodeDetection,
      onError: (error) {
        print("Error in barcode stream: $error");
      },
    );

    // Listen to controller state changes for initialization
    // This is a common pattern, but for mobile_scanner v5, initialization is tied to the widget.
    // We can check _scannerController.value.isInitialized.
    // Let's rely on the MobileScanner widget to handle camera initialization.
    // We can use a flag or check controller.value.isRunning or controller.value.isInitialized.
    // For simplicity, we'll assume the MobileScanner widget handles initialization.
    // If MobileScanner widget is in the tree and visible, camera should start.

    // We can check the controller's value to see if it's running.
    // This is more of a reactive check.
    _scannerController.addListener(_onControllerStateChanged);

    if (mounted) {
      setState(() {
        _isCameraInitialized =
            true; // Assume initialization will proceed with widget
      });
    }
  }

  void _onControllerStateChanged() {
    if (!mounted) return;
    // You can react to changes in _scannerController.value here if needed
    // For example, if _scannerController.value.hasError
    if (_scannerController.value.error != null) {
      print("MobileScannerController error: ${_scannerController.value.error}");
      // Potentially show a message to the user
      if (mounted &&
          context.findRenderObject() != null &&
          context.findRenderObject()!.attached) {
        // ScaffoldMessenger.of(context).showSnackBar(
        //     SnackBar(content: Text('Camera error: ${_scannerController.value.error}')),
        // );
      }
    }
    // Update preview size if it changes and is valid
    if (_scannerController.value.size.width > 0 &&
        _scannerController.value.size.height > 0) {
      if (_previewSize != _scannerController.value.size) {
        setState(() {
          _previewSize = _scannerController.value.size;
        });
      }
    }
  }

  void _handleBarcodeDetection(BarcodeCapture capture) {
    if (!mounted || _isProcessing) return;

    if (capture.barcodes.isNotEmpty) {
      _isProcessing = true;
      setState(() {
        _barcodes = capture.barcodes;
        // Ensure preview size is captured correctly from the controller's current value
        if (_scannerController.value.size.width > 0 &&
            _scannerController.value.size.height > 0) {
          _previewSize = _scannerController.value.size;
        }
      });

      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _isProcessing = false;
        }
      });
    } else {
      if (_barcodes.isNotEmpty) {
        setState(() {
          _barcodes = [];
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // The mobile_scanner widget itself handles lifecycle states like pausing and resuming the camera.
    // Explicitly calling start/stop on the controller based on app lifecycle might
    // conflict with the widget's own lifecycle management in v5.x.
    // It's generally recommended to let the widget manage this.
    // If you need fine-grained control, ensure it doesn't conflict.
    // For now, we remove explicit start/stop here to rely on the widget.

    // Example: if (state == AppLifecycleState.inactive) { _scannerController.stop(); }
    // else if (state == AppLifecycleState.resumed) { _scannerController.start(); }
    // This needs careful testing with mobile_scanner v5.x behavior.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _scannerController.removeListener(_onControllerStateChanged);
    // Dispose the controller when the widget is disposed.
    // This is important to release camera resources.
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live QR Code Scanner'),
        actions: [
          // Torch toggle
          ValueListenableBuilder<TorchState>(
            valueListenable:
                _torchState, // This is ValueNotifier<TorchState> in v5.x
            builder: (context, torchState, child) {
              // torchState is TorchState
              IconData icon;
              Color color = Colors.grey;
              switch (torchState) {
                case TorchState.off:
                  icon = Icons.flash_off;
                  break;
                case TorchState.on:
                  icon = Icons.flash_on;
                  color = Colors.yellow;
                  break;
                case TorchState.auto: // Handle the 'auto' case
                  icon = Icons.flash_auto; // Or another appropriate icon
                  color = Colors.blue; // Example color for auto
                  break;
                case TorchState.unavailable:
                  icon = Icons.flashlight_off; // Icon for unavailable
                  color = Colors.red; // Example color for unavailable
                  break;
              }
              return IconButton(
                icon: Icon(icon, color: color),
                onPressed: () => _scannerController.toggleTorch(),
              );
            },
          ),
          // Camera switch
          ValueListenableBuilder<CameraFacing>(
            valueListenable:
                _cameraFacing, // This is ValueNotifier<CameraFacing> in v5.x
            builder: (context, cameraFacing, child) {
              // cameraFacing is CameraFacing
              IconData icon;
              switch (cameraFacing) {
                case CameraFacing.front:
                  icon = Icons.camera_front;
                  break;
                case CameraFacing.back:
                  icon = Icons.camera_rear;
                  break;
                // No default needed as CameraFacing has only two states.
              }
              return IconButton(
                icon: Icon(icon),
                onPressed: () => _scannerController.switchCamera(),
              );
            },
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (!_isPermissionGranted) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Camera permission not granted. Please grant permission in app settings.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Check if the controller's value indicates the camera is running and has a valid size
          // _isCameraInitialized can be true, but controller.value.isRunning or .isInitialized is more direct
          // For v5, MobileScanner widget handles the camera state.
          // We show MobileScanner directly. If it fails, it might show an error internally or we rely on controller.value.error.

          return LayoutBuilder(
            builder: (context, constraints) {
              _widgetSize = Size(constraints.maxWidth, constraints.maxHeight);

              // Update previewSize from controller if available and different
              // This is also handled in _onControllerStateChanged
              if (_scannerController.value.size.width > 0 &&
                  _scannerController.value.size.height > 0) {
                if (_previewSize != _scannerController.value.size) {
                  // Schedule a microtask to avoid calling setState during build
                  Future.microtask(() {
                    if (mounted) {
                      setState(() {
                        _previewSize = _scannerController.value.size;
                      });
                    }
                  });
                }
              } else if (_previewSize == null &&
                  _widgetSize != null &&
                  _widgetSize!.width > 0 &&
                  _widgetSize!.height > 0) {
                // Fallback if controller size is not yet available, use widget size as a rough estimate for initial paint
                // This is not ideal for coordinate mapping but prevents painter from crashing
                // _previewSize = _widgetSize; // This might lead to incorrect scaling initially.
                // It's better to wait for actual preview size.
              }

              return Stack(
                children: [
                  MobileScanner(
                    controller: _scannerController,
                    fit: BoxFit.cover,
                    // onDetect is an alternative to listening to the barcodes stream
                    // It's often simpler for basic use cases.
                    // onDetect: _handleBarcodeDetection, // if you prefer this
                    errorBuilder: (context, error, child) {
                      // Handle scanner errors, e.g., camera not available
                      print("MobileScanner error: $error");
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'Scanner Error: ${error.errorDetails?.message ?? 'Unknown error'}\nPlease ensure camera is available and permissions are granted.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      );
                    },
                  ),
                  if (_barcodes.isNotEmpty &&
                      _previewSize != null &&
                      _widgetSize != null &&
                      _previewSize!.width > 0 &&
                      _previewSize!.height > 0)
                    CustomPaint(
                      painter: QRCodePainter(
                        barcodes: _barcodes,
                        imageAnalysisSize: _previewSize!,
                        widgetSize: _widgetSize!,
                        // Get current camera facing from controller's value for painter
                        cameraFacing: _scannerController.facing,
                      ),
                      size: _widgetSize!,
                    ),
                  // Show a loading indicator or message if preview size is not yet determined
                  if (_previewSize == null || _previewSize!.isEmpty)
                    const Center(child: Text("Initializing camera...")),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class QRCodePainter extends CustomPainter {
  final List<Barcode> barcodes;
  final ui.Size imageAnalysisSize;
  final Size widgetSize;
  final CameraFacing cameraFacing;

  QRCodePainter({
    required this.barcodes,
    required this.imageAnalysisSize,
    required this.widgetSize,
    required this.cameraFacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageAnalysisSize.isEmpty ||
        widgetSize.isEmpty ||
        imageAnalysisSize.width == 0 ||
        imageAnalysisSize.height == 0)
      return;

    final double imageAspect =
        imageAnalysisSize.width / imageAnalysisSize.height;
    final double widgetAspect = widgetSize.width / widgetSize.height;

    double scaleX, scaleY;
    double offsetX = 0.0;
    double offsetY = 0.0;

    if (widgetAspect > imageAspect) {
      scaleY = widgetSize.height / imageAnalysisSize.height;
      scaleX = scaleY;
      offsetX = (widgetSize.width - imageAnalysisSize.width * scaleX) / 2.0;
    } else {
      scaleX = widgetSize.width / imageAnalysisSize.width;
      scaleY = scaleX;
      offsetY = (widgetSize.height - imageAnalysisSize.height * scaleY) / 2.0;
    }

    final Paint paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..color = Colors.red.shade700;

    final Paint backgroundPaint =
        Paint()
          ..color = Colors.black.withOpacity(0.7)
          ..style = PaintingStyle.fill;

    for (final barcode in barcodes) {
      final List<Offset?> corners = barcode.corners;
      final String displayValue =
          barcode.displayValue ?? barcode.rawValue ?? 'N/A';

      if (corners.isNotEmpty && corners.length >= 4) {
        if (corners.any((p) => p == null)) continue;
        final List<Offset> validCorners = corners.cast<Offset>().toList();

        final List<Offset> scaledCorners =
            validCorners.map((corner) {
              double dx = corner.dx * scaleX + offsetX;
              double dy = corner.dy * scaleY + offsetY;

              // For front camera with BoxFit.cover, if the image from the scanner is mirrored,
              // and the corners are relative to that mirrored image, this scaling might be sufficient.
              // If corners are relative to a non-mirrored image but displayed mirrored,
              // then dx might need to be `widgetSize.width - dx` after scaling.
              // However, mobile_scanner usually provides corners that work with its display.
              // Test this part carefully with front camera.
              // if (cameraFacing == CameraFacing.front) {
              //   dx = (imageAnalysisSize.width - corner.dx) * scaleX + offsetX; // Example if mirroring needed
              // }

              return Offset(dx, dy);
            }).toList();

        final Path path = Path();
        path.moveTo(scaledCorners[0].dx, scaledCorners[0].dy);
        for (int i = 1; i < scaledCorners.length; i++) {
          path.lineTo(scaledCorners[i].dx, scaledCorners[i].dy);
        }
        path.close();
        canvas.drawPath(path, paint);

        final TextSpan span = TextSpan(
          text: displayValue,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14.0,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                blurRadius: 2.0,
                color: Colors.black.withOpacity(0.7),
                offset: const Offset(1.0, 1.0),
              ),
            ],
          ),
        );
        final TextPainter tp = TextPainter(
          text: span,
          textAlign: TextAlign.left,
          textDirection: TextDirection.ltr,
        );
        tp.layout(maxWidth: widgetSize.width - 20);

        double textX = scaledCorners[0].dx;
        double textY = scaledCorners[0].dy - tp.height - 8;

        if (textY < 5) {
          textY =
              (scaledCorners.length > 3
                  ? scaledCorners[3].dy
                  : scaledCorners[0].dy) +
              8;
        }
        if (textX + tp.width > widgetSize.width - 5) {
          textX = widgetSize.width - tp.width - 5;
        }
        if (textX < 5) {
          textX = 5;
        }

        if (textY + tp.height > widgetSize.height - 5) {
          textY = widgetSize.height - tp.height - 5;
        }

        Rect textBackgroundRect = Rect.fromLTWH(
          textX - 4,
          textY - 4,
          tp.width + 8,
          tp.height + 8,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(textBackgroundRect, const Radius.circular(4)),
          backgroundPaint,
        );

        tp.paint(canvas, Offset(textX, textY));
      }
    }
  }

  @override
  bool shouldRepaint(covariant QRCodePainter oldDelegate) {
    return oldDelegate.barcodes != barcodes ||
        oldDelegate.imageAnalysisSize != imageAnalysisSize ||
        oldDelegate.widgetSize != widgetSize ||
        oldDelegate.cameraFacing != cameraFacing;
  }
}
