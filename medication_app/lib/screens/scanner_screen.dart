import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../services/notification_service.dart';

class ScannerScreen extends StatefulWidget {
  final String backendUrl;
  const ScannerScreen({super.key, required this.backendUrl});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  late MobileScannerController _scannerController;
  final TextRecognizer _textRecognizer = TextRecognizer();
  
  bool _isScanning = true;
  bool _isLoading = false;
  bool _isOcrMode = false;
  String? _errorMessage;
  
  // Animation for the scanning line
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 0, end: 1).animate(_animationController);
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _textRecognizer.close();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (!_isScanning || _isLoading) return;
    
    final barcode = capture.barcodes.first;
    if (barcode.rawValue == null) return;

    setState(() {
      _isScanning = false;
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse("${widget.backendUrl}/api/medicine/${barcode.rawValue}"),
      );

      if (response.statusCode == 200) {
        NotificationService().triggerVibration();
        final data = jsonDecode(response.body);
        _showSuccess(data);
      } else {
        setState(() {
          _errorMessage = "Medicine not found. Try OCR or Manual entry.";
          _isLoading = false;
          _isScanning = true;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Network error. Please try again.";
        _isLoading = false;
        _isScanning = true;
      });
    }
  }

  Future<void> _performOcr() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      setState(() {
        _errorMessage = "OCR feature coming soon! Please use Barcode or Manual Entry.";
        _isLoading = false;
        _isScanning = true;
      });
    } catch (e) {
       setState(() {
        _errorMessage = "OCR error.";
        _isLoading = false;
        _isScanning = true;
      });
    }
  }

  void _showSuccess(Map<String, dynamic> data) {
    Navigator.pop(context, data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onBarcodeDetected,
          ),
          CustomPaint(
            painter: ScannerOverlayPainter(),
            child: Container(),
          ),
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Positioned(
                top: MediaQuery.of(context).size.height * 0.25 + (MediaQuery.of(context).size.height * 0.4 * _animation.value),
                left: MediaQuery.of(context).size.width * 0.15,
                right: MediaQuery.of(context).size.width * 0.15,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0EA5E9).withOpacity(0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 60,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            top: 70,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                _isOcrMode ? "Text Recognition" : "Barcode Scanner",
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (_errorMessage != null)
            Positioned(
              bottom: 120,
              left: 40,
              right: 40,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.8), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildActionButton(
                  icon: Icons.qr_code_scanner,
                  label: "Barcode",
                  isActive: !_isOcrMode,
                  onTap: () => setState(() => _isOcrMode = false),
                ),
                const SizedBox(width: 40),
                _buildActionButton(
                  icon: Icons.text_fields,
                  label: "OCR",
                  isActive: _isOcrMode,
                  onTap: () => setState(() => _isOcrMode = true),
                ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF0EA5E9)),
                    SizedBox(height: 20),
                    Text("Fetching Details...", style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF0EA5E9) : Colors.white24,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: GoogleFonts.outfit(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final width = size.width;
    final height = size.height;
    final scanBoxWidth = width * 0.7;
    final scanBoxHeight = height * 0.4;
    final left = (width - scanBoxWidth) / 2;
    final top = (height - scanBoxHeight) / 2;

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, width, height)),
        Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, scanBoxWidth, scanBoxHeight),
            const Radius.circular(20),
          )),
      ),
      paint,
    );

    final borderPaint = Paint()
      ..color = const Color(0xFF0EA5E9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, scanBoxWidth, scanBoxHeight),
        const Radius.circular(20),
      ),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
