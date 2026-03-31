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
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  Map<String, dynamic>? _selectedNode;

  double _safeDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  String _calculateStatus(double cm) {
    if (cm <= 15) return 'Normal';
    if (cm > 15 && cm <= 30) return 'Risky';
    return 'Impassable';
  }

  Color _getStatusColor(String status) {
    if (status == 'Impassable' || status == 'Critical') return Colors.red;
    if (status == 'Risky' || status == 'Warning') return Colors.orange;
    return Colors.green;
  }

  Color _getDecisionColor(String? decision) {
    switch (decision) {
      case 'Impassable': return Colors.red;
      case 'Risky': return Colors.orange;
      default: return Colors.blue;
    }
  }

  void _showAdminActionDialog(Map<String, dynamic> report) {
    setState(() { _selectedNode = report; });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Verify Report", style: TextStyle(fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              onPressed: () => _deleteReport(report['id']), 
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(report['location_name'] ?? "Unknown Location"),
            const SizedBox(height: 12),
            if (report['image_url'] != null && report['image_url'].toString().isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(report['image_url'], height: 150, width: double.infinity, fit: BoxFit.cover),
              )
            else
              Container(
                height: 100, width: double.infinity,
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                child: const Center(child: Icon(Icons.image_not_supported)),
              ),
            const SizedBox(height: 16),
            const Text("Set Decision:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => _updateReportStatus(report['id'], 'Risky'),
            child: const Text("Risky"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => _updateReportStatus(report['id'], 'Impassable'),
            child: const Text("Impassable"),
          ),
        ],
      ),
    );
  }

  Future<void> _updateReportStatus(dynamic reportId, String decision) async {
    try {
      await Supabase.instance.client.from('user_reports').update({'admin_decision': decision}).eq('id', reportId);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) { debugPrint("Update error: $e"); }
  }

  Future<void> _deleteReport(dynamic reportId) async {
    try {
      await Supabase.instance.client.from('user_reports').delete().match({'id': reportId});
      if (!mounted) return;
      Navigator.pop(context);
      setState(() { _selectedNode = null; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Deleted"), backgroundColor: Colors.black));
    } catch (e) { debugPrint("Delete error: $e"); }
  }

  void _onNodeSelected(Map<String, dynamic> node) {
    setState(() {
      // Importante: I-keep ang coordinates kung ang gi-click kay history log
      double lat = _safeDouble(node['latitude']);
      double lng = _safeDouble(node['longitude']);

      if (lat == 0.0 && _selectedNode != null) {
        lat = _safeDouble(_selectedNode!['latitude']);
        lng = _safeDouble(_selectedNode!['longitude']);
      }

      _selectedNode = {
        ...node,
        'latitude': lat > 0 ? lat : 10.2644,
        'longitude': lng > 0 ? lng : 123.8503,
      };
    });
    
    _mapController.move(LatLng(_safeDouble(_selectedNode!['latitude']), _safeDouble(_selectedNode!['longitude'])), 14.5);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 350,
          color: Colors.white,
          child: Column(
            children: [
              _buildSidebarHeaderWidget(),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client.from('sensor_logs').stream(primaryKey: ['id']).order('recorded_at', ascending: false),
                  builder: (context, sensorSnapshot) {
                    return StreamBuilder<List<Map<String, dynamic>>>(
                      stream: Supabase.instance.client.from('user_reports').stream(primaryKey: ['id']),
                      builder: (context, reportSnapshot) {
                        final sensors = _getUniqueSensors(sensorSnapshot.data ?? []);
                        final reports = reportSnapshot.data ?? [];
                        return ListView(
                          children: [
                            const _SectionHeader(title: "LIVE SENSOR NODES"),
                            ...sensors.map((s) => _buildListTile(s, false)),
                            if (_selectedNode != null && _selectedNode!.containsKey('sensor_id')) ...[
                              const Divider(thickness: 2, height: 32),
                              _buildNodeInfoTile(),
                              _buildNodeHistoryList(_selectedNode!['sensor_id'].toString()),
                            ],
                            const Divider(height: 32),
                            const _SectionHeader(title: "COMMUTER REPORTS"),
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
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client.from('sensor_logs').stream(primaryKey: ['id']).order('recorded_at', ascending: false),
            builder: (context, sensorSnapshot) {
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client.from('user_reports').stream(primaryKey: ['id']),
                builder: (context, reportSnapshot) {
                  final sensors = _getUniqueSensors(sensorSnapshot.data ?? []);
                  final userReports = reportSnapshot.data ?? [];

                  return FlutterMap(
                    mapController: _mapController,
                    options: const MapOptions(initialCenter: LatLng(10.2644, 123.8503), initialZoom: 14),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                      
                      CircleLayer(
                        circles: [
                          if (_selectedNode != null)
                            CircleMarker(
                              point: LatLng(_safeDouble(_selectedNode!['latitude']), _safeDouble(_selectedNode!['longitude'])),
                              radius: 600, useRadiusInMeter: true,
                              color: _getStatusColor(_selectedNode!.containsKey('sensor_id') 
                                ? _calculateStatus(_safeDouble(_selectedNode!['water_level_cm'])) 
                                : (_selectedNode!['admin_decision'] == 'Impassable' ? 'Impassable' : (_selectedNode!['admin_decision'] == 'Risky' ? 'Risky' : 'Normal'))).withAlpha(40),
                              borderColor: _getStatusColor(_selectedNode!.containsKey('sensor_id') 
                                ? _calculateStatus(_safeDouble(_selectedNode!['water_level_cm'])) 
                                : (_selectedNode!['admin_decision'] == 'Impassable' ? 'Impassable' : (_selectedNode!['admin_decision'] == 'Risky' ? 'Risky' : 'Normal'))), 
                              borderStrokeWidth: 3,
                            ),
                        ],
                      ),

                      MarkerLayer(
                        markers: [
                          ...sensors.map((s) => _buildMarker(s, false)),
                          ...userReports.map((r) => _buildMarker(r, true)),
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

  Widget _buildListTile(Map<String, dynamic> data, bool isUser) {
    bool isSelected = _selectedNode?['id'] == data['id'];
    double cm = _safeDouble(data['water_level_cm']);
    Color iconColor = isUser ? _getDecisionColor(data['admin_decision']) : _getStatusColor(_calculateStatus(cm));

    return ListTile(
      selected: isSelected,
      selectedTileColor: Colors.blue.withAlpha(12),
      leading: Icon(isUser ? Icons.report_problem : Icons.sensors, color: iconColor),
      title: Text(data['location_name'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      subtitle: Text(isUser ? "Decision: ${data['admin_decision'] ?? 'Pending'}" : "# ${data['sensor_id']}"),
      onTap: () => isUser ? _showAdminActionDialog(data) : _onNodeSelected(data),
    );
  }

  Marker _buildMarker(Map<String, dynamic> data, bool isUser) {
    double cm = _safeDouble(data['water_level_cm']);
    Color markerColor = isUser ? _getDecisionColor(data['admin_decision']) : _getStatusColor(_calculateStatus(cm));
    return Marker(
      point: LatLng(_safeDouble(data['latitude']), _safeDouble(data['longitude'])),
      width: 50, height: 50,
      child: GestureDetector(
        onTap: () => isUser ? _showAdminActionDialog(data) : _onNodeSelected(data),
        child: Icon(isUser ? Icons.warning : Icons.location_on, color: markerColor, size: 35),
      ),
    );
  }

  List<Map<String, dynamic>> _getUniqueSensors(List<Map<String, dynamic>> logs) {
    final Map<String, Map<String, dynamic>> unique = {};
    for (var s in logs) { if (!unique.containsKey(s['sensor_id'])) unique[s['sensor_id']] = s; }
    return unique.values.toList();
  }

  Widget _buildNodeInfoTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: ListTile(
        dense: true,
        title: Text("SENSING: ${_selectedNode!['location_name'] ?? 'UNKNOWN'}".toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        trailing: IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => _selectedNode = null)),
      ),
    );
  }

  Widget _buildNodeHistoryList(String sensorId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client.from('sensor_logs').select().eq('sensor_id', sensorId).order('recorded_at', ascending: false).limit(10),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        return ListView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, i) {
            final item = snapshot.data![i];
            double cm = _safeDouble(item['water_level_cm']);
            String status = _calculateStatus(cm);
            bool isCurrentSelected = _selectedNode?['id'] == item['id'];

            return ListTile(
              dense: true,
              selected: isCurrentSelected,
              selectedTileColor: _getStatusColor(status).withAlpha(10),
              onTap: () => _onNodeSelected(item), 
              title: Text("$cm cm", style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(item['recorded_at'].toString().substring(11, 16)),
              trailing: _buildStatusBadge(status),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(4)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold)),
    );
  }

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
            decoration: InputDecoration(hintText: "Search locations...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: EdgeInsets.zero),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)));
  }
}