import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccessControlPage extends StatefulWidget {
  const AccessControlPage({super.key});

  @override
  State<AccessControlPage> createState() => _AccessControlPageState();
}

class _AccessControlPageState extends State<AccessControlPage> {
  static const Map<String, List<String>> _rolePermissions = {
    'Rescuer': [
      'view_assigned_requests',
      'confirm_help_request',
      'update_rescue_status',
      'view_rescue_map',
    ],
    'Admin': [
      'access_admin_dashboard',
      'manage_alerts',
      'dispatch_rescuers',
      'manage_users_and_roles',
      'view_logs_and_analytics',
      'edit_system_settings',
    ],
  };

  // Role Templates
  String _selectedRole = 'Admin';

  // Create Account
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _newAccountRole = 'Rescuer';
  bool _obscurePassword = true;
  bool _creating = false;

  final _supabase = Supabase.instance.client;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Supabase: Create Account ─────────────────────────────────────────────

  Future<void> _createAccount() async {
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (name.isEmpty || username.isEmpty || password.isEmpty) {
      _showSnackBar('Please fill in all fields.', isError: true);
      return;
    }

    if (password.length < 6) {
      _showSnackBar('Password must be at least 6 characters.', isError: true);
      return;
    }

    setState(() => _creating = true);

    try {
      // 1. Create auth user via Admin API
      //    Requires the Supabase client to be initialized with service role key.
      //    Constructs a system email from username so auth has a valid identifier.
      final res = await _supabase.auth.admin.createUser(
        AdminUserAttributes(
          email: '$username@cebu161.local',
          password: password,
          emailConfirm: true,
          userMetadata: {
            'username': username,
            'name': name,
          },
        ),
      );

      final userId = res.user?.id;
      if (userId == null) throw Exception('User creation returned no ID.');

      // 2. Upsert into profiles table
      await _supabase.from('profiles').upsert({
        'id': userId,
        'username': username,
        'email': '$username@cebu161.local',
        'role': _newAccountRole.toLowerCase(), // 'admin' or 'rescuer'
        'is_on_duty': false,
      });

      // 3. Clear form
      _nameCtrl.clear();
      _usernameCtrl.clear();
      _passwordCtrl.clear();

      _showSnackBar('Account "$name" created as $_newAccountRole.');
    } on AuthException catch (e) {
      _showSnackBar('Auth error: ${e.message}', isError: true);
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final permissions = _rolePermissions[_selectedRole] ?? const <String>[];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // ── Header
          const Row(
            children: [
              Icon(Icons.admin_panel_settings_outlined, color: Colors.blueGrey),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Access Control',
                      style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage RBAC for Rescuers and Admins',
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Body
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // ── Role Templates
                  _SectionCard(
                    title: 'Role Templates',
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Preview Role'),
                          trailing: DropdownButton<String>(
                            value: _selectedRole,
                            onChanged: (v) =>
                                setState(() => _selectedRole = v ?? 'Admin'),
                            items: _rolePermissions.keys
                                .map((r) => DropdownMenuItem(
                                    value: r, child: Text(r)))
                                .toList(),
                          ),
                        ),
                        const Divider(),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: permissions
                                .map(
                                  (p) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(999),
                                      border: Border.all(
                                          color: Colors.black
                                              .withValues(alpha: 0.08)),
                                    ),
                                    child: Text(
                                      p,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Create Account
                  _SectionCard(
                    title: 'Create Account + Assign Role',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name
                        TextField(
                          controller: _nameCtrl,
                          enabled: !_creating,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            hintText: 'e.g. Juan Dela Cruz',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Username
                        TextField(
                          controller: _usernameCtrl,
                          enabled: !_creating,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            hintText: 'e.g. jdelacruz',
                            prefixIcon: const Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Password
                        TextField(
                          controller: _passwordCtrl,
                          enabled: !_creating,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _createAccount(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Min. 6 characters',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Role selector — Admin & Rescuer only
                        DropdownButtonFormField<String>(
                          initialValue: _newAccountRole,
                          onChanged: _creating
                              ? null
                              : (v) => setState(
                                  () => _newAccountRole = v ?? 'Rescuer'),
                          items: const [
                            DropdownMenuItem(
                                value: 'Rescuer', child: Text('Rescuer')),
                            DropdownMenuItem(
                                value: 'Admin', child: Text('Admin')),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Role',
                            prefixIcon:
                                const Icon(Icons.shield_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Role badge preview
                        _RoleBadgePreview(role: _newAccountRole),

                        const SizedBox(height: 16),

                        // Submit button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _creating ? null : _createAccount,
                            icon: _creating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.person_add_outlined),
                            label: Text(
                              _creating ? 'Creating...' : 'Create Account',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey.shade800,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Note about admin API
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 13,
                                color: Colors.blueGrey.shade400),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Requires Supabase client initialized with service role key.',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueGrey.shade400),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Role Badge Preview ───────────────────────────────────────────────────────

class _RoleBadgePreview extends StatelessWidget {
  final String role;
  const _RoleBadgePreview({required this.role});

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'Admin';
    final color = isAdmin ? Colors.purple : Colors.teal;
    final icon = isAdmin ? Icons.admin_panel_settings : Icons.health_and_safety_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            'Will be created as: $role',
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Section Card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}