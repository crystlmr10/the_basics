import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- DATABASE MODEL ---
class HistoricalLogRow {
  final String id;
  final DateTime ts;
  final String location;
  final double waterLevelCm;

  const HistoricalLogRow({
    required this.id,
    required this.ts,
    required this.location,
    required this.waterLevelCm,
  });

  factory HistoricalLogRow.fromMap(Map<String, dynamic> map) {
    return HistoricalLogRow(
      id: map['id']?.toString() ?? '',
      ts: DateTime.tryParse(map['recorded_at'] ?? '') ?? DateTime.now(),
      location: map['location_name'] ?? 'Unknown Location',
      waterLevelCm: (map['water_level_cm'] as num? ?? 0.0).toDouble(),
    );
  }
}

enum FloodLabel { normal, lowFlood, deepFlood }

class HistoricalLogsPage extends StatefulWidget {
  const HistoricalLogsPage({super.key});

  @override
  State<HistoricalLogsPage> createState() => _HistoricalLogsPageState();
}

class _HistoricalLogsPageState extends State<HistoricalLogsPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  late final Stream<List<HistoricalLogRow>> _logsStream;

  DateTimeRange? _range;
  String _locationFilter = 'All';
  String _chartLocation = 'Tabunok, Talisay';

  @override
  void initState() {
    super.initState();
    // Initialize real-time Supabase stream
    _logsStream = Supabase.instance.client
        .from('sensor_logs')
        .stream(primaryKey: ['id'])
        .order('recorded_at')
        .map((data) => data.map((map) => HistoricalLogRow.fromMap(map)).toList());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _locations => const [
        'All',
        'Tabunok, Talisay',
        'Linao, Talisay',
        'Bulacao Pardo',
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 1350;

    return StreamBuilder<List<HistoricalLogRow>>(
      stream: _logsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Use mock curve data only if database is empty for visual testing
        final allData = (snapshot.data == null || snapshot.data!.isEmpty)
            ? _seedCurvedMockData()
            : snapshot.data!;

        final filtered = _applyFilters(allData);
        final chartRows = filtered.where((r) => r.location == _chartLocation).toList()
          ..sort((a, b) => a.ts.compareTo(b.ts));

        return Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. TOP SECTION: FILTERS
                _FiltersCard(
                  locations: _locations,
                  selectedLocation: _locationFilter,
                  onLocationChanged: (v) => setState(() => _locationFilter = v),
                  range: _range,
                  onPickRange: _pickRange,
                  searchCtrl: _searchCtrl,
                  onSearchChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),

                // 2. MIDDLE SECTION: Side-by-side (Table | Sidebar)
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: _TableCard(rows: filtered),
                      ),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 360,
                        child: _RecentEventsSidebar(rows: filtered),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      _TableCard(rows: filtered),
                      const SizedBox(height: 24),
                      _RecentEventsSidebar(rows: filtered),
                    ],
                  ),

                const SizedBox(height: 24),

                // 3. BOTTOM SECTION: ANALYTICS CHART (Full Width)
                SizedBox(
                  height: 450, // Specific height to handle hit-testing correctly
                  child: _TrendCard(
                    scheme: scheme,
                    chartLocations: _locations.where((l) => l != 'All').toList(),
                    chartLocation: _chartLocation,
                    onChartLocationChanged: (v) => setState(() => _chartLocation = v),
                    chartRows: chartRows,
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  List<HistoricalLogRow> _applyFilters(List<HistoricalLogRow> rows) {
    final q = _searchCtrl.text.trim().toLowerCase();
    return rows.where((row) {
      if (_locationFilter != 'All' && row.location != _locationFilter) return false;
      if (_range != null) {
        if (row.ts.isBefore(_range!.start) || row.ts.isAfter(_range!.end.add(const Duration(days: 1)))) return false;
      }
      if (q.isNotEmpty && !row.location.toLowerCase().contains(q)) return false;
      return true;
    }).toList()..sort((a, b) => b.ts.compareTo(a.ts));
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  static FloodLabel _labelFor(double cm) {
    if (cm < 15) return FloodLabel.normal;
    if (cm <= 30) return FloodLabel.lowFlood;
    return FloodLabel.deepFlood;
  }

  static String _formatTs(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  static List<HistoricalLogRow> _seedCurvedMockData() {
    final now = DateTime.now();
    final locations = <String>['Tabunok, Talisay', 'Linao, Talisay', 'Bulacao Pardo'];
    final rows = <HistoricalLogRow>[];
    for (final loc in locations) {
      final baseOffset = switch (loc) { 'Tabunok, Talisay' => 0.0, 'Linao, Talisay' => 5.0, _ => 10.0 };
      for (int i = 0; i < 24; i++) {
        final ts = now.subtract(Duration(hours: 23 - i));
        final angle = (i / 24.0) * 2 * pi;
        final cm = 15.0 + (10.0 * sin(angle - (pi / 2))) + baseOffset;
        rows.add(HistoricalLogRow(id: 'MOCK-$i', ts: ts, location: loc, waterLevelCm: cm.clamp(2.0, 45.0)));
      }
    }
    return rows;
  }
}

// --- DATA LOGS TABLE ---
class _TableCard extends StatefulWidget {
  final List<HistoricalLogRow> rows;
  const _TableCard({required this.rows});
  @override
  State<_TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<_TableCard> {
  int _rowsPerPage = PaginatedDataTable.defaultRowsPerPage;
  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.black.withValues(alpha: 0.06)),
          child: PaginatedDataTable(
            header: const Row(children: [Icon(Icons.table_chart_outlined, size: 18), SizedBox(width: 10), Text('Data Logs', style: TextStyle(fontWeight: FontWeight.w900))]),
            columns: const [
              DataColumn(label: Text('Time & Date')),
              DataColumn(label: Text('Location')),
              DataColumn(label: Text('Water Level (cm)')),
              DataColumn(label: Text('Flood Label'))
            ],
            source: _LogsTableSource(widget.rows),
            rowsPerPage: _rowsPerPage,
            onRowsPerPageChanged: (v) => setState(() => _rowsPerPage = v ?? 10),
            showFirstLastButtons: true,
          ),
        ),
      ),
    );
  }
}

// --- REFINED LINE GRAPH ANALYTICS ---
class _TrendCard extends StatelessWidget {
  final ColorScheme scheme;
  final List<String> chartLocations;
  final String chartLocation;
  final ValueChanged<String> onChartLocationChanged;
  final List<HistoricalLogRow> chartRows;

  const _TrendCard({required this.scheme, required this.chartLocations, required this.chartLocation, required this.onChartLocationChanged, required this.chartRows});

  @override
  Widget build(BuildContext context) {
    const Color primaryBlack = Color(0xFF1A1A1B);
    final spots = chartRows.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.waterLevelCm)).toList();
    final maxY = (chartRows.isEmpty ? 50.0 : chartRows.map((e) => e.waterLevelCm).reduce((a, b) => a > b ? a : b)) + 10;

    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(children: [
              const _CardTitle(icon: Icons.show_chart, title: 'Water Level Trend Analysis'),
              const Spacer(),
              _LocationDropdown(label: 'Select Location', value: chartLocation, locations: chartLocations, onChanged: onChartLocationChanged, compact: true)
            ]),
            const SizedBox(height: 32),
            Expanded(
              child: chartRows.isEmpty
                  ? const Center(child: Text('No historical data available for this selection.'))
                  : LineChart(LineChartData(
                      minY: 0,
                      maxY: maxY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        horizontalInterval: 10,
                        verticalInterval: 1,
                        getDrawingHorizontalLine: (value) => FlLine(color: Colors.black.withValues(alpha: 0.05), strokeWidth: 1),
                        getDrawingVerticalLine: (value) => FlLine(color: Colors.black.withValues(alpha: 0.05), strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: true, border: Border.all(color: Colors.black.withValues(alpha: 0.05))),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 45,
                            interval: 10,
                            getTitlesWidget: (v, meta) => Text('${v.toInt()}cm', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: (chartRows.length / 6).clamp(1, 999).toDouble(),
                            getTitlesWidget: (v, meta) {
                              final idx = v.round().clamp(0, chartRows.length - 1);
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text('${chartRows[idx].ts.hour}:00', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              );
                            },
                          ),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          isCurved: true,
                          curveSmoothness: 0.4,
                          spots: spots,
                          barWidth: 3.5,
                          color: primaryBlack,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [primaryBlack.withValues(alpha: 0.12), Colors.transparent],
                            ),
                          ),
                        )
                      ],
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          tooltipRoundedRadius: 8,
                          getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                            return LineTooltipItem('${s.y.toInt()} cm', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
                          }).toList(),
                        ),
                      ),
                    )),
            ),
          ],
        ),
      ),
    );
  }
}

// --- RECENT EVENTS SIDEBAR ---
class _RecentEventsSidebar extends StatelessWidget {
  final List<HistoricalLogRow> rows;
  const _RecentEventsSidebar({required this.rows});
  @override
  Widget build(BuildContext context) {
    final critical = rows.where((r) => _HistoricalLogsPageState._labelFor(r.waterLevelCm) == FloodLabel.deepFlood).take(8).toList();
    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _CardTitle(icon: Icons.notifications_active_outlined, title: 'Critical Logs'),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: critical.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('No danger levels detected.', style: TextStyle(color: Colors.grey, fontSize: 12))),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      itemCount: critical.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, i) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                          title: Text(critical[i].location, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          subtitle: Text('${critical[i].waterLevelCm.toInt()}cm at ${_HistoricalLogsPageState._formatTs(critical[i].ts)}', style: const TextStyle(fontSize: 11)),
                        );
                      }),
            ),
          ],
        ),
      ),
    );
  }
}

// --- HELPER COMPONENTS ---
class _LocationDropdown extends StatelessWidget {
  final String label, value;
  final List<String> locations;
  final ValueChanged<String> onChanged;
  final bool compact;
  const _LocationDropdown({required this.label, required this.value, required this.locations, required this.onChanged, this.compact = false});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 260,
      height: compact ? 44 : null,
      child: DropdownButtonFormField<String>(
          key: ValueKey(value),
          initialValue: value,
          items: locations.map((l) => DropdownMenuItem(value: l, child: Text(l, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => v != null ? onChanged(v) : null,
          decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true)));
}

class _LogsTableSource extends DataTableSource {
  final List<HistoricalLogRow> rows;
  _LogsTableSource(this.rows);
  @override
  DataRow? getRow(int index) {
    if (index >= rows.length) return null;
    final r = rows[index];
    return DataRow.byIndex(index: index, cells: [
      DataCell(Text(_HistoricalLogsPageState._formatTs(r.ts), style: const TextStyle(fontWeight: FontWeight.bold))),
      DataCell(Text(r.location)),
      DataCell(Text('${r.waterLevelCm.toInt()} cm', style: const TextStyle(fontWeight: FontWeight.bold))),
      DataCell(_FloodBadge(label: _HistoricalLogsPageState._labelFor(r.waterLevelCm)))
    ]);
  }
  @override bool get isRowCountApproximate => false;
  @override int get rowCount => rows.length;
  @override int get selectedRowCount => 0;
}

class _FloodBadge extends StatelessWidget {
  final FloodLabel label;
  const _FloodBadge({required this.label});
  @override
  Widget build(BuildContext context) {
    final (text, bg) = switch (label) {
      FloodLabel.normal => ('Normal', Colors.green),
      FloodLabel.lowFlood => ('Low Flood', Colors.orange),
      FloodLabel.deepFlood => ('Deep Flood', Colors.redAccent)
    };
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)));
  }
}

class _FiltersCard extends StatelessWidget {
  final List<String> locations;
  final String selectedLocation;
  final ValueChanged<String> onLocationChanged;
  final DateTimeRange? range;
  final VoidCallback onPickRange;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  const _FiltersCard({required this.locations, required this.selectedLocation, required this.onLocationChanged, required this.range, required this.onPickRange, required this.searchCtrl, required this.onSearchChanged});
  @override
  Widget build(BuildContext context) => _CardShell(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const _CardTitle(icon: Icons.filter_alt_outlined, title: 'Historical Filters'),
            _RangeButton(range: range, onPick: onPickRange),
            _LocationDropdown(label: 'Location', value: selectedLocation, locations: locations, onChanged: onLocationChanged),
            SizedBox(
                width: 320,
                child: TextField(
                    controller: searchCtrl,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                        hintText: 'Search timestamps...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true)))
          ])));
}

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 5))],
          border: Border.all(color: Colors.black.withValues(alpha: 0.06))),
      child: child);
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _CardTitle({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) =>
      Row(children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))]);
}

class _RangeButton extends StatelessWidget {
  final DateTimeRange? range;
  final VoidCallback onPick;
  const _RangeButton({required this.range, required this.onPick});
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: onPick,
      icon: const Icon(Icons.date_range),
      label: Text(range == null ? 'Select Time Range' : '${range!.start.month}/${range!.start.day} - ${range!.end.month}/${range!.end.day}'));
}