import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- DATA MODEL ---
class AdminUser {
  final String id;
  final String name;
  final String email;
  final String status;
  final int reportsCount;
  final String joinDate;

  AdminUser({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    required this.reportsCount,
    required this.joinDate,
  });

  // Maps Supabase data to our Model
  factory AdminUser.fromMap(Map<String, dynamic> profile, int reportCount) {
    return AdminUser(
      id: profile['id'].toString(),
      name: profile['full_name'] ?? 'Anonymous User',
      email: profile['email'] ?? 'No Email Provided',
      status: profile['status'] ?? 'Active',
      reportsCount: reportCount,
      joinDate: profile['created_at'] != null 
          ? profile['created_at'].toString().split('T')[0] 
          : 'N/A',
    );
  }
}

class AdminUserManagementPage extends StatefulWidget {
  const AdminUserManagementPage({super.key});

  @override
  State<AdminUserManagementPage> createState() => _AdminUserManagementPageState();
}

class _AdminUserManagementPageState extends State<AdminUserManagementPage> {
  final supabase = Supabase.instance.client;

  // --- FIXED FETCH FUNCTION ---
  // Using .length on the returned List is the most stable way across SDK versions
  Future<List<AdminUser>> fetchAdminUsers() async {
    try {
      // 1. Fetch all profiles
      final List<dynamic> profilesData = await supabase
          .from('profiles')
          .select()
          .order('created_at', ascending: false);

      List<AdminUser> adminUsers = [];

      // 2. Loop through profiles to get report counts
      for (var profile in profilesData) {
        // Fetch only the IDs of reports for this specific user
        final List<dynamic> reports = await supabase
            .from('user_reports')
            .select('id')
            .eq('user_id', profile['id']);
        
        // Use .length to get the count (fixes the 'undefined getter count' error)
        int count = reports.length;
        
        adminUsers.add(AdminUser.fromMap(profile, count));
      }

      return adminUsers;
    } catch (e) {
      debugPrint("Error fetching users: $e");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text("User Management", 
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF0052CC)),
            onPressed: () => setState(() {}), 
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: FutureBuilder<List<AdminUser>>(
        future: fetchAdminUsers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text("Connection Error. Check your RLS policies."));
          }

          final users = snapshot.data ?? [];
          final activeUsers = users.where((u) => u.status == 'Active').length;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Monitor registered users and report activity from Supabase", 
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
                
                // --- Stat Cards ---
                Row(
                  children: [
                    _buildStatCard("Total Users", "${users.length}", Icons.group_outlined, Colors.blue),
                    const SizedBox(width: 12),
                    _buildStatCard("Active Users", "$activeUsers", Icons.circle, Colors.green),
                    const SizedBox(width: 12),
                    _buildStatCard("Inactive", "${users.length - activeUsers}", Icons.person_off_outlined, Colors.grey),
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
                  child: DataTable(
                    horizontalMargin: 20,
                    columnSpacing: 10,
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    columns: const [
                      DataColumn(label: Text("USER")),
                      DataColumn(label: Text("STATUS")),
                      DataColumn(label: Text("REPORTS")),
                      DataColumn(label: Text("JOINED")),
                      DataColumn(label: Text("ACTION")),
                    ],
                    rows: users.map((user) => _buildUserRow(user)).toList(),
                  ),
                ),
              ],
            ),
          );
        },
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

  // UI Helper for Table Rows
  DataRow _buildUserRow(AdminUser user) {
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
            color: user.status == 'Active' ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            user.status, 
            style: TextStyle(color: user.status == 'Active' ? Colors.green : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      DataCell(Text("${user.reportsCount}", style: const TextStyle(fontSize: 12))),
      DataCell(Text(user.joinDate, style: const TextStyle(fontSize: 12))),
      DataCell(
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), 
          onPressed: () {
            // Delete Logic
          },
        ),
      ),
    ]);
  }
}