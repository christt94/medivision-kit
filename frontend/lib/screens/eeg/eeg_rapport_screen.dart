import 'dart:convert';

import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'eeg_interpretation_screen.dart';

class EegRapportScreen extends StatefulWidget {
  final String patientId;
  const EegRapportScreen({super.key, required this.patientId});

  @override
  State<EegRapportScreen> createState() => _EegRapportState();
}

class _EegRapportState extends State<EegRapportScreen> {
  List<Map<String, dynamic>> _rapports = [];
  bool _loading = true;
  String? _error;

  static const teal = Color(0xFF01696f);

  @override
  void initState() {
    super.initState();
    _loadRapports();
  }

  Future<void> _loadRapports() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await ApiClient.get('/eeg/rapports/patient/${widget.patientId}');
      if (mounted) {
        setState(() {
          _rapports = List<Map<String, dynamic>>.from(
            (data as Map)['rapports'] as List? ?? [],
          );
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _exportPdf(String rapportId) async {
    try {
      await ApiClient.downloadPdf(
        '/eeg/export-pdf',
        fields: {'rapport_id': rapportId},
        fileName: 'rapport_eeg_${rapportId.substring(0, 8)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur PDF : $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _openRapport(String rapportId) async {
    try {
      final data = await ApiClient.get('/eeg/rapports/$rapportId');
      final payload = Map<String, dynamic>.from(data as Map);
      final rapportData = Map<String, dynamic>.from(payload['data'] as Map? ?? {});
      final rawJson = rapportData['raw_json']?.toString() ?? '{}';
      final rawResult = Map<String, dynamic>.from(jsonDecode(rawJson) as Map);

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EegInterpretationScreen(
            rapportId: rapportId,
            rapportData: rapportData,
            rawResult: rawResult,
          ),
        ),
      );
      await _loadRapports();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur ouverture rapport : $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Color _diagColor(String? diag) {
    if (diag == null) return Colors.grey;
    final d = diag.toLowerCase();
    if (d.contains('pilepsie') || d.contains('epilep')) {
      return const Color(0xFFc0392b);
    }
    if (d.contains('normal')) return const Color(0xFF43a047);
    if (d.contains('sommeil') || d.contains('sleep')) {
      return const Color(0xFF1e88e5);
    }
    return teal;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapports EEG'),
        backgroundColor: teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRapports,
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF01696f)),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadRapports,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Réessayer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : _rapports.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.psychology_outlined, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(
                            'Aucun rapport EEG',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Les rapports s\'afficheront ici après analyse',
                            style: TextStyle(color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadRapports,
                      color: teal,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rapports.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final r = _rapports[i];
                          final id = r['id'] as String? ?? '';
                          final diag = r['diagnostic'] as String? ?? '—';
                          final cim11 = r['cim11_code'] as String?;
                          final conf = (r['confidence'] as num?)?.toDouble();
                          final date = (r['created_at'] as String? ?? '').substring(0, 10);
                          final dColor = _diagColor(diag);

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: dColor.withOpacity(0.08),
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(color: dColor, shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          diag,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: dColor,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        date,
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  child: Row(
                                    children: [
                                      if (cim11 != null) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: teal.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'CIM-11: $cim11',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: teal,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      if (conf != null)
                                        Text(
                                          '${(conf * 100).toStringAsFixed(1)}% confiance',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                        ),
                                      const Spacer(),
                                      Text(
                                        id.isNotEmpty ? 'Réf: ${id.substring(0, 8).toUpperCase()}' : '',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade400,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        onPressed: id.isEmpty ? null : () => _openRapport(id),
                                        icon: const Icon(Icons.visibility_outlined, size: 16),
                                        label: const Text('Ouvrir', style: TextStyle(fontSize: 13)),
                                        style: TextButton.styleFrom(foregroundColor: Colors.blueGrey),
                                      ),
                                      TextButton.icon(
                                        onPressed: id.isEmpty ? null : () => _exportPdf(id),
                                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                                        label: const Text('PDF', style: TextStyle(fontSize: 13)),
                                        style: TextButton.styleFrom(foregroundColor: teal),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}