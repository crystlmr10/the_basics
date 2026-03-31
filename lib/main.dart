import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/settings_page.dart';
import 'pages/admin_dash.dart'; 

// App entry: bootstraps Supabase + global settings controller.
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
      // 1. LOOKUP: Find the email and role associated with the Admin ID (username)
      // This maps "admin.1" to "gironcrystalmarie@gmail.com"
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

      // 2. ROLE CHECK: Verify they are actually an admin
      if (role != 'admin') {
        throw Exception("Access Denied: This ID does not have admin privileges.");
      }

      // 3. AUTHENTICATE: Log in with the real email and password
      await Supabase.instance.client.auth.signInWithPassword(
        email: realEmail,
        password: password,
      );

      // 4. NAVIGATION: Success!
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
            backgroundColor: Colors.redAccent,
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
      backgroundColor: const Color(0xFFF4F7FA),
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_outlined, size: 48, color: Color(0xFF1A1A1B)),
              const SizedBox(height: 16),
              const Text(
                "Floote Admin",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Master Controller Access",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _adminIdController,
                decoration: const InputDecoration(
                  labelText: "Admin ID",
                  hintText: "e.g., admin.1",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
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
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text("Access Dashboard", style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}