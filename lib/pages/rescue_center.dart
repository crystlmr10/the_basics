import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// Rescue Center page:
// incident intake, rescuer assignment, and mission map view.
enum RescuerStatus { available, onMission }

class RescueIncident {
  final String id;
  final String userName;
  final LatLng userPos;
  final String depthLabel;
  final DateTime reportedAt;

  const RescueIncident({
    required this.id,
    required this.userName,
    required this.userPos,
    required this.depthLabel,
    required this.reportedAt,
  });
}

class Rescuer {
  final String id;
  final String name;
  final RescuerStatus status;
  final LatLng pos;
  final DateTime lastSeen;

  const Rescuer({
    required this.id,
    required this.name,
    required this.status,
    required this.pos,
    required this.lastSeen,
  });
}

class RescueCenterPage extends StatefulWidget {
  const RescueCenterPage({super.key});

  @override
  State<RescueCenterPage> createState() => _RescueCenterPageState();
}

class _RescueCenterPageState extends State<RescueCenterPage> {
  final MapController _mapController = MapController();

  final List<RescueIncident> _incidents = [
    RescueIncident(
      id: 'INC-001',
      userName: 'Ana Quisumbing',
      userPos: const LatLng(10.2608, 123.8215),
      depthLabel: 'Low',
      reportedAt: DateTime(2026, 1, 4, 5, 39),
    ),
    RescueIncident(
      id: 'INC-002',
      userName: 'Maria Fernandez',
      userPos: const LatLng(10.2605, 123.8420),
      depthLabel: 'High',
      reportedAt: DateTime(2026, 1, 4, 5, 39),
    ),
  ];

  final List<Rescuer> _initialRescuers = [
    Rescuer(
      id: 'RES-001',
      name: 'Rescuer A',
      status: RescuerStatus.available,
      pos: const LatLng(10.2620, 123.8410),
      lastSeen: DateTime(2026, 1, 4, 5, 38),
    ),
    Rescuer(
      id: 'RES-002',
      name: 'Rescuer B',
      status: RescuerStatus.available,
      pos: const LatLng(10.2690, 123.8540),
      lastSeen: DateTime(2026, 1, 4, 5, 37),
    ),
  ];

  late List<Rescuer> _rescuers;
  final Map<String, String> _assignedRescuerByIncidentId = {};
  String? _expandedIncidentId;
  String? _selectedRescuerIdForExpandedIncident;

  @override
  void initState() {
    super.initState();
    _rescuers = List.of(_initialRescuers);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const _TopTitle(
            title: 'Rescue Center',
            subtitle: 'Command and dispatch community help requests',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      Expanded(
                        child: _CardShell(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.fromLTRB(18, 18, 18, 10),
                                child: Text('Incident Reports', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _incidents.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                                  itemBuilder: (context, i) {
                                    final inc = _incidents[i];
                                    final assignedRescuerId = _assignedRescuerByIncidentId[inc.id];
                                    final isExpanded = _expandedIncidentId == inc.id;
                                    return _IncidentCard(
                                      incident: inc,
                                      assignedRescuerId: assignedRescuerId,
                                      isExpanded: isExpanded,
                                      rescuers: _rescuers,
                                      selectedRescuerId: _selectedRescuerIdForExpandedIncident,
                                      onDispatchToggle: () {
                                        setState(() {
                                          _expandedIncidentId = inc.id;
                                          _selectedRescuerIdForExpandedIncident = _availableRescuers().firstOrNull()?.id;
                                        });
                                      },
                                      onRescuerSelected: (id) => setState(() => _selectedRescuerIdForExpandedIncident = id),
                                      onAssign: () => _assignRescuer(inc.id),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        flex: 1,
                        child: _CardShell(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.fromLTRB(18, 18, 18, 10),
                                child: Text('Rescuer Status', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.vertical,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('Rescuer Name', style: TextStyle(fontWeight: FontWeight.w900))),
                                      DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w900))),
                                      DataColumn(label: Text('Last Seen', style: TextStyle(fontWeight: FontWeight.w900))),
                                    ],
                                    rows: _rescuers.map((r) {
                                      final statusLabel = r.status == RescuerStatus.available ? 'Available' : 'On-Mission';
                                      final statusColor = r.status == RescuerStatus.available ? Colors.green : Colors.blue;
                                      return DataRow(cells: [
                                        DataCell(Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                                        DataCell(Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w900))),
                                        DataCell(Text(_formatTime(r.lastSeen), style: const TextStyle(fontWeight: FontWeight.w800))),
                                      ]);
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: double.infinity,
                    child: _CardShell(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: FlutterMap(
                          mapController: _mapController,
                          options: const MapOptions(
                            initialCenter: LatLng(10.26, 123.84),
                            initialZoom: 12.8,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'the_basics',
                            ),
                            MarkerLayer(
                              markers: [
                                ..._incidents.map((inc) => Marker(
                                      point: inc.userPos,
                                      width: 42,
                                      height: 42,
                                      child: const Icon(Icons.location_on, color: Colors.redAccent, size: 34),
                                    )),
                                ..._rescuers.map((r) => Marker(
                                      point: r.pos,
                                      width: 42,
                                      height: 42,
                                      child: const Icon(Icons.location_on, color: Colors.blueAccent, size: 34),
                                    )),
                              ],
                            ),
                            PolylineLayer(
                              polylines: _activeMissionsPolylines(),
                            ),
                          ],
                        ),
                      ),
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

  List<Polyline> _activeMissionsPolylines() {
    final polylines = <Polyline>[];
    for (final inc in _incidents) {
      final rescuerId = _assignedRescuerByIncidentId[inc.id];
      if (rescuerId == null) continue;
      final rescuer = _rescuers.firstWhere((r) => r.id == rescuerId);
      polylines.add(
        Polyline(
          points: [inc.userPos, rescuer.pos],
          strokeWidth: 3,
          color: Colors.blueAccent.withValues(alpha: 0.8),
        ),
      );
    }
    return polylines;
  }

  List<Rescuer> _availableRescuers() => _rescuers.where((r) => r.status == RescuerStatus.available).toList();

  void _assignRescuer(String incidentId) {
    final rescuerId = _selectedRescuerIdForExpandedIncident;
    if (rescuerId == null) return;

    setState(() {
      _assignedRescuerByIncidentId[incidentId] = rescuerId;
      _rescuers = _rescuers.map((r) {
        if (r.id != rescuerId) return r;
        return Rescuer(
          id: r.id,
          name: r.name,
          status: RescuerStatus.onMission,
          pos: r.pos,
          lastSeen: DateTime.now(),
        );
      }).toList();
      _expandedIncidentId = null;
      _selectedRescuerIdForExpandedIncident = null;
    });

    final inc = _incidents.firstWhere((i) => i.id == incidentId);
    _mapController.move(inc.userPos, 14.0);
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _TopTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _TopTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _PersonShadowIcon(color: Colors.purple),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonShadowIcon extends StatelessWidget {
  final Color color;
  const _PersonShadowIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 2,
            top: 3,
            child: Icon(Icons.person, size: 22, color: color.withValues(alpha: 0.25)),
          ),
          Icon(Icons.person_outline, size: 22, color: color),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: child,
    );
  }
}

class _IncidentCard extends StatelessWidget {
  final RescueIncident incident;
  final String? assignedRescuerId;
  final bool isExpanded;
  final List<Rescuer> rescuers;
  final String? selectedRescuerId;
  final VoidCallback onDispatchToggle;
  final ValueChanged<String?> onRescuerSelected;
  final VoidCallback onAssign;

  const _IncidentCard({
    required this.incident,
    required this.assignedRescuerId,
    required this.isExpanded,
    required this.rescuers,
    required this.selectedRescuerId,
    required this.onDispatchToggle,
    required this.onRescuerSelected,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_pin_circle, color: Colors.redAccent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(incident.userName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
                  if (assignedRescuerId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999)),
                      child: const Text('Assigned', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w900, fontSize: 11)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Coordinates: ${incident.userPos.latitude.toStringAsFixed(4)}, ${incident.userPos.longitude.toStringAsFixed(4)}',
                style: TextStyle(color: Colors.blueGrey.shade700, fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('Reported Depth: ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.blueGrey)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: incident.depthLabel == 'High' ? Colors.orange.withValues(alpha: 0.15) : Colors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      incident.depthLabel == 'High' ? 'Waist High' : 'Low',
                      style: TextStyle(
                        color: incident.depthLabel == 'High' ? Colors.orange.shade700 : Colors.blueGrey.shade700,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onDispatchToggle,
                      icon: const Icon(Icons.safety_divider),
                      label: const Text('Dispatch Rescuer', style: TextStyle(fontWeight: FontWeight.w900)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade50,
                        foregroundColor: Colors.blueGrey.shade800,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              if (isExpanded) ...[
                const SizedBox(height: 10),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Select rescuer',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedRescuerId,
                      isExpanded: true,
                      items: rescuers
                          .where((r) => r.status == RescuerStatus.available)
                          .map((r) => DropdownMenuItem(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: onRescuerSelected,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onAssign,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Assign', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Reported: ${incident.reportedAt.toString().substring(0, 16).replaceAll('T', ' ')}',
                style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w700, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? firstOrNull() => isEmpty ? null : first;
}

