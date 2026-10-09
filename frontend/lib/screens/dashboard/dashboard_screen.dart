import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/api_client.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override State<DashboardScreen> createState() => _State();
}

class _State extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiClient.get('/stats/');
      setState(() { _stats = data; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Réessayer')),
            ]))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                Text('MediVision Kit',
                  style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
                const Text(
                  'Système d\'analyse ECG/EEG assisté par IA — Cameroun',
                  style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 32),

                // ── KPI cards ECG + EEG ──────────────────────────────
                Wrap(spacing: 16, runSpacing: 16, children: [
                  _KpiCard(
                    icon: Icons.people,
                    label: 'Patients',
                    value: '${_stats!['total_patients']}',
                    color: Colors.blue,
                    onTap: () => context.go('/patients'),
                  ),
                  // ECG
                  _KpiCard(
                    icon: Icons.monitor_heart,
                    label: 'ECGs total',
                    value: '${_stats!['total_ecgs']}',
                    color: Colors.green,
                    onTap: () => context.go('/ecgs/all'),
                  ),
                  _KpiCard(
                    icon: Icons.today,
                    label: "ECGs aujourd'hui",
                    value: '${_stats!['ecgs_today']}',
                    color: Colors.teal,
                    onTap: () => context.go('/ecgs/today'),
                  ),
                  // EEG NOUVEAU
                  _KpiCard(
                    icon: Icons.waves, // Icône EEG
                    label: 'EEGs total',
                    value: '${_stats!['total_eegs'] ?? 0}',
                    color: Colors.indigo,
                    onTap: () => context.go('/eegs/all'),
                  ),
                  _KpiCard(
                    icon: Icons.today,
                    label: "EEGs aujourd'hui",
                    value: '${_stats!['eegs_today'] ?? 0}',
                    color: Colors.indigoAccent,
                    onTap: () => context.go('/eegs/today'),
                  ),
                  _KpiCard(
                    icon: Icons.rate_review,
                    label: 'File de révision',
                    value: '${_stats!['review_queue']}',
                    color: (_stats!['review_queue'] as int) > 0
                      ? Colors.orange : Colors.grey,
                    onTap: () => context.go('/ecgs/revision'),
                  ),
                  _KpiCard(
                    icon: Icons.insights,
                    label: 'Confiance moy.',
                    value:
                      '${((_stats!['avg_confidence'] as num)*100).toStringAsFixed(1)}%',
                    color: Colors.purple,
                  ),
                ]),
                const SizedBox(height: 32),

                // ── Distribution ECG ────────────────────────────────
                if ((_stats!['ecg_class_distribution'] as List?)?.isNotEmpty ?? false) ...[
                  Text('Distribution diagnostics ECG',
                    style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _DistributionChart(
                    distribution: List<Map<String, dynamic>>.from(
                      _stats!['ecg_class_distribution']),
                    total: _stats!['total_ecgs'] as int,
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Distribution EEG NOUVEAU ────────────────────────
                if ((_stats!['eeg_class_distribution'] as List?)?.isNotEmpty ?? false) ...[
                  Text('Distribution diagnostics EEG',
                    style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const SizedBox(height: 16),
                  _DistributionChart(
                    distribution: List<Map<String, dynamic>>.from(
                      _stats!['eeg_class_distribution']),
                    total: _stats!['total_eegs'] as int,
                    color: Colors.indigo,
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Daily charts ECG + EEG ─────────────────────────
                if ((_stats!['daily_ecgs'] as List).isNotEmpty) ...[
                  Text('ECGs — 7 derniers jours',
                    style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Card(child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                    child: SizedBox(
                      height: 180,
                      child: _DailyEcgChart(
                        daily: List<Map<String, dynamic>>.from(
                          _stats!['daily_ecgs']))))),
                  const SizedBox(height: 24),
                ],

                if ((_stats!['daily_eegs'] as List?)?.isNotEmpty ?? false) ...[
                  Text('EEGs — 7 derniers jours',
                    style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const SizedBox(height: 16),
                  Card(child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                    child: SizedBox(
                      height: 180,
                      child: _DailyEegChart(
                        daily: List<Map<String, dynamic>>.from(
                          _stats!['daily_eegs']))))),
                  const SizedBox(height: 32),
                ],

                // ── Quick actions ──────────────────────────────────
                Text('Actions rapides',
                  style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _ActionButton(
                    icon: Icons.person_add,
                    label: 'Nouveau patient',
                    onTap: () => context.push('/patients/new')),
                  _ActionButton(
                    icon: Icons.monitor_heart,
                    label: 'Analyser ECG',
                    onTap: () => context.go('/ecg')),
                  _ActionButton(
                    icon: Icons.waves,
                    label: 'Analyser EEG', // NOUVEAU
                    onTap: () => context.go('/eeg')),
                  _ActionButton(
                    icon: Icons.people,
                    label: 'Voir les patients',
                    onTap: () => context.go('/patients')),
                  _ActionButton(
                    icon: Icons.rate_review,
                    label: 'File de révision',
                    onTap: () => context.go('/ecgs/revision')),
                ]),
              ])),
    );
  }
}

// ── Widget Distribution (réutilisable ECG/EEG) ──────────────────────────────
class _DistributionChart extends StatelessWidget {
  final List<Map<String, dynamic>> distribution;
  final int total;
  final Color? color;
  const _DistributionChart({
    required this.distribution,
    required this.total,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color?.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: distribution.map((d) {
          final count = d['count'] as int;
          final pct = total > 0 ? count / total : 0.0;
          final diagColor = _diagColor(d['label'] as String, color);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(d['label'] ?? 'N/A',
                    style: const TextStyle(fontWeight: FontWeight.w500))),
                  Text(
                    '$count (${(pct*100).toStringAsFixed(0)}%)',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: pct.toDouble(),
                  color: diagColor,
                  backgroundColor: Colors.grey.shade100,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4)),
              ]));
        }).toList())),
    );
  }

  Color _diagColor(String label, Color? baseColor) {
    final l = label.toLowerCase();
    if (l.contains('normal')) return Colors.green;
    if (l.contains('infarc') || l.contains('épilepsie')) return Colors.red;
    if (l.contains('trouble') || l.contains('conduction')) return Colors.orange;
    if (l.contains('hyper')) return Colors.purple;
    return baseColor ?? Colors.blue;
  }
}

// ── Widgets existants (modifiés) ────────────────────────────────────────────
class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  const _KpiCard({
    required this.icon, required this.label,
    required this.value, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      width: 160, height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.2))),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          if (onTap != null)
            Icon(Icons.arrow_forward_ios, size: 10,
              color: color.withOpacity(0.5)),
        ]),
        const Spacer(),
        Text(value,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
            color: color)),
        Text(label,
          style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
      ])));
}


class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      );
}

class _DailyEcgChart extends StatelessWidget {
  final List<Map<String, dynamic>> daily;

  const _DailyEcgChart({required this.daily});

  @override
  Widget build(BuildContext context) {
    final sorted = [...daily]
      ..sort((a, b) => (a['day'] as String).compareTo(b['day'] as String));

    final groups = <BarChartGroupData>[];
    for (var i = 0; i < sorted.length; i++) {
      final count = (sorted[i]['count'] as num?)?.toDouble() ?? 0;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: count,
              width: 18,
              color: Colors.green,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        barGroups: groups,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= sorted.length) return const SizedBox.shrink();
                final day = sorted[i]['day'] as String? ?? '';
                final short = day.length >= 10 ? day.substring(5) : day;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(short, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyEegChart extends StatelessWidget {
  final List<Map<String, dynamic>> daily;

  const _DailyEegChart({required this.daily});

  @override
  Widget build(BuildContext context) {
    final sorted = [...daily]
      ..sort((a, b) => (a['day'] as String).compareTo(b['day'] as String));

    final groups = <BarChartGroupData>[];
    for (var i = 0; i < sorted.length; i++) {
      final count = (sorted[i]['count'] as num?)?.toDouble() ?? 0;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: count,
              width: 18,
              color: Colors.indigo,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        barGroups: groups,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= sorted.length) return const SizedBox.shrink();
                final day = sorted[i]['day'] as String? ?? '';
                final short = day.length >= 10 ? day.substring(5) : day;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(short, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
