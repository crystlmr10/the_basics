import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart'; 

import 'live_map.dart' as live; 
import 'sensor_network.dart' as sn; 
import 'historical_logs.dart';
import 'smart_hub_alerts.dart';
import 'rescue_center.dart';
import 'access_control_page.dart';
import 'settings_page.dart';

class AdminDashboard extends StatefulWidget {
  final int initialIndex;
  final AppSettingsController settings;
  const AdminDashboard({super.key, this.initialIndex = 0, required this.settings});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late int _selectedIndex;
  final Color primaryBlack = const Color(0xFF1A1A1B);
  final Color bgLightGray = const Color(0xFFF4F7FA);

  // Helper to determine color based on strict DB logic
  Color _getFloodColor(double cm) {
    if (cm <= 15) return Colors.green; // Normal
    if (cm <= 30) return Colors.orange; // Risky
    return Colors.red; // Impassable
  }

  // Helper to determine label based on strict DB logic
  String _getFloodStatus(double cm) {
    if (cm <= 15) return 'Normal';
    if (cm <= 30) return 'Risky';
    return 'Impassable';
  }

  // Stream for the dashboard
  final Stream<List<Map<String, dynamic>>> _historicalStream = Supabase.instance.client
      .from('sensor_logs')
      .stream(primaryKey: ['id'])
      .order('recorded_at', ascending: true);

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, 7);
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
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.grid_view), label: Text("Dashboard")),
              NavigationRailDestination(icon: Icon(Icons.map_outlined), label: Text("Live Map View")),
              NavigationRailDestination(icon: Icon(Icons.sensors), label: Text("Sensor Network")),
              NavigationRailDestination(icon: Icon(Icons.history), label: Text("Historical Data Logs")),
              NavigationRailDestination(icon: Icon(Icons.notifications_active_outlined), label: Text("Alert & Notification")),
              NavigationRailDestination(icon: _RescuePersonShadowNavIcon(), label: Text("Rescue Center")),
              NavigationRailDestination(icon: Icon(Icons.admin_panel_settings_outlined), label: Text("Access Control")),
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
                      const live.LiveMapView(), 
                      const sn.SensorNetworkPage(), 
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
      stream: _historicalStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final logs = snapshot.data ?? [];
        final trendData = logs.where((l) => l['location_name'] == 'Tabunok, Talisay').toList();

        // 1. COUNT ONLY IMPASSABLE AND RISKY (> 15cm)
        final activeAlertsCount = logs.where((s) {
          final double cm = (s['water_level_cm'] as num).toDouble();
          return cm > 15; 
        }).length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: StatCard(title: "Active Flood Alerts", value: "$activeAlertsCount", sub: "Risky & Impassable", color: Colors.red, icon: Icons.warning_amber)),
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
                  Expanded(flex: 2, child: _buildMapCard(logs)), 
                  const SizedBox(width: 24),
                  // 2. SHOW EVERYTHING IN RECENT LOGS
                  Expanded(flex: 1, child: _buildRecentEventsCard(logs)),
                ],
              ),
              const SizedBox(height: 24),
              _buildTrendChartCard(trendData),
            ],
          ),
        );
      }
    );
  }

  Widget _buildMapCard(List<Map<String, dynamic>> logs) {
    final Map<String, Map<String, dynamic>> latestNodes = {};
    for (var log in logs) {
      latestNodes[log['location_name']] = log;
    }
    final sensors = latestNodes.values.toList();

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
                _MapLegend(color: Colors.orange, label: "Risky"),
                _MapLegend(color: Colors.red, label: "Impassable"),
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
                      final double cm = (s['water_level_cm'] as num).toDouble();
                      Color pinColor = _getFloodColor(cm);
                      return Marker(
                        point: LatLng((s['latitude'] ?? 0) as double, (s['longitude'] ?? 0) as double),
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

Widget _buildTrendChartCard(List<Map<String, dynamic>> trendData) {
    final List<FlSpot> spots = trendData.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), (e.value['water_level_cm'] as num).toDouble());
    }).toList();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Flood Inundation Trend", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 32),
          SizedBox(
            height: 300, 
            child: spots.length < 2 
              ? const Center(child: Text("Insufficient data for trend line", style: TextStyle(color: Colors.grey)))
              : LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: true, border: Border.all(color: Colors.black12)),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, 
                        reservedSize: 40, 
                        getTitlesWidget: (v, m) => Text('${v.toInt()}cm', style: const TextStyle(fontSize: 10))
                      )
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1, // Ensure every log point gets a label
                        getTitlesWidget: (value, meta) {
                          // Look up the index in our trendData list
                          int index = value.toInt();
                          if (index >= 0 && index < trendData.length) {
                            // Extract time from 'recorded_at' (e.g., "2026-03-31T17:17:00" -> "17:17")
                            final String fullTime = trendData[index]['recorded_at']?.toString() ?? "";
                            if (fullTime.length >= 16) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  fullTime.substring(11, 16), 
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)
                                ),
                              );
                            }
                          }
                          return const Text("");
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false, 
                      color: Colors.blueAccent, 
                      barWidth: 3,
                      dotData: const FlDotData(show: true), 
                      belowBarData: BarAreaData(show: true, color: Colors.blueAccent.withValues(alpha: 0.1)),
                    )
                  ]
                )
              )
          )
        ],
      ),
    );
  }

  Widget _buildRecentEventsCard(List<Map<String, dynamic>> logs) {
    // Shows EVERY item in the database, sorted by latest
    final allLogs = logs.reversed.toList();
    
    return Container(
      height: 450, 
      padding: const EdgeInsets.all(20), 
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          const Row(children: [Icon(Icons.access_time, size: 18), SizedBox(width: 8), Text("Recent Logs", style: TextStyle(fontWeight: FontWeight.bold))]), 
          const Divider(), 
          Expanded(
            child: ListView.builder(
              itemCount: allLogs.length,
              itemBuilder: (context, i) {
                final log = allLogs[i];
                final double cm = (log['water_level_cm'] as num).toDouble();
                
                return _EventItem(
                  tag: "[SENSOR]", 
                  time: log['recorded_at']?.toString().substring(11, 16) ?? "--:--", 
                  color: _getFloodColor(cm), 
                  message: "${log['location_name']}: ${cm}cm",
                  subMessage: _getFloodStatus(cm),
                );
              },
            ),
          )
        ]
      )
    );
  }

  Widget _buildTopBar() { 
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15), 
      color: Colors.white, 
      child: Row(children: [
        const Text("Dashboard / Overview", style: TextStyle(color: Colors.grey, fontSize: 13)), 
        const Spacer(), 
        _buildUserStatusIndicator(),
        const SizedBox(width: 16), 
        const Icon(Icons.notifications_none, color: Colors.black)
      ])
    );
  }

  Widget _buildUserStatusIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
      decoration: BoxDecoration(color: bgLightGray, borderRadius: BorderRadius.circular(12)), 
      child: Row(children: [
        const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [Text("02:13:29 PM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), Text("WED, 25 FEB 2026", style: TextStyle(color: Colors.grey, fontSize: 9))]), 
        const SizedBox(width: 16), 
        Container(height: 30, width: 1, color: Colors.black12), 
        const SizedBox(width: 16), 
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Admin System", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text("Online", style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold))]),
        const SizedBox(width: 12), 
        CircleAvatar(radius: 18, backgroundColor: primaryBlack, child: const Icon(Icons.person_outline, color: Colors.white, size: 20))
      ])
    );
  }

  Widget _buildSidebarHeader() { return const Padding(padding: EdgeInsets.symmetric(vertical: 30, horizontal: 20), child: Row(children: [Icon(Icons.shield_outlined, color: Colors.white, size: 30), SizedBox(width: 10), Text("Floote", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))])); }
  Widget _buildLogoutButton() { return Material(color: Colors.transparent, child: InkWell(onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => FlooteLoginScreen(settings: widget.settings))), child: Container(padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20), child: const Row(children: [Icon(Icons.logout, color: Colors.redAccent, size: 20), SizedBox(width: 12), Text("Logout", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13))])))); }
  Widget _buildSystemStatus() { return Container(margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)), child: const Row(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(radius: 4, backgroundColor: Colors.white), SizedBox(width: 8), Text("LoRa Connected", style: TextStyle(color: Colors.white, fontSize: 12))])); }
  Widget _buildSystemHealthCard() { return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: const Border(left: BorderSide(color: Colors.blue, width: 6))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("System Health", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)), Icon(Icons.monitor_heart, color: Colors.blue.withValues(alpha: 0.3))]), const Text("Normal", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const Text("All services active", style: TextStyle(color: Colors.blue, fontSize: 11))])); }
}

class _MapLegend extends StatelessWidget { final Color color; final String label; const _MapLegend({required this.color, required this.label}); @override Widget build(BuildContext context) { return Padding(padding: const EdgeInsets.only(left: 12), child: Row(children: [CircleAvatar(radius: 4, backgroundColor: color), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 10))])); } }

class _EventItem extends StatelessWidget { 
  final String tag, time, message, subMessage; 
  final Color color; 
  const _EventItem({required this.tag, required this.time, required this.color, required this.message, required this.subMessage}); 
  @override 
  Widget build(BuildContext context) { 
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), 
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(tag, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)), 
          Text(time, style: const TextStyle(color: Colors.grey, fontSize: 11))
        ]), 
        const SizedBox(height: 4), 
        Text(message, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        Text(subMessage, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7), fontWeight: FontWeight.bold)),
      ])); 
  } 
}

class StatCard extends StatelessWidget { final String title, value, sub; final Color color; final IconData icon; const StatCard({super.key, required this.title, required this.value, required this.sub, required this.color, required this.icon}); @override Widget build(BuildContext context) { return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: color, width: 6))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)), Icon(icon, color: color.withValues(alpha: 0.3))]), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)), Text(sub, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold))])); } }

class _RescuePersonShadowNavIcon extends StatelessWidget { const _RescuePersonShadowNavIcon(); @override Widget build(BuildContext context) { final c = IconTheme.of(context).color ?? Colors.white; return Stack(clipBehavior: Clip.none, children: [Positioned(left: 1, top: 2, child: Icon(Icons.person, size: 22, color: c.withValues(alpha: 0.25))), Icon(Icons.person_outline, size: 22, color: c)]); } }