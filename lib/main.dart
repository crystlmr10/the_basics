import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:simple_animations/simple_animations.dart';

// Ensure these paths are correct for your project structure
import 'pages/settings_page.dart';
import 'pages/admin_dash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://ttsrktldvvqrgkfhsbbl.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR0c3JrdGxkdnZxcmdrZmhzYmJsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI1NDYxODcsImV4cCI6MjA4ODEyMjE4N30.DkQAOtyA4gezkPFCWPtyoS2UKw2NYvZcAlsAWbql3QY',
  );

  runApp(const AdminApp());
}

class AdminApp extends StatefulWidget {
  const AdminApp({super.key});

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  final AppSettingsController _settings = AppSettingsController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _settings.load();
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) => MaterialApp(
        title: 'Floote Admin Control',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const AppScrollBehavior(),
        themeMode: _settings.themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _settings.primaryColor),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _settings.primaryColor,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: FlooteLoginScreen(settings: _settings),
      ),
    );
  }
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: false,
      trackVisibility: false,
      child: child,
    );
  }
}

class FlooteLoginScreen extends StatefulWidget {
  final AppSettingsController settings;
  const FlooteLoginScreen({super.key, required this.settings});

  @override
  State<FlooteLoginScreen> createState() => _FlooteLoginScreenState();
}

class _FlooteLoginScreenState extends State<FlooteLoginScreen> {
  final _adminIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _adminIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _adminLogin() async {
    final adminID = _adminIdController.text.trim();
    final password = _passwordController.text;

    if (adminID.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter both Admin ID and Password")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userQuery = await Supabase.instance.client
          .from('profiles')
          .select('email, role')
          .eq('username', adminID)
          .maybeSingle();

      if (userQuery == null) {
        throw Exception("Admin ID '$adminID' not found.");
      }

      final String realEmail = userQuery['email'];
      final String role = userQuery['role'];

      if (role != 'admin') {
        throw Exception("Access Denied: This ID does not have admin privileges.");
      }

      await Supabase.instance.client.auth.signInWithPassword(
        email: realEmail,
        password: password,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AdminDashboard(
              initialIndex: 0,
              settings: widget.settings,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: ${e.toString().replaceAll("Exception:", "")}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedWaveBackground()),
          Center(
            child: PlayAnimationBuilder<double>(
              tween: Tween(begin: -20.0, end: 0.0),
              duration: const Duration(seconds: 1),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, value),
                  child: child,
                );
              },
              child: PlayAnimationBuilder<double>(
                tween: Tween(begin: 0.95, end: 1.0),
                duration: const Duration(seconds: 2),
                curve: Curves.easeInOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: child,
                  );
                },
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha((255 * 0.85).round()),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha((255 * 0.1).round()),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      )
                    ],
                    border: Border.all(color: Colors.white.withAlpha((255 * 0.5).round())),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined, size: 48, color: Color(0xFF1A1A1B)),
                      const SizedBox(height: 16),
                      const Text(
                        "Floote Admin",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Master Controller Access",
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _adminIdController,
                        decoration: InputDecoration(
                          labelText: "Admin ID",
                          hintText: "e.g., admin.1",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: "Password",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _adminLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A1A1B),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 5,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : const Text("Access Dashboard",
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedWaveBackground extends StatelessWidget {
  const AnimatedWaveBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final tween = MovieTween()
      ..tween('color1', ColorTween(begin: Colors.blue.shade200, end: Colors.blue.shade400),
          duration: const Duration(seconds: 4))
      ..tween('color2', ColorTween(begin: Colors.cyan.shade200, end: Colors.cyan.shade400),
          duration: const Duration(seconds: 4));

    return LoopAnimationBuilder<Movie>(
      tween: tween,
      duration: tween.duration,
      builder: (context, value, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [value.get("color1"), value.get("color2")],
            ),
          ),
          child: child,
        );
      },
      child: const Wave(),
    );
  }
}

class Wave extends StatelessWidget {
  const Wave({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: PlayAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(seconds: 3),
        builder: (context, value, child) {
          return CustomPaint(
            painter: WavePainter(animationValue: value),
          );
        },
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  final double animationValue;

  WavePainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha((255 * 0.1).round())
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height * 0.8);

    for (double i = 0; i < size.width; i++) {
      path.lineTo(
        i,
        size.height * 0.8 +
            (animationValue * 10) *
                (i / size.width * 2 - 1).abs() *
                (i % 100 / 50 - 1).abs() *
                20 *
                (1 + math.sin(animationValue * 2 * math.pi)),
      );
    }

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}