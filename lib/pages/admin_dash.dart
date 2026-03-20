import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart'; 
import 'live_map.dart'; 
import 'sensor_network.dart';
import 'historical_logs.dart';
import 'smart_hub_alerts.dart';
import 'rescue_center.dart';
import 'access_control_page.dart';
import 'settings_page.dart';

// Admin dashboard shell: navigation + page composition.
class AdminDashboard extends StatefulWidget {
  final int initialIndex;
  final AppSettingsController settings;
  const AdminDashboard({super.key, this.initialIndex = 0, required this.settings});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late int _selectedIndex;
  String selectedFilter = 'All Sensors';

  final Color primaryBlack = const Color(0xFF1A1A1B);
  final Color bgLightGray = const Color(0xFFF4F7FA);

  // --- SENSOR DATA STREAM ---
  final Stream<List<Map<String, dynamic>>> _sensorStream = Supabase.instance.client
      .from('sensors')
      .stream(primaryKey: ['id']);

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, 7);
  }

  void _showUsersList() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(Icons.people_alt_outlined, color: primaryBlack),
            const SizedBox(width: 12),
            const Text("Registered Commuters", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: Supabase.instance.client.from('profiles').select().eq('role', 'user'),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.black));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text("No users found."));
              }
              final users = snapshot.data!;
              return ListView.separated(
                itemCount: users.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) => ListTile(
                  title: Text(users[index]['email'] ?? 'N/A'),
                  subtitle: Text(users[index]['phone_number'] ?? 'N/A'),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLightGray,
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: primaryBlack,
            extended: true,
            minExtendedWidth: 260,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) => setState(() => _selectedIndex = index),
            leading: _buildSidebarHeader(),
            unselectedIconTheme: const IconThemeData(color: Colors.white38),
            unselectedLabelTextStyle: const TextStyle(color: Colors.white38),
            selectedIconTheme: const IconThemeData(color: Colors.white),
            selectedLabelTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            destinations: [
              NavigationRailDestination(icon: Icon(Icons.grid_view), label: Text("Dashboard")),
              NavigationRailDestination(icon: Icon(Icons.map_outlined), label: Text("Live Map View")),
              NavigationRailDestination(icon: Icon(Icons.sensors), label: Text("Sensor Network")),
              NavigationRailDestination(icon: Icon(Icons.history), label: Text("Historical Data Logs")),
              NavigationRailDestination(icon: const Icon(Icons.notifications_active_outlined), label: const Text("Alert & Notification")),
              NavigationRailDestination(icon: const _RescuePersonShadowNavIcon(), label: const Text("Rescue Center")),
              NavigationRailDestination(icon: const Icon(Icons.admin_panel_settings_outlined), label: const Text("Access Control")),
              NavigationRailDestination(icon: Icon(Icons.settings_outlined), label: Text("Settings")),
            ],
            trailing: Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildLogoutButton(),
                  const SizedBox(height: 10),
                  _buildSystemStatus(),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      _buildDashboardContent(), 
                      const LiveMapView(), 
                      const SensorNetworkPage(),
                      const HistoricalLogsPage(),
                      SmartHubAlertsPage(settings: widget.settings),
                      const RescueCenterPage(),
                      const AccessControlPage(),
                      SettingsPage(settings: widget.settings),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _sensorStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final sensors = snapshot.data ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: StatCard(title: "Active Flood Alerts", value: sensors.where((s) => s['status'] != 'Normal').length.toString(), sub: "Talisay Area", color: Colors.red, icon: Icons.warning_amber)),
                  const SizedBox(width: 16),
                  const Expanded(child: StatCard(title: "Sensor Network", value: "3/3", sub: "All Nodes Online", color: Colors.green, icon: Icons.wifi)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildSystemHealthCard()),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: _buildMapCard(sensors)), 
                  const SizedBox(width: 24),
                  Expanded(flex: 1, child: _buildRecentEventsCard()),
                ],
              ),
              const SizedBox(height: 24),
              _buildTrendChartCard(),
            ],
          ),
        );
      }
    );
  }

  Widget _buildMapCard(List<Map<String, dynamic>> sensors) {
    return Container(
      height: 450,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined, size: 18),
                SizedBox(width: 8),
                Text("Live Sensor Map", style: TextStyle(fontWeight: FontWeight.bold)),
                Spacer(),
                _MapLegend(color: Colors.green, label: "Normal"),
                _MapLegend(color: Colors.red, label: "Critical"),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
              child: FlutterMap(
                options: const MapOptions(initialCenter: LatLng(10.2644, 123.8503), initialZoom: 13),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                  MarkerLayer(
                    markers: sensors.map((s) {
                      Color pinColor = s['status'] == "Critical" ? Colors.red : (s['status'] == "Warning" ? Colors.orange : Colors.green);
                      return Marker(
                        point: LatLng(s['latitude'], s['longitude']),
                        child: Icon(Icons.location_on, color: pinColor, size: 30),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Header, TopBar, and StatCard builders
  Widget _buildSidebarHeader() { return const Padding(padding: EdgeInsets.symmetric(vertical: 30, horizontal: 20), child: Row(children: [Icon(Icons.shield_outlined, color: Colors.white, size: 30), SizedBox(width: 10), Text("Floote", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))])); }
  
  Widget _buildTopBar() { 
    String breadcrumb = switch (_selectedIndex) {
      0 => "Dashboard / Overview",
      1 => "Dashboard / Live Map View",
      2 => "Dashboard / Sensor Network",
      3 => "Dashboard / Historical Data Logs",
      4 => "Dashboard / Alert & Notification",
      5 => "Dashboard / Rescue Center",
      6 => "Dashboard / Access Control",
      7 => "Dashboard / Settings",
      _ => "Dashboard",
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15), 
      color: Colors.white, 
      child: Row(
        children: [
          Text(breadcrumb, style: const TextStyle(color: Colors.grey, fontSize: 13)), 
          const Spacer(), 
          InkWell(
            onTap: _showUsersList, 
            borderRadius: BorderRadius.circular(12), 
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
              decoration: BoxDecoration(color: bgLightGray, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withValues(alpha: 0.05))), 
              child: Row(
                children: [
                  const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [Text("02:13:29 PM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), Text("WED, 25 FEB 2026", style: TextStyle(color: Colors.grey, fontSize: 9))]), 
                  const SizedBox(width: 16), 
                  Container(height: 30, width: 1, color: Colors.black.withValues(alpha: 0.1)), 
                  const SizedBox(width: 16), 
                  Column(
                    mainAxisSize: MainAxisSize.min, 
                    crossAxisAlignment: CrossAxisAlignment.start, 
                    children: [
                      const Text("Admin System", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), 
                      Row(
                        children: [
                          const CircleAvatar(radius: 3, backgroundColor: Colors.green), 
                          const SizedBox(width: 4), 
                          StreamBuilder(
                            stream: Supabase.instance.client.from('profiles').stream(primaryKey: ['id']).eq('role', 'user'), 
                            builder: (context, snapshot) { 
                              int count = snapshot.hasData ? snapshot.data!.length : 0; 
                              return Text("$count Active Users", style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)); 
                            }
                          )
                        ]
                      )
                    ]
                  ), 
                  const SizedBox(width: 12), 
                  CircleAvatar(radius: 18, backgroundColor: primaryBlack, child: const Icon(Icons.person_outline, color: Colors.white, size: 20))
                ]
              )
            )
          ), 
          const SizedBox(width: 16), 
          const Icon(Icons.notifications_none, color: Colors.black)
        ]
      )
    ); 
  }

  Widget _buildLogoutButton() { return Material(color: Colors.transparent, child: InkWell(onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => FlooteLoginScreen(settings: widget.settings))), child: Container(padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20), child: const Row(children: [Icon(Icons.logout, color: Colors.redAccent, size: 20), SizedBox(width: 12), Text("Logout Session", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13))])))); }
  Widget _buildSystemStatus() { return Container(margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)), child: const Row(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(radius: 4, backgroundColor: Colors.white), SizedBox(width: 8), Text("LoRa Connected", style: TextStyle(color: Colors.white, fontSize: 12))])); }
  Widget _buildSystemHealthCard() { return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: const Border(left: BorderSide(color: Colors.blue, width: 6))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("System Health", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)), Icon(Icons.monitor_heart, color: Colors.blue.withValues(alpha: 0.3))]), const Text("Normal Operation", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 8), const Text("All core services running", style: TextStyle(color: Colors.blue, fontSize: 11))])); }
  Widget _buildRecentEventsCard() { return Container(height: 450, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(Icons.access_time, size: 18), SizedBox(width: 8), Text("Recent Events", style: TextStyle(fontWeight: FontWeight.bold))]), Divider(), _EventItem(tag: "[SYSTEM]", time: "08:00 AM", color: Colors.blue, message: "Sensors Online", subMessage: "")])); }
  Widget _buildTrendChartCard() { return Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Water Level Trend", style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 32), SizedBox(height: 250, child: LineChart(LineChartData(gridData: const FlGridData(show: true), lineBarsData: [LineChartBarData(spots: const [FlSpot(0, 0.2), FlSpot(10, 2.8), FlSpot(24, 0.2)], isCurved: true, color: Colors.black)])))])); }
}

class _MapLegend extends StatelessWidget { final Color color; final String label; const _MapLegend({required this.color, required this.label}); @override Widget build(BuildContext context) { return Padding(padding: const EdgeInsets.only(left: 12), child: Row(children: [CircleAvatar(radius: 4, backgroundColor: color), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 10))])); } }
class _EventItem extends StatelessWidget { final String tag, time, message, subMessage; final Color color; const _EventItem({required this.tag, required this.time, required this.color, required this.message, required this.subMessage}); @override Widget build(BuildContext context) { return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(tag, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)), Text(time, style: const TextStyle(color: Colors.grey, fontSize: 11))]), const SizedBox(height: 4), Text(message, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))])); } }
class StatCard extends StatelessWidget { final String title, value, sub; final Color color; final IconData icon; const StatCard({super.key, required this.title, required this.value, required this.sub, required this.color, required this.icon}); @override Widget build(BuildContext context) { return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: color, width: 6))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)), Icon(icon, color: color.withValues(alpha: 0.3))]), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)), Text(sub, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold))])); } }

class _RescuePersonShadowNavIcon extends StatelessWidget {
  const _RescuePersonShadowNavIcon();

  @override
  Widget build(BuildContext context) {
    final c = IconTheme.of(context).color ?? Colors.white;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Shadow part (slightly offset)
        Positioned(
          left: 1,
          top: 2,
          child: Icon(Icons.person, size: 22, color: c.withValues(alpha: 0.25)),
        ),
        Icon(Icons.person_outline, size: 22, color: c),
      ],
    );
  }
}