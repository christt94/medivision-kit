import 'package:flutter/material.dart';
import '../../core/api_client.dart';

class EegInterpretationScreen extends StatefulWidget {
  final String rapportId;
  final Map<String, dynamic> rapportData;
  final Map<String, dynamic> rawResult;

  const EegInterpretationScreen({
    super.key,
    required this.rapportId,
    required this.rapportData,
    required this.rawResult,
  });

  @override
  State<EegInterpretationScreen> createState() =>
      _EegInterpretationScreenState();
}

class _EegInterpretationScreenState extends State<EegInterpretationScreen> {
  static const teal = Color(0xFF01696f);
  static const red = Color(0xFFc0392b);
  static const orange = Color(0xFFe67e22);
  static const green = Color(0xFF43a047);
  static const blue = Color(0xFF1e88e5);
  static const purple = Color(0xFF8e24aa);

  late String _reviewLevel;
  late TextEditingController _conduiteCtrl;
  bool _saving = false;
  bool _exportingPdf = false;
  String? _error;

  Map<String, dynamic> get _diag =>
      Map<String, dynamic>.from(widget.rawResult['diagnostic'] as Map? ?? {});
  Map<String, dynamic> get _bandes =>
      Map<String, dynamic>.from(widget.rawResult['bandes'] as Map? ?? {});
  Map<String, dynamic> get _meta =>
      Map<String, dynamic>.from(widget.rawResult['meta'] as Map? ?? {});

  @override
  void initState() {
    super.initState();
    _reviewLevel = (widget.rapportData['review_level'] as String? ?? 'AUTO').trim();
    _conduiteCtrl = TextEditingController(
      text: (widget.rapportData['conduite'] as String? ??
              _diag['description'] as String? ??
              '')
          .trim(),
    );
  }

  @override
  void dispose() {
    _conduiteCtrl.dispose();
    super.dispose();
  }

  Color _diagColor(String label) {
    switch (label) {
      case 'Epilepsy':
        return red;
      case 'Sleep_REM':
        return orange;
      case 'Sleep_N3':
        return purple;
      case 'Sleep_N1':
      case 'Sleep_N2':
        return blue;
      case 'Normal':
        return green;
      default:
        return teal;
    }
  }

  Color _confColor(double conf) {
    if (conf >= 88) return green;
    if (conf >= 65) return orange;
    return red;
  }

  Color _reviewColor(String review) {
    switch (review) {
      case 'VALIDATED':
        return green;
      case 'REVIEW':
        return orange;
      default:
        return teal;
    }
  }

  String _reviewLabel(String review) {
    switch (review) {
      case 'VALIDATED':
        return 'VALIDÉ';
      case 'REVIEW':
        return 'À REVOIR';
      default:
        return 'AUTO';
    }
  }

  Future<void> _saveInterpretation() async {
    if (mounted) {
      setState(() {
        _saving = true;
        _error = null;
      });
    }
    try {
      await ApiClient.patch(
        '/eeg/rapports/${widget.rapportId}',
        {
          'review_level': _reviewLevel,
          'conduite': _conduiteCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rapport EEG mis à jour')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportPdf() async {
    if (mounted) {
      setState(() {
        _exportingPdf = true;
        _error = null;
      });
    }
    try {
      await ApiClient.downloadPdf(
        '/eeg/export-pdf',
        fields: {'rapport_id': widget.rapportId},
        fileName: 'rapport_eeg_${widget.rapportId.substring(0, 8)}.pdf',
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  List<Map<String, String>> _diffsFor(String label) {
    switch (label) {
      case 'Epilepsy':
        return [
          {
            'name': 'Épilepsie focale',
            'cim': '8A61.0',
            'note': 'Décharges focales unilatérales'
          },
          {
            'name': 'État de mal épileptique',
            'cim': '8A62',
            'note': 'Crises prolongées'
          },
        ];
      case 'Sleep_REM':
        return [
          {
            'name': 'Trouble comportemental REM',
            'cim': '7B01',
            'note': 'Polysomnographie recommandée'
          },
        ];
      default:
        return [
          {
            'name': 'Artefact de mouvement',
            'cim': '—',
            'note': 'Vérifier la qualité du tracé'
          },
          {
            'name': 'Somnolence physiologique',
            'cim': '—',
            'note': 'Corréler au contexte clinique'
          },
        ];
    }
  }

  List<Map<String, String>> _prescriptionsFor(String label) {
    if (label != 'Epilepsy') return [];
    return [
      {
        'intention': '1re intention',
        'dci': 'Carbamazépine',
        'atc': 'N03AF01',
        'posologie': '200 mg 2×/jour puis adaptation progressive',
        'surveillance': 'NFS, bilan hépatique, natrémie',
      },
      {
        'intention': '2e intention',
        'dci': 'Lamotrigine',
        'atc': 'N03AX09',
        'posologie': '25 mg/jour puis titration lente',
        'surveillance': 'Rash cutané, bilan hépatique',
      },
      {
        'intention': '3e intention',
        'dci': 'Lévétiracétam',
        'atc': 'N03AX14',
        'posologie': '500 mg 2×/jour puis adaptation',
        'surveillance': 'Tolérance neuropsychiatrique, créatinine',
      },
    ];
  }

  List<Map<String, String>> _bilansFor(String label) {
    if (label == 'Epilepsy') {
      return [
        {
          'priorite': 'STAT',
          'nom': 'Glycémie capillaire',
          'loinc': '2345-7',
          'indication': 'Éliminer une hypoglycémie',
        },
        {
          'priorite': 'STAT',
          'nom': 'Ionogramme sanguin',
          'loinc': '24326-1',
          'indication': 'Trouble hydro-électrolytique',
        },
        {
          'priorite': 'URGENT',
          'nom': 'IRM cérébrale',
          'loinc': '36643-5',
          'indication': 'Recherche de lésion structurelle',
        },
      ];
    }
    return [
      {
        'priorite': 'ROUTINE',
        'nom': 'EEG de contrôle',
        'loinc': '18107-6',
        'indication': 'Surveillance évolutive',
      },
    ];
  }

  List<Map<String, String>> _interactionsFor(String label) {
    if (label != 'Epilepsy') return [];
    return [
      {
        'niveau': 'MAJEURE',
        'paire': 'Carbamazépine + Lamotrigine',
        'effet': 'Diminution de l’exposition à la lamotrigine',
        'conduite': 'Adapter la posologie et surveiller',
      },
      {
        'niveau': 'MODÉRÉE',
        'paire': 'Lévétiracétam + Carbamazépine',
        'effet': 'Majorations possibles des effets SNC',
        'conduite': 'Surveillance clinique',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final diag = _diag;
    final bandes = _bandes;
    final meta = _meta;

    final label = diag['label'] as String? ?? 'Normal';
    final labelFr = diag['label_fr'] as String? ?? label;
    final cim11 = diag['cim11'] as String? ?? '—';
    final conf = (diag['confiance'] as num?)?.toDouble() ?? 0.0;
    final desc = diag['description'] as String? ?? '';
    final patientName = widget.rapportData['patient_name'] as String? ??
        widget.rapportData['patient_id'] as String? ??
        '—';
    final createdAt = widget.rapportData['created_at'] as String? ?? '';
    final dColor = _diagColor(label);

    final diffs = _diffsFor(label);
    final prescriptions = _prescriptionsFor(label);
    final bilans = _bilansFor(label);
    final interactions = _interactionsFor(label);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Interprétation EEG'),
        backgroundColor: teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _exportingPdf ? null : _exportPdf,
            icon: _exportingPdf
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
            label: const Text('PDF', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: dColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DIAGNOSTIC PRINCIPAL',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    labelFr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'CIM-11 : $cim11',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (desc.isNotEmpty)
                    Text(
                      desc,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(
                  label: 'Confiance',
                  value: '${conf.toStringAsFixed(1)}%',
                  color: _confColor(conf),
                ),
                _MetricCard(
                  label: 'Canaux',
                  value: '${meta['nb_canaux'] ?? '—'}',
                  color: teal,
                ),
                _MetricCard(
                  label: 'Fréquence',
                  value: '${meta['sfreq'] ?? '—'} Hz',
                  color: blue,
                ),
                _MetricCard(
                  label: 'Durée',
                  value: '${meta['duree_s'] ?? '—'} s',
                  color: purple,
                ),
                _MetricCard(
                  label: 'Mode',
                  value: '${meta['mode'] ?? '—'}',
                  color: green,
                ),
                _MetricCard(
                  label: 'Validation',
                  value: _reviewLabel(_reviewLevel),
                  color: _reviewColor(_reviewLevel),
                ),
              ],
            ),

            const SizedBox(height: 16),
            _SectionCard(
              title: 'Patient et signal',
              child: Column(
                children: [
                  _InfoRow('Patient', patientName),
                  _InfoRow('Référence', widget.rapportId.substring(0, 8).toUpperCase()),
                  _InfoRow('Date', createdAt.isNotEmpty ? createdAt.substring(0, 10) : '—'),
                  _InfoRow('Fichier', meta['fichier'] as String? ?? '—'),
                ],
              ),
            ),

            const SizedBox(height: 12),
            _SectionCard(
              title: 'Validation clinique',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: _reviewLevel,
                    decoration: const InputDecoration(
                      labelText: 'Statut de validation',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'AUTO', child: Text('AUTO')),
                      DropdownMenuItem(value: 'REVIEW', child: Text('À REVOIR')),
                      DropdownMenuItem(value: 'VALIDATED', child: Text('VALIDÉ')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _reviewLevel = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _conduiteCtrl,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Conduite clinique',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _saveInterpretation,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Enregistrer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: teal,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            _SectionCard(
              title: 'Bandes spectrales',
              child: Column(
                children: [
                  _BandValueRow('δ Delta', bandes['delta']),
                  _BandValueRow('θ Theta', bandes['theta']),
                  _BandValueRow('α Alpha', bandes['alpha']),
                  _BandValueRow('β Beta', bandes['beta']),
                  _BandValueRow('γ Gamma', bandes['gamma']),
                ],
              ),
            ),

            const SizedBox(height: 12),
            _SectionCard(
              title: 'Diagnostics différentiels',
              child: Column(
                children: diffs
                    .map(
                      (d) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          d['name'] ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('CIM-11: ${d['cim']} • ${d['note']}'),
                      ),
                    )
                    .toList(),
              ),
            ),

            const SizedBox(height: 12),
            _SectionCard(
              title: 'Prescription neurologique',
              child: prescriptions.isEmpty
                  ? const Text('Aucune prescription médicamenteuse indiquée.')
                  : Column(
                      children: prescriptions
                          .map(
                            (p) => Card(
                              elevation: 0,
                              color: Colors.grey.shade50,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                title: Text(
                                  '${p['intention']} — ${p['dci']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  'ATC: ${p['atc']}\n'
                                  'Posologie: ${p['posologie']}\n'
                                  'Surveillance: ${p['surveillance']}',
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),

            const SizedBox(height: 12),
            _SectionCard(
              title: 'Bilan biologique',
              child: Column(
                children: bilans
                    .map(
                      (b) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${b['priorite']} — ${b['nom']}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('LOINC ${b['loinc']} • ${b['indication']}'),
                      ),
                    )
                    .toList(),
              ),
            ),

            const SizedBox(height: 12),
            _SectionCard(
              title: 'Interactions médicamenteuses',
              child: interactions.isEmpty
                  ? const Text('Aucune interaction médicamenteuse détectée.')
                  : Column(
                      children: interactions
                          .map(
                            (it) => Card(
                              elevation: 0,
                              color: (it['niveau'] == 'MAJEURE' ? red : orange)
                                  .withOpacity(0.08),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                title: Text(
                                  '${it['niveau']} — ${it['paire']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  'Effet: ${it['effet']}\nConduite: ${it['conduite']}',
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _BandValueRow extends StatelessWidget {
  final String label;
  final dynamic value;

  const _BandValueRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final numValue = (value as num?)?.toDouble() ?? 0.0;
    final progress = (numValue.isFinite && numValue >= 0)
        ? (numValue > 1.0 ? numValue / 100.0 : numValue).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF01696f)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              numValue.toStringAsExponential(2),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}