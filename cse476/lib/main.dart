import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

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
    facing: CameraFacing.back,
  );

  StreamSubscription<BarcodeCapture>? _subscription;
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
    _subscription = _scannerController.barcodes.listen(
      _handleBarcodeDetection,
      onError: (error) {
        print("Error in barcode stream: $error");
      },
    );

    _scannerController.addListener(_onControllerStateChanged);

    if (mounted) {
      setState(() {
        _isCameraInitialized = true;
      });
    }
  }

  void _onControllerStateChanged() {
    if (!mounted) return;

    if (_scannerController.value.error != null) {
      print("MobileScannerController error: ${_scannerController.value.error}");
    }

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

  // Check if text contains a URL
  bool _isUrl(String text) {
    final urlPattern = RegExp(
      r'^(https?:\/\/)?([\da-z\.-]+)\.([a-z\.]{2,6})([\/\w \.-]*)*\/?$',
      caseSensitive: false,
    );
    return urlPattern.hasMatch(text) ||
        text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.startsWith('www.');
  }

  // Handle tap on QR code label
  Future<void> _handleLabelTap(String text, Offset tapPosition) async {
    if (_isUrl(text)) {
      await _showUrlActionDialog(text);
    } else {
      await _copyToClipboard(text);
    }
  }

  // Show dialog for URL actions
  Future<void> _showUrlActionDialog(String url) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('URL Detected'),
          content: Text('Found URL: $url'),
          actions: <Widget>[
            TextButton(
              child: const Text('Copy'),
              onPressed: () {
                _copyToClipboard(url);
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Open'),
              onPressed: () async {
                Navigator.of(context).pop();
                await _openUrl(url);
              },
            ),
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Copy text to clipboard
  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied to clipboard: $text'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Open URL in browser
  Future<void> _openUrl(String url) async {
    try {
      // Ensure URL has proper protocol
      String formattedUrl = url;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        formattedUrl = 'https://$url';
      }

      final Uri uri = Uri.parse(formattedUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot open URL: $url'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening URL: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _scannerController.removeListener(_onControllerStateChanged);
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live QR Code Scanner'),
        actions: [
          ValueListenableBuilder<TorchState>(
            valueListenable: _torchState,
            builder: (context, torchState, child) {
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
                case TorchState.auto:
                  icon = Icons.flash_auto;
                  color = Colors.blue;
                  break;
                case TorchState.unavailable:
                  icon = Icons.flashlight_off;
                  color = Colors.red;
                  break;
              }
              return IconButton(
                icon: Icon(icon, color: color),
                onPressed: () => _scannerController.toggleTorch(),
              );
            },
          ),
          ValueListenableBuilder<CameraFacing>(
            valueListenable: _cameraFacing,
            builder: (context, cameraFacing, child) {
              IconData icon;
              switch (cameraFacing) {
                case CameraFacing.front:
                  icon = Icons.camera_front;
                  break;
                case CameraFacing.back:
                  icon = Icons.camera_rear;
                  break;
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

          return LayoutBuilder(
            builder: (context, constraints) {
              _widgetSize = Size(constraints.maxWidth, constraints.maxHeight);

              if (_scannerController.value.size.width > 0 &&
                  _scannerController.value.size.height > 0) {
                if (_previewSize != _scannerController.value.size) {
                  Future.microtask(() {
                    if (mounted) {
                      setState(() {
                        _previewSize = _scannerController.value.size;
                      });
                    }
                  });
                }
              }

              return Stack(
                children: [
                  MobileScanner(
                    controller: _scannerController,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, child) {
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
                    ClickableQROverlay(
                      barcodes: _barcodes,
                      imageAnalysisSize: _previewSize!,
                      widgetSize: _widgetSize!,
                      cameraFacing: _scannerController.facing,
                      onLabelTap: _handleLabelTap,
                      isUrl: _isUrl,
                    ),
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

class ClickableQROverlay extends StatelessWidget {
  final List<Barcode> barcodes;
  final ui.Size imageAnalysisSize;
  final Size widgetSize;
  final CameraFacing cameraFacing;
  final Function(String, Offset) onLabelTap;
  final Function(String) isUrl;

  const ClickableQROverlay({
    super.key,
    required this.barcodes,
    required this.imageAnalysisSize,
    required this.widgetSize,
    required this.cameraFacing,
    required this.onLabelTap,
    required this.isUrl,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: QRCodePainter(
        barcodes: barcodes,
        imageAnalysisSize: imageAnalysisSize,
        widgetSize: widgetSize,
        cameraFacing: cameraFacing,
      ),
      child: GestureDetector(
        onTapDown: (TapDownDetails details) {
          _handleTap(details.localPosition);
        },
        child: Container(
          width: widgetSize.width,
          height: widgetSize.height,
          color: Colors.transparent,
        ),
      ),
    );
  }

  void _handleTap(Offset tapPosition) {
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
              return Offset(dx, dy);
            }).toList();

        // Calculate text position (same logic as in painter)
        double textX = scaledCorners[0].dx;
        double textY =
            scaledCorners[0].dy - 40; // Approximate text height + padding

        if (textY < 5) {
          textY =
              (scaledCorners.length > 3
                  ? scaledCorners[3].dy
                  : scaledCorners[0].dy) +
              8;
        }
        if (textX < 5) {
          textX = 5;
        }
        if (textY > widgetSize.height - 25) {
          textY = widgetSize.height - 25;
        }

        // Create approximate text bounds for tap detection
        final textWidth = displayValue.length * 8.0; // Rough approximation
        final textHeight = 20.0; // Approximate text height
        final textRect = Rect.fromLTWH(
          textX - 4,
          textY - 4,
          textWidth + 8,
          textHeight + 8,
        );

        if (textRect.contains(tapPosition)) {
          onLabelTap(displayValue, tapPosition);
          return; // Only handle the first matching tap
        }
      }
    }
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

    final Paint urlBackgroundPaint =
        Paint()
          ..color = Colors.blue.withOpacity(0.8)
          ..style = PaintingStyle.fill;

    for (final barcode in barcodes) {
      final List<Offset?> corners = barcode.corners;
      final String displayValue =
          barcode.displayValue ?? barcode.rawValue ?? 'N/A';
      final bool isUrl = _isUrl(displayValue);

      if (corners.isNotEmpty && corners.length >= 4) {
        if (corners.any((p) => p == null)) continue;
        final List<Offset> validCorners = corners.cast<Offset>().toList();

        final List<Offset> scaledCorners =
            validCorners.map((corner) {
              double dx = corner.dx * scaleX + offsetX;
              double dy = corner.dy * scaleY + offsetY;
              return Offset(dx, dy);
            }).toList();

        final Path path = Path();
        path.moveTo(scaledCorners[0].dx, scaledCorners[0].dy);
        for (int i = 1; i < scaledCorners.length; i++) {
          path.lineTo(scaledCorners[i].dx, scaledCorners[i].dy);
        }
        path.close();
        canvas.drawPath(path, paint);

        // Create text with different styling for URLs
        final TextSpan span = TextSpan(
          text:
              isUrl
                  ? '🔗 $displayValue (tap to open)'
                  : '$displayValue (tap to copy)',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14.0,
            fontWeight: FontWeight.bold,
            decoration: isUrl ? TextDecoration.underline : TextDecoration.none,
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
          isUrl ? urlBackgroundPaint : backgroundPaint,
        );

        tp.paint(canvas, Offset(textX, textY));
      }
    }
  }

  bool _isUrl(String text) {
    final urlPattern = RegExp(
      r'^(https?:\/\/)?([\da-z\.-]+)\.([a-z\.]{2,6})([\/\w \.-]*)*\/?$',
      caseSensitive: false,
    );
    return urlPattern.hasMatch(text) ||
        text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.startsWith('www.');
  }

  @override
  bool shouldRepaint(covariant QRCodePainter oldDelegate) {
    return oldDelegate.barcodes != barcodes ||
        oldDelegate.imageAnalysisSize != imageAnalysisSize ||
        oldDelegate.widgetSize != widgetSize ||
        oldDelegate.cameraFacing != cameraFacing;
  }
}
