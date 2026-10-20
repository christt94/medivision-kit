import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';

class EegListScreen extends StatefulWidget {
  final String title;
  final String endpoint;

  const EegListScreen({
    super.key,
    required this.title,
    required this.endpoint,
  });

  @override
  State<EegListScreen> createState() => _EegListScreenState();
}

class _EegListScreenState extends State<EegListScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  static const Color teal = Color(0xFF01696f);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.get(widget.endpoint);
      setState(() {
        if (data is List) {
          _items = data;
        } else if (data is Map && data['rapports'] is List) {
          _items = List<dynamic>.from(data['rapports'] as List);
        } else {
          _items = [];
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _confColor(double conf) =>
      conf >= 0.88 ? Colors.green : conf >= 0.65 ? Colors.orange : Colors.red;

  Color _reviewColor(String level) {
    switch (level) {
      case 'AUTO':
        return teal;
      case 'REVIEW':
        return Colors.orange;
      case 'VALIDATED':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _reviewLabel(String level) {
    switch (level) {
      case 'AUTO':
        return 'Auto';
      case 'REVIEW':
        return 'Révision';
      case 'VALIDATED':
        return 'Validé';
      default:
        return level;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: teal),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.psychology_outlined,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Aucun EEG trouvé',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                          child: Row(
                            children: [
                              Text(
                                '${_items.length} résultat(s)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          color: teal,
                          child: const Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  'Patient',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'Diagnostic',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  'Confiance',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  'Statut',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'Date',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              SizedBox(width: 96),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              final item = _items[i] as Map<String, dynamic>;
                              final conf =
                                  (item['confidence'] as num?)?.toDouble() ?? 0.0;
                              final level =
                                  item['review_level'] as String? ?? 'AUTO';
                              final raw = item['created_at'] as String? ?? '';
                              final date = raw.length >= 16
                                  ? raw.substring(0, 16).replaceAll('T', ' ')
                                  : raw;
                              final rapportId = item['id'] as String? ?? '';

                              return Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (item['patient_name'] as String?)?.isNotEmpty ==
                                                    true
                                                ? item['patient_name'] as String
                                                : (item['patient_id'] as String? ?? '—'),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            item['patient_id'] as String? ?? '—',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['diagnostic'] as String? ?? '—',
                                            style: const TextStyle(fontSize: 12),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 2,
                                          ),
                                          if ((item['cim11_code'] as String?)
                                                  ?.isNotEmpty ==
                                              true)
                                            Text(
                                              'CIM-11: ${item['cim11_code']}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Column(
                                        children: [
                                          Text(
                                            '${(conf * 100).toStringAsFixed(0)}%',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: _confColor(conf),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          LinearProgressIndicator(
                                            value: conf.clamp(0.0, 1.0).toDouble(),
                                            color: _confColor(conf),
                                            backgroundColor: Colors.grey.shade200,
                                            minHeight: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _reviewColor(level).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          _reviewLabel(level),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: _reviewColor(level),
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        date,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 96,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          if ((item['patient_id'] as String?)
                                                  ?.isNotEmpty ==
                                              true)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.visibility_outlined,
                                                size: 18,
                                              ),
                                              tooltip: 'Voir rapports EEG',
                                              onPressed: () {
                                                context.push(
                                                  '/eeg/rapports/${item['patient_id']}',
                                                );
                                              },
                                            ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.picture_as_pdf,
                                              size: 18,
                                              color: Colors.red,
                                            ),
                                            tooltip: 'Télécharger PDF',
                                            onPressed: rapportId.isEmpty
                                                ? null
                                                : () => _exportPdf(rapportId),
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
                      ],
                    ),
    );
  }
}
