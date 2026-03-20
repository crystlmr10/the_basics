import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

// Historical logs page:
// filterable analytics + data table + recent-event feed.
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
}

enum FloodLabel { normal, lowFlood, deepFlood }

class HistoricalLogsPage extends StatefulWidget {
  const HistoricalLogsPage({super.key});

  @override
  State<HistoricalLogsPage> createState() => _HistoricalLogsPageState();
}

class _HistoricalLogsPageState extends State<HistoricalLogsPage> {
  // Mock data for immediate UI. Replace with API/Supabase later.
  late final List<HistoricalLogRow> _allRows = _seedMockData();

  final TextEditingController _searchCtrl = TextEditingController();

  DateTimeRange? _range;
  String _locationFilter = 'All';
  String _chartLocation = 'Tabunok, Talisay City';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _locations => const [
        'All',
        'Tabunok, Talisay City',
        'Linao, Talisay City',
        'Bulacao',
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 1200;

    final filtered = _filteredRows();
    final chartRows = filtered.where((r) => r.location == _chartLocation).toList()
      ..sort((a, b) => a.ts.compareTo(b.ts));

    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          _FiltersCard(
                            locations: _locations,
                            selectedLocation: _locationFilter,
                            onLocationChanged: (v) => setState(() => _locationFilter = v),
                            range: _range,
                            onPickRange: _pickRange,
                            searchCtrl: _searchCtrl,
                            onSearchChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _AnalyticsAndTable(
                              scheme: scheme,
                              chartLocations: _locations.where((l) => l != 'All').toList(),
                              chartLocation: _chartLocation,
                              onChartLocationChanged: (v) => setState(() => _chartLocation = v),
                              chartRows: chartRows,
                              tableRows: filtered,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 360,
                      child: _RecentEventsSidebar(rows: filtered),
                    ),
                  ],
                )
              : Column(
                  children: [
                    SingleChildScrollView(
                      child: Column(
                        children: [
                          _FiltersCard(
                            locations: _locations,
                            selectedLocation: _locationFilter,
                            onLocationChanged: (v) => setState(() => _locationFilter = v),
                            range: _range,
                            onPickRange: _pickRange,
                            searchCtrl: _searchCtrl,
                            onSearchChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 420,
                            child: _TrendCard(
                              scheme: scheme,
                              chartLocations: _locations.where((l) => l != 'All').toList(),
                              chartLocation: _chartLocation,
                              onChartLocationChanged: (v) => setState(() => _chartLocation = v),
                              chartRows: chartRows,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(height: 520, child: _TableCard(rows: filtered)),
                          const SizedBox(height: 16),
                          SizedBox(height: 380, child: _RecentEventsSidebar(rows: filtered)),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initial = _range ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      helpText: 'Select date range',
    );
    if (!mounted) return;
    if (picked != null) setState(() => _range = picked);
  }

  List<HistoricalLogRow> _filteredRows() {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _allRows.where((row) {
      if (_locationFilter != 'All' && row.location != _locationFilter) return false;

      if (_range != null) {
        final start = DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
        final end = DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59);
        if (row.ts.isBefore(start) || row.ts.isAfter(end)) return false;
      }

      if (q.isEmpty) return true;
      final tsStr = _formatTs(row.ts).toLowerCase();
      return row.id.toLowerCase().contains(q) || tsStr.contains(q);
    }).toList()
      ..sort((a, b) => b.ts.compareTo(a.ts));
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

  static List<HistoricalLogRow> _seedMockData() {
    final now = DateTime.now();
    final locations = <String>[
      'Tabunok, Talisay City',
      'Linao, Talisay City',
      'Bulacao',
    ];
    final rows = <HistoricalLogRow>[];

    // 3 days hourly points per location (~72*3 = 216 rows)
    for (final loc in locations) {
      for (int i = 0; i < 72; i++) {
        final ts = now.subtract(Duration(hours: i));
        final base = switch (loc) {
          'Tabunok, Talisay City' => 10.0,
          'Linao, Talisay City' => 14.0,
          _ => 18.0,
        };
        final wave = (i % 24) / 24.0;
        final spike = (i % 29 == 0) ? 18 : 0;
        final cm = (base + (wave * 22) + spike).clamp(0, 60).toDouble();
        rows.add(
          HistoricalLogRow(
            id: 'LOG-${loc.hashCode.abs()}-${ts.millisecondsSinceEpoch}',
            ts: ts,
            location: loc,
            waterLevelCm: cm,
          ),
        );
      }
    }
    return rows;
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

  const _FiltersCard({
    required this.locations,
    required this.selectedLocation,
    required this.onLocationChanged,
    required this.range,
    required this.onPickRange,
    required this.searchCtrl,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const _CardTitle(icon: Icons.filter_alt_outlined, title: 'Filters'),
            _RangeButton(range: range, onPick: onPickRange),
            _LocationDropdown(
              label: 'Location',
              value: selectedLocation,
              locations: locations,
              onChanged: onLocationChanged,
            ),
            SizedBox(
              width: 320,
              child: TextField(
                controller: searchCtrl,
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search timestamps or IDs…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsAndTable extends StatelessWidget {
  final ColorScheme scheme;
  final List<String> chartLocations;
  final String chartLocation;
  final ValueChanged<String> onChartLocationChanged;
  final List<HistoricalLogRow> chartRows;
  final List<HistoricalLogRow> tableRows;

  const _AnalyticsAndTable({
    required this.scheme,
    required this.chartLocations,
    required this.chartLocation,
    required this.onChartLocationChanged,
    required this.chartRows,
    required this.tableRows,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 320,
          child: _TrendCard(
            scheme: scheme,
            chartLocations: chartLocations,
            chartLocation: chartLocation,
            onChartLocationChanged: onChartLocationChanged,
            chartRows: chartRows,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(child: _TableCard(rows: tableRows)),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  final ColorScheme scheme;
  final List<String> chartLocations;
  final String chartLocation;
  final ValueChanged<String> onChartLocationChanged;
  final List<HistoricalLogRow> chartRows;

  const _TrendCard({
    required this.scheme,
    required this.chartLocations,
    required this.chartLocation,
    required this.onChartLocationChanged,
    required this.chartRows,
  });

  @override
  Widget build(BuildContext context) {
    final primary = scheme.primary;
    final spots = <FlSpot>[];

    // x = index to keep axis readable; we show time labels sparsely
    for (int i = 0; i < chartRows.length; i++) {
      spots.add(FlSpot(i.toDouble(), chartRows[i].waterLevelCm));
    }

    final maxY = (chartRows.isEmpty ? 40.0 : chartRows.map((e) => e.waterLevelCm).reduce((a, b) => a > b ? a : b)) + 5;

    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _CardTitle(icon: Icons.show_chart, title: 'Water Level Trend'),
                const Spacer(),
                _LocationDropdown(
                  label: 'Chart view',
                  value: chartLocation,
                  locations: chartLocations,
                  onChanged: onChartLocationChanged,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: chartRows.isEmpty
                  ? Center(
                      child: Text(
                        'No data for selected filters.',
                        style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontWeight: FontWeight.w700),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: maxY,
                        gridData: const FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 10),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 42,
                              interval: 10,
                              getTitlesWidget: (v, meta) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text('${v.toInt()}cm', style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: (chartRows.length / 4).clamp(1, 9999).toDouble(),
                              getTitlesWidget: (v, meta) {
                                final idx = v.round().clamp(0, chartRows.length - 1);
                                final ts = chartRows[idx].ts;
                                String two(int x) => x.toString().padLeft(2, '0');
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text('${two(ts.hour)}:${two(ts.minute)}', style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.w700)),
                                );
                              },
                            ),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            isCurved: true,
                            curveSmoothness: 0.25,
                            spots: spots,
                            barWidth: 3,
                            color: primary,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  primary.withValues(alpha: 0.28),
                                  primary.withValues(alpha: 0.00),
                                ],
                              ),
                            ),
                          ),
                        ],
                        lineTouchData: LineTouchData(
                          handleBuiltInTouches: true,
                          touchTooltipData: LineTouchTooltipData(
                            tooltipRoundedRadius: 12,
                            getTooltipItems: (items) {
                              return items.map((it) {
                                final idx = it.x.round().clamp(0, chartRows.length - 1);
                                final row = chartRows[idx];
                                return LineTooltipItem(
                                  '${_HistoricalLogsPageState._formatTs(row.ts)}\n${row.waterLevelCm.toStringAsFixed(0)} cm',
                                  const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                                );
                              }).toList();
                            },
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.black.withValues(alpha: 0.06),
        ),
        child: PaginatedDataTable(
          header: const Row(
            children: [
              Icon(Icons.table_chart_outlined, size: 18),
              SizedBox(width: 10),
              Text('Data Logs', style: TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          columns: const [
            DataColumn(label: Text('Time & Date')),
            DataColumn(label: Text('Location')),
            DataColumn(label: Text('Water Level (cm)')),
            DataColumn(label: Text('Flood Label')),
          ],
          source: _LogsTableSource(widget.rows),
          rowsPerPage: _rowsPerPage,
          onRowsPerPageChanged: (v) {
            if (v == null) return;
            setState(() => _rowsPerPage = v);
          },
          showFirstLastButtons: true,
        ),
      ),
    );
  }
}

class _LogsTableSource extends DataTableSource {
  final List<HistoricalLogRow> rows;
  _LogsTableSource(this.rows);

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= rows.length) return null;
    final r = rows[index];
    final label = _HistoricalLogsPageState._labelFor(r.waterLevelCm);
    final badge = _FloodBadge(label: label);

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(Text(_HistoricalLogsPageState._formatTs(r.ts), style: const TextStyle(fontWeight: FontWeight.w700))),
        DataCell(Text(r.location)),
        DataCell(Text(r.waterLevelCm.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.w800))),
        DataCell(badge),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => rows.length;

  @override
  int get selectedRowCount => 0;
}

class _RecentEventsSidebar extends StatelessWidget {
  final List<HistoricalLogRow> rows;
  const _RecentEventsSidebar({required this.rows});

  @override
  Widget build(BuildContext context) {
    final critical = rows
        .where((r) => _HistoricalLogsPageState._labelFor(r.waterLevelCm) == FloodLabel.deepFlood)
        .take(12)
        .toList();

    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle(icon: Icons.notifications_active_outlined, title: 'Recent Events'),
            const SizedBox(height: 12),
            Expanded(
              child: critical.isEmpty
                  ? Center(
                      child: Text(
                        'No recent critical updates.',
                        style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontWeight: FontWeight.w700),
                      ),
                    )
                  : ListView.separated(
                      itemCount: critical.length,
                      separatorBuilder: (_, __) => Divider(color: Colors.black.withValues(alpha: 0.06)),
                      itemBuilder: (context, i) {
                        final r = critical[i];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(top: 5),
                              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${r.location} reached Danger Level',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_HistoricalLogsPageState._formatTs(r.ts)} • ${r.waterLevelCm.toStringAsFixed(0)} cm',
                                    style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w700, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloodBadge extends StatelessWidget {
  final FloodLabel label;
  const _FloodBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final (text, bg, fg) = switch (label) {
      FloodLabel.normal => ('Normal', Colors.green, Colors.white),
      FloodLabel.lowFlood => ('Low Flood', Colors.orange, Colors.white),
      FloodLabel.deepFlood => ('Deep Flood', Colors.redAccent, Colors.white),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: bg.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 10))],
      ),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 11)),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 16, offset: const Offset(0, 10))],
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _CardTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.blueGrey),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      ],
    );
  }
}

class _LocationDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> locations;
  final ValueChanged<String> onChanged;
  final bool compact;

  const _LocationDropdown({
    required this.label,
    required this.value,
    required this.locations,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = DropdownButtonFormField<String>(
      key: ValueKey(value),
      initialValue: value,
      items: locations.map((l) => DropdownMenuItem(value: l, child: Text(l, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) {
        if (v == null) return;
        onChanged(v);
      },
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );

    if (!compact) return SizedBox(width: 260, child: child);
    return SizedBox(width: 260, height: 44, child: child);
  }
}

class _RangeButton extends StatelessWidget {
  final DateTimeRange? range;
  final VoidCallback onPick;
  const _RangeButton({required this.range, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final text = range == null
        ? 'Pick date range'
        : '${range!.start.year}-${range!.start.month.toString().padLeft(2, '0')}-${range!.start.day.toString().padLeft(2, '0')} → '
            '${range!.end.year}-${range!.end.month.toString().padLeft(2, '0')}-${range!.end.day.toString().padLeft(2, '0')}';

    return OutlinedButton.icon(
      onPressed: onPick,
      icon: const Icon(Icons.date_range),
      label: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
      ),
    );
  }
}

