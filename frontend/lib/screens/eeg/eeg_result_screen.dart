import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'eeg_interpretation_screen.dart';
import 'eeg_rapport_screen.dart';

class EegResultScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  final String patientName;
  const EegResultScreen({
    super.key,
    required this.result,
    required this.patientName,
  });
  
  @override
  State<EegResultScreen> createState() => _EegResultState();
}

class _EegResultState extends State<EegResultScreen> {
  bool _exportingPdf = false;
  String? _pdfError;
  bool _loadingRapport = false;

  static const teal = Color(0xFF01696f);
  static const red = Color(0xFFc0392b);
  static const orange = Color(0xFFe67e22);
  static const green = Color(0xFF43a047);
  static const blue = Color(0xFF1e88e5);
  static const purple = Color(0xFF8e24aa);

  Map<String, dynamic> get _diag => 
      (widget.result['diagnostic'] as Map<String, dynamic>? ?? {});
  Map<String, dynamic> get _meta => 
      (widget.result['meta'] as Map<String, dynamic>? ?? {});
  String get _rapportId => widget.result['rapport_id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    // Auto-ouvre l'interprétation après 2 secondes
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _rapportId.isNotEmpty) {
        _openInterpretation();
      }
    });
  }

  Color _diagColor(String label) {
    switch (label) {
      case 'Epilepsy': return red;
      case 'Sleep_REM': return orange;
      case 'Sleep_N3': return purple;
      case 'Sleep_N1':
      case 'Sleep_N2': return blue;
      case 'Normal': return green;
      default: return teal;
    }
  }

  Color _confColor(double conf) {
    if (conf >= 88) return green;
    if (conf >= 65) return orange;
    return red;
  }

  Future<void> _openInterpretation() async {
    if (_rapportId.isEmpty || !mounted) return;
    
    if (mounted) {
      setState(() => _loadingRapport = true);
    }

    try {
      // Récupère les données complètes du rapport depuis la DB
      final data = await ApiClient.get('/eeg/rapports/$_rapportId');
      final payload = Map<String, dynamic>.from(data as Map);
      final rapportData = Map<String, dynamic>.from(payload['data'] as Map? ?? {});
      final rawJson = rapportData['raw_json']?.toString() ?? '{}';
      final rawResult = Map<String, dynamic>.from(jsonDecode(rawJson) as Map);

      if (!mounted) return;
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EegInterpretationScreen(
            rapportId: _rapportId,
            rapportData: rapportData,
            rawResult: rawResult,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingRapport = false;
          _pdfError = 'Erreur chargement rapport : $e';
        });
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_rapportId.isEmpty) return;
    if (mounted) {
      setState(() {
        _exportingPdf = true;
        _pdfError = null;
      });
    }
    try {
      await ApiClient.downloadPdf(
        '/eeg/export-pdf',
        fields: {'rapport_id': _rapportId},
        fileName: 'rapport_eeg_${_rapportId.substring(0, 8)}.pdf',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _pdfError = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _exportingPdf = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final diag = _diag;
    final meta = _meta;
    final label = diag['label'] as String? ?? 'Normal';
    final labelFr = diag['label_fr'] as String? ?? label;
    final cim11 = diag['cim11'] as String? ?? '—';
    final conf = (diag['confiance'] as num?)?.toDouble() ?? 0.0;
    final desc = diag['description'] as String? ?? '';
    final dColor = _diagColor(label);
    final patientId = widget.result['patient_id'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Résultat EEG'),
        backgroundColor: teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_rapportId.isNotEmpty)
            TextButton.icon(
              onPressed: _loadingRapport ? null : _openInterpretation,
              icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
              label: Text(
                _loadingRapport ? 'Chargement…' : 'Interpréter',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EegRapportScreen(patientId: patientId),
              ),
            ),
            icon: const Icon(Icons.history, color: Colors.white, size: 18),
            label: const Text('Historique', style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bannière diagnostic
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: dColor, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.psychology, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('DIAGNOSTIC PRINCIPAL',
                        style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.2)),
                  ]),
                  const SizedBox(height: 8),
                  Text(labelFr, 
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('CIM-11 : $cim11', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 12),
                  if (desc.isNotEmpty)
                    Text(desc, style: const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Métriques
            Row(children: [
              _MetricCard(label: 'Confiance', value: '${conf.toStringAsFixed(1)}%', 
                         color: _confColor(conf), icon: Icons.verified_outlined),
              const SizedBox(width: 12),
              _MetricCard(label: 'Canaux', value: '${meta['nb_canaux'] ?? '—'}', 
                         color: teal, icon: Icons.cable_outlined),
              const SizedBox(width: 12),
              _MetricCard(label: 'Fréquence', value: '${meta['sfreq'] ?? '—'} Hz', 
                         color: blue, icon: Icons.waves_outlined),
            ]),

            const SizedBox(height: 12),

            Row(children: [
              _MetricCard(label: 'Durée', value: _formatDuration((meta['duree_s'] as num?)?.toDouble() ?? 0), 
                         color: purple, icon: Icons.timer_outlined),
              const SizedBox(width: 12),
              _MetricCard(label: 'Mode', value: meta['mode'] as String? ?? '—', 
                         color: green, icon: Icons.memory_outlined),
              const SizedBox(width: 12),
              const _MetricCard(label: 'Validation', value: 'AUTO', 
                         color: green, icon: Icons.check_circle_outline),
            ]),

            const SizedBox(height: 24),

            // Actions principales
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _loadingRapport ? null : _openInterpretation,
                      icon: _loadingRapport
                          ? const SizedBox(width: 18, height: 18, 
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.edit_outlined),
                      label: Text(_loadingRapport ? 'Ouverture…' : 'Interpréter le rapport'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _exportingPdf ? null : _exportPdf,
                    icon: _exportingPdf
                        ? const SizedBox(width: 18, height: 18, 
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),

            if (_pdfError != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(_pdfError!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(double seconds) {
    if (seconds < 60) return '${seconds.toStringAsFixed(0)} s';
    if (seconds < 3600) return '${(seconds / 60).toStringAsFixed(0)} min';
    return '${(seconds / 3600).toStringAsFixed(1)} h';
}

}

class _MetricCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 6, 
          offset: const Offset(0, 2),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    ),
  );
}
