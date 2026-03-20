import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'settings_page.dart';

// Alert & Notification page:
// combines manual alerts with auto-generated (simulated) alerts.
enum AlertSeverity { critical, warning, advisory }
enum AlertSource { sensorAuto, manual }

class SmartHubAlert {
  final String id;
  final String locationKey; // internal key for matching sensors
  final String locationLabel; // display label
  final LatLng center;
  final double radiusKm;
  final String message;
  final DateTime createdAt;
  final AlertSeverity severity;
  final AlertSource source;

  const SmartHubAlert({
    required this.id,
    required this.locationKey,
    required this.locationLabel,
    required this.center,
    required this.radiusKm,
    required this.message,
    required this.createdAt,
    required this.severity,
    required this.source,
  });
}

class SmartHubThresholds {
  final double criticalCm;
  final double warningCm;

  const SmartHubThresholds({required this.criticalCm, required this.warningCm});
}

class SmartHubAlertsPage extends StatefulWidget {
  final AppSettingsController settings;
  const SmartHubAlertsPage({super.key, required this.settings});

  @override
  State<SmartHubAlertsPage> createState() => _SmartHubAlertsPageState();
}

class _SmartHubAlertsPageState extends State<SmartHubAlertsPage> {
  final MapController _mapController = MapController();

  // Fixed 3 sites (as requested).
  static const _sites = [
    _Site(
      key: 'linao_talisay',
      label: 'Linao Talisay',
      center: LatLng(10.26, 123.82),
    ),
    _Site(
      key: 'tabunok_talisay',
      label: 'Tabunok Talisay',
      center: LatLng(10.26, 123.84),
    ),
    _Site(
      key: 'bulacao',
      label: 'Bulacao',
      center: LatLng(10.27, 123.85),
    ),
  ];

  Timer? _dummyTimer;
  late math.Random _rng;
  late Map<String, double> _dummyWaterCmByLocationKey;

  final List<SmartHubAlert> _activeAlerts = [];
  final Map<String, String> _autoAlertIdByLocationKey = {};
  final Map<String, AlertSeverity> _dismissedAutoSeverityByLocationKey = {};

  SmartHubThresholds _thresholds = const SmartHubThresholds(criticalCm: 40, warningCm: 15);

  bool _hasReceivedSensorData = false;

  // Manual creator form state.
  String _manualLocationKey = _sites[0].key;
  final TextEditingController _manualMessageCtrl = TextEditingController();
  final TextEditingController _manualRadiusCtrl = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();

    // Dummy water-level generator (since sensors are not integrated yet).
    _rng = math.Random();
    _dummyWaterCmByLocationKey = {
      for (final s in _sites) s.key: 8 + _rng.nextDouble() * 22,
    };

    widget.settings.addListener(_onSettingsChanged);
    _startDummyTimer();
  }

  void _startDummyTimer() {
    _dummyTimer?.cancel();
    final seconds = _effectiveIntervalSeconds(widget.settings.fetchIntervalSeconds);
    _dummyTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      _hasReceivedSensorData = true;

      final updated = <String, double>{};
      for (final site in _sites) {
        final current = _dummyWaterCmByLocationKey[site.key] ?? 0;
        // Random walk: +/- up to ~5cm per tick.
        final delta = (_rng.nextDouble() * 10.0) - 5.0;
        final next = (current + delta).clamp(0.0, 60.0);
        updated[site.key] = next;
      }

      _dummyWaterCmByLocationKey = updated;
      _syncAutoAlertsFromWaterLevels(updated);
    });
  }

  void _onSettingsChanged() {
    final active = _dummyTimer?.isActive ?? false;
    if (!active) {
      _startDummyTimer();
      return;
    }

    // Restart timer when fetch interval changes.
    // We use runtimeType+periodic rebuild approach by simply restarting each settings update;
    // settings writes are debounced, so this won't thrash.
    _startDummyTimer();
  }

  int _effectiveIntervalSeconds(int value) {
    // Keep simulation practical while still honoring settings buckets.
    // 30s / 60s / 300s are expected values.
    if (value <= 30) return 30;
    if (value <= 60) return 60;
    return 300;
  }

  @override
  void dispose() {
    _dummyTimer?.cancel();
    widget.settings.removeListener(_onSettingsChanged);
    _manualMessageCtrl.dispose();
    _manualRadiusCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _activeAlerts.length;
    final systemHealth = _computeSystemHealth(_activeAlerts);
    final scheme = Theme.of(context).colorScheme;

    final criticalCount = _activeAlerts.where((a) => a.severity == AlertSeverity.critical).length;
    final warningCount = _activeAlerts.where((a) => a.severity == AlertSeverity.warning).length;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _Header(
            title: 'Alert & Notification',
            subtitle: 'Create and manage flood alerts and notifications',
            rightStats: [
              _SmallStat(
                icon: Icons.notifications_active_outlined,
                label: 'Active Alerts',
                value: '$activeCount',
                color: scheme.primary,
              ),
              _SmallStat(
                icon: Icons.monitor_heart,
                label: 'System Health',
                value: systemHealth.label,
                color: systemHealth.color,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _ActiveAlertsList(
                    alerts: _activeAlerts.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
                    hasReceivedSensorData: _hasReceivedSensorData,
                    onFocusAlert: (alert) => _mapController.move(alert.center, 14.5),
                    onDismiss: (alert) => _dismissAlert(alert),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      Expanded(
                        flex: 5,
                        child: _MapWithAlertZones(
                          alerts: _activeAlerts,
                          mapController: _mapController,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        flex: 2,
                        child: _ManualCreatorCard(
                          manualLocationKey: _manualLocationKey,
                          onLocationKeyChanged: (v) => setState(() => _manualLocationKey = v),
                          messageCtrl: _manualMessageCtrl,
                          radiusCtrl: _manualRadiusCtrl,
                          onCreate: () => _createManualAlert(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        flex: 2,
                        child: _AutoTriggerSettingsCard(
                          thresholds: _thresholds,
                          criticalCount: criticalCount,
                          warningCount: warningCount,
                          onChanged: (t) => setState(() => _thresholds = t),
                        ),
                      ),
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

  void _createManualAlert() {
    final site = _sites.firstWhere((s) => s.key == _manualLocationKey);
    final msg = _manualMessageCtrl.text.trim();
    final radiusKm = double.tryParse(_manualRadiusCtrl.text.trim()) ?? 1;
    if (msg.isEmpty) return;
    if (radiusKm <= 0) return;

    final now = DateTime.now();
    final alert = SmartHubAlert(
      id: 'MAN-${now.millisecondsSinceEpoch}',
      locationKey: site.key,
      locationLabel: site.label,
      center: site.center,
      radiusKm: radiusKm,
      message: msg,
      createdAt: now,
      severity: AlertSeverity.warning, // manual alerts default to warning (orange) for visibility
      source: AlertSource.manual,
    );

    setState(() {
      _activeAlerts.insert(0, alert);
    });

    _mapController.move(alert.center, 14.5);
  }

  void _dismissAlert(SmartHubAlert alert) {
    setState(() {
      _activeAlerts.removeWhere((a) => a.id == alert.id);
    });

    if (alert.source == AlertSource.sensorAuto) {
      _dismissedAutoSeverityByLocationKey[alert.locationKey] = alert.severity;
    }
  }

  void _syncAutoAlertsFromWaterLevels(Map<String, double> waterCmByLocationKey) {
    // Determine severity for each site and update corresponding auto alerts.
    final now = DateTime.now();
    bool changed = false;

    for (final site in _sites) {
      final cm = waterCmByLocationKey[site.key];
      final existingAutoId = _autoAlertIdByLocationKey[site.key];

      if (cm == null) {
        // If we cannot infer water level, remove auto alerts for that site.
        if (existingAutoId != null) {
          changed = true;
          _activeAlerts.removeWhere((a) => a.id == existingAutoId);
          _autoAlertIdByLocationKey.remove(site.key);
        }
        continue;
      }

      final newSeverity = _severityFromWaterCm(cm, _thresholds);
      final dismissedSeverity = _dismissedAutoSeverityByLocationKey[site.key];

      // If user dismissed this exact severity and it hasn't changed yet, keep it dismissed.
      if (dismissedSeverity != null && dismissedSeverity == newSeverity) {
        continue;
      }

      final newId = existingAutoId ?? 'AUTO-${site.key}';
      _autoAlertIdByLocationKey[site.key] = newId;

      final existingIdx = _activeAlerts.indexWhere((a) => a.id == newId);
      if (existingIdx == -1) {
        changed = true;
        _activeAlerts.add(
          SmartHubAlert(
            id: newId,
            locationKey: site.key,
            locationLabel: site.label,
            center: site.center,
            radiusKm: _defaultRadiusForSeverity(newSeverity),
            message: 'System-Generated: ${_severityToLabel(newSeverity)} flood detected at ${cm.toStringAsFixed(0)}cm',
            createdAt: now,
            severity: newSeverity,
            source: AlertSource.sensorAuto,
          ),
        );
      } else {
        // Update message/severity/radius if needed.
        final current = _activeAlerts[existingIdx];
        final nextMsg =
            'System-Generated: ${_severityToLabel(newSeverity)} flood detected at ${cm.toStringAsFixed(0)}cm';

        if (current.severity != newSeverity || current.message != nextMsg) {
          changed = true;
          _activeAlerts[existingIdx] = SmartHubAlert(
            id: current.id,
            locationKey: current.locationKey,
            locationLabel: current.locationLabel,
            center: current.center,
            radiusKm: _defaultRadiusForSeverity(newSeverity),
            message: nextMsg,
            createdAt: now,
            severity: newSeverity,
            source: current.source,
          );
        }
      }
    }

    // Clear suppression once severity differs (so dismissed alerts can come back).
    for (final site in _sites) {
      final dismissed = _dismissedAutoSeverityByLocationKey[site.key];
      if (dismissed == null) continue;

      final cm = waterCmByLocationKey[site.key];
      if (cm == null) continue;

      final nextSeverity = _severityFromWaterCm(cm, _thresholds);
      if (nextSeverity != dismissed) {
        _dismissedAutoSeverityByLocationKey.remove(site.key);
      }
    }

    if (!changed) return;
    if (!mounted) return;
    setState(() {});
  }

  AlertSeverity _severityFromWaterCm(double cm, SmartHubThresholds t) {
    if (cm >= t.criticalCm) return AlertSeverity.critical;
    if (cm >= t.warningCm) return AlertSeverity.warning;
    return AlertSeverity.advisory;
  }

  String _severityToLabel(AlertSeverity s) {
    return switch (s) {
      AlertSeverity.critical => 'Critical',
      AlertSeverity.warning => 'Warning',
      AlertSeverity.advisory => 'Advisory',
    };
  }

  double _defaultRadiusForSeverity(AlertSeverity s) {
    return switch (s) {
      AlertSeverity.critical => 2.5,
      AlertSeverity.warning => 1.5,
      AlertSeverity.advisory => 1.0,
    };
  }

  _SystemHealth _computeSystemHealth(List<SmartHubAlert> alerts) {
    final critical = alerts.where((a) => a.severity == AlertSeverity.critical).length;
    final warning = alerts.where((a) => a.severity == AlertSeverity.warning).length;

    if (critical > 0) return const _SystemHealth(label: 'Impassable', color: Colors.redAccent);
    if (warning > 0) return const _SystemHealth(label: 'Advisory', color: Colors.orange);
    return const _SystemHealth(label: 'Normal Operation', color: Colors.green);
  }
}

class _Site {
  final String key;
  final String label;
  final LatLng center;

  const _Site({required this.key, required this.label, required this.center});
}

class _SystemHealth {
  final String label;
  final Color color;

  const _SystemHealth({required this.label, required this.color});
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_SmallStat> rightStats;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.rightStats,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.notifications_active_outlined, color: Colors.orange),
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
        const SizedBox(width: 16),
        Row(
          children: rightStats
              .map(
                (s) => Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: s,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _SmallStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SmallStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.withValues(alpha: 0.95)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: color)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              ],
            ),
          ),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: child,
    );
  }
}

class _ActiveAlertsList extends StatelessWidget {
  final List<SmartHubAlert> alerts;
  final bool hasReceivedSensorData;
  final ValueChanged<SmartHubAlert> onFocusAlert;
  final ValueChanged<SmartHubAlert> onDismiss;

  const _ActiveAlertsList({
    required this.alerts,
    required this.hasReceivedSensorData,
    required this.onFocusAlert,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(
              children: [
                Icon(Icons.list_alt_outlined, color: Colors.blueGrey),
                SizedBox(width: 10),
                Text('Active Alerts', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: alerts.isEmpty
                ? Center(
                    child: Text(
                      hasReceivedSensorData ? 'No active alerts.' : 'Waiting for sensor data...',
                      style: TextStyle(color: Colors.blueGrey.shade600, fontWeight: FontWeight.w700),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: alerts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      return _AlertListItem(
                        alert: alerts[i],
                        onFocus: () => onFocusAlert(alerts[i]),
                        onDismiss: () => onDismiss(alerts[i]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AlertListItem extends StatelessWidget {
  final SmartHubAlert alert;
  final VoidCallback onFocus;
  final VoidCallback onDismiss;

  const _AlertListItem({
    required this.alert,
    required this.onFocus,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (alert.severity) {
      AlertSeverity.critical => Colors.redAccent,
      AlertSeverity.warning => Colors.orange,
      AlertSeverity.advisory => Colors.blue,
    };

    final sourceBg = alert.source == AlertSource.sensorAuto ? Colors.blueGrey.withValues(alpha: 0.10) : Colors.green.withValues(alpha: 0.10);
    final sourceColor = alert.source == AlertSource.sensorAuto ? Colors.blueGrey : Colors.green;
    final sourceLabel = alert.source == AlertSource.sensorAuto ? 'Sensor-Auto' : 'Manual';

    final ts = '${alert.createdAt.year}-${alert.createdAt.month.toString().padLeft(2, '0')}-${alert.createdAt.day.toString().padLeft(2, '0')} '
        '${alert.createdAt.hour.toString().padLeft(2, '0')}:${alert.createdAt.minute.toString().padLeft(2, '0')}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onFocus,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 110,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: sourceBg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: sourceColor.withValues(alpha: 0.22)),
                          ),
                          child: Text(
                            sourceLabel,
                            style: TextStyle(color: sourceColor, fontWeight: FontWeight.w900, fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            switch (alert.severity) {
                              AlertSeverity.critical => 'Critical',
                              AlertSeverity.warning => 'Warning',
                              AlertSeverity.advisory => 'Advisory',
                            },
                            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Dismiss',
                          onPressed: onDismiss,
                          icon: const Icon(Icons.close_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      alert.locationLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      alert.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.blueGrey.shade700, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ts,
                      style: TextStyle(color: Colors.blueGrey.shade600, fontWeight: FontWeight.w800, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapWithAlertZones extends StatelessWidget {
  final List<SmartHubAlert> alerts;
  final MapController mapController;

  const _MapWithAlertZones({required this.alerts, required this.mapController});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          mapController: mapController,
          options: const MapOptions(
            initialCenter: LatLng(10.26, 123.84),
            initialZoom: 12.8,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'the_basics',
            ),
            CircleLayer(
              circles: alerts.map((a) {
                final color = switch (a.severity) {
                  AlertSeverity.critical => Colors.redAccent,
                  AlertSeverity.warning => Colors.orange,
                  AlertSeverity.advisory => Colors.blue,
                };
                return CircleMarker(
                  point: a.center,
                  radius: a.radiusKm * 1000,
                  useRadiusInMeter: true,
                  color: color.withValues(alpha: 0.18),
                  borderColor: color,
                  borderStrokeWidth: 2,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualCreatorCard extends StatelessWidget {
  final String manualLocationKey;
  final ValueChanged<String> onLocationKeyChanged;
  final TextEditingController messageCtrl;
  final TextEditingController radiusCtrl;
  final VoidCallback onCreate;

  const _ManualCreatorCard({
    required this.manualLocationKey,
    required this.onLocationKeyChanged,
    required this.messageCtrl,
    required this.radiusCtrl,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final locations = const <MapEntry<String, String>>[
      MapEntry('linao_talisay', 'Linao Talisay'),
      MapEntry('tabunok_talisay', 'Tabunok Talisay'),
      MapEntry('bulacao', 'Bulacao'),
    ];

    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Manual Creator', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(height: 10),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Location',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: manualLocationKey,
                    isExpanded: true,
                    items: locations
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => onLocationKeyChanged(v ?? locations.first.key),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: messageCtrl,
                decoration: InputDecoration(
                  labelText: 'Message',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: radiusCtrl,
                      decoration: InputDecoration(
                        labelText: 'Radius (km)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 42,
                    child: ElevatedButton(
                      onPressed: onCreate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD18A2B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Create alert', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoTriggerSettingsCard extends StatelessWidget {
  final SmartHubThresholds thresholds;
  final int criticalCount;
  final int warningCount;
  final ValueChanged<SmartHubThresholds> onChanged;

  const _AutoTriggerSettingsCard({
    required this.thresholds,
    required this.criticalCount,
    required this.warningCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final criticalCtrl = TextEditingController(text: thresholds.criticalCm.toStringAsFixed(0));
    final warningCtrl = TextEditingController(text: thresholds.warningCm.toStringAsFixed(0));

    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Auto-Trigger Config', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(height: 8),
              Text(
                'If Sensor JSN-SR04T > critical threshold, create Red System-Generated alerts instantly.',
                style: TextStyle(color: Colors.blueGrey.shade700, fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: criticalCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Critical threshold (cm)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                      onSubmitted: (_) {
                        final c = double.tryParse(criticalCtrl.text.trim()) ?? thresholds.criticalCm;
                        final w = double.tryParse(warningCtrl.text.trim()) ?? thresholds.warningCm;
                        onChanged(SmartHubThresholds(criticalCm: c, warningCm: w));
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: warningCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Warning threshold (cm)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                      onSubmitted: (_) {
                        final w = double.tryParse(warningCtrl.text.trim()) ?? thresholds.warningCm;
                        final c = double.tryParse(criticalCtrl.text.trim()) ?? thresholds.criticalCm;
                        onChanged(SmartHubThresholds(criticalCm: c, warningCm: w));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Current: $criticalCount Critical • $warningCount Warning',
                style: TextStyle(color: Colors.blueGrey.shade600, fontWeight: FontWeight.w800, fontSize: 11),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

