import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class SosDispatch {
  final String id;
  final String ticketNumber;
  final String userId;
  final String? userName;
  final String? userEmail;
  final double latitude;
  final double longitude;
  final String status;
  final DateTime submittedAt;
  final String? emergencyMainCategory;
  final String? emergencySubcategory;
  final String? emergencyOtherNote;
  final String? callerPhone;
  final String? assignedRescuerId;

  const SosDispatch({
    required this.id,
    required this.ticketNumber,
    required this.userId,
    this.userName,
    this.userEmail,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.submittedAt,
    this.emergencyMainCategory,
    this.emergencySubcategory,
    this.emergencyOtherNote,
    this.callerPhone,
    this.assignedRescuerId,
  });

  String get displayName => userName ?? userEmail ?? userId.substring(0, 8);

  String get categoryLabel {
    if (emergencyMainCategory != null && emergencySubcategory != null) {
      return '$emergencyMainCategory › $emergencySubcategory';
    }
    return emergencyMainCategory ?? emergencyOtherNote ?? 'Emergency';
  }

  factory SosDispatch.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'] as Map<String, dynamic>?;
    return SosDispatch(
      id: m['id'] as String,
      ticketNumber: m['ticket_number'] as String,
      userId: m['user_id'] as String,
      userName: profile?['username'] as String?,
      userEmail: profile?['email'] as String?,
      latitude: (m['latitude'] as num).toDouble(),
      longitude: (m['longitude'] as num).toDouble(),
      status: m['status'] as String,
      submittedAt: DateTime.parse(m['submitted_at'] as String).toLocal(),
      emergencyMainCategory: m['emergency_main_category'] as String?,
      emergencySubcategory: m['emergency_subcategory'] as String?,
      emergencyOtherNote: m['emergency_other_note'] as String?,
      callerPhone: m['caller_phone'] as String?,
      assignedRescuerId: m['assigned_rescuer_id'] as String?,
    );
  }
}

class UserReport {
  final String id;
  final String? userId;
  final String? userName;
  final String? userEmail;
  final String? locationName;
  final String? userComments;
  final String? imageUrl;
  final double latitude;
  final double longitude;
  final String adminDecision;
  final DateTime createdAt;

  const UserReport({
    required this.id,
    this.userId,
    this.userName,
    this.userEmail,
    this.locationName,
    this.userComments,
    this.imageUrl,
    required this.latitude,
    required this.longitude,
    required this.adminDecision,
    required this.createdAt,
  });

  String get displayReporter => userName ?? userEmail ?? 'Anonymous';

  factory UserReport.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'] as Map<String, dynamic>?;
    return UserReport(
      id: m['id'] as String,
      userId: m['user_id'] as String?,
      userName: profile?['username'] as String?,
      userEmail: profile?['email'] as String?,
      locationName: m['location_name'] as String?,
      userComments: m['user_comments'] as String?,
      imageUrl: m['image_url'] as String?,
      latitude: (m['latitude'] as num).toDouble(),
      longitude: (m['longitude'] as num).toDouble(),
      adminDecision: m['admin_decision'] as String? ?? 'pending',
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    );
  }
}

class RescuerProfile {
  final String id;
  final String? username;
  final String? email;
  final bool isOnDuty;
  final double? lastLatitude;
  final double? lastLongitude;
  final DateTime? lastLocationAt;

  const RescuerProfile({
    required this.id,
    this.username,
    this.email,
    required this.isOnDuty,
    this.lastLatitude,
    this.lastLongitude,
    this.lastLocationAt,
  });

  String get displayName => username ?? email ?? id.substring(0, 8);

  factory RescuerProfile.fromMap(Map<String, dynamic> m) {
    return RescuerProfile(
      id: m['id'] as String,
      username: m['username'] as String?,
      email: m['email'] as String?,
      isOnDuty: m['is_on_duty'] as bool? ?? false,
      lastLatitude: m['last_latitude'] != null
          ? (m['last_latitude'] as num).toDouble()
          : null,
      lastLongitude: m['last_longitude'] != null
          ? (m['last_longitude'] as num).toDouble()
          : null,
      lastLocationAt: m['last_location_at'] != null
          ? DateTime.parse(m['last_location_at'] as String).toLocal()
          : null,
    );
  }
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class RescueCenterPage extends StatefulWidget {
  const RescueCenterPage({super.key});

  @override
  State<RescueCenterPage> createState() => _RescueCenterPageState();
}

class _RescueCenterPageState extends State<RescueCenterPage> {
  final _supabase = Supabase.instance.client;
  final MapController _mapController = MapController();

  List<SosDispatch> _incidents = [];
  List<UserReport> _userReports = [];
  List<RescuerProfile> _rescuers = [];

  bool _loading = true;
  bool _assigning = false;
  String? _error;

  // UI state
  final Map<String, String> _assignedRescuerByIncidentId = {};
  String? _expandedIncidentId;
  String? _selectedRescuerIdForExpandedIncident;
  UserReport? _selectedUserReport;

  // Realtime
  StreamSubscription<List<Map<String, dynamic>>>? _sosSub;
  StreamSubscription<List<Map<String, dynamic>>>? _reportsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _rescuersSub;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _sosSub?.cancel();
    _reportsSub?.cancel();
    _rescuersSub?.cancel();
    super.dispose();
  }

  // ── Data Loading ────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Future.wait([
        _loadIncidents(),
        _loadUserReports(),
        _loadRescuers(),
      ]);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadIncidents() async {
    final data = await _supabase
        .from('sos_dispatches')
        .select('*, profiles!sos_dispatches_user_id_fkey(username, email)')
        .neq('status', 'closed')
        .order('submitted_at', ascending: false);

    final list = (data as List)
        .map((m) => SosDispatch.fromMap(m as Map<String, dynamic>))
        .toList();

    if (mounted) {
      setState(() {
        _incidents = list;
        // Sync assignment map from DB
        for (final inc in list) {
          if (inc.assignedRescuerId != null) {
            _assignedRescuerByIncidentId[inc.id] = inc.assignedRescuerId!;
          }
        }
      });
    }
  }

  Future<void> _loadUserReports() async {
    final data = await _supabase
        .from('user_reports')
        .select('*, profiles!user_reports_user_id_fkey(username, email)')
        .order('created_at', ascending: false);

    final list = (data as List)
        .map((m) => UserReport.fromMap(m as Map<String, dynamic>))
        .toList();

    if (mounted) setState(() => _userReports = list);
  }

  Future<void> _loadRescuers() async {
    final data = await _supabase
        .from('profiles')
        .select('*')
        .eq('role', 'rescuer');

    final list = (data as List)
        .map((m) => RescuerProfile.fromMap(m as Map<String, dynamic>))
        .toList();

    if (mounted) setState(() => _rescuers = list);
  }

  // ── Realtime ────────────────────────────────────────────────────────────────

  void _subscribeRealtime() {
    _sosSub = _supabase
        .from('sos_dispatches')
        .stream(primaryKey: ['id'])
        .listen((_) => _loadIncidents());

    _reportsSub = _supabase
        .from('user_reports')
        .stream(primaryKey: ['id'])
        .listen((_) => _loadUserReports());

    _rescuersSub = _supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('role', 'rescuer')
        .listen((_) => _loadRescuers());
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _assignRescuer(String incidentId) async {
    final rescuerId = _selectedRescuerIdForExpandedIncident;
    if (rescuerId == null) return;

    setState(() => _assigning = true);

    try {
      await _supabase.from('sos_dispatches').update({
        'assigned_rescuer_id': rescuerId,
        'status': 'dispatching',
      }).eq('id', incidentId);

      setState(() {
        _assignedRescuerByIncidentId[incidentId] = rescuerId;
        _expandedIncidentId = null;
        _selectedRescuerIdForExpandedIncident = null;
      });

      final inc = _incidents.where((i) => i.id == incidentId).firstOrNull;
      if (inc != null) {
        _mapController.move(LatLng(inc.latitude, inc.longitude), 14.0);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rescuer dispatched successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }

      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to assign rescuer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  List<RescuerProfile> _availableRescuers() => _rescuers
      .where((r) =>
          r.isOnDuty && !_assignedRescuerByIncidentId.values.contains(r.id))
      .toList();

  List<Polyline> _activeMissionsPolylines() {
    final polylines = <Polyline>[];
    for (final inc in _incidents) {
      final rescuerId = _assignedRescuerByIncidentId[inc.id];
      if (rescuerId == null) continue;
      final matches = _rescuers.where((r) => r.id == rescuerId);
      if (matches.isEmpty) continue;
      final rescuer = matches.first;
      if (rescuer.lastLatitude == null || rescuer.lastLongitude == null) {
        continue;
      }
      polylines.add(
        Polyline(
          points: [
            LatLng(inc.latitude, inc.longitude),
            LatLng(rescuer.lastLatitude!, rescuer.lastLongitude!),
          ],
          strokeWidth: 3,
          color: Colors.blueAccent.withValues(alpha: 0.8),
        ),
      );
    }
    return polylines;
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading && _incidents.isEmpty && _userReports.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text('Error: $_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // ── Header
          Row(
            children: [
              const _TopTitle(
                title: 'Rescue Center',
                subtitle: 'Command and dispatch community help requests',
              ),
              const Spacer(),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh data',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Body
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Left column
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      // Incident Reports
                      Expanded(
                        child: _CardShell(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(18, 18, 18, 10),
                                child: Row(
                                  children: [
                                    const Text(
                                      'Incident Reports',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent
                                            .withValues(alpha: 0.10),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '${_incidents.length} active',
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: _incidents.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No active incidents',
                                          style: TextStyle(
                                              color: Colors.blueGrey),
                                        ),
                                      )
                                    : ListView.separated(
                                        padding: const EdgeInsets.all(16),
                                        itemCount: _incidents.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 12),
                                        itemBuilder: (context, i) {
                                          final inc = _incidents[i];
                                          final assignedRescuerId =
                                              _assignedRescuerByIncidentId[
                                                  inc.id];
                                          final isExpanded =
                                              _expandedIncidentId == inc.id;
                                          return _IncidentCard(
                                            incident: inc,
                                            assignedRescuerId:
                                                assignedRescuerId,
                                            isExpanded: isExpanded,
                                            rescuers: _availableRescuers(),
                                            selectedRescuerId: isExpanded
                                                ? _selectedRescuerIdForExpandedIncident
                                                : null,
                                            assigning: _assigning &&
                                                _expandedIncidentId == inc.id,
                                            onDispatchToggle: () {
                                              setState(() {
                                                _expandedIncidentId = inc.id;
                                                _selectedRescuerIdForExpandedIncident =
                                                    _availableRescuers()
                                                        .firstOrNull
                                                        ?.id;
                                              });
                                            },
                                            onRescuerSelected: (id) =>
                                                setState(() =>
                                                    _selectedRescuerIdForExpandedIncident =
                                                        id),
                                            onAssign: () =>
                                                _assignRescuer(inc.id),
                                            onLocate: () =>
                                                _mapController.move(
                                              LatLng(inc.latitude,
                                                  inc.longitude),
                                              15.0,
                                            ),
                                            formatDateTime: _formatDateTime,
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Rescuer Status
                      Expanded(
                        flex: 1,
                        child: _CardShell(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(18, 18, 18, 10),
                                child: Row(
                                  children: [
                                    const Text(
                                      'Rescuer Status',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${_rescuers.where((r) => r.isOnDuty).length} on duty',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: _rescuers.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No rescuers found',
                                          style: TextStyle(
                                              color: Colors.blueGrey),
                                        ),
                                      )
                                    : SingleChildScrollView(
                                        scrollDirection: Axis.vertical,
                                        child: DataTable(
                                          columnSpacing: 12,
                                          columns: const [
                                            DataColumn(
                                                label: Text('Name',
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900))),
                                            DataColumn(
                                                label: Text('Status',
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900))),
                                            DataColumn(
                                                label: Text('Duty',
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900))),
                                          ],
                                          rows: _rescuers.map((r) {
                                            final isAssigned =
                                                _assignedRescuerByIncidentId
                                                    .values
                                                    .contains(r.id);
                                            final statusLabel = isAssigned
                                                ? 'On-Mission'
                                                : r.isOnDuty
                                                    ? 'Available'
                                                    : 'Off-Duty';
                                            final statusColor = isAssigned
                                                ? Colors.blue
                                                : r.isOnDuty
                                                    ? Colors.green
                                                    : Colors.grey;
                                            return DataRow(cells: [
                                              DataCell(Text(r.displayName,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800))),
                                              DataCell(Text(statusLabel,
                                                  style: TextStyle(
                                                      color: statusColor,
                                                      fontWeight:
                                                          FontWeight.w900))),
                                              DataCell(Icon(
                                                r.isOnDuty
                                                    ? Icons.check_circle
                                                    : Icons.cancel,
                                                color: r.isOnDuty
                                                    ? Colors.green
                                                    : Colors.grey,
                                                size: 18,
                                              )),
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

                // ── Map
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: double.infinity,
                    child: _CardShell(
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: FlutterMap(
                              mapController: _mapController,
                              options: const MapOptions(
                                initialCenter: LatLng(10.26, 123.84),
                                initialZoom: 12.8,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'the_basics',
                                ),
                                MarkerLayer(
                                  markers: [
                                    // SOS Incidents — red SOS icon
                                    ..._incidents.map(
                                      (inc) => Marker(
                                        point: LatLng(
                                            inc.latitude, inc.longitude),
                                        width: 44,
                                        height: 44,
                                        child: GestureDetector(
                                          onTap: () => _mapController.move(
                                            LatLng(inc.latitude, inc.longitude),
                                            15.0,
                                          ),
                                          child: Tooltip(
                                            message:
                                                '${inc.displayName} — ${inc.ticketNumber}',
                                            child: const Icon(
                                              Icons.sos,
                                              color: Colors.redAccent,
                                              size: 36,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Rescuers — blue pin (only if location known)
                                    ..._rescuers
                                        .where((r) =>
                                            r.lastLatitude != null &&
                                            r.lastLongitude != null)
                                        .map(
                                          (r) => Marker(
                                            point: LatLng(r.lastLatitude!,
                                                r.lastLongitude!),
                                            width: 44,
                                            height: 44,
                                            child: Tooltip(
                                              message: r.displayName,
                                              child: const Icon(
                                                Icons.location_on,
                                                color: Colors.blueAccent,
                                                size: 36,
                                              ),
                                            ),
                                          ),
                                        ),
                                    // User Reports — amber/orange/green pin
                                    ..._userReports.map(
                                      (rep) => Marker(
                                        point: LatLng(
                                            rep.latitude, rep.longitude),
                                        width: 44,
                                        height: 44,
                                        child: GestureDetector(
                                          onTap: () => setState(
                                              () => _selectedUserReport = rep),
                                          child: Tooltip(
                                            message: rep.locationName ??
                                                'User Report',
                                            child: Icon(
                                              Icons.report_problem_rounded,
                                              color: rep.adminDecision ==
                                                      'impassable'
                                                  ? Colors.deepOrange
                                                  : rep.adminDecision ==
                                                          'passable'
                                                      ? Colors.green
                                                      : Colors.amber.shade700,
                                              size: 36,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                PolylineLayer(
                                  polylines: _activeMissionsPolylines(),
                                ),
                              ],
                            ),
                          ),

                          // User Report popup (top-right)
                          if (_selectedUserReport != null)
                            Positioned(
                              top: 12,
                              right: 12,
                              width: 280,
                              child: _UserReportPopup(
                                report: _selectedUserReport!,
                                onClose: () =>
                                    setState(() => _selectedUserReport = null),
                                formatDateTime: _formatDateTime,
                              ),
                            ),

                          // Map legend (bottom-left)
                          const Positioned(
                            bottom: 12,
                            left: 12,
                            child: _MapLegend(),
                          ),
                        ],
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
}

// ─── Incident Card ────────────────────────────────────────────────────────────

class _IncidentCard extends StatelessWidget {
  final SosDispatch incident;
  final String? assignedRescuerId;
  final bool isExpanded;
  final List<RescuerProfile> rescuers;
  final String? selectedRescuerId;
  final bool assigning;
  final VoidCallback onDispatchToggle;
  final ValueChanged<String?> onRescuerSelected;
  final VoidCallback onAssign;
  final VoidCallback onLocate;
  final String Function(DateTime) formatDateTime;

  const _IncidentCard({
    required this.incident,
    required this.assignedRescuerId,
    required this.isExpanded,
    required this.rescuers,
    required this.selectedRescuerId,
    required this.assigning,
    required this.onDispatchToggle,
    required this.onRescuerSelected,
    required this.onAssign,
    required this.onLocate,
    required this.formatDateTime,
  });

  @override
  Widget build(BuildContext context) {
    final isAssigned = assignedRescuerId != null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row
            Row(
              children: [
                const Icon(Icons.person_pin_circle,
                    color: Colors.redAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        incident.displayName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                      Text(
                        incident.ticketNumber,
                        style: TextStyle(
                            color: Colors.blueGrey.shade500,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (isAssigned)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Assigned',
                      style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w900,
                          fontSize: 11),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // ── Coordinates
            Text(
              'Coords: ${incident.latitude.toStringAsFixed(5)}, '
              '${incident.longitude.toStringAsFixed(5)}',
              style: TextStyle(
                  color: Colors.blueGrey.shade700,
                  fontWeight: FontWeight.w700,
                  fontSize: 11),
            ),

            const SizedBox(height: 6),

            // ── Category
            if (incident.emergencyMainCategory != null) ...[
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      incident.categoryLabel,
                      style: TextStyle(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w700,
                          fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],

            // ── Status chip
            Row(
              children: [
                const Text('Status: ',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: Colors.blueGrey)),
                _StatusChip(status: incident.status),
              ],
            ),

            const SizedBox(height: 10),

            // ── Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onLocate,
                    icon: const Icon(Icons.my_location, size: 16),
                    label: const Text('Locate',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isAssigned ? null : onDispatchToggle,
                    icon: const Icon(Icons.safety_divider, size: 16),
                    label: const Text('Dispatch',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade50,
                      foregroundColor: Colors.blueGrey.shade800,
                      disabledBackgroundColor:
                          Colors.green.withValues(alpha: 0.1),
                      disabledForegroundColor: Colors.green.shade700,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),

            // ── Rescuer selector (expanded)
            if (isExpanded) ...[
              const SizedBox(height: 10),
              if (rescuers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'No available rescuers on duty',
                        style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.w700,
                            fontSize: 12),
                      ),
                    ],
                  ),
                )
              else ...[
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Select Rescuer',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedRescuerId,
                      isExpanded: true,
                      isDense: true,
                      items: rescuers
                          .map((r) => DropdownMenuItem(
                                value: r.id,
                                child: Text(r.displayName,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: onRescuerSelected,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: assigning ? null : onAssign,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: assigning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Confirm Dispatch',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 8),

            // ── Footer timestamp
            Text(
              'Reported: ${formatDateTime(incident.submittedAt)}',
              style: const TextStyle(
                  color: Colors.blueGrey,
                  fontWeight: FontWeight.w700,
                  fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── User Report Popup ────────────────────────────────────────────────────────

class _UserReportPopup extends StatelessWidget {
  final UserReport report;
  final VoidCallback onClose;
  final String Function(DateTime) formatDateTime;

  const _UserReportPopup({
    required this.report,
    required this.onClose,
    required this.formatDateTime,
  });

  Color get _decisionColor {
    switch (report.adminDecision) {
      case 'impassable':
        return Colors.deepOrange;
      case 'passable':
        return Colors.green;
      default:
        return Colors.amber.shade700;
    }
  }

  String get _decisionLabel {
    switch (report.adminDecision) {
      case 'impassable':
        return 'Impassable';
      case 'passable':
        return 'Passable';
      default:
        return 'Pending Review';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
              decoration: BoxDecoration(
                color: _decisionColor.withValues(alpha: 0.08),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.report_problem_rounded,
                      color: _decisionColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      report.locationName ?? 'User Report',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: Colors.blueGrey,
                  ),
                ],
              ),
            ),

            // ── Body
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Reporter
                  _InfoRow(
                    icon: Icons.person_outline,
                    label: 'Reported by',
                    value: report.displayReporter,
                  ),
                  const SizedBox(height: 8),

                  // Coordinates
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    label: 'Coordinates',
                    value:
                        '${report.latitude.toStringAsFixed(5)}, ${report.longitude.toStringAsFixed(5)}',
                  ),
                  const SizedBox(height: 8),

                  // Status
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 14, color: Colors.blueGrey),
                      const SizedBox(width: 6),
                      const Text('Status: ',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Colors.blueGrey)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _decisionColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _decisionLabel,
                          style: TextStyle(
                              color: _decisionColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 11),
                        ),
                      ),
                    ],
                  ),

                  // Comments
                  if (report.userComments != null &&
                      report.userComments!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '"${report.userComments}"',
                        style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 12,
                            color: Colors.blueGrey),
                      ),
                    ),
                  ],

                  // Image
                  if (report.imageUrl != null &&
                      report.imageUrl!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        report.imageUrl!,
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 60,
                          color: Colors.blueGrey.withValues(alpha: 0.1),
                          child: const Center(
                            child: Icon(Icons.broken_image,
                                color: Colors.blueGrey),
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Timestamp
                  Text(
                    'Submitted: ${formatDateTime(report.createdAt)}',
                    style: const TextStyle(
                        color: Colors.blueGrey,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Status Chip ─────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  Color get _color {
    switch (status) {
      case 'submitted':
        return Colors.orange;
      case 'received':
        return Colors.blue;
      case 'dispatching':
        return Colors.purple;
      case 'en_route':
        return Colors.teal;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  String get _label {
    switch (status) {
      case 'submitted':
        return 'Submitted';
      case 'received':
        return 'Received';
      case 'dispatching':
        return 'Dispatching';
      case 'en_route':
        return 'En Route';
      case 'closed':
        return 'Closed';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _label,
        style: TextStyle(
            color: _color, fontWeight: FontWeight.w900, fontSize: 11),
      ),
    );
  }
}

// ─── Info Row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.blueGrey),
        const SizedBox(width: 6),
        Text('$label: ',
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Colors.blueGrey)),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ─── Map Legend ───────────────────────────────────────────────────────────────

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(
              icon: Icons.sos, color: Colors.redAccent, label: 'SOS Dispatch'),
          SizedBox(height: 6),
          _LegendItem(
              icon: Icons.location_on,
              color: Colors.blueAccent,
              label: 'Rescuer'),
          SizedBox(height: 6),
          _LegendItem(
              icon: Icons.report_problem_rounded,
              color: Colors.deepOrange,
              label: 'Impassable'),
          SizedBox(height: 6),
          _LegendItem(
              icon: Icons.report_problem_rounded,
              color: Colors.green,
              label: 'Passable'),
          SizedBox(height: 6),
          _LegendItem(
              icon: Icons.report_problem_rounded,
              color: Colors.amber,
              label: 'Pending Report'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _LegendItem(
      {required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ─── Top Title ────────────────────────────────────────────────────────────────

class _TopTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _TopTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PersonShadowIcon(color: Colors.purple),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 22)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: TextStyle(
                    color: Colors.blueGrey.shade600,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
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
            child: Icon(Icons.person,
                size: 22, color: color.withValues(alpha: 0.25)),
          ),
          Icon(Icons.person_outline, size: 22, color: color),
        ],
      ),
    );
  }
}

// ─── Card Shell ───────────────────────────────────────────────────────────────

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
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 8))
        ],
      ),
      child: child,
    );
  }
}