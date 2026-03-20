import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// Sensor network page:
// LoRa connection health + water level status + map markers.
enum SensorConnectionStatus { online, offline }

class SensorNodeStatus {
  final String locationName; // e.g., "Tabunok, Talisay"
  final String municipality; // e.g., "Talisay"
  final String barangay; // e.g., "Tabunok"
  final SensorConnectionStatus loraStatus;
  final int? rssiDbm; // negative dBm (null when offline / unknown)
  final double waterLevelCm; // JSN-SR04T measurement (cm)
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
}

class SensorNetworkPage extends StatefulWidget {
  const SensorNetworkPage({super.key});

  @override
  State<SensorNetworkPage> createState() => _SensorNetworkPageState();
}

class _SensorNetworkPageState extends State<SensorNetworkPage> {
  // Static sample data per requirements (replace with Supabase stream later).
  late final List<SensorNodeStatus> _nodes = [
    SensorNodeStatus(
      locationName: 'Tabunok, Talisay',
      municipality: 'Talisay',
      barangay: 'Tabunok',
      loraStatus: SensorConnectionStatus.online,
      rssiDbm: -85,
      waterLevelCm: 12,
      batteryPercent: 78,
      sensorId: 'LORA-001',
      lastSeen: DateTime.now().subtract(const Duration(minutes: 2)),
      // Tabunok, Talisay City (approx.)
      position: const LatLng(10.26, 123.84),
    ),
    SensorNodeStatus(
      locationName: 'Linao, Talisay City',
      municipality: 'Talisay',
      barangay: 'Linao',
      loraStatus: SensorConnectionStatus.offline,
      rssiDbm: null,
      waterLevelCm: 0,
      batteryPercent: 52,
      sensorId: 'LORA-002',
      lastSeen: DateTime.now().subtract(const Duration(hours: 5, minutes: 18)),
      // Linao, Talisay City (approx.)
      position: const LatLng(10.26, 123.82),
    ),
    SensorNodeStatus(
      locationName: 'Bulacao',
      municipality: 'Cebu City',
      barangay: 'Bulacao',
      loraStatus: SensorConnectionStatus.online,
      rssiDbm: -92,
      waterLevelCm: 28,
      batteryPercent: 64,
      sensorId: 'LORA-003',
      lastSeen: DateTime.now().subtract(const Duration(minutes: 7)),
      // Bulacao (approx.)
      position: const LatLng(10.27, 123.85),
    ),
  ];

  SensorNodeStatus? _selected;

  @override
  void initState() {
    super.initState();
    _selected = _nodes.first;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final total = _nodes.length;
    final online = _nodes.where((n) => n.loraStatus == SensorConnectionStatus.online).length;
    final offline = _nodes.where((n) => n.loraStatus == SensorConnectionStatus.offline).length;
    final lowSignal = _nodes.where((n) => _isLowSignal(n.rssiDbm)).length;

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
                Expanded(
                  flex: 3,
                  child: _buildRightDashboard(context, scheme, total, online, offline, lowSignal),
                ),
              ],
            )
          : Column(
              children: [
                SizedBox(height: 520, child: _buildLeftListCard(context)),
                const SizedBox(height: 16),
                SizedBox(
                  height: (size.height - 24 - 24 - 16).clamp(520.0, 740.0),
                  child: _buildRightDashboard(context, scheme, total, online, offline, lowSignal),
                ),
              ],
            ),
    );
  }

  Widget _buildLeftListCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Icon(Icons.sensors, color: scheme.primary),
                const SizedBox(width: 10),
                const Text(
                  'Sensor Network',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_nodes.length} nodes',
                    style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
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
                final selected = identical(node, _selected);
                return _SensorNodeCard(
                  node: node,
                  selected: selected,
                  onTap: () => setState(() => _selected = node),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightDashboard(
    BuildContext context,
    ColorScheme scheme,
    int total,
    int online,
    int offline,
    int lowSignal,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _SummaryCard(title: 'Total Sensors', value: '$total', icon: Icons.sensors, color: scheme.primary)),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(title: 'Online', value: '$online', icon: Icons.wifi, color: Colors.green)),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(title: 'Offline', value: '$offline', icon: Icons.wifi_off, color: Colors.redAccent)),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(title: 'Low Signal', value: '$lowSignal', icon: Icons.network_wifi_1_bar, color: Colors.orange)),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: const LatLng(10.26, 123.84),
                      initialZoom: 13,
                      onTap: (_, __) => FocusScope.of(context).unfocus(),
                    ),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'the_basics'),
                      MarkerLayer(
                        markers: _nodes
                            .map(
                              (n) => Marker(
                                point: n.position,
                                width: 46,
                                height: 46,
                                child: GestureDetector(
                                  onTap: () => setState(() => _selected = n),
                                  child: Icon(
                                    Icons.location_on,
                                    size: 40,
                                    color: n.loraStatus == SensorConnectionStatus.online ? Colors.green : Colors.redAccent,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                  if (_selected != null)
                    Positioned(
                      left: 16,
                      top: 16,
                      child: _MapInfoPill(node: _selected!),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static bool _isLowSignal(int? rssiDbm) {
    // LoRa/ESP32 RSSI is negative; closer to 0 is stronger.
    // Consider <= -90 dBm as low (tunable).
    if (rssiDbm == null) return false;
    return rssiDbm <= -90;
  }
}

class _SensorNodeCard extends StatelessWidget {
  final SensorNodeStatus node;
  final bool selected;
  final VoidCallback onTap;

  const _SensorNodeCard({
    required this.node,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = node.loraStatus == SensorConnectionStatus.online ? Colors.green : Colors.redAccent;
    final borderColor = selected ? scheme.primary.withValues(alpha: 0.65) : Colors.black.withValues(alpha: 0.08);

    final waterColor = _waterLevelColor(node.waterLevelCm);
    final progress = (node.waterLevelCm / 50).clamp(0.0, 1.0);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: selected ? 0.06 : 0.03),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.locationName,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _StatusDot(color: statusColor),
                            const SizedBox(width: 8),
                            Text(
                              node.loraStatus == SensorConnectionStatus.online ? 'Online (LoRa32)' : 'Offline (LoRa32)',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor),
                            ),
                            const SizedBox(width: 10),
                            _SignalBars(rssiDbm: node.rssiDbm),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.black.withValues(alpha: 0.35)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.water_drop_outlined, size: 16, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Text(
                    'Live Water Level: ${node.waterLevelCm.toStringAsFixed(0)} cm',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  backgroundColor: Colors.black.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(waterColor),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetaChip(icon: Icons.battery_full, label: '${node.batteryPercent}%'),
                  _MetaChip(icon: Icons.numbers, label: node.sensorId),
                  _MetaChip(icon: Icons.access_time, label: _formatLastSeen(node.lastSeen)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _waterLevelColor(double cm) {
    if (cm < 15) return Colors.green;
    if (cm <= 30) return Colors.orange;
    return Colors.redAccent;
  }

  static String _formatLastSeen(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Last seen: just now';
    if (diff.inMinutes < 60) return 'Last seen: ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last seen: ${diff.inHours}h ago';
    return 'Last seen: ${diff.inDays}d ago';
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 6)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 16, offset: const Offset(0, 10)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 6),
                Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          Icon(icon, color: color.withValues(alpha: 0.35), size: 28),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10)]),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  final int? rssiDbm;
  const _SignalBars({required this.rssiDbm});

  @override
  Widget build(BuildContext context) {
    final bars = _rssiToBars(rssiDbm);
    final activeColor = (rssiDbm == null) ? Colors.grey : Colors.blueGrey;
    final inactiveColor = Colors.black.withValues(alpha: 0.12);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) {
        final active = i < bars;
        final h = 6.0 + (i * 4.0);
        return Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Container(
            width: 4,
            height: h,
            decoration: BoxDecoration(
              color: active ? activeColor : inactiveColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  static int _rssiToBars(int? rssiDbm) {
    if (rssiDbm == null) return 0;
    // Map negative RSSI (stronger is closer to 0).
    // -30..-59 => 4 bars, -60..-74 => 3, -75..-89 => 2, <= -90 => 1
    if (rssiDbm >= -59) return 4;
    if (rssiDbm >= -74) return 3;
    if (rssiDbm >= -89) return 2;
    return 1;
  }
}

class _MapInfoPill extends StatelessWidget {
  final SensorNodeStatus node;
  const _MapInfoPill({required this.node});

  @override
  Widget build(BuildContext context) {
    final statusColor = node.loraStatus == SensorConnectionStatus.online ? Colors.green : Colors.redAccent;
    final rssiText = node.rssiDbm == null ? 'RSSI: N/A' : 'RSSI: ${node.rssiDbm} dBm';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 10))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(color: statusColor),
          const SizedBox(width: 10),
          Text(node.locationName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          const SizedBox(width: 10),
          Text(rssiText, style: const TextStyle(color: Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

