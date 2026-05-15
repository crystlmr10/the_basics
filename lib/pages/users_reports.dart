import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminUser {
  final String id;
  final String name;
  final String email;
  final String status;
  final int floodReports;
  final int sosReports;
  final String joinDate;
  final bool isOnline;
  final String role;
  /// False when listing via REST fallback (no `profiles.status` in DB / RPC broken).
  final bool accountStatusWritable;

  AdminUser({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    required this.floodReports,
    required this.sosReports,
    required this.joinDate,
    required this.isOnline,
    required this.role,
    this.accountStatusWritable = true,
  });

  factory AdminUser.fromRpcMap(Map<String, dynamic> row) {
    final rawName = _readString(row['full_name']);
    final rawUsername = _readString(row['username']);
    final rawEmail = _readString(row['email']);
    final normalizedStatus = _normalizeStatusLabel(row['status']);
    final role = _readString(row['role']).isEmpty ? 'user' : _readString(row['role']);

    return AdminUser(
      id: row['user_id'].toString(),
      name: rawName.isNotEmpty
          ? rawName
          : (rawUsername.isNotEmpty ? rawUsername : 'Anonymous User'),
      email: rawEmail.isNotEmpty ? rawEmail : 'No Email Provided',
      status: normalizedStatus,
      floodReports: _toInt(row['flood_reports']),
      sosReports: _toInt(row['sos_reports']),
      joinDate: _formatJoinedDate(row['joined_at']),
      isOnline: _isOnlineStatus(row['status']),
      role: role,
      accountStatusWritable: true,
    );
  }

  /// REST fallback when RPC is unavailable or DB is missing `profiles.status`.
  factory AdminUser.fromProfileMaps({
    required Map<String, dynamic> profile,
    required int floodReports,
    required int sosReports,
    required bool statusColumnPresent,
  }) {
    final rawName = _readString(profile['full_name']);
    final rawUsername = _readString(profile['username']);
    final rawEmail = _readString(profile['email']);
    final rawStatus = profile['status'];
    final effectiveStatus =
        statusColumnPresent && rawStatus != null ? rawStatus : 'active';
    final normalizedStatus = _normalizeStatusLabel(effectiveStatus);
    final role =
        _readString(profile['role']).isEmpty ? 'user' : _readString(profile['role']);

    return AdminUser(
      id: profile['id'].toString(),
      name: rawName.isNotEmpty
          ? rawName
          : (rawUsername.isNotEmpty ? rawUsername : 'Anonymous User'),
      email: rawEmail.isNotEmpty ? rawEmail : 'No Email Provided',
      status: normalizedStatus,
      floodReports: floodReports,
      sosReports: sosReports,
      joinDate: 'N/A',
      isOnline: _isOnlineStatus(effectiveStatus),
      role: role,
      accountStatusWritable: statusColumnPresent,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _readString(dynamic value) => value?.toString().trim() ?? '';

  static String _formatJoinedDate(dynamic createdAt) {
    final raw = createdAt?.toString().trim() ?? '';
    if (raw.isEmpty) return 'N/A';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.split('T').first;
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day';
  }

  static bool _isOnlineStatus(dynamic rawStatus) {
    final normalized = rawStatus?.toString().trim().toLowerCase() ?? '';
    return normalized == 'active';
  }

  static String _normalizeStatusLabel(dynamic rawStatus) {
    final normalized = rawStatus?.toString().trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return 'Inactive';
    if (normalized == 'active') return 'Active';
    if (normalized == 'inactive') return 'Inactive';
    return normalized
        .split(RegExp(r'[\s_]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

class _AdminUsersLoadResult {
  final List<AdminUser> users;
  final String? errorMessage;
  final String? warningMessage;

  const _AdminUsersLoadResult({
    required this.users,
    this.errorMessage,
    this.warningMessage,
  });
}

class AdminUserManagementPage extends StatefulWidget {
  const AdminUserManagementPage({super.key});

  @override
  State<AdminUserManagementPage> createState() => _AdminUserManagementPageState();
}

class _AdminUserManagementPageState extends State<AdminUserManagementPage> {
  final supabase = Supabase.instance.client;
  late Future<_AdminUsersLoadResult> _usersFuture;
  String? _updatingUserId;

  @override
  void initState() {
    super.initState();
    _usersFuture = fetchAdminUsers();
  }

  Future<_AdminUsersLoadResult> fetchAdminUsers() async {
    try {
      final data = await supabase.rpc('admin_user_management_list');
      if (data is! List) {
        return await _fetchAdminUsersDirect(
          reason: 'Unexpected RPC response (expected a list).',
        );
      }
      final rows = data.whereType<Map>().map((m) {
        final out = <String, dynamic>{};
        for (final entry in m.entries) {
          out[entry.key.toString()] = entry.value;
        }
        return out;
      }).toList();
      final adminUsers = rows.map(AdminUser.fromRpcMap).toList();

      return _AdminUsersLoadResult(users: adminUsers);
    } on PostgrestException catch (e) {
      if (_shouldFallbackToDirectFetch(e)) {
        return await _fetchAdminUsersDirect(
          reason: _fullPostgrestMessage(e),
        );
      }
      return _AdminUsersLoadResult(
        users: const [],
        errorMessage: _errorMessageForPostgrest(e),
      );
    } catch (e) {
      return _AdminUsersLoadResult(
        users: const [],
        errorMessage: 'Unexpected error while loading users: $e',
      );
    }
  }

  bool _shouldFallbackToDirectFetch(PostgrestException e) {
    final blob = _fullPostgrestMessage(e).toLowerCase();
    if (blob.contains('p.status') && blob.contains('does not exist')) {
      return true;
    }
    if (blob.contains('profiles.status') && blob.contains('does not exist')) {
      return true;
    }
    if (blob.contains('column') &&
        blob.contains('status') &&
        blob.contains('does not exist')) {
      return true;
    }
    if (blob.contains('function') &&
        blob.contains('admin_user_management_list') &&
        blob.contains('does not exist')) {
      return true;
    }
    return false;
  }

  String _fullPostgrestMessage(PostgrestException e) {
    final parts = <String>[e.message.trim()];
    final d = e.details?.toString().trim();
    if (d != null && d.isNotEmpty) parts.add(d);
    final h = e.hint?.toString().trim();
    if (h != null && h.isNotEmpty) parts.add(h);
    return parts.join(' ');
  }

  Future<_AdminUsersLoadResult> _fetchAdminUsersDirect({required String reason}) async {
    try {
      final profilesData = await supabase.from('profiles').select() as List;
      final floodRows =
          await supabase.from('user_reports').select('user_id') as List;
      final floodCounts = <String, int>{};
      for (final raw in floodRows) {
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['user_id']?.toString().trim();
        if (id == null || id.isEmpty) continue;
        floodCounts[id] = (floodCounts[id] ?? 0) + 1;
      }

      final sosCounts = <String, int>{};
      try {
        final sosRows =
            await supabase.from('sos_dispatches').select('user_id') as List;
        for (final raw in sosRows) {
          if (raw is! Map<String, dynamic>) continue;
          final id = raw['user_id']?.toString().trim();
          if (id == null || id.isEmpty) continue;
          sosCounts[id] = (sosCounts[id] ?? 0) + 1;
        }
      } catch (_) {
        // sos_dispatches may be blocked by RLS or schema drift — keep flood counts only.
      }

      String sortKey(Map<String, dynamic> p) {
        final e = p['email']?.toString().trim() ?? '';
        if (e.isNotEmpty) return e.toLowerCase();
        final u = p['username']?.toString().trim() ?? '';
        if (u.isNotEmpty) return u.toLowerCase();
        return p['id'].toString().toLowerCase();
      }

      final rows = profilesData.whereType<Map<String, dynamic>>().toList()
        ..sort((a, b) => sortKey(a).compareTo(sortKey(b)));

      final statusColumnPresent = rows.isNotEmpty &&
          rows.any((p) => p.containsKey('status'));

      final users = rows
          .map(
            (p) => AdminUser.fromProfileMaps(
              profile: p,
              floodReports: floodCounts[p['id'].toString()] ?? 0,
              sosReports: sosCounts[p['id'].toString()] ?? 0,
              statusColumnPresent: statusColumnPresent,
            ),
          )
          .toList();

      return _AdminUsersLoadResult(
        users: users,
        warningMessage: statusColumnPresent
            ? 'Loaded via fallback (admin RPC unavailable). Reason: $reason'
            : 'Loaded via fallback — `profiles.status` missing or RPC failed. '
                  'Reason: $reason\n'
                  'Run `profiles_ensure_status.sql` + `admin_user_management_rpc.sql`, '
                  'then reload API schema. Activate/Deactivate disabled until then.',
      );
    } on PostgrestException catch (e) {
      return _AdminUsersLoadResult(
        users: const [],
        errorMessage: _errorMessageForPostgrest(e),
      );
    } catch (e) {
      return _AdminUsersLoadResult(
        users: const [],
        errorMessage: 'Fallback load failed: $e\nOriginal: $reason',
      );
    }
  }

  String _errorMessageForPostgrest(PostgrestException e) {
    final message = _fullPostgrestMessage(e);
    final lower = message.toLowerCase();
    if (lower.contains('admin_user_management_list') &&
        lower.contains('does not exist')) {
      return 'Missing SQL function `admin_user_management_list`. '
          'Run `supabase/sql/admin_user_management_rpc.sql` in Supabase SQL editor.';
    }
    if (lower.contains('p.status') ||
        lower.contains('profiles.status') ||
        (lower.contains('column') && lower.contains('status'))) {
      return 'Database is missing `profiles.status` (or PostgREST cache is stale).\n'
          '1) Run `supabase/sql/profiles_ensure_status.sql` in Supabase SQL Editor.\n'
          '2) Run `supabase/sql/admin_user_management_rpc.sql` again.\n'
          '3) Supabase Dashboard → Settings → API → Reload schema.\n'
          'Raw error: $message';
    }
    if (lower.contains('permission') || lower.contains('rls')) {
      return 'Permission denied while loading users. Check admin RLS policies.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network issue while loading users. Check connection and retry.';
    }
    return message.isEmpty
        ? 'Database error while loading users.'
        : 'Database error: $message';
  }

  void _refreshUsers() {
    setState(() {
      _usersFuture = fetchAdminUsers();
    });
  }

  Future<void> _toggleAccountStatus(AdminUser user) async {
    final shouldActivate = !user.isOnline;
    final actionLabel = shouldActivate ? 'activate' : 'deactivate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${shouldActivate ? 'Activate' : 'Deactivate'} Account'),
        content: Text(
          'Are you sure you want to $actionLabel ${user.name}? '
          'This is a soft account status change and does not delete data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(shouldActivate ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _updatingUserId = user.id);
    try {
      final res = await supabase.rpc(
        'admin_user_management_set_status',
        params: {
          'p_user_id': user.id,
          'p_status': shouldActivate ? 'active' : 'inactive',
        },
      );
      final map = res is Map
          ? Map<String, dynamic>.from(res)
          : <String, dynamic>{};
      if (map['ok'] != true) {
        final err = (map['error'] ?? 'unknown_error').toString();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not update account: $err'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.name} ${shouldActivate ? 'activated' : 'deactivated'}.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _refreshUsers();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessageForPostgrest(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: FutureBuilder<_AdminUsersLoadResult>(
        future: _usersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final result = snapshot.data;
          if (result == null) {
            return _buildStateMessage(
              title: 'Could not load users',
              subtitle: 'No response received. Please refresh and try again.',
            );
          }
          if (result.errorMessage != null) {
            return _buildStateMessage(
              title: 'Unable to load user data',
              subtitle: result.errorMessage!,
              showRetry: true,
            );
          }

          final users = result.users;
          final activeUsers = users.where((u) => u.isOnline).length;
          final inactiveUsers = users.length - activeUsers;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.warningMessage != null) ...[
                  Material(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.amber.shade900, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              result.warningMessage!,
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text("Monitor registered users and report activity from Supabase", 
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
                
                // --- Stat Cards ---
                Row(
                  children: [
                    _buildStatCard(
                      "Total Users",
                      "${users.length}",
                      Icons.group_outlined,
                      Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      "Active Users",
                      "$activeUsers",
                      Icons.circle,
                      Colors.green,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      "Inactive",
                      "$inactiveUsers",
                      Icons.person_off_outlined,
                      Colors.grey,
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // --- User Table ---
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
                    ],
                  ),
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) => SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minWidth: constraints.maxWidth),
                            child: DataTable(
                              horizontalMargin: 24,
                              columnSpacing: 28,
                              headingTextStyle: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                              columns: const [
                                DataColumn(label: Text("USER")),
                                DataColumn(label: Text("STATUS")),
                                DataColumn(label: Text("FLOOD REPORTS")),
                                DataColumn(label: Text("SOS REPORTS")),
                                DataColumn(label: Text("JOINED")),
                                DataColumn(label: Text("ACTION")),
                              ],
                              rows: users
                                  .map((user) => _buildUserRow(user))
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                      if (users.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 4, 16, 20),
                          child: Text(
                            'No users found.',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStateMessage({
    required String title,
    required String subtitle,
    bool showRetry = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.blueGrey),
            ),
            if (showRetry) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _refreshUsers,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // UI Helper for Stat Cards
  Widget _buildStatCard(String title, String count, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                const SizedBox(height: 4),
                Text(count, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
            const Spacer(),
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1), 
              radius: 16,
              child: Icon(icon, color: color, size: 14),
            )
          ],
        ),
      ),
    );
  }

  DataRow _buildUserRow(AdminUser user) {
    final isUpdating = _updatingUserId == user.id;
    final canToggle =
        user.role.toLowerCase() != 'admin' && user.accountStatusWritable;
    return DataRow(cells: [
      DataCell(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              Text(user.email, style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
        ),
      ),
      DataCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: user.isOnline
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            user.isOnline ? 'Active' : 'Inactive',
            style: TextStyle(
              color: user.isOnline ? Colors.green : Colors.grey,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      DataCell(
        Text("${user.floodReports}", style: const TextStyle(fontSize: 12)),
      ),
      DataCell(
        Text("${user.sosReports}", style: const TextStyle(fontSize: 12)),
      ),
      DataCell(Text(user.joinDate, style: const TextStyle(fontSize: 12))),
      DataCell(
        FilledButton.tonal(
          onPressed: (!canToggle || isUpdating)
              ? null
              : () => _toggleAccountStatus(user),
          style: FilledButton.styleFrom(
            backgroundColor: user.isOnline
                ? Colors.red.withValues(alpha: 0.1)
                : Colors.green.withValues(alpha: 0.12),
            foregroundColor: user.isOnline
                ? Colors.red.shade700
                : Colors.green.shade700,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          child: isUpdating
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  canToggle
                      ? (user.isOnline ? 'Deactivate' : 'Activate')
                      : 'Protected',
                ),
        ),
      ),
    ]);
  }
}