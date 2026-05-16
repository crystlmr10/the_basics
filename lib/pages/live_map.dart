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
  Map<String, Map<String, dynamic>> _sensorMeta = {};

  static const LatLng linaoCoords     = LatLng(10.257778, 123.817528);
  static const LatLng goldenFuCoords  = LatLng(10.264846, 123.840291);
  static const LatLng metrobankCoords = LatLng(10.267833, 123.843472);

  static const Duration _reportMaxAge = Duration(hours: 5);

  @override
  void initState() {
    super.initState();
    _loadSensorMeta();
  }

  Future<void> _loadSensorMeta() async {
    final nodes = await Supabase.instance.client.from('sensor_nodes').select();
    if (mounted) {
      setState(() {
        _sensorMeta = {for (var n in nodes) n['sensor_id'] as String: n};
      });
    }
  }

  double _safeDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  bool _isReportActive(Map<String, dynamic> report) {
    final rawTime = report['created_at'] ?? report['reported_at'];
    if (rawTime == null) return true;
    try {
      final reportTime = DateTime.parse(rawTime.toString()).toUtc();
      return DateTime.now().toUtc().difference(reportTime) <= _reportMaxAge;
    } catch (_) {
      return true;
    }
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('impassable') || s.contains('severe') || s.contains('flooding')) return Colors.red;
    if (s.contains('risky') || s.contains('warning')) return Colors.orange;
    return Colors.green;
  }

  Color _getDecisionColor(String? decision) {
    final d = (decision ?? '').toLowerCase();
    if (d.contains('impassable')) return Colors.red;
    if (d.contains('risky')) return Colors.orange;
    return Colors.blue;
  }

  Map<String, dynamic> _getEnhancedSensorData(Map<String, dynamic> log) {
    final String rawId = (log['sensor_id'] ?? '').toString();
    final meta = _sensorMeta[rawId];
    if (meta != null) {
      return {
        ...log,
        'display_name': meta['location_name'] ?? rawId,
        'municipality': meta['municipality'] ?? '',
        'barangay': meta['barangay'] ?? '',
        'latitude': _safeDouble(meta['latitude'] ?? log['latitude']),
        'longitude': _safeDouble(meta['longitude'] ?? log['longitude']),
      };
    }

    final String idUp = rawId.toUpperCase();
    String name;
    LatLng pos;

    if (idUp.contains('LINAO')) {
      name = 'Linao, Talisay';
      pos  = linaoCoords;
    } else if (idUp.contains('MASTER') || idUp.contains('GOLDEN') ||
               (idUp.contains('TABUNOC') && !idUp.contains('MB'))) {
      name = 'Tabunoc';
      pos  = goldenFuCoords;
    } else if (idUp.contains('MB') || idUp.contains('METROBANK')) {
      name = 'Tabunok – Metrobank';
      pos  = metrobankCoords;
    } else {
      name = rawId;
      pos  = LatLng(_safeDouble(log['latitude']), _safeDouble(log['longitude']));
    }

    return {
      ...log,
      'display_name': name,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
    };
  }

  void _onNodeSelected(Map<String, dynamic> node) {
    final enhanced = node.containsKey('sensor_id') ? _getEnhancedSensorData(node) : node;
    setState(() => _selectedNode = enhanced);
    _mapController.move(LatLng(enhanced['latitude'], enhanced['longitude']), 15.0);
  }

  List<Map<String, dynamic>> _getUniqueSensors(List<Map<String, dynamic>> logs) {
    final Map<String, Map<String, dynamic>> unique = {};
    for (final s in logs) {
      if (!unique.containsKey(s['sensor_id'])) unique[s['sensor_id']] = s;
    }
    return unique.values.toList();
  }

  // ── Heatmap helper — identical to admin_dashboard ─────────────────────────
  List<CircleMarker> _heatRings(LatLng point, Color baseColor, {bool severe = true}) {
    final double outer  = severe ? 300 : 250;
    final double middle = severe ? 175 : 140;
    final double core   = severe ? 80  : 65;

    return [
      CircleMarker(point: point, radius: outer,  useRadiusInMeter: true,
          color: baseColor.withValues(alpha: 0.06), borderStrokeWidth: 0),
      CircleMarker(point: point, radius: middle, useRadiusInMeter: true,
          color: baseColor.withValues(alpha: 0.18), borderStrokeWidth: 0),
      CircleMarker(point: point, radius: core,   useRadiusInMeter: true,
          color: baseColor.withValues(alpha: 0.45),
          borderColor: baseColor.withValues(alpha: 0.85), borderStrokeWidth: 1.5),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── Sidebar ───────────────────────────────────────────────────────
        Container(
          width: 350,
          color: Colors.white,
          child: Column(
            children: [
              _buildSidebarHeaderWidget(),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client
                      .from('sensor_logs')
                      .stream(primaryKey: ['id'])
                      .order('created_at', ascending: false),
                  builder: (context, sensorSnapshot) {
                    return StreamBuilder<List<Map<String, dynamic>>>(
                      stream: Supabase.instance.client
                          .from('user_reports')
                          .stream(primaryKey: ['id']),
                      builder: (context, reportSnapshot) {
                        final sensors = _getUniqueSensors(sensorSnapshot.data ?? []);
                        final reports = (reportSnapshot.data ?? [])
                            .where(_isReportActive)
                            .toList();

                        return ListView(
                          children: [
                            const _SectionHeader(title: 'LIVE SENSOR NODES'),
                            if (sensors.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('Searching for sensor data...',
                                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ),
                            ...sensors.map((s) => _buildSensorTile(s)),

                            if (_selectedNode != null &&
                                _selectedNode!.containsKey('sensor_id')) ...[
                              const Divider(thickness: 2, height: 32),
                              _buildNodeInfoTile(),
                              _buildNodeHistoryList(_selectedNode!['sensor_id'].toString()),
                            ],

                            const Divider(height: 32),
                            const _SectionHeader(title: 'COMMUTER REPORTS'),
                            if (reports.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('No active reports in the last 5 hours.',
                                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ),
                            ...reports.map((r) => _buildReportTile(r)),
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

        // ── Map — dashboard-style card ────────────────────────────────────
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('sensor_logs')
                .stream(primaryKey: ['id'])
                .order('created_at', ascending: false),
            builder: (context, sensorSnapshot) {
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from('user_reports')
                    .stream(primaryKey: ['id']),
                builder: (context, reportSnapshot) {
                  final sensors    = _getUniqueSensors(sensorSnapshot.data ?? []);
                  final userReports = (reportSnapshot.data ?? []).where(_isReportActive).toList();

                  // Build heatmap circles
                  final List<CircleMarker> heatCircles = [];
                  for (final s in sensors) {
                    final e  = _getEnhancedSensorData(s);
                    final pt = LatLng(e['latitude'], e['longitude']);
                    final st = (s['status'] ?? '').toString().toLowerCase();

                    if (st.contains('severe') || st.contains('impassable')) {
                      heatCircles.addAll(_heatRings(pt, Colors.red,    severe: true));
                    } else if (st.contains('risky') || st.contains('warning')) {
                      heatCircles.addAll(_heatRings(pt, Colors.orange, severe: false));
                    }
                  }
                  for (final r in userReports) {
                    final pt = LatLng(_safeDouble(r['latitude']), _safeDouble(r['longitude']));
                    final d  = (r['admin_decision'] ?? '').toString().toLowerCase();
                    if (d == 'impassable') {
                      heatCircles.addAll(_heatRings(pt, Colors.red,    severe: true));
                    } else if (d == 'risky') {
                      heatCircles.addAll(_heatRings(pt, Colors.orange, severe: false));
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        children: [
                          // ── Header with legend — matches admin_dashboard ──
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Icon(Icons.location_searching, size: 18, color: Colors.blueAccent),
                                SizedBox(width: 8),
                                Text("Live Node Network",
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                                Spacer(),
                                _MapLegend(color: Colors.green,  label: "Normal"),
                                _MapLegend(color: Colors.orange, label: "Risky"),
                                _MapLegend(color: Colors.red,    label: "Severe"),
                              ],
                            ),
                          ),

                          // ── Map body ──────────────────────────────────────
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(15)),
                              child: FlutterMap(
                                mapController: _mapController,
                                options: const MapOptions(
                                  initialCenter: LatLng(10.2635, 123.8320),
                                  initialZoom: 14,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  ),

                                  // Heatmap rings
                                  CircleLayer(circles: heatCircles),

                                  // Only user report markers — sensor nodes are shown in Sensor Network
                                  MarkerLayer(
                                    markers: [
                                      // User report markers
                                      ...userReports.map((r) {
                                        final String decision = (r['admin_decision'] ?? 'Pending').toString();
                                        final Color iconColor = _getDecisionColor(decision);

                                        return Marker(
                                          point: LatLng(_safeDouble(r['latitude']),
                                              _safeDouble(r['longitude'])),
                                          width: 140,
                                          height: 70,
                                          child: GestureDetector(
                                            onTap: () => _showAdminActionDialog(r),
                                            child: Column(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 4, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(4),
                                                    boxShadow: const [
                                                      BoxShadow(blurRadius: 2, color: Colors.black26),
                                                    ],
                                                  ),
                                                  child: Text(
                                                    "${r['location_name'] ?? 'Report'}\n$decision",
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                        fontSize: 7, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                                Icon(Icons.warning, color: iconColor, size: 35),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Sensor tile ───────────────────────────────────────────────────────────
  Widget _buildSensorTile(Map<String, dynamic> data) {
    final enhanced   = _getEnhancedSensorData(data);
    final isSelected = _selectedNode?['id'] == data['id'];
    final String displayName = enhanced['display_name'] ?? data['sensor_id'];
    final String rawId       = (data['sensor_id'] ?? '').toString();
    final double cm          = _safeDouble(data['water_level_cm']);
    final String status      = (data['status'] ?? 'Normal').toString();
    final Color statusColor  = _getStatusColor(status);

    final lastSeenStr = data['created_at']?.toString();
    final lastSeen    = DateTime.tryParse(lastSeenStr ?? '') ?? DateTime.now();
    final bool online = DateTime.now().difference(lastSeen).inMinutes < 10;
    final Color onlineColor = online ? Colors.green : Colors.redAccent;

    final int rssi       = (data['rssi_dbm'] as num? ?? -120).toInt();
    final Color rssiColor = rssi > -70 ? Colors.green : (rssi > -90 ? Colors.orange : Colors.red);

    return InkWell(
      onTap: () => _onNodeSelected(data),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).primaryColor
                : Colors.black.withValues(alpha: 0.08),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(displayName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                ),
                const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: onlineColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(online ? 'Online' : 'Offline',
                    style: TextStyle(fontSize: 12, color: onlineColor, fontWeight: FontWeight.bold)),
                const Spacer(),
                Icon(Icons.podcasts, size: 12, color: rssiColor),
                const SizedBox(width: 4),
                Text('$rssi dBm',
                    style: TextStyle(fontSize: 11, color: rssiColor, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Current Level: ${cm.toStringAsFixed(1)} cm',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: (cm / 60).clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade100,
              color: statusColor,
              minHeight: 8,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _Badge(icon: Icons.tag,        label: rawId),
                _Badge(icon: Icons.water_drop, label: status),
                _Badge(icon: Icons.access_time, label: _timeSince(lastSeen)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Report tile ───────────────────────────────────────────────────────────
  Widget _buildReportTile(Map<String, dynamic> data) {
    final isSelected = _selectedNode?['id'] == data['id'];
    final String status = (data['admin_decision'] ?? 'Pending').toString();
    final Color iconColor = _getDecisionColor(status);

    return ListTile(
      selected: isSelected,
      selectedTileColor: Colors.blue.withValues(alpha: 0.1),
      leading: Icon(Icons.report_problem, color: iconColor),
      title: Text(data['location_name'] ?? 'Report',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      subtitle: Text('Decision: $status'),
      onTap: () => _showAdminActionDialog(data),
    );
  }

  String? _reportImageUrl(Map<String, dynamic> report) {
    final raw = report['image_url'] ?? report['imageUrl'];
    final s = raw?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  // ── Admin dialog ──────────────────────────────────────────────────────────
  void _showAdminActionDialog(Map<String, dynamic> report) {
    final imageUrl = _reportImageUrl(report);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify Report'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Location: ${report['location_name'] ?? 'Unknown'}'),
                const SizedBox(height: 4),
                Text(
                  'Current: ${report['admin_decision'] ?? 'Pending'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (imageUrl != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Uploaded photo',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Colors.blueGrey.shade800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      imageUrl,
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 160,
                          alignment: Alignment.center,
                          color: Colors.blueGrey.withValues(alpha: 0.06),
                          child: const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        color: Colors.blueGrey.withValues(alpha: 0.1),
                        child: Row(
                          children: [
                            Icon(Icons.broken_image_outlined,
                                color: Colors.blueGrey.shade600),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Could not load image.',
                                style: TextStyle(
                                  color: Colors.blueGrey.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => _updateReportStatus(report['id'], 'Risky'),
            child: const Text('Risky', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => _updateReportStatus(report['id'], 'Impassable'),
            child: const Text('Impassable', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _updateReportStatus(dynamic id, String decision) async {
    await Supabase.instance.client
        .from('user_reports')
        .update({'admin_decision': decision}).eq('id', id);
    if (mounted) Navigator.pop(context);
  }

  // ── Node detail widgets ───────────────────────────────────────────────────
  Widget _buildNodeInfoTile() {
    return ListTile(
      dense: true,
      title: Text(
        'HISTORY: ${_selectedNode!['display_name'] ?? _selectedNode!['sensor_id']}'.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16),
        onPressed: () => setState(() => _selectedNode = null),
      ),
    );
  }

  Widget _buildNodeHistoryList(String sensorId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('sensor_logs')
          .select()
          .eq('sensor_id', sensorId)
          .order('created_at', ascending: false)
          .limit(5),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        return Column(
          children: snapshot.data!
              .map((item) => ListTile(
                    dense: true,
                    title: Text('${item['water_level_cm']} cm - ${item['status']}'),
                    subtitle: Text(item['created_at'].toString().substring(11, 16)),
                  ))
              .toList(),
        );
      },
    );
  }

  // ── Sidebar header ────────────────────────────────────────────────────────
  Widget _buildSidebarHeaderWidget() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Live Map',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  String _timeSince(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours  < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays   < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

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

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Badge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.blueGrey),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
        ],
      );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Text(title,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
    );
  }
}
