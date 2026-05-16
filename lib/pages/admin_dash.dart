import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:simple_animations/simple_animations.dart';

import 'live_map.dart' as live;
import 'historical_logs.dart';
import 'users_reports.dart';
import 'rescue_center.dart';
import 'access_control_page.dart';
import 'settings_page.dart';

class AdminDashboard extends StatefulWidget {
  final int initialIndex;
  final dynamic settings;
  const AdminDashboard({super.key, this.initialIndex = 0, required this.settings});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late int _selectedIndex;
  final Color sidebarBlue = const Color(0xFF0B3C78);
  final Color bgLightGray = const Color(0xFFF4F7FA);

  static const linaoCoords     = LatLng(10.257778, 123.817528);
  static const goldenFuCoords  = LatLng(10.264846, 123.840291);
  static const metrobankCoords = LatLng(10.267833, 123.843472);

  Color _getFloodColor(String status) {
    final s = status.toLowerCase();
    if (s.contains("severe") || s.contains("impassable")) return Colors.red;
    if (s.contains("risky")) return Colors.orange;
    return Colors.green;
  }

  final Stream<List<Map<String, dynamic>>> _sensorStream = Supabase.instance.client
      .from('sensor_logs')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: true);

  final Stream<List<Map<String, dynamic>>> _reportsStream = Supabase.instance.client
      .from('user_reports')
      .stream(primaryKey: ['id']);

  static bool _isReportActive(Map<String, dynamic> r) {
    final raw = r['created_at'] ?? r['reported_at'];
    if (raw == null) return true;
    try {
      final t = DateTime.parse(raw.toString()).toUtc();
      return DateTime.now().toUtc().difference(t) <= const Duration(hours: 5);
    } catch (_) {
      return true;
    }
  }

  Color _getDecisionColor(String? decision) {
    final d = (decision ?? '').toLowerCase();
    if (d.contains('impassable')) return Colors.red;
    if (d.contains('risky')) return Colors.orange;
    return Colors.blue;
  }

  static double _safeDouble(dynamic v, {double d = 0.0}) {
    if (v == null) return d;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? d;
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, 6);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLightGray,
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: sidebarBlue,
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
              NavigationRailDestination(icon: Icon(Icons.history), label: Text("Historical Data Logs")),
              NavigationRailDestination(icon: Icon(Icons.assignment_ind_outlined), label: Text("Users and Reports")),
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
                      const HistoricalLogsPage(),
                      const AdminUserManagementPage(),
                      RescueCenterPage(settings: widget.settings),
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Database Error: ${snapshot.error}"));
        }

        final allLogs = snapshot.data ?? [];

        final Map<String, Map<String, dynamic>> latestBySensor = {};
        for (var log in allLogs) {
          latestBySensor[log['sensor_id'] ?? 'Unknown'] = log;
        }
        final latestList = latestBySensor.values.toList();

        final activeAlertsCount = latestList.where((s) {
          final String status = (s['status'] ?? "").toString().toLowerCase();
          return status != "normal" && status.isNotEmpty;
        }).length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: PlayAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * 12),
                  child: child,
                ),
              );
            },
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: StatCard(
                      title: "Active Flood Alerts",
                      value: "$activeAlertsCount",
                      sub: activeAlertsCount > 0 ? "Alerts Triggered" : "Normal Conditions",
                      color: activeAlertsCount > 0 ? Colors.red : Colors.green,
                      icon: Icons.warning_amber,
                    )),
                    const SizedBox(width: 16),
                    const Expanded(child: StatCard(
                      title: "Sensor Network",
                      value: "3/3",
                      sub: "LoRa Nodes Online",
                      color: Colors.blue,
                      icon: Icons.wifi,
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: _buildSystemHealthCard()),
                  ],
                ),
                const SizedBox(height: 24),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _reportsStream,
                  builder: (context, reportSnap) {
                    final userReports = (reportSnap.data ?? [])
                        .where(_isReportActive)
                        .toList();
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildMapCard(latestBySensor, userReports)),
                        const SizedBox(width: 24),
                        Expanded(flex: 1, child: _buildRecentEventsCard(latestBySensor)),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Builds all 3 concentric heatmap rings for one point ──────────────────
  List<CircleMarker> _heatRings(LatLng point, Color baseColor, {bool severe = true}) {
    // severe  → larger + more intense rings (red palette)
    // !severe → smaller + softer rings      (orange palette)
    final double outer  = severe ? 300 : 250;
    final double middle = severe ? 175 : 140;
    final double core   = severe ? 80  : 65;

    return [
      // Outer glow
      CircleMarker(
        point: point,
        radius: outer,
        useRadiusInMeter: true,
        color: baseColor.withValues(alpha: 0.06),
        borderStrokeWidth: 0,
      ),
      // Middle ring
      CircleMarker(
        point: point,
        radius: middle,
        useRadiusInMeter: true,
        color: baseColor.withValues(alpha: 0.18),
        borderStrokeWidth: 0,
      ),
      // Hot core
      CircleMarker(
        point: point,
        radius: core,
        useRadiusInMeter: true,
        color: baseColor.withValues(alpha: 0.45),
        borderColor: baseColor.withValues(alpha: 0.85),
        borderStrokeWidth: 1.5,
      ),
    ];
  }

  Widget _buildMapCard(
    Map<String, Map<String, dynamic>> latestNodes,
    List<Map<String, dynamic>> userReports,
  ) {
    final List<Map<String, dynamic>> nodeMap = [
      {'name': 'Linao, Talisay', 'sensorId': 'LORA-LINAO',      'coords': linaoCoords},
      {'name': 'Tabunoc',        'sensorId': 'LORA-MASTER-TAB', 'coords': goldenFuCoords},
      {'name': 'Tabunoc – MB',   'sensorId': 'LORA-TABUNOC-MB', 'coords': metrobankCoords},
    ];

    // Heatmap rings — sensor alerts
    final List<CircleMarker> heatCircles = [];
    for (final node in nodeMap) {
      final data = latestNodes[node['sensorId'] as String];
      final String s = (data?['status'] ?? '').toString().toLowerCase();
      final LatLng coords = node['coords'] as LatLng;
      if (s.contains('severe') || s.contains('impassable')) {
        heatCircles.addAll(_heatRings(coords, Colors.red, severe: true));
      } else if (s.contains('risky') || s.contains('warning')) {
        heatCircles.addAll(_heatRings(coords, Colors.orange, severe: false));
      }
    }
    // Heatmap rings — user report decisions
    for (final r in userReports) {
      final pt = LatLng(_safeDouble(r['latitude']), _safeDouble(r['longitude']));
      final d = (r['admin_decision'] ?? '').toString().toLowerCase();
      if (d == 'impassable') {
        heatCircles.addAll(_heatRings(pt, Colors.red, severe: true));
      } else if (d == 'risky') {
        heatCircles.addAll(_heatRings(pt, Colors.orange, severe: false));
      }
    }

    return Container(
      height: 450,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.location_searching, size: 18, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text("Live Node Network", style: TextStyle(fontWeight: FontWeight.bold)),
                Spacer(),
                _MapLegend(color: Colors.green,  label: "Normal"),
                _MapLegend(color: Colors.orange, label: "Risky"),
                _MapLegend(color: Colors.red,    label: "Severe"),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
              child: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(10.2635, 123.8320),
                  initialZoom: 14,
                ),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                  CircleLayer(circles: heatCircles),
                  // User report warning markers only (same as live map)
                  MarkerLayer(
                    markers: userReports.map((r) {
                      final String decision = (r['admin_decision'] ?? 'Pending').toString();
                      final Color iconColor = _getDecisionColor(decision);
                      return Marker(
                        point: LatLng(_safeDouble(r['latitude']), _safeDouble(r['longitude'])),
                        width: 140,
                        height: 70,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)],
                              ),
                              child: Text(
                                "${r['location_name'] ?? 'Report'}\n$decision",
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Icon(Icons.warning, color: iconColor, size: 35),
                          ],
                        ),
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

  Widget _buildRecentEventsCard(Map<String, Map<String, dynamic>> latestBySensor) {
    int severity(String status) {
      final s = status.toLowerCase();
      if (s.contains('severe') || s.contains('impassable')) return 2;
      if (s.contains('risky') || s.contains('warning')) return 1;
      return 0;
    }

    final nodes = latestBySensor.values.toList()
      ..sort((a, b) => severity((b['status'] ?? '').toString())
          .compareTo(severity((a['status'] ?? '').toString())));

    return Container(
      height: 450,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.sensors, size: 18),
            SizedBox(width: 8),
            Text("Current Sensor Status",
                style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const Divider(),
          Expanded(
            child: nodes.isEmpty
                ? const Center(
                    child: Text("No sensor data found",
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: nodes.length,
                    itemBuilder: (context, i) {
                      final log = nodes[i];
                      final double cm =
                          (log['water_level_cm'] as num? ?? 0).toDouble();
                      final String status = log['status'] ?? 'Normal';
                      final String sensor = log['sensor_id'] ?? 'Unknown';
                      final String? createdAt = log['created_at']?.toString();
                      final DateTime? ts = createdAt != null
                          ? DateTime.tryParse(createdAt)
                          : null;
                      String two(int v) => v.toString().padLeft(2, '0');
                      final timeLabel = ts != null
                          ? '${two(ts.hour)}:${two(ts.minute)} ${two(ts.month)}/${two(ts.day)}'
                          : 'LIVE';
                      return _EventItem(
                        tag: "[$sensor]",
                        time: timeLabel,
                        color: _getFloodColor(status),
                        message: "Water Level: ${cm.toStringAsFixed(1)} cm",
                        subMessage: "Status: $status",
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
      color: Colors.white,
      child: const Row(children: [
        Text("Dashboard / Overview",
            style: TextStyle(color: Colors.grey, fontSize: 13)),
        Spacer(),
        Icon(Icons.notifications_none, color: Colors.black),
      ]),
    );
  }

  Widget _buildSidebarHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      child: MirrorAnimationBuilder<double>(
        tween: Tween(begin: -4.0, end: 4.0),
        duration: const Duration(seconds: 3),
        curve: Curves.easeInOut,
        builder: (context, value, child) {
          return Transform.translate(offset: Offset(0, value), child: child);
        },
        child: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.white, size: 30),
            SizedBox(width: 10),
            Text("Floote",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          child: const Row(children: [
            Icon(Icons.logout, color: Colors.redAccent, size: 20),
            SizedBox(width: 12),
            Text("Logout",
                style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ]),
        ),
      ),
    );
  }

  Widget _buildSystemStatus() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 4, backgroundColor: Colors.white),
        SizedBox(width: 8),
        Text("Database Connected",
            style: TextStyle(color: Colors.white, fontSize: 12)),
      ]),
    );
  }

  Widget _buildSystemHealthCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: Colors.blue, width: 6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("System Health",
              style:
                  TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          Icon(Icons.monitor_heart, color: Colors.blue.withValues(alpha: 0.3)),
        ]),
        const Text("Stable",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Text("All sensor nodes reporting",
            style: TextStyle(color: Colors.blue, fontSize: 11)),
      ]),
    );
  }
}

// ── Small reusable widgets ────────────────────────────────────────────────────

class _MapLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _MapLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(children: [
        CircleAvatar(radius: 4, backgroundColor: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ]),
    );
  }
}

class _EventItem extends StatelessWidget {
  final String tag, time, message, subMessage;
  final Color color;
  const _EventItem({
    required this.tag,
    required this.time,
    required this.color,
    required this.message,
    required this.subMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(tag,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 11)),
          Text(time,
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ]),
        const SizedBox(height: 4),
        Text(message,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        Text(subMessage,
            style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.7),
                fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title, value, sub;
  final Color color;
  final IconData icon;
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.sub,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 6)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
          Icon(icon, color: color.withValues(alpha: 0.3)),
        ]),
        const SizedBox(height: 8),
        Text(value,
            style:
                const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        Text(sub,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class _RescuePersonShadowNavIcon extends StatelessWidget {
  const _RescuePersonShadowNavIcon();

  @override
  Widget build(BuildContext context) {
    final c = IconTheme.of(context).color ?? Colors.white;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
          left: 1,
          top: 2,
          child: Icon(Icons.person, size: 22, color: c.withValues(alpha: 0.25))),
      Icon(Icons.person_outline, size: 22, color: c),
    ]);
  }
}
