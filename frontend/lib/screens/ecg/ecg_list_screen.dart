import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../services/pdf_report_service.dart';

class EcgListScreen extends StatefulWidget {
  final String title;
  final String endpoint;
  final bool showRevisionBadge;

  const EcgListScreen({
    super.key,
    required this.title,
    required this.endpoint,
    this.showRevisionBadge = false,
  });

  @override
  State<EcgListScreen> createState() => _EcgListScreenState();
}

class _EcgListScreenState extends State<EcgListScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

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
        _items = data as List;
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
        return Colors.green;
      case 'REVIEW_REQUIRED':
        return Colors.orange;
      case 'EXPERT_ESCALATION':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _reviewLabel(String level) {
    switch (level) {
      case 'AUTO':
        return 'Auto';
      case 'REVIEW_REQUIRED':
        return 'Révision';
      case 'EXPERT_ESCALATION':
        return 'Expert';
      default:
        return level;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                            Icons.monitor_heart_outlined,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Aucun ECG trouvé',
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
                              const Spacer(),
                              if (widget.showRevisionBadge)
                                const Chip(
                                  label: Text(
                                    'Révision requise',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                  backgroundColor: Colors.orange,
                                  padding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          color: Theme.of(context).colorScheme.primary,
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
                              SizedBox(width: 80),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              final item = _items[i] as Map<String, dynamic>;
                              final conf =
                                  (item['confidence'] as num?)?.toDouble() ?? 0;
                              final level = item['review_level'] as String? ?? '—';
                              final raw = (item['created_at'] as String?) ?? '';
                              final date = raw.length >= 16
                                  ? raw.substring(0, 16).replaceAll('T', ' ')
                                  : raw;

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
                                            () {
                                              final n =
                                                  item['patient_name'] as String? ?? '';
                                              final p =
                                                  item['patient_id'] as String? ?? '';
                                              final isUuid = RegExp(
                                                r'^[0-9a-f-]{36}$',
                                              ).hasMatch(n);
                                              return (n.isEmpty || isUuid)
                                                  ? (p.length > 8
                                                      ? '${p.substring(0, 8)}…'
                                                      : p.isEmpty
                                                          ? '—'
                                                          : p)
                                                  : n;
                                            }(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '${item['age'] ?? '—'} ans  •  ${item['sexe'] ?? '—'}',
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
                                            item['diagnostic'] ?? '—',
                                            style: const TextStyle(fontSize: 12),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 2,
                                          ),
                                          if ((item['cim11_code'] as String?)
                                                  ?.isNotEmpty ??
                                              false)
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
                                            value: conf,
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
                                      width: 80,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          if ((item['patient_id'] as String?)
                                                  ?.isNotEmpty ??
                                              false)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.person_outline,
                                                size: 18,
                                              ),
                                              tooltip: 'Voir patient',
                                              onPressed: () {
                                                final raw2 = item['raw_json'];
                                                context.push(
                                                  '/patients/${item['patient_id']}',
                                                  extra: raw2 is Map<String, dynamic>
                                                      ? raw2
                                                      : <String, dynamic>{
                                                          'id': item['patient_id'],
                                                          'nom': '',
                                                          'prenom':
                                                              item['patient_name'] ?? '',
                                                        },
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
                                            onPressed: () {
                                              final raw2 = item['raw_json'];
                                              if (raw2 is Map<String, dynamic>) {
                                                PdfReportService.downloadReport(
                                                  context,
                                                  raw2,
                                                );
                                              }
                                            },
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
