import 'package:flutter/material.dart';

class AccessControlPage extends StatefulWidget {
  const AccessControlPage({super.key});

  @override
  State<AccessControlPage> createState() => _AccessControlPageState();
}

class _AccessControlPageState extends State<AccessControlPage> {
  static const Map<String, List<String>> _rolePermissions = {
    'Regular User': [
      'view_navigation_map',
      'submit_help_request',
      'view_alert_notifications',
      'view_safe_routes',
    ],
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

  String _selectedRole = 'Admin';
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String _newAccountRole = 'Rescuer';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissions = _rolePermissions[_selectedRole] ?? const <String>[];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.admin_panel_settings_outlined, color: Colors.blueGrey),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Access Control', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                    SizedBox(height: 4),
                    Text(
                      'Manage RBAC for Regular Users, Rescuers, and Admins',
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _SectionCard(
                    title: 'Role Templates',
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Preview Role'),
                          trailing: DropdownButton<String>(
                            value: _selectedRole,
                            onChanged: (v) => setState(() => _selectedRole = v ?? 'Admin'),
                            items: _rolePermissions.keys
                                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
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
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                                    ),
                                    child: Text(
                                      p,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
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
                  _SectionCard(
                    title: 'Create Account + Assign Role',
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _emailCtrl,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _newAccountRole,
                          onChanged: (v) => setState(() => _newAccountRole = v ?? 'Rescuer'),
                          items: const [
                            DropdownMenuItem(value: 'Regular User', child: Text('Regular User')),
                            DropdownMenuItem(value: 'Rescuer', child: Text('Rescuer')),
                            DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Role',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: () {
                              final name = _nameCtrl.text.trim();
                              final email = _emailCtrl.text.trim();
                              if (name.isEmpty || email.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter name and email.')),
                                );
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Prepared account "$name" as $_newAccountRole.',
                                  ),
                                ),
                              );
                            },
                            child: const Text('Create Access'),
                          ),
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
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

