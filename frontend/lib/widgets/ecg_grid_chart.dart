import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class EcgGridChart extends StatelessWidget {
  final Uint8List csvBytes;
  const EcgGridChart({super.key, required this.csvBytes});

  static const _leadNames = [
    'I','II','III','aVR','aVL','aVF',
    'V1','V2','V3','V4','V5','V6',
  ];

  static const _colors = [
    Color(0xFFE53935), Color(0xFF8E24AA), Color(0xFF1E88E5), Color(0xFF00ACC1),
    Color(0xFF43A047), Color(0xFFFB8C00), Color(0xFFE53935), Color(0xFF8E24AA),
    Color(0xFF1E88E5), Color(0xFF00ACC1), Color(0xFF43A047), Color(0xFFFB8C00),
  ];

  List<List<double>> _parseLeads() {
    try {
      final text  = String.fromCharCodes(csvBytes);
      final lines = text.trim().split('\n')
          .where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) return [];

      // Skip header if first row contains letters
      final start = lines[0].contains(RegExp(r'[a-zA-Z]')) ? 1 : 0;
      final rows  = lines.sublist(start).map((l) =>
        l.split(',').map((v) => double.tryParse(v.trim()) ?? 0.0).toList()
      ).where((r) => r.isNotEmpty).toList();

      if (rows.isEmpty) return [];
      final nLeads = rows[0].length;
      if (nLeads == 0) return [];

      // Transpose: rows[sample][lead] → leads[lead][sample]
      return List.generate(nLeads.clamp(0, 12),
        (lead) => rows.map((row) =>
          lead < row.length ? row[lead] : 0.0).toList());
    } catch (e) {
      debugPrint('EcgGridChart parse error: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final leads = _parseLeads();

    if (leads.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: const Text('Signal non disponible',
          style: TextStyle(color: Colors.grey)));
    }

    final nLeads = leads.length;
    final nRows  = (nLeads / 3).ceil();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header
      Row(children: [
        const Icon(Icons.monitor_heart, size: 16, color: Colors.redAccent),
        const SizedBox(width: 6),
        Text('ECG — $nLeads dérivations',
          style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.bold)),
        const Spacer(),
        Text('${leads[0].length} pts  •  ${(leads[0].length/100).toStringAsFixed(1)}s',
          style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
      const SizedBox(height: 12),

      // Grid: nRows rows of 3 leads each
      for (var row = 0; row < nRows; row++) ...[
        IntrinsicHeight(child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var col = 0; col < 3; col++) ...[
              Builder(builder: (_) {
                final idx = row * 3 + col;
                if (idx >= nLeads) return const Expanded(child: SizedBox());
                return Expanded(child: _LeadTile(
                  name:    idx < _leadNames.length ? _leadNames[idx] : 'L${idx+1}',
                  samples: leads[idx],
                  color:   _colors[idx % _colors.length],
                ));
              }),
              if (col < 2) const SizedBox(width: 4),
            ],
          ],
        )),
        const SizedBox(height: 4),
      ],
    ]);
  }
}

class _LeadTile extends StatelessWidget {
  final String       name;
  final List<double> samples;
  final Color        color;
  const _LeadTile({required this.name, required this.samples, required this.color});

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) return const SizedBox(height: 90);

    // Downsample to max 300 pts for performance
    final step = ((samples.length / 300).ceil()).clamp(1, 9999);
    final pts  = <FlSpot>[];
    for (var i = 0; i < samples.length; i += step) {
      pts.add(FlSpot(i.toDouble(), samples[i]));
    }

    double minY = samples.reduce((a, b) => a < b ? a : b);
    double maxY = samples.reduce((a, b) => a > b ? a : b);
    if ((maxY - minY).abs() < 0.001) { minY -= 0.5; maxY += 0.5; }
    final pad = (maxY - minY) * 0.25;

    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F8),
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(children: [
          // ECG paper grid
          CustomPaint(painter: _EcgGridPainter(), size: Size.infinite),
          // Signal
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 16),
            child: LineChart(
              duration: Duration.zero,
              LineChartData(
                minY: minY - pad,
                maxY: maxY + pad,
                gridData:   const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(
                  leftTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [LineChartBarData(
                  spots:    pts,
                  isCurved: false,
                  color:    color,
                  barWidth: 1.2,
                  dotData:  const FlDotData(show: false),
                )],
                lineTouchData: const LineTouchData(enabled: false),
              ),
            )),
          // Lead label bottom-left
          Positioned(left: 5, bottom: 3,
            child: Text(name, style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.bold, color: color))),
        ])));
  }
}

class _EcgGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()..color = const Color(0xFFFFCDD2)..strokeWidth = 0.3;
    final major = Paint()..color = const Color(0xFFEF9A9A)..strokeWidth = 0.6;
    const step = 5.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height),
        x % 25 == 0 ? major : minor);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
        y % 25 == 0 ? major : minor);
    }
  }
  @override bool shouldRepaint(_) => false;
}
