import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/admin_dash.dart'; // Ensure this matches your dashboard file name

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase for the Admin Website
  await Supabase.initialize(
    url: 'https://ttsrktldvvqrgkfhsbbl.supabase.co/',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR0c3JrdGxkdnZxcmdrZmhzYmJsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI1NDYxODcsImV4cCI6MjA4ODEyMjE4N30.DkQAOtyA4gezkPFCWPtyoS2UKw2NYvZcAlsAWbql3QY', // Paste your real anon key here!
  );

  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Floote Admin Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A1A1B)),
        useMaterial3: true,
      ),
      // This is the screen your logout button routes back to
      home: const FlooteLoginScreen(), 
    );
  }
}

class FlooteLoginScreen extends StatefulWidget {
  const FlooteLoginScreen({super.key});

  @override
  State<FlooteLoginScreen> createState() => _FlooteLoginScreenState();
}

class _FlooteLoginScreenState extends State<FlooteLoginScreen> {
  // Changed controller name to reflect it takes an ID, not a full email
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
    setState(() => _isLoading = true);
    try {
      final adminID = _adminIdController.text.trim();
      final password = _passwordController.text;

      // 1. Format the ID to match the admin dummy email we created in Supabase
      String formattedEmail = "$adminID@admin.floote.com";

      // 2. Send the formatted credentials to Supabase for verification
      final AuthResponse res = await Supabase.instance.client.auth.signInWithPassword(
        email: formattedEmail,
        password: password,
      );

      // 3. Double-check they actually have admin privileges in the profiles table
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', res.user!.id)
          .single();

      if (profile['role'] == 'admin') {
        // 4. If successful, push them to the Dashboard
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AdminDashboard()),
          );
        }
      } else {
        // Kick them out if a standard user tries to log in here
        await Supabase.instance.client.auth.signOut();
        throw Exception("Access Denied: Not an authorized admin account.");
      }
    } catch (e) {
      // 5. If it fails, show an error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login failed: Invalid Admin ID or Password'),
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
      backgroundColor: const Color(0xFFF4F7FA), // Matches your dashboard background
      body: Center(
        child: Container(
          width: 400, // Keeps the login box a nice fixed size on a web browser
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
              
              // Changed from Email to Admin ID input
              TextField(
                controller: _adminIdController,
                decoration: const InputDecoration(
                  labelText: "Admin ID",
                  hintText: "e.g., admin.1",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline), // Updated icon
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