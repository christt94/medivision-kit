import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class EcgWaveformChart extends StatelessWidget {
  final Uint8List csvBytes;
  const EcgWaveformChart({super.key, required this.csvBytes});

  List<FlSpot> _parseChannel(int channelIndex) {
    final lines = const LineSplitter().convert(utf8.decode(csvBytes));
    final spots = <FlSpot>[];
    int i = 0;
    for (final line in lines) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final cols = line.split(',');
      if (cols.length <= channelIndex) continue;
      final val = double.tryParse(cols[channelIndex].trim());
      if (val != null) {
        spots.add(FlSpot(i.toDouble(), val));
        i++;
        if (i >= 500) break;
      }
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final leadI  = _parseChannel(0);
    final leadII = _parseChannel(1);

    if (leadI.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Impossible de parser le signal ECG',
          style: TextStyle(color: Colors.grey)));
    }

    final allY  = [...leadI, ...leadII].map((s) => s.y).toList();
    final minY  = allY.reduce((a, b) => a < b ? a : b) - 0.2;
    final maxY  = allY.reduce((a, b) => a > b ? a : b) + 0.2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Signal ECG — Lead I & II',
          style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: LineChart(LineChartData(
            minY: minY, maxY: maxY,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              show: true,
              horizontalInterval: 0.5,
              verticalInterval:   50,
              getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.red.shade100, strokeWidth: 0.5),
              getDrawingVerticalLine: (_) =>
                FlLine(color: Colors.red.shade100, strokeWidth: 0.5),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: Colors.grey.shade300)),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 44,
                getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 9, color: Colors.grey)))),
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 20, interval: 100,
                getTitlesWidget: (v, _) => Text('${(v / 500).toStringAsFixed(1)}s',
                  style: const TextStyle(fontSize: 9, color: Colors.grey)))),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: leadI,  isCurved: false,
                color: Colors.red.shade700, barWidth: 1.2,
                dotData: const FlDotData(show: false)),
              LineChartBarData(
                spots: leadII, isCurved: false,
                color: Colors.blue.shade400, barWidth: 1.0,
                dotData: const FlDotData(show: false)),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((s) =>
                  LineTooltipItem('${s.y.toStringAsFixed(3)} mV',
                    const TextStyle(fontSize: 11, color: Colors.white))).toList())),
          )),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _Legend(color: Colors.red.shade700,  label: 'Lead I'),
          const SizedBox(width: 16),
          _Legend(color: Colors.blue.shade400, label: 'Lead II'),
        ]),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 24, height: 3, color: color),
    const SizedBox(width: 6),
    Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
  ]);
}
