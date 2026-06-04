import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';
import '../services/device_service.dart';
import '../widgets/bottom_nav_bar.dart';

// ─── helpers ──────────────────────────────────────────────────────────────────

double? _parseDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String _formatTs(int ts) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} ${dt.day}, $h:$m';
}

// Map N sorted history entries to X positions 0–72 (3 days in hours)
const double _trendRangeHours = 72.0;

List<FlSpot> _computeSpots(
  List<Map<dynamic, dynamic>> entries,
  String field, {
  bool smooth = false,
}) {
  final raw   = <double>[];
  final xVals = <double>[];
  final count = entries.length;

  for (int i = 0; i < count; i++) {
    final val = _parseDouble(entries[i][field]);
    if (val != null) {
      xVals.add(count > 1 ? (i / (count - 1)) * _trendRangeHours : 0.0);
      raw.add(val);
    }
  }

  if (!smooth || raw.length < 3) {
    return [for (int i = 0; i < raw.length; i++) FlSpot(xVals[i], raw[i])];
  }

  // 3-point moving average — smooths noise without hiding real trends
  final spots = <FlSpot>[];
  for (int i = 0; i < raw.length; i++) {
    final double v;
    if (i == 0) {
      v = (raw[0] + raw[1]) / 2;
    } else if (i == raw.length - 1) {
      v = (raw[i - 1] + raw[i]) / 2;
    } else {
      v = (raw[i - 1] + raw[i] + raw[i + 1]) / 3.0;
    }
    spots.add(FlSpot(xVals[i], v));
  }
  return spots;
}

String _avgLabel(List<FlSpot> spots, String unit) {
  if (spots.isEmpty) return 'AVG -- $unit';
  final avg = spots.map((s) => s.y).reduce((a, b) => a + b) / spots.length;
  final decimals = unit == 'ppm' ? 0 : 1;
  return 'AVG ${avg.toStringAsFixed(decimals)} $unit';
}

double _tdsMaxY(List<BarChartGroupData> bars) {
  if (bars.isEmpty) return 600;
  double maxVal = 0;
  for (final g in bars) {
    for (final rod in g.barRods) {
      if (rod.toY > maxVal) maxVal = rod.toY;
    }
  }
  final headroom = maxVal * 1.25;
  // Snap to a clean step size relative to magnitude
  final step = headroom <= 300 ? 50.0 : (headroom <= 1000 ? 200.0 : 500.0);
  final rounded = ((headroom / step).ceil() * step).toDouble();
  return rounded < 300 ? 300 : rounded;
}

// Pick a Y-axis interval that yields ~5 labels regardless of maxY magnitude.
double _niceInterval(double maxY) {
  if (maxY <= 0) return 50;
  final raw = maxY / 5.0;
  final mag = _pow10Below(raw);
  final norm = raw / mag;
  double step;
  if (norm < 1.5) {
    step = 1 * mag;
  } else if (norm < 3.5) {
    step = 2 * mag;
  } else if (norm < 7.5) {
    step = 5 * mag;
  } else {
    step = 10 * mag;
  }
  return step;
}

double _pow10Below(double v) {
  double m = 1;
  while (m * 10 <= v) {
    m *= 10;
  }
  return m;
}

// ─── data models ──────────────────────────────────────────────────────────────

class _CycleEntry {
  final String id;
  final String info1; // e.g. "pH 7.2"
  final String info2; // e.g. "May 11, 16:49"

  const _CycleEntry({
    required this.id,
    required this.info1,
    required this.info2,
  });
}

class _PageData {
  final String lastCycleStr;
  final List<_CycleEntry> cycles;
  final List<FlSpot> phSpots;
  final List<FlSpot> tempSpots;
  final List<BarChartGroupData> tdsBars;
  final List<String> tdsBarLabels;
  final String avgPhLabel;
  final String avgTempLabel;
  final String avgTdsLabel;

  const _PageData({
    required this.lastCycleStr,
    required this.cycles,
    required this.phSpots,
    required this.tempSpots,
    required this.tdsBars,
    required this.tdsBarLabels,
    required this.avgPhLabel,
    required this.avgTempLabel,
    required this.avgTdsLabel,
  });

  factory _PageData.empty() => const _PageData(
        lastCycleStr: '--',
        cycles: [],
        phSpots: [],
        tempSpots: [],
        tdsBars: [],
        tdsBarLabels: [],
        avgPhLabel: 'AVG -- pH',
        avgTempLabel: 'AVG --°C',
        avgTdsLabel: 'AVG -- ppm',
      );

  factory _PageData.fromSnapshots({
    required DataSnapshot lastCycleSnap,
    required DataSnapshot cyclesSnap,
    required DataSnapshot histSnap,
  }) {
    // ── last cycle string ───────────────────────────────────────────────────
    final lastCycleStr = lastCycleSnap.value?.toString() ?? '--';

    // ── cycles list (most recent first, up to 5) ───────────────────────────
    final cycles = <_CycleEntry>[];
    final cyclesRaw = cyclesSnap.value;

    // Firebase converts integer-keyed nodes to List, handle both Map and List
    Iterable<MapEntry<dynamic, dynamic>> cycleEntries = const [];
    if (cyclesRaw is Map) {
      cycleEntries = cyclesRaw.entries;
    } else if (cyclesRaw is List) {
      // keys "1","2" → list [null, cycle1, cycle2]; skip null slots
      cycleEntries = cyclesRaw.asMap().entries
          .where((e) => e.value != null)
          .map((e) => MapEntry<dynamic, dynamic>(e.key, e.value));
    }

    if (cycleEntries.isNotEmpty) {
      final sorted = cycleEntries.toList()
        ..sort((a, b) => b.key.toString().compareTo(a.key.toString()));

      for (int i = 0; i < sorted.length && i < 5; i++) {
        final entry = sorted[i];
        final data = entry.value;

        final keyNum = int.tryParse(entry.key.toString());
        final cycleId = '#${keyNum ?? (sorted.length - i)}';

        String info1 = 'pH --';
        String info2 = '--';

        if (data is Map) {
          final phRaw = data['phAtEvent'] ?? data['ph'];
          final ph = _parseDouble(phRaw);
          if (ph != null) info1 = 'pH ${ph.toStringAsFixed(1)}';

          final tsRaw = data['ts'];
          final tsInt = tsRaw is int
              ? tsRaw
              : int.tryParse(tsRaw?.toString() ?? '');
          if (tsInt != null) info2 = _formatTs(tsInt);
        }

        cycles.add(_CycleEntry(id: cycleId, info1: info1, info2: info2));
      }
    }

    // ── history entries: filter last 3 days, sorted oldest→newest ──────────
    final cutoffTs =
        DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch ~/
            1000;
    final histEntries = <Map<dynamic, dynamic>>[];
    final histRaw = histSnap.value;
    if (histRaw is Map) {
      final sorted = histRaw.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final e in sorted) {
        if (e.value is! Map) continue;
        final m = e.value as Map<dynamic, dynamic>;
        final tsRaw = m['ts'];
        final ts = tsRaw is int ? tsRaw : int.tryParse('$tsRaw') ?? 0;
        if (ts >= cutoffTs) histEntries.add(m);
      }
    }

    // ── line chart spots ───────────────────────────────────────────────────
    final phSpots   = _computeSpots(histEntries, 'ph');               // raw — shows pH drops clearly
    final tempSpots = _computeSpots(histEntries, 'temp', smooth: true); // smoothed — removes noise

    // ── TDS bar chart (last 5 history entries with sane readings) ─────────
    // Reject sensor glitches: aquarium TDS realistically 0–1500 ppm.
    const tdsMaxRealistic = 1500.0;
    final tdsClean = histEntries.where((e) {
      final v = _parseDouble(e['tds']);
      return v != null && v >= 0 && v <= tdsMaxRealistic;
    }).toList();
    final tdsSource = tdsClean.length > 5
        ? tdsClean.sublist(tdsClean.length - 5)
        : tdsClean;

    final tdsBars = <BarChartGroupData>[];
    final tdsBarLabels = <String>[];

    for (int i = 0; i < tdsSource.length; i++) {
      final tds = _parseDouble(tdsSource[i]['tds']) ?? 0.0;
      final tsRaw = tdsSource[i]['ts'];
      final tsInt =
          tsRaw is int ? tsRaw : int.tryParse(tsRaw?.toString() ?? '');

      String label = '--';
      if (tsInt != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(tsInt * 1000);
        label =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      tdsBarLabels.add(label);

      tdsBars.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: tds,
            color: i == tdsSource.length - 1
                ? AppColors.darkNavy
                : AppColors.midBlue,
            width: 28,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      ));
    }

    // ── averages ───────────────────────────────────────────────────────────
    String avgTdsLabel = 'AVG -- ppm';
    if (tdsSource.isNotEmpty) {
      final vals = tdsSource
          .map((e) => _parseDouble(e['tds']))
          .whereType<double>()
          .toList();
      if (vals.isNotEmpty) {
        final avg = vals.reduce((a, b) => a + b) / vals.length;
        avgTdsLabel = 'AVG ${avg.toStringAsFixed(0)} ppm';
      }
    }

    return _PageData(
      lastCycleStr: lastCycleStr,
      cycles: cycles,
      phSpots: phSpots,
      tempSpots: tempSpots,
      tdsBars: tdsBars,
      tdsBarLabels: tdsBarLabels,
      avgPhLabel: _avgLabel(phSpots, 'pH'),
      avgTempLabel: _avgLabel(tempSpots, '°C'),
      avgTdsLabel: avgTdsLabel,
    );
  }
}

// ─── page ─────────────────────────────────────────────────────────────────────

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String get _base => DeviceService.basePath();
  late Future<_PageData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _fetchData();
  }

  Future<_PageData> _fetchData() async {
    try {
      final db = FirebaseDatabase.instance;
      final results = await Future.wait([
        db.ref('$_base/status/lastCycleStr').get(),
        db.ref('$_base/cycles').orderByKey().limitToLast(5).get(),
        db.ref('$_base/history').orderByKey().limitToLast(500).get(),
      ]);
      return _PageData.fromSnapshots(
        lastCycleSnap: results[0],
        cyclesSnap: results[1],
        histSnap: results[2],
      );
    } catch (_) {
      return _PageData.empty();
    }
  }

  void _refresh() => setState(() => _dataFuture = _fetchData());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7FF),
      appBar: AppBar(
        backgroundColor: AppColors.darkNavy,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppColors.white, size: 18),
          onPressed: () =>
              Navigator.pushReplacementNamed(context, '/dashboard'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'History',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
              ),
            ),
            Text(
              DeviceService.deviceId,
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: AppColors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.white, size: 20),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<_PageData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.darkNavy),
            );
          }

          final data = snapshot.data ?? _PageData.empty();

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLastCycleCard(data.lastCycleStr),
                const SizedBox(height: 20),
                _sectionTitle('Water Change Cycles'),
                const SizedBox(height: 12),
                _buildCycleList(data.cycles),
                const SizedBox(height: 24),
                _sectionTitle('pH Trend (Last 3 Days)'),
                const SizedBox(height: 12),
                _buildPhChart(data.phSpots, data.avgPhLabel),
                const SizedBox(height: 24),
                _sectionTitle('Temperature Trend (Last 3 Days)'),
                const SizedBox(height: 12),
                _buildTempChart(data.tempSpots, data.avgTempLabel),
                const SizedBox(height: 24),
                _sectionTitle('TDS Levels During Cycles'),
                const SizedBox(height: 12),
                _buildTdsChart(data.tdsBars, data.tdsBarLabels, data.avgTdsLabel),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const BetankBottomNav(currentIndex: 1),
    );
  }

  // ── last cycle card ────────────────────────────────────────────────────────

  Widget _buildLastCycleCard(String lastCycleStr) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.darkNavy,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last Water Change',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.lightBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            lastCycleStr,
            style: GoogleFonts.poppins(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: Color(0xFF4CAF50), shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                'Last cycle occurred',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.lightBlue.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── section title ──────────────────────────────────────────────────────────

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.darkNavy,
      ),
    );
  }

  // ── cycle list ─────────────────────────────────────────────────────────────

  Widget _buildCycleList(List<_CycleEntry> cycles) {
    if (cycles.isEmpty) {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkNavy.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'No cycle history available',
            style: GoogleFonts.poppins(
                fontSize: 13, color: AppColors.darkGrey),
          ),
        ),
      );
    }
    return Column(
      children: cycles
          .map((c) =>
              _CycleTile(cycleId: c.id, info1: c.info1, info2: c.info2))
          .toList(),
    );
  }

  // ── pH line chart (scrollable) ────────────────────────────────────────────

  Widget _buildPhChart(List<FlSpot> spots, String avgLabel) {
    return _ScrollableTrendChart(
      spots: spots,
      avgLabel: avgLabel,
      minY: 0,
      maxY: 14,
      yInterval: 2,
      yUnit: 'pH',
    );
  }

  Widget _buildTempChart(List<FlSpot> spots, String avgLabel) {
    return _ScrollableTrendChart(
      spots: spots,
      avgLabel: avgLabel,
      minY: 0,
      maxY: 40,
      yInterval: 10,
      yUnit: '°C',
    );
  }

  // ── TDS bar chart ──────────────────────────────────────────────────────────

  Widget _buildTdsChart(
    List<BarChartGroupData> bars,
    List<String> labels,
    String avgLabel,
  ) {
    final maxY = _tdsMaxY(bars);
    final yInterval = _niceInterval(maxY);

    return _ChartCard(
      avgLabel: avgLabel,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: AppColors.lightBlue, strokeWidth: 1, dashArray: [4, 4]),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: yInterval,
                getTitlesWidget: (value, _) => Text(
                  '${value.toInt()}ppm',
                  style: GoogleFonts.poppins(
                      fontSize: 9, color: AppColors.darkGrey),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= labels.length) {
                    return const SizedBox();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labels[idx],
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          barGroups: bars,
        ),
      ),
    );
  }

  // ── shared X-axis label (00:00, 06:00, 12:00, 18:00, 24:00) ──────────────

  Widget _timeAxisLabel(double value, TitleMeta meta) {
    const labels = <int, String>{
      0: '-3d',
      24: '-2d',
      48: '-1d',
      72: 'Now',
    };
    final label = labels[value.round()];
    if (label == null) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        label,
        style: GoogleFonts.poppins(fontSize: 9, color: AppColors.darkGrey),
      ),
    );
  }
}

// ─── cycle tile ───────────────────────────────────────────────────────────────

class _CycleTile extends StatelessWidget {
  final String cycleId;
  final String info1; // e.g. "pH 7.2"
  final String info2; // e.g. "May 11, 16:49"

  const _CycleTile({
    required this.cycleId,
    required this.info1,
    required this.info2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.lightBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                cycleId,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkNavy,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cycle $cycleId',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkNavy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$info1  ·  $info2',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: AppColors.darkGrey),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Completed',
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── scrollable trend chart (3 days, default focus = last 24h) ───────────────

class _ScrollableTrendChart extends StatefulWidget {
  final List<FlSpot> spots;
  final String avgLabel;
  final double minY;
  final double maxY;
  final double yInterval;
  final String yUnit;

  const _ScrollableTrendChart({
    required this.spots,
    required this.avgLabel,
    required this.minY,
    required this.maxY,
    required this.yInterval,
    required this.yUnit,
  });

  @override
  State<_ScrollableTrendChart> createState() => _ScrollableTrendChartState();
}

class _ScrollableTrendChartState extends State<_ScrollableTrendChart> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ChartCard(
      avgLabel: widget.avgLabel,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          // Each day takes about one screen-worth; total chart = 3x viewport.
          final viewportW = constraints.maxWidth - 36; // minus sticky Y col
          final chartW = viewportW * 3;

          return Row(
            children: [
              SizedBox(
                width: 36,
                child: _StickyYAxis(
                  minY: widget.minY,
                  maxY: widget.maxY,
                  interval: widget.yInterval,
                  unit: widget.yUnit,
                  bottomReserved: 28,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    width: chartW,
                    child: LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: _trendRangeHours,
                        minY: widget.minY,
                        maxY: widget.maxY,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: true,
                          horizontalInterval: widget.yInterval,
                          verticalInterval: 6,
                          getDrawingHorizontalLine: (_) => FlLine(
                              color: AppColors.lightBlue,
                              strokeWidth: 1,
                              dashArray: [4, 4]),
                          getDrawingVerticalLine: (v) => FlLine(
                              color: AppColors.lightBlue.withValues(alpha: 0.4),
                              strokeWidth: 1,
                              dashArray: [2, 4]),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                              interval: 6,
                              getTitlesWidget: _swipeTimeLabel,
                            ),
                          ),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: widget.spots.isEmpty
                                ? const [FlSpot.nullSpot]
                                : widget.spots,
                            isCurved: true,
                            curveSmoothness: 0.4,
                            preventCurveOverShooting: true,
                            color: AppColors.darkNavy,
                            barWidth: 2.5,
                            dotData: FlDotData(
                              // hide dots when data is dense (>30 points)
                              show: widget.spots.length <= 30,
                              getDotPainter: (spot, p, bar, i) =>
                                  FlDotCirclePainter(
                                radius: 3,
                                color: AppColors.darkNavy,
                                strokeWidth: 0,
                                strokeColor: Colors.transparent,
                              ),
                            ),
                            belowBarData: BarAreaData(
                              show: widget.spots.isNotEmpty,
                              color: AppColors.lightBlue.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Widget _swipeTimeLabel(double value, TitleMeta meta) {
  // 0..72 hours mapped to "-3d, -66h, -60h, ... 0h"
  const labels = <int, String>{
    0: '-3d',
    12: '-60h',
    24: '-2d',
    36: '-36h',
    48: '-1d',
    60: '-12h',
    72: 'Now',
  };
  final label = labels[value.round()];
  if (label == null) return const SizedBox();
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      label,
      style: GoogleFonts.poppins(fontSize: 9, color: AppColors.darkGrey),
    ),
  );
}

class _StickyYAxis extends StatelessWidget {
  final double minY;
  final double maxY;
  final double interval;
  final String unit;
  final double bottomReserved;

  const _StickyYAxis({
    required this.minY,
    required this.maxY,
    required this.interval,
    required this.unit,
    this.bottomReserved = 28,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final h = c.maxHeight - bottomReserved;
        final children = <Widget>[];
        for (double v = maxY; v >= minY - 0.0001; v -= interval) {
          final top = ((maxY - v) / (maxY - minY)) * h - 6;
          children.add(
            Positioned(
              top: top,
              right: 4,
              child: Text(
                '${v.toInt()}$unit',
                style: GoogleFonts.poppins(
                    fontSize: 9, color: AppColors.darkGrey),
              ),
            ),
          );
        }
        return Stack(clipBehavior: Clip.none, children: children);
      },
    );
  }
}

// ─── chart card ───────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final Widget child;
  final String? avgLabel;

  const _ChartCard({required this.child, this.avgLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (avgLabel != null)
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.darkNavy,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    avgLabel!,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.white,
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 12),
            const SizedBox(height: 4),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
