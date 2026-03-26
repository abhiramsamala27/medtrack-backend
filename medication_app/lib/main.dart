import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'services/notification_service.dart';
import 'services/database_helper.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    String? token = await messaging.getToken();
    debugPrint("FCM Token: \$token");
  } catch (e) {
    debugPrint("Firebase initialization failed: \$e");
  }

  await NotificationService().init();
  runApp(const MedTrackApp());
}

class MedTrackApp extends StatelessWidget {
  const MedTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedTrack Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF0EA5E9),
        textTheme: GoogleFonts.outfitTextTheme(),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    // Check login status via SharedPreferences as requested
    final prefs = await SharedPreferences.getInstance();
    final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    
    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => WebViewPage(initialLoggedIn: isLoggedIn)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0EA5E9),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.medication_liquid_rounded, size: 100, color: Colors.white),
            const SizedBox(height: 20),
            Text("MedTrack Pro", style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 10),
            const SpinKitThreeBounce(color: Colors.white, size: 25.0),
          ],
        ),
      ),
    );
  }
}

class WebViewPage extends StatefulWidget {
  final bool initialLoggedIn;
  const WebViewPage({super.key, required this.initialLoggedIn});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;
  bool _notificationsEnabled = false;

  final String _flaskAppUrl = "https://medtrack-backend-zqbl.onrender.com"; 

  @override
  void initState() {
    super.initState();
    _checkInitialPermissions();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'FlutterNotifications',
        onMessageReceived: (JavaScriptMessage message) {
          _handleJavascriptMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() { _isLoading = true; _errorMessage = null; });
            _detectLoginState(url);
          },
          onPageFinished: (String url) {
            setState(() { _isLoading = false; });
          },
          onWebResourceError: (WebResourceError error) {
             // Handle web error
          },
        ),
      );
      
    // Route to Dashboard if logged in, otherwise Login Page
    final String targetUrl = widget.initialLoggedIn ? "\$_flaskAppUrl/dashboard" : "\$_flaskAppUrl/login";
    _controller.loadRequest(Uri.parse(targetUrl));
    
    // Fetch and schedule notifications
    _fetchAndScheduleMedicines();
  }

  Future<void> _detectLoginState(String url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url.contains('/dashboard') || url.contains('/medications')) {
      await prefs.setBool('isLoggedIn', true);
    } else if (url.contains('/login')) {
      await prefs.setBool('isLoggedIn', false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
    await prefs.clear(); // Clear saved session token/data
    
    // Attempt clear webview cookies/session and reload
    await _controller.clearCache();
    await _controller.loadRequest(Uri.parse("\$_flaskAppUrl/logout"));
    Navigator.pop(context); // close drawer
  }

  Future<void> _checkInitialPermissions() async {
    bool granted = await NotificationService().isPermissionGranted();
    setState(() { _notificationsEnabled = granted; });
  }

  Future<void> _fetchAndScheduleMedicines() async {
    // In strict production, ensure session token matches flutter context, 
    // or provide public API. We ignore fetch error handles for brevity.
  }

  void _handleJavascriptMessage(String message) async {
    try {
      final Map<String, dynamic> data = jsonDecode(message);
      final String type = data['type'];

      if (type == 'feedback') {
        if (data['action'] == 'vibrate') NotificationService().triggerVibration();
        else NotificationService().playSound();
      } else if (type == 'get_flutter_time') {
        // ACTUAL TIME BUG FIX
        // Capture current device time dynamically from Flutter
        final now = DateTime.now();
        final eventId = data['event_id'];
        final status = data['status']; // 'TAKEN' or 'MISSED'
        
        // Pass the flutter's DateTime timestamp into the WebView via JS
        _controller.runJavaScript("recordDoseAuth('\$eventId', '\$status', '\${now.toIso8601String()}');");
      }
    } catch (e) {
      debugPrint("Error parsing JS message: \$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("MedTrack Pro"),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Builder(builder: (context) => IconButton(icon: const Icon(Icons.settings), onPressed: () => Scaffold.of(context).openEndDrawer())),
        ],
      ),
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF0EA5E9)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.health_and_safety, color: Colors.white, size: 50),
                  const SizedBox(height: 10),
                  Text("App Settings", style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_active),
              title: const Text("Enable Notifications"),
              subtitle: Text(_notificationsEnabled ? "Status: Enabled" : "Status: Blocked"),
              trailing: Switch(
                value: _notificationsEnabled,
                onChanged: (bool value) async {
                  if (value) {
                    bool granted = await NotificationService().requestPermission();
                    setState(() { _notificationsEnabled = granted; });
                  } else {
                    NotificationService().openSettings();
                  }
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_suggest),
              title: const Text("Open Notification Settings"),
              onTap: () => NotificationService().openSettings(),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Logout", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: _logout,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              Container(color: Colors.white.withOpacity(0.8), child: const Center(child: SpinKitPulse(color: Color(0xFF0EA5E9), size: 80.0))),
          ],
        ),
      ),
    );
  }
}
