import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SensorConnectionStatus { online, offline }

class SensorNodeStatus {
  final String locationName;
  final String municipality;
  final String barangay;
  final SensorConnectionStatus loraStatus;
  final int? rssiDbm;
  final double waterLevelCm;
  final int batteryPercent;
  final String sensorId;
  final DateTime lastSeen;
  final LatLng position;

  const SensorNodeStatus({
    required this.locationName,
    required this.municipality,
    required this.barangay,
    required this.loraStatus,
    required this.rssiDbm,
    required this.waterLevelCm,
    required this.batteryPercent,
    required this.sensorId,
    required this.lastSeen,
    required this.position,
  });

  factory SensorNodeStatus.fromRecord(Map<String, dynamic> rec) {
    final recordedAtStr = rec['recorded_at'] as String?;
    final lastSeenDate = DateTime.tryParse(recordedAtStr ?? '') ?? DateTime.now();
    final bool onlineFlag = rec['is_online'] ?? (DateTime.now().difference(lastSeenDate).inMinutes < 10);
    
    return SensorNodeStatus(
      locationName: rec['location_name'] as String? ?? 'Unknown',
      municipality: rec['municipality'] as String? ?? 'Unknown',
      barangay: rec['barangay'] as String? ?? 'Unknown',
      loraStatus: onlineFlag ? SensorConnectionStatus.online : SensorConnectionStatus.offline,
      rssiDbm: rec['rssi_dbm'] as int?,
      waterLevelCm: (rec['water_level_cm'] as num? ?? 0).toDouble(),
      batteryPercent: rec['battery_percent'] as int? ?? 0,
      sensorId: rec['sensor_id'] as String? ?? 'Unknown',
      lastSeen: lastSeenDate,
      position: LatLng(rec['latitude'] as double? ?? 0.0, rec['longitude'] as double? ?? 0.0),
    );
  }
}

class SensorNetworkPage extends StatefulWidget {
  const SensorNetworkPage({super.key});

  @override
  State<SensorNetworkPage> createState() => _SensorNetworkPageState();
}

class _SensorNetworkPageState extends State<SensorNetworkPage> {
  late final Stream<List<SensorNodeStatus>> _nodesStream;
  List<SensorNodeStatus> _nodes = [];
  SensorNodeStatus? _selected;

  @override
  void initState() {
    super.initState();
    _nodesStream = Supabase.instance.client
        .from('sensor_logs')
        .stream(primaryKey: ['id'])
        .order('recorded_at', ascending: false)
        .map((recs) {
          final Map<String, SensorNodeStatus> uniqueMap = {};
          for (var r in recs) {
            final node = SensorNodeStatus.fromRecord(r);
            if (!uniqueMap.containsKey(node.sensorId)) {
              uniqueMap[node.sensorId] = node;
            }
          }
          return uniqueMap.values.toList();
        });
  }

  void _showSensorHistory(SensorNodeStatus node) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.history, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(child: Text("${node.locationName} Reports", style: const TextStyle(fontWeight: FontWeight.bold))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ],
        ),
        content: SizedBox(
          width: 550,
          height: 600,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: Supabase.instance.client
                .from('sensor_logs')
                .select()
                .eq('sensor_id', node.sensorId)
                .order('recorded_at', ascending: false),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text("No historical reports available."));
              }
              final logs = snapshot.data!;
              return ListView.separated(
                itemCount: logs.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, i) {
                  final log = logs[i];
                  final cm = (log['water_level_cm'] as num).toDouble();
                  final int rssi = log['rssi_dbm'] as int? ?? 0;
                  final time = DateTime.tryParse(log['recorded_at'] ?? '') ?? DateTime.now();
                  
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cm < 15 ? Colors.green : (cm <= 30 ? Colors.orange : Colors.red),
                      radius: 8,
                    ),
                    title: Text("${cm.toStringAsFixed(0)} cm", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Time: ${time.hour}:${time.minute.toString().padLeft(2, '0')} - ${time.month}/${time.day}"),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("${log['battery_percent']}% 🔋", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 2),
                        Text("$rssi dBm 📶", 
                          style: TextStyle(
                            fontSize: 10, 
                            fontWeight: FontWeight.bold,
                            color: rssi > -70 ? Colors.green : (rssi > -90 ? Colors.orange : Colors.red)
                          )
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<SensorNodeStatus>>(
      stream: _nodesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _nodes.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));

        _nodes = snapshot.data ?? _nodes;
        
        if (_nodes.isNotEmpty && _selected == null) {
          _selected = _nodes.first;
        }
        
        if (_selected != null) {
          final fresh = _nodes.where((n) => n.sensorId == _selected!.sensorId);
          if (fresh.isNotEmpty) _selected = fresh.first;
        }

        final size = MediaQuery.of(context).size;
        final isWide = size.width >= 1100;

        return Padding(
          padding: const EdgeInsets.all(24),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _buildLeftListCard(context)),
                    const SizedBox(width: 24),
                    Expanded(flex: 3, child: _buildRightDashboard(context, scheme)),
                  ],
                )
              : ListView(
                  children: [
                    _buildLeftListCard(context),
                    const SizedBox(height: 16),
                    _buildRightDashboard(context, scheme),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildLeftListCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 550,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.sensors, color: scheme.primary),
                const SizedBox(width: 10),
                const Text('Sensor Network', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${_nodes.length} Active Nodes', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _nodes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final node = _nodes[index];
                final isSelected = _selected?.sensorId == node.sensorId;
                return _SensorNodeCard(
                  node: node,
                  selected: isSelected,
                  onTap: () {
                    setState(() => _selected = node);
                    _showSensorHistory(node);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightDashboard(BuildContext context, ColorScheme scheme) {
    final online = _nodes.where((n) => n.loraStatus == SensorConnectionStatus.online).length;
    final offline = _nodes.where((n) => n.loraStatus == SensorConnectionStatus.offline).length;
    final lowSignal = _nodes.where((n) => (n.rssiDbm ?? 0) <= -90).length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _SummaryCard(title: 'Online', value: '$online', icon: Icons.wifi, color: Colors.green)),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(title: 'Offline', value: '$offline', icon: Icons.wifi_off, color: Colors.redAccent)),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(title: 'Low Signal', value: '$lowSignal', icon: Icons.network_wifi_1_bar, color: Colors.orange)),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          height: 480,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              options: const MapOptions(initialCenter: LatLng(10.26, 123.84), initialZoom: 13),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                MarkerLayer(
                  markers: _nodes.map((n) => Marker(
                    point: n.position,
                    width: 45, height: 45,
                    child: Icon(
                      Icons.location_on,
                      size: 40,
                      color: n.loraStatus == SensorConnectionStatus.online ? Colors.green : Colors.redAccent,
                    ),
                  )).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SensorNodeCard extends StatelessWidget {
  final SensorNodeStatus node;
  final bool selected;
  final VoidCallback onTap;

  const _SensorNodeCard({required this.node, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final statusColor = node.loraStatus == SensorConnectionStatus.online ? Colors.green : Colors.redAccent;
    final waterColor = node.waterLevelCm < 15 ? Colors.green : (node.waterLevelCm <= 30 ? Colors.orange : Colors.redAccent);
    
    final int signal = node.rssiDbm ?? -120;
    final Color signalColor = signal > -70 ? Colors.green : (signal > -90 ? Colors.orange : Colors.red);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Theme.of(context).primaryColor : Colors.black.withValues(alpha: 0.08), 
            width: selected ? 2 : 1
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(node.locationName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(node.loraStatus == SensorConnectionStatus.online ? 'Online' : 'Offline', 
                     style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold)),
                const Spacer(),
                Icon(Icons.podcasts, size: 12, color: signalColor),
                const SizedBox(width: 4),
                Text('$signal dBm', style: TextStyle(fontSize: 11, color: signalColor, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Text('Current Level: ${node.waterLevelCm.toStringAsFixed(0)} cm', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: (node.waterLevelCm / 60).clamp(0, 1),
              backgroundColor: Colors.grey.shade100,
              color: waterColor,
              minHeight: 8,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _Badge(icon: Icons.battery_charging_full, label: '${node.batteryPercent}%'),
                _Badge(icon: Icons.tag, label: node.sensorId),
                _Badge(icon: Icons.access_time, label: _timeSince(node.lastSeen)),
                _Badge(
                  icon: Icons.signal_cellular_alt, 
                  label: '${node.rssiDbm ?? "N/A"} dBm', 
                  customColor: signalColor
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _timeSince(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

class _Badge extends StatelessWidget {
  final IconData icon; 
  final String label;
  final Color? customColor;
  const _Badge({required this.icon, required this.label, this.customColor});
  
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: customColor ?? Colors.blueGrey), 
      const SizedBox(width: 4), 
      Text(label, style: TextStyle(fontSize: 10, color: customColor ?? Colors.blueGrey, fontWeight: FontWeight.bold))
    ]
  );
}

class _SummaryCard extends StatelessWidget {
  final String title, value; final IconData icon; final Color color;
  const _SummaryCard({required this.title, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border(left: BorderSide(color: color, width: 6))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    ]),
  );
}