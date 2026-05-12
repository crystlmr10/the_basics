import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/philippine_mobile_input_formatter.dart';
import '../utils/philippine_phone.dart';

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
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _newAccountRole = 'Rescuer';
  bool _obscurePassword = true;
  bool _creating = false;

  final _supabase = Supabase.instance.client;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Supabase: Create Account ─────────────────────────────────────────────

  Future<void> _createAccount() async {
    final firstName = _firstNameCtrl.text.trim();
    final middleName = _middleNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final name = [firstName, middleName, lastName]
        .where((part) => part.isNotEmpty)
        .join(' ');
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final role = _newAccountRole.toLowerCase();
    final usernameRule = RegExp(r'^[a-zA-Z0-9._-]{3,32}$');
    final phoneE164 = normalizePhilippineMobile(_phoneCtrl.text);
    final nationalDigits = extractPhilippineNationalInputDigits(_phoneCtrl.text);

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        username.isEmpty ||
        password.isEmpty) {
      _showSnackBar('Please fill in all fields.', isError: true);
      return;
    }

    final requiresPhone = role == 'rescuer';
    if (requiresPhone && nationalDigits.isEmpty) {
      _showSnackBar('Please enter a phone number.', isError: true);
      return;
    }

    if (nationalDigits.isNotEmpty &&
        (phoneE164 == null || nationalDigits.length != 10)) {
      _showSnackBar(
        'Enter a valid Philippine mobile number (+63 9XX XXX XXXX).',
        isError: true,
      );
      return;
    }

    if (!usernameRule.hasMatch(username)) {
      _showSnackBar(
        'Username must be 3-32 chars (letters, numbers, dot, underscore, hyphen).',
        isError: true,
      );
      return;
    }

    if (password.length < 6) {
      _showSnackBar('Password must be at least 6 characters.', isError: true);
      return;
    }

    setState(() => _creating = true);

    try {
      final response = await _supabase.functions.invoke(
        'admin-create-account',
        body: {
          'fullName': name,
          'username': username,
          'phoneNumber': phoneE164,
          'password': password,
          'role': role,
        },
      );

      final data = response.data;
      if (response.status < 200 || response.status >= 300) {
        _showSnackBar(
          _adminFacingAccountError(
            status: response.status,
            body: data,
          ),
          isError: true,
        );
        return;
      }

      // Clear form
      _firstNameCtrl.clear();
      _middleNameCtrl.clear();
      _lastNameCtrl.clear();
      _usernameCtrl.clear();
      _phoneCtrl.clear();
      _passwordCtrl.clear();

      _showSnackBar(
        'Account created successfully.',
      );
    } on FunctionException catch (e) {
      _showSnackBar(
        _adminFacingAccountError(status: e.status, body: e.details),
        isError: true,
      );
    } catch (_) {
      _showSnackBar(
        'Something went wrong. Please try again in a moment.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  /// Maps Edge Function `{ "code": "..." }` (and HTTP status) to admin-facing copy.
  /// Never surfaces raw backend or database text.
  String _adminFacingAccountError({required int status, dynamic body}) {
    String? code;
    if (body is Map) {
      final raw = body['code'];
      if (raw is String && raw.isNotEmpty) code = raw;
    }

    const byCode = <String, String>{
      'METHOD_NOT_ALLOWED': 'This action is not available. Please refresh the page.',
      'NOT_AUTHENTICATED': 'Please sign in again, then retry.',
      'INVALID_SESSION': 'Your session has expired. Please sign in again.',
      'FORBIDDEN_NOT_ADMIN': 'You do not have permission to create accounts.',
      'MALFORMED_REQUEST': 'The request could not be processed. Check your input and try again.',
      'MISSING_FIELDS': 'Please complete all required fields.',
      'INVALID_USERNAME': 'Username format is not valid. Use 3–32 letters, numbers, dot, underscore, or hyphen.',
      'INVALID_PHONE':
          'Phone number must be a valid Philippine mobile (+63 9XX XXX XXXX).',
      'INVALID_PASSWORD': 'Password must be at least 6 characters.',
      'INVALID_ROLE': 'That role cannot be assigned from this screen.',
      'DUPLICATE_USERNAME':
          'That username is already in use. Choose a different one.',
      'DUPLICATE_PHONE':
          'That phone number is already registered. Use a different number.',
      // Legacy code (older Edge deployments); treat same as duplicate username.
      'DUPLICATE_USERNAME_OR_USER_ID':
          'That username is already in use. Choose a different one.',
      'ACCOUNT_CREATE_UNAVAILABLE':
          'The account could not be created right now. Try again later or contact support.',
      'PROFILE_SYNC_FAILED':
          'The account was created but could not be finalized. Please contact support.',
      'SERVICE_UNAVAILABLE':
          'The service is temporarily unavailable. Please try again shortly.',
    };

    if (code != null) {
      final mapped = byCode[code];
      if (mapped != null) return mapped;
    }

    if (status == 401) {
      return byCode['NOT_AUTHENTICATED']!;
    }
    if (status == 403) {
      return byCode['FORBIDDEN_NOT_ADMIN']!;
    }
    if (status == 409) {
      return 'That username or phone number is already in use. Choose a different one.';
    }
    if (status == 400) {
      return 'Some information looks invalid. Please review the form and try again.';
    }
    if (status >= 500) {
      return byCode['SERVICE_UNAVAILABLE']!;
    }
    return 'The account could not be created. Please try again.';
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
                          controller: _firstNameCtrl,
                          enabled: !_creating,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'First Name',
                            hintText: 'e.g. Juan',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),

                        TextField(
                          controller: _middleNameCtrl,
                          enabled: !_creating,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Middle Name (Optional)',
                            hintText: 'e.g. Dela',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),

                        TextField(
                          controller: _lastNameCtrl,
                          enabled: !_creating,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Last Name',
                            hintText: 'e.g. Cruz',
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

                        // Phone (+63 national segment: 9XX XXX XXXX)
                        TextField(
                          controller: _phoneCtrl,
                          enabled: !_creating,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            PhilippineNationalMobileInputFormatter(),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Phone Number',
                            hintText: '9XX XXX XXXX',
                            prefixIcon: Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: 12,
                                end: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '🇵🇭',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '+63',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.blueGrey.shade800,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 1,
                                    height: 22,
                                    color: Colors.black.withValues(alpha: 0.15),
                                  ),
                                ],
                              ),
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 108,
                              minHeight: 48,
                            ),
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
                                'Staff accounts are created through a secure admin process.',
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