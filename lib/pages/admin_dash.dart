import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart'; // Import to access FlooteLoginScreen for logout logic

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  String selectedFilter = 'All Sensors';

  // Monochrome Theme Colors
  final Color primaryBlack = const Color(0xFF1A1A1B);
  final Color bgLightGray = const Color(0xFFF4F7FA);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLightGray,
      body: Row(
        children: [
          // --- SIDEBAR (MONOCHROME) ---
          NavigationRail(
            backgroundColor: primaryBlack,
            extended: true,
            minExtendedWidth: 260,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) =>
                setState(() => _selectedIndex = index),
            leading: _buildSidebarHeader(),
            unselectedIconTheme: const IconThemeData(color: Colors.white38),
            unselectedLabelTextStyle: const TextStyle(color: Colors.white38),
            selectedIconTheme: const IconThemeData(color: Colors.white),
            selectedLabelTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            indicatorColor: Colors.white.withValues(alpha: 0.1),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.grid_view),
                label: Text("Dashboard"),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.map_outlined),
                label: Text("Live Map View"),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.sensors),
                label: Text("Sensor Network"),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history),
                label: Text("Historical Data Logs"),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                label: Text("Settings"),
              ),
            ],
            trailing: Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // --- ADDED LOGOUT SESSION BUTTON ---
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FlooteLoginScreen(),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 15,
                          horizontal: 20,
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.logout,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            SizedBox(width: 12),
                            Text(
                              "Logout Session",
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildSystemStatus(),
                ],
              ),
            ),
          ),

          // --- MAIN CONTENT AREA ---
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // ROW 1: STAT CARDS
                        Row(
                          children: [
                            const Expanded(
                              child: StatCard(
                                title: "Active Flood Alerts",
                                value: "2",
                                sub: "Colon St, Mabolo",
                                color: Colors.red,
                                icon: Icons.warning_amber,
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: StatCard(
                                title: "Sensor Network Status",
                                value: "3/3",
                                sub: "All Nodes Online",
                                color: Colors.green,
                                icon: Icons.wifi,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: _buildSystemHealthCard()),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // ROW 2: MAP AND RECENT EVENTS
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 2, child: _buildMapCard()),
                            const SizedBox(width: 24),
                            Expanded(flex: 1, child: _buildRecentEventsCard()),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // ROW 3: TREND CHART WITH DROPDOWN
                        _buildTrendChartCard(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildSidebarHeader() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: Colors.white, size: 30),
          SizedBox(width: 10),
          Text(
            "Floote",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
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
      child: const Row(
        children: [
          Text(
            "Dashboard / Overview",
            style: TextStyle(color: Colors.grey),
          ),
          Spacer(),
          Text(
            "02:13:29 PM \nWED, 25 FEB 2026",
            textAlign: TextAlign.right,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          SizedBox(width: 20),
          Icon(Icons.notifications_none, color: Colors.black),
          SizedBox(width: 20),
          CircleAvatar(radius: 16, backgroundColor: Colors.blueGrey),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Admin System",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                "Master Controller",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                "142 Active Users",
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "System Health",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(
                Icons.monitor_heart,
                color: Colors.blue.withValues(alpha: 0.3),
              ),
            ],
          ),
          const Text(
            "Normal Operation",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.blue),
                SizedBox(width: 4),
                Text(
                  "All core services running",
                  style: TextStyle(color: Colors.blue, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapCard() {
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
                Icon(Icons.location_on_outlined, size: 18),
                SizedBox(width: 8),
                Text(
                  "Live Sensor Map - Cebu City",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Spacer(),
                _MapLegend(color: Colors.green, label: "Normal"),
                _MapLegend(color: Colors.orange, label: "Warning"),
                _MapLegend(color: Colors.red, label: "Critical"),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(15),
              ),
              child: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(10.3157, 123.8854),
                  initialZoom: 13,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),
                  const MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(10.2975, 123.9000),
                        child: Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 30,
                        ),
                      ),
                      Marker(
                        point: LatLng(10.3400, 123.9100),
                        child: Icon(
                          Icons.location_on,
                          color: Colors.orange,
                          size: 30,
                        ),
                      ),
                      Marker(
                        point: LatLng(10.3250, 123.9150),
                        child: Icon(
                          Icons.location_on,
                          color: Colors.green,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentEventsCard() {
    return Container(
      height: 450,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.access_time, size: 18),
              SizedBox(width: 8),
              Text(
                "Recent Critical Events",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Divider(),
          _EventItem(
            tag: "[CRITICAL]",
            time: "10:42 AM",
            color: Colors.red,
            message: "Sensor ID #C-01 (Colon) reports 3ft water level.",
            subMessage: "Alert dispatched to traffic units.",
          ),
          _EventItem(
            tag: "[WARNING]",
            time: "10:15 AM",
            color: Colors.orange,
            message: "Sensor ID #B-14 (Banilad) showing rapid increase.",
            subMessage: "",
          ),
          _EventItem(
            tag: "[SYSTEM]",
            time: "08:00 AM",
            color: Colors.blue,
            message: "Diagnostic completed. 3 sensors online.",
            subMessage: "",
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChartCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, size: 18),
              const SizedBox(width: 8),
              const Text(
                "Average Water Level Trend (Last 24h)",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // --- DROPDOWN FILTER IMPLEMENTED ---
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: selectedFilter,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  items: <String>['All Sensors', 'Colon', 'Banilad', 'Mabolo']
                      .map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      })
                      .toList(),
                  onChanged: (newValue) {
                    setState(() {
                      selectedFilter = newValue!;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 250,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: const FlTitlesData(
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 0.2),
                      FlSpot(4, 0.3),
                      FlSpot(8, 0.8),
                      FlSpot(10, 2.8),
                      FlSpot(14, 1.4),
                      FlSpot(18, 0.6),
                      FlSpot(24, 0.2),
                    ],
                    isCurved: true,
                    color: Colors.black,
                    barWidth: 3,
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.black.withValues(alpha: 0.05),
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

  Widget _buildSystemStatus() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 4, backgroundColor: Colors.white),
          SizedBox(width: 8),
          Text(
            "PtMP Connected",
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _MapLegend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        children: [
          CircleAvatar(radius: 4, backgroundColor: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
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
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tag,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
                Text(
                  time,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            if (subMessage.isNotEmpty)
              Text(
                subMessage,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
      ),
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Icon(icon, color: color.withValues(alpha: 0.3)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          Text(
            sub,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
