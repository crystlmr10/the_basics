import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/sos_emergency_categories.dart';
import 'settings_page.dart';

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
  final DateTime? updatedAt;
  final DateTime? acceptedAt;
  final DateTime? enRouteAt;
  final DateTime? closedAt;
  final bool adminCancelled;

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
    this.updatedAt,
    this.acceptedAt,
    this.enRouteAt,
    this.closedAt,
    this.adminCancelled = false,
  });

  String get displayName => userName ?? userEmail ?? userId.substring(0, 8);

  String get categoryLabel {
    if (emergencyMainCategory != null && emergencySubcategory != null) {
      return '$emergencyMainCategory › $emergencySubcategory';
    }
    return emergencyMainCategory ?? emergencyOtherNote ?? 'Emergency';
  }

  String get emergencyTypeDisplay => formatSosEmergencyTypeLine(
        emergencyMainCategory,
        emergencySubcategory,
        emergencyOtherNote,
      );

  factory SosDispatch.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'] as Map<String, dynamic>?;
    final rawStatus = (m['status'] as String?)?.trim().toLowerCase();
    final rawTicket = (m['ticket_number'] as String?)?.trim();
    return SosDispatch(
      id: m['id'] as String,
      ticketNumber: (rawTicket == null || rawTicket.isEmpty)
          ? 'SOS-${(m['id'] as String).substring(0, 6).toUpperCase()}'
          : rawTicket,
      userId: m['user_id'] as String,
      userName: profile?['username'] as String?,
      userEmail: profile?['email'] as String?,
      latitude: (m['latitude'] as num).toDouble(),
      longitude: (m['longitude'] as num).toDouble(),
      status: (rawStatus == null || rawStatus.isEmpty)
          ? 'submitted'
          : rawStatus,
      submittedAt: DateTime.parse(m['submitted_at'] as String).toLocal(),
      emergencyMainCategory: m['emergency_main_category'] as String?,
      emergencySubcategory: m['emergency_subcategory'] as String?,
      emergencyOtherNote: m['emergency_other_note'] as String?,
      callerPhone: m['caller_phone'] as String?,
      assignedRescuerId: m['assigned_rescuer_id'] as String?,
      updatedAt: m['updated_at'] != null
          ? DateTime.parse(m['updated_at'] as String).toLocal()
          : null,
      acceptedAt: m['accepted_at'] != null
          ? DateTime.parse(m['accepted_at'] as String).toLocal()
          : null,
      enRouteAt: m['en_route_at'] != null
          ? DateTime.parse(m['en_route_at'] as String).toLocal()
          : null,
      closedAt: m['closed_at'] != null
          ? DateTime.parse(m['closed_at'] as String).toLocal()
          : null,
      adminCancelled: m['admin_cancelled'] == true,
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
  final AppSettingsController? settings;
  const RescueCenterPage({super.key, this.settings});

  @override
  State<RescueCenterPage> createState() => _RescueCenterPageState();
}

class _RescueCenterPageState extends State<RescueCenterPage> {
  final _supabase = Supabase.instance.client;
  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  List<SosDispatch> _incidents = [];
  List<SosDispatch> _incidentHistory = [];
  List<UserReport> _userReports = [];
  List<RescuerProfile> _rescuers = [];

  bool _loading = true;
  bool _assigning = false;
  String? _cancellingIncidentId;
  String? _error;

  // UI state
  final Map<String, String> _queueNoticeByIncidentId = {};
  String? _expandedIncidentId;
  String? _selectedRescuerIdForExpandedIncident;
  UserReport? _selectedUserReport;
  bool _showSosHistory = false;

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
  bool _isActiveSosStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'submitted':
      case 'received':
      case 'dispatching':
      case 'en_route':
        return true;
      default:
        return false;
    }
  }

  /// Mission phase: rescuer counts as On-Mission and is excluded from new dispatch picks.
  bool _isMissionStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'dispatching':
      case 'en_route':
        return true;
      default:
        return false;
    }
  }

  bool _rescuerIsOnMission(String rescuerId) {
    return _incidents.any(
      (i) =>
          i.assignedRescuerId == rescuerId &&
          i.assignedRescuerId != null &&
          _isMissionStatus(i.status),
    );
  }

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
    final previousById = {
      for (final incident in _incidents) incident.id: incident,
    };
    final data = await _supabase
        .from('sos_dispatches')
        .select('*, profiles!sos_dispatches_user_id_fkey(username, email)')
        .order('submitted_at', ascending: false);

    final list = (data as List)
        .map((m) => SosDispatch.fromMap(m as Map<String, dynamic>))
        .toList();
    final activeList = list.where((inc) => _isActiveSosStatus(inc.status)).toList();

    if (mounted) {
      setState(() {
        _incidents = activeList;
        _incidentHistory = list;
        final activeIds = activeList.map((e) => e.id).toSet();
        _queueNoticeByIncidentId.removeWhere((id, _) => !activeIds.contains(id));
      });
      _emitQueueWorkflowUpdates(previousById, list);
    }
  }

  Future<void> _loadUserReports() async {
    final data = await _supabase
        .from('user_reports')
        .select('*, profiles!user_reports_user_id_fkey(username, email)')
        .isFilter('deleted_at', null)
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
    final incident = _incidents.where((i) => i.id == incidentId).firstOrNull;
    if (incident == null) return;

    final options = _rescuersForIncidentDispatch(incident);
    final rescuerId = _selectedRescuerIdForExpandedIncident;
    final hasValidSelection = rescuerId != null &&
        options.candidates.any((c) => c.rescuer.id == rescuerId);
    if (!hasValidSelection) {
      if (mounted) {
        setState(() {
          _selectedRescuerIdForExpandedIncident =
              options.candidates.firstOrNull?.rescuer.id;
        });
        _notifyRealtimeEvent(
          'Rescuer list updated. Please confirm the selected rescuer again.',
          color: Colors.orange.shade800,
        );
      }
      return;
    }

    setState(() => _assigning = true);

    try {
      final rpcRes = await _supabase.rpc(
        'admin_assign_sos_dispatch',
        params: {
          'p_dispatch_id': incidentId,
          'p_rescuer_id': rescuerId,
        },
      );
      final map = rpcRes is Map
          ? Map<String, dynamic>.from(rpcRes)
          : <String, dynamic>{};
      final ok = map['ok'] == true;
      if (!ok) {
        final err = (map['error'] ?? '').toString().trim().toLowerCase();
        if (err == 'already_assigned') {
          _notifyRealtimeEvent(
            'Request already accepted by rescuer. Assignment was not changed.',
            color: Colors.orange.shade800,
          );
          if (mounted) {
            setState(() {
              _queueNoticeByIncidentId[incidentId] =
                  'A rescuer already accepted this request.';
              _expandedIncidentId = null;
              _selectedRescuerIdForExpandedIncident = null;
            });
          }
          await _loadIncidents();
          return;
        }
        if (err == 'rescuer_busy') {
          _notifyRealtimeEvent(
            '${_rescuerNameById(rescuerId)} already has an active SOS.',
            color: Colors.orange.shade800,
          );
          return;
        }
        if (err == 'dispatch_closed') {
          _notifyRealtimeEvent(
            'This request is already closed.',
            color: Colors.orange.shade800,
          );
          await _loadIncidents();
          return;
        }
        _notifyRealtimeEvent(
          'Failed to assign rescuer: ${err.isEmpty ? 'unknown error' : err}',
          color: Colors.red,
        );
        return;
      }

      setState(() {
        _queueNoticeByIncidentId[incidentId] =
            'Admin assigned ${_rescuerNameById(rescuerId)}.';
        _expandedIncidentId = null;
        _selectedRescuerIdForExpandedIncident = null;
      });

      final inc = _incidents.where((i) => i.id == incidentId).firstOrNull;
      if (inc != null) {
        _mapController.move(LatLng(inc.latitude, inc.longitude), 14.0);
      }

      if (mounted) {
        _notifyRealtimeEvent('Rescuer dispatched successfully',
            color: Colors.green);
      }

      await _loadAll();
    } catch (e) {
      if (mounted) {
        _notifyRealtimeEvent('Failed to assign rescuer: $e', color: Colors.red);
      }
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  Future<void> _confirmAndCancelSos(SosDispatch inc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel SOS report?'),
        content: Text(
          'Are you sure you want to cancel ${inc.ticketNumber}? '
          'It will be closed and appear in SOS History as cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _cancellingIncidentId = inc.id);
    try {
      final rpcRes = await _supabase.rpc(
        'admin_cancel_sos_dispatch',
        params: {'p_dispatch_id': inc.id},
      );
      final map = rpcRes is Map
          ? Map<String, dynamic>.from(rpcRes)
          : <String, dynamic>{};
      final ok = map['ok'] == true;
      if (!ok) {
        final err = (map['error'] ?? '').toString().trim().toLowerCase();
        if (err == 'dispatch_already_closed') {
          _notifyRealtimeEvent(
            'This request is already closed.',
            color: Colors.orange.shade800,
          );
        } else if (err == 'forbidden' || err == 'not_authenticated') {
          _notifyRealtimeEvent(
            'You are not allowed to cancel this request.',
            color: Colors.red,
          );
        } else {
          _notifyRealtimeEvent(
            'Could not cancel: ${err.isEmpty ? 'unknown error' : err}',
            color: Colors.red,
          );
        }
        await _loadIncidents();
        return;
      }
      if (mounted) {
        setState(() {
          _expandedIncidentId = null;
          _selectedRescuerIdForExpandedIncident = null;
          _queueNoticeByIncidentId.remove(inc.id);
        });
        _notifyRealtimeEvent(
          '${inc.ticketNumber} closed (cancelled).',
          color: Colors.deepOrange.shade700,
        );
      }
      await _loadAll();
    } catch (e) {
      if (mounted) {
        _notifyRealtimeEvent('Failed to cancel: $e', color: Colors.red);
      }
    } finally {
      if (mounted) setState(() => _cancellingIncidentId = null);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  String _rescuerNameById(String? rescuerId) {
    if (rescuerId == null) return 'rescuer';
    final match = _rescuers.where((r) => r.id == rescuerId).firstOrNull;
    return match?.displayName ?? 'rescuer';
  }

  double? _distanceKmToIncident(SosDispatch incident, RescuerProfile rescuer) {
    if (rescuer.lastLatitude == null || rescuer.lastLongitude == null) {
      return null;
    }
    return _distance.as(
      LengthUnit.Kilometer,
      LatLng(incident.latitude, incident.longitude),
      LatLng(rescuer.lastLatitude!, rescuer.lastLongitude!),
    );
  }

  Duration? _etaFromDistanceKm(double? distanceKm) {
    if (distanceKm == null) return null;
    final minutes = math.max(1, (distanceKm / 28.0 * 60).round());
    return Duration(minutes: minutes);
  }

  _RescuerSearchResult _rescuersForIncidentDispatch(SosDispatch incident) {
    final available = _rescuers.where((r) =>
        r.isOnDuty &&
        !_rescuerIsOnMission(r.id) &&
        r.lastLatitude != null &&
        r.lastLongitude != null);

    final candidates = available
        .map((r) => _RescuerCandidate(
              rescuer: r,
              distanceKm: _distanceKmToIncident(incident, r)!,
            ))
        .toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

    if (candidates.isEmpty) {
      return const _RescuerSearchResult(
        candidates: [],
        radiusKmUsed: 10,
        expandedFrom10km: false,
      );
    }

    var radius = 10.0;
    while (radius <= 50.0) {
      final within = candidates.where((c) => c.distanceKm <= radius).toList();
      if (within.isNotEmpty) {
        return _RescuerSearchResult(
          candidates: within,
          radiusKmUsed: radius,
          expandedFrom10km: radius > 10.0,
        );
      }
      radius += 5.0;
    }

    return _RescuerSearchResult(
      candidates: candidates,
      radiusKmUsed: candidates.last.distanceKm,
      expandedFrom10km: true,
    );
  }

  String _formatEta(Duration eta) {
    final h = eta.inHours;
    final m = eta.inMinutes.remainder(60);
    if (h <= 0) return '$m min';
    if (m == 0) return '$h hr';
    return '$h hr $m min';
  }

  void _notifyRealtimeEvent(String message, {Color color = Colors.blueGrey}) {
    if (!mounted) return;
    if (widget.settings?.soundAlerts ?? true) {
      SystemSound.play(SystemSoundType.alert);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _emitQueueWorkflowUpdates(
    Map<String, SosDispatch> previousById,
    List<SosDispatch> nextList,
  ) {
    for (final next in nextList) {
      final prev = previousById[next.id];
      if (prev == null) continue;

      final statusChanged = prev.status != next.status;
      final assignmentChanged = prev.assignedRescuerId != next.assignedRescuerId;
      if (!statusChanged && !assignmentChanged) continue;

      if (assignmentChanged &&
          prev.assignedRescuerId != null &&
          next.assignedRescuerId == null &&
          (next.status == 'submitted' || next.status == 'received')) {
        final notice = '${_rescuerNameById(prev.assignedRescuerId)} declined the request.';
        setState(() => _queueNoticeByIncidentId[next.id] = notice);
        _notifyRealtimeEvent(notice, color: Colors.orange.shade800);
      }

      if (assignmentChanged &&
          prev.assignedRescuerId == null &&
          next.assignedRescuerId != null) {
        final notice = '${_rescuerNameById(next.assignedRescuerId)} accepted ${next.ticketNumber}.';
        setState(() => _queueNoticeByIncidentId[next.id] = notice);
        _notifyRealtimeEvent(notice, color: Colors.blue.shade700);
      }

      if (statusChanged) {
        final phase = _formatSosDispatchStatusForBadge(next.status);
        if (next.status == 'en_route') {
          final notice = '${_rescuerNameById(next.assignedRescuerId)} is en route.';
          setState(() => _queueNoticeByIncidentId[next.id] = notice);
          _notifyRealtimeEvent('$phase: ${next.ticketNumber}', color: Colors.teal);
        } else if (next.status == 'closed') {
          setState(() => _queueNoticeByIncidentId.remove(next.id));
          if (next.adminCancelled) {
            _notifyRealtimeEvent(
              '${next.ticketNumber} closed (cancelled by admin).',
              color: Colors.deepOrange.shade700,
            );
          } else {
            _notifyRealtimeEvent('${next.ticketNumber} is now closed.',
                color: Colors.green.shade700);
          }
        } else {
          _notifyRealtimeEvent(
            '${next.ticketNumber} status updated to $phase',
            color: Colors.blueGrey,
          );
        }
      }
    }
  }

  List<Polyline> _activeMissionsPolylines() {
    final polylines = <Polyline>[];
    for (final inc in _incidents) {
      if (!_isMissionStatus(inc.status)) continue;
      final rescuerId = inc.assignedRescuerId;
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
                      // SOS Reports
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
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          _SosTabButton(
                                            label: 'SOS Reports',
                                            selected: !_showSosHistory,
                                            onTap: () => setState(
                                                () => _showSosHistory = false),
                                          ),
                                          _SosTabButton(
                                            label: 'SOS History',
                                            selected: _showSosHistory,
                                            onTap: () => setState(
                                                () => _showSosHistory = true),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _showSosHistory
                                            ? Colors.blueGrey.withValues(alpha: 0.10)
                                            : Colors.redAccent.withValues(alpha: 0.10),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        _showSosHistory
                                            ? '${_incidentHistory.length} total'
                                            : '${_incidents.length} active',
                                        style: TextStyle(
                                          color: _showSosHistory
                                              ? Colors.blueGrey
                                              : Colors.redAccent,
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
                                child: _showSosHistory
                                    ? _buildSosHistoryList()
                                    : _incidents.isEmpty
                                        ? const Center(
                                        child: Text(
                                          'No active SOS reports',
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
                                              inc.assignedRescuerId;
                                          final assignedRescuer = _rescuers
                                              .where((r) =>
                                                  r.id == assignedRescuerId)
                                              .firstOrNull;
                                          final assignedDistanceKm =
                                              assignedRescuer == null
                                                  ? null
                                                  : _distanceKmToIncident(
                                                      inc, assignedRescuer);
                                          final eta = _etaFromDistanceKm(
                                              assignedDistanceKm);
                                          final rescuerSearch =
                                              _rescuersForIncidentDispatch(inc);
                                          final isExpanded =
                                              _expandedIncidentId == inc.id;
                                          return _IncidentCard(
                                            incident: inc,
                                            assignedRescuerId:
                                                assignedRescuerId,
                                            assignedRescuerName:
                                                assignedRescuer?.displayName,
                                            assignedDistanceKm:
                                                assignedDistanceKm,
                                            assignedEtaLabel:
                                                eta == null ? null : _formatEta(eta),
                                            workflowNotice:
                                                _queueNoticeByIncidentId[inc.id],
                                            isExpanded: isExpanded,
                                            rescuers: rescuerSearch.candidates,
                                            expandedSearchRadiusKm:
                                                rescuerSearch.expandedFrom10km
                                                    ? rescuerSearch.radiusKmUsed
                                                    : null,
                                            selectedRescuerId: isExpanded
                                                ? _selectedRescuerIdForExpandedIncident
                                                : null,
                                            assigning: _assigning &&
                                                _expandedIncidentId == inc.id,
                                            onDispatchToggle: () {
                                              final options =
                                                  _rescuersForIncidentDispatch(
                                                      inc);
                                              setState(() {
                                                _expandedIncidentId = inc.id;
                                                _selectedRescuerIdForExpandedIncident =
                                                    options.candidates
                                                        .firstOrNull
                                                        ?.rescuer
                                                        .id;
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
                                            onCancel: () =>
                                                _confirmAndCancelSos(inc),
                                            cancelling:
                                                _cancellingIncidentId == inc.id,
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
                                                _rescuerIsOnMission(r.id);
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

  Widget _buildSosHistoryList() {
    if (_incidentHistory.isEmpty) {
      return const Center(
        child: Text(
          'No SOS history yet',
          style: TextStyle(color: Colors.blueGrey),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _incidentHistory.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final incident = _incidentHistory[index];
        final rescuer = _rescuers
            .where((r) => r.id == incident.assignedRescuerId)
            .firstOrNull;
        final statusBadge = _sosHistoryStatusBadgeText(incident);
        final st = incident.status.trim().toLowerCase();
        final cancelled = st == 'closed' && incident.adminCancelled;
        final Color pillBg;
        final Color pillFg;
        if (cancelled) {
          pillBg = Colors.deepOrange.withValues(alpha: 0.12);
          pillFg = Colors.deepOrange.shade800;
        } else if (st == 'closed') {
          pillBg = Colors.green.withValues(alpha: 0.12);
          pillFg = Colors.green.shade700;
        } else {
          pillBg = Colors.orange.withValues(alpha: 0.12);
          pillFg = Colors.orange.shade800;
        }
        final closedAt = incident.closedAt ??
            (st == 'closed' ? incident.updatedAt : null);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      incident.ticketNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: pillBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusBadge,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: pillFg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Rescuer: ${rescuer?.displayName ?? 'Unassigned'}',
                style: TextStyle(
                  color: Colors.blueGrey.shade800,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Opened: ${_formatDateTime(incident.submittedAt)}',
                style: TextStyle(
                  color: Colors.blueGrey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Closed: ${closedAt != null ? _formatDateTime(closedAt) : '—'}',
                style: TextStyle(
                  color: Colors.blueGrey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Badge text: first letter of each word capitalized (handles `en_route` → "En Route").
String _formatSosDispatchStatusForBadge(String? raw) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return '—';
  return s
      .split(RegExp(r'[\s_]+'))
      .where((w) => w.isNotEmpty)
      .map((w) {
        final lower = w.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}

/// History pill: distinguish admin-cancelled closures from normal closed.
String _sosHistoryStatusBadgeText(SosDispatch inc) {
  final st = inc.status.trim().toLowerCase();
  if (st == 'closed' && inc.adminCancelled) {
    return 'Closed (Cancelled)';
  }
  return _formatSosDispatchStatusForBadge(inc.status);
}

class _SosPinHeaderIcon extends StatelessWidget {
  const _SosPinHeaderIcon();

  @override
  Widget build(BuildContext context) {
    const double pinSize = 22;
    return SizedBox(
      width: pinSize,
      height: pinSize + 2,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.location_on,
            size: 24,
            color: Colors.red.shade700,
          ),
          Positioned(
            top: 1,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.shade700,
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              alignment: Alignment.center,
              child: const Text(
                'SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 5.5,
                  height: 1,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SosTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SosTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: Colors.black.withValues(alpha: 0.08))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: selected ? Colors.black87 : Colors.blueGrey,
          ),
        ),
      ),
    );
  }
}

// ─── Incident Card ────────────────────────────────────────────────────────────

class _IncidentCard extends StatelessWidget {
  final SosDispatch incident;
  final String? assignedRescuerId;
  final String? assignedRescuerName;
  final double? assignedDistanceKm;
  final String? assignedEtaLabel;
  final String? workflowNotice;
  final bool isExpanded;
  final List<_RescuerCandidate> rescuers;
  final double? expandedSearchRadiusKm;
  final String? selectedRescuerId;
  final bool assigning;
  final VoidCallback onDispatchToggle;
  final ValueChanged<String?> onRescuerSelected;
  final VoidCallback onAssign;
  final VoidCallback onLocate;
  final VoidCallback onCancel;
  final bool cancelling;
  final String Function(DateTime) formatDateTime;

  const _IncidentCard({
    required this.incident,
    required this.assignedRescuerId,
    required this.assignedRescuerName,
    required this.assignedDistanceKm,
    required this.assignedEtaLabel,
    required this.workflowNotice,
    required this.isExpanded,
    required this.rescuers,
    required this.expandedSearchRadiusKm,
    required this.selectedRescuerId,
    required this.assigning,
    required this.onDispatchToggle,
    required this.onRescuerSelected,
    required this.onAssign,
    required this.onLocate,
    required this.onCancel,
    required this.cancelling,
    required this.formatDateTime,
  });

  @override
  Widget build(BuildContext context) {
    final isAssigned = assignedRescuerId != null;
    final uniqueRescuersById = <String, _RescuerCandidate>{};
    for (final candidate in rescuers) {
      uniqueRescuersById.putIfAbsent(candidate.rescuer.id, () => candidate);
    }
    final uniqueRescuers = uniqueRescuersById.values.toList();
    final safeSelectedRescuerId =
        (selectedRescuerId != null &&
                uniqueRescuers.any((r) => r.rescuer.id == selectedRescuerId))
            ? selectedRescuerId
            : null;
    final phoneRaw = incident.callerPhone?.trim();
    final phoneDisplay =
        (phoneRaw != null && phoneRaw.isNotEmpty) ? phoneRaw : '—';

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
            Row(
              children: [
                const _SosPinHeaderIcon(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    incident.ticketNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAssigned
                        ? Colors.blue.withValues(alpha: 0.12)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatSosDispatchStatusForBadge(incident.status),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: isAssigned ? Colors.blue.shade700 : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              incident.displayName,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              phoneDisplay,
              style: TextStyle(
                color: Colors.blueGrey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              incident.emergencyTypeDisplay,
              style: TextStyle(
                color: Colors.blueGrey.shade800,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            Text(
              '${incident.latitude.toStringAsFixed(5)}, '
              '${incident.longitude.toStringAsFixed(5)}',
              style: TextStyle(
                color: Colors.blueGrey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (assignedRescuerName != null) ...[
              const SizedBox(height: 4),
              Text(
                'Assigned rescuer: $assignedRescuerName',
                style: TextStyle(
                  color: Colors.blueGrey.shade700,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
            if (isAssigned && incident.updatedAt != null) ...[
              const SizedBox(height: 2),
              Text(
                'Accepted: ${formatDateTime(incident.acceptedAt ?? incident.updatedAt!)}',
                style: TextStyle(
                  color: Colors.blueGrey.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
            if (isAssigned &&
                assignedDistanceKm != null &&
                assignedEtaLabel != null) ...[
              const SizedBox(height: 2),
              Text(
                'ETA: $assignedEtaLabel • ${assignedDistanceKm!.toStringAsFixed(1)} km',
                style: TextStyle(
                  color: Colors.blueGrey.shade700,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 12),

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
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (cancelling || (assigning && isExpanded))
                    ? null
                    : onCancel,
                icon: cancelling
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.red.shade700,
                        ),
                      )
                    : Icon(Icons.cancel_outlined,
                        size: 16, color: Colors.red.shade700),
                label: Text(
                  cancelling ? 'Cancelling…' : 'Cancel',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.red.shade700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            // ── Rescuer selector (expanded)
            if (isExpanded) ...[
              const SizedBox(height: 10),
              if (uniqueRescuers.isEmpty)
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
                if (expandedSearchRadiusKm != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.radar, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No rescuer within 10 km. Radius expanded to ${expandedSearchRadiusKm!.toStringAsFixed(0)} km.',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
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
                      key: ValueKey('${incident.id}:$safeSelectedRescuerId'),
                      value: safeSelectedRescuerId,
                      isExpanded: true,
                      isDense: true,
                      items: uniqueRescuers
                          .map((r) => DropdownMenuItem(
                                value: r.rescuer.id,
                                child: Text(
                                    '${r.rescuer.displayName} • ${r.distanceKm.toStringAsFixed(1)} km',
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
            if (workflowNotice != null && workflowNotice!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  workflowNotice!,
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
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

class _RescuerCandidate {
  final RescuerProfile rescuer;
  final double distanceKm;
  const _RescuerCandidate({
    required this.rescuer,
    required this.distanceKm,
  });
}

class _RescuerSearchResult {
  final List<_RescuerCandidate> candidates;
  final double radiusKmUsed;
  final bool expandedFrom10km;
  const _RescuerSearchResult({
    required this.candidates,
    required this.radiusKmUsed,
    required this.expandedFrom10km,
  });
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