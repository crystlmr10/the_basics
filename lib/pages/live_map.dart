import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveMapView extends StatefulWidget {
  const LiveMapView({super.key});

  @override
  State<LiveMapView> createState() => _LiveMapViewState();
}

class _LiveMapViewState extends State<LiveMapView> {
  final TextEditingController _searchController = TextEditingController();

  // --- DATABASE HELPER: UPDATE STATUS IN SUPABASE ---
  // This updates the 'admin_decision' column to trigger commuter rerouting
  Future<void> _updateRoadStatus(String locationName, String status) async {
    try {
      await Supabase.instance.client
          .from('user_reports')
          .update({'admin_decision': status})
          .eq('location_name', locationName);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("$locationName marked as $status. Rerouting commuters..."),
            backgroundColor: status == 'Impassable' ? Colors.red : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error updating road status: $e");
    }
  }

  // --- POP-UP: DYNAMIC WINDOW ---
  void _openReportWindow(Map<String, dynamic> data, bool isUserReport) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPopupHeader(data),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isUserReport) ...[
                      _buildInfoRow(Icons.person, "User Comments", data['user_comments'] ?? "No comment provided."),
                      const SizedBox(height: 12),
                      _buildInfoRow(Icons.height, "Estimated Level", data['human_level'] ?? "Unknown", color: Colors.orange),
                      const SizedBox(height: 12),
                      const Divider(),
                      const Text("ADMIN COMMAND CENTER", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 11)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _actionButton("SET RISKY", Colors.orange, () => _updateRoadStatus(data['location_name'], "Risky")),
                          const SizedBox(width: 10),
                          _actionButton("SET IMPASSABLE", Colors.red, () => _updateRoadStatus(data['location_name'], "Impassable")),
                        ],
                      ),
                    ] else ...[
                      Row(
                        children: [
                          _detailStat("WATER LEVEL", "${data['water_level_ft']} ft", Icons.water_drop),
                          const SizedBox(width: 16),
                          _detailStat("STATUS", data['status'], Icons.info_outline),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // --- LEFT SIDEBAR WITH REAL-TIME LISTS ---
        Container(
          width: 350,
          color: Colors.white,
          child: Column(
            children: [
              _buildSidebarHeaderWidget(),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  // Combine streams or handle separately
                  stream: Supabase.instance.client.from('sensors').stream(primaryKey: ['id']),
                  builder: (context, sensorSnapshot) {
                    return StreamBuilder<List<Map<String, dynamic>>>(
                      stream: Supabase.instance.client.from('user_reports').stream(primaryKey: ['id']),
                      builder: (context, reportSnapshot) {
                        final sensors = sensorSnapshot.data ?? [];
                        final reports = reportSnapshot.data ?? [];

                        return ListView(
                          children: [
                            const _SectionHeader("LIVE SENSOR NODES"),
                            ...sensors.map((s) => _buildListTile(s, false)),
                            const Divider(),
                            const _SectionHeader("COMMUTER REPORTS"),
                            ...reports.map((r) => _buildListTile(r, true)),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // --- LIVE MAP WITH REAL-TIME MARKERS ---
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client.from('sensors').stream(primaryKey: ['id']),
            builder: (context, sensorSnapshot) {
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client.from('user_reports').stream(primaryKey: ['id']),
                builder: (context, reportSnapshot) {
                  final sensors = sensorSnapshot.data ?? [];
                  final reports = reportSnapshot.data ?? [];

                  return FlutterMap(
                    options: const MapOptions(initialCenter: LatLng(10.2644, 123.8503), initialZoom: 14),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                      MarkerLayer(
                        markers: [
                          ...sensors.map((s) => _buildMarker(s, false)),
                          ...reports.map((r) => _buildMarker(r, true)),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // --- SUPPORTING UI WIDGETS ---

  Widget _buildSidebarHeaderWidget() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Monitoring Center", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(hintText: "Search streets...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: EdgeInsets.zero),
          ),
        ],
      ),
    );
  }

  Widget _buildListTile(Map<String, dynamic> data, bool isUser) {
    Color iconColor = isUser ? Colors.orange : (data['status'] == 'Critical' ? Colors.red : Colors.blue);
    return ListTile(
      leading: Icon(isUser ? Icons.person_pin_circle : Icons.sensors, color: iconColor),
      title: Text(data['location_name'] ?? data['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(isUser ? "Report: ${data['human_level']}" : "Depth: ${data['water_level_ft']} ft", style: const TextStyle(fontSize: 11)),
      onTap: () => _openReportWindow(data, isUser),
    );
  }

  Marker _buildMarker(Map<String, dynamic> data, bool isUser) {
    Color markerColor = isUser ? Colors.orange : (data['status'] == 'Critical' ? Colors.red : Colors.blue);
    LatLng position = isUser 
        ? LatLng(data['latitude'], data['longitude']) 
        : LatLng(data['latitude'], data['longitude']); // Adjusted for database keys

    return Marker(
      point: position, width: 60, height: 60,
      child: GestureDetector(
        onTap: () => _openReportWindow(data, isUser),
        child: Icon(isUser ? Icons.person_pin_circle : Icons.location_on, color: markerColor, size: 40),
      ),
    );
  }

  Widget _buildPopupHeader(Map<String, dynamic> data) {
    return Stack(
      children: [
        Container(
          height: 180, width: double.infinity,
          decoration: const BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: const Icon(Icons.image_outlined, size: 50, color: Colors.white70),
        ),
        Positioned(
          bottom: 15, left: 20,
          child: Text(data['location_name'] ?? data['name'], style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
        ),
        Positioned(top: 10, right: 10, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Color color = Colors.black}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text("$label: ", style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13))),
      ],
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onPressed) {
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, elevation: 0),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _detailStat(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, size: 12, color: Colors.blue), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold))]),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)));
  }
}