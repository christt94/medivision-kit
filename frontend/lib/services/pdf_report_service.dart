import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;

class PdfReportService {
  static const String _base = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api',
  );

  static Future<void> downloadReport(
    BuildContext context,
    Map<String, dynamic> result,
  ) async {
    final edited = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RevisionDialog(result: result),
    );
    if (edited == null) return;

    final reportId = edited['report_id'] as String?;
    if (reportId != null && reportId.isNotEmpty) {
      try {
        await http.patch(
          Uri.parse('$_base/ecg/rapports/$reportId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            if (edited['diagnostic_principal'] != null)
              'diagnostic_libelle': edited['diagnostic_principal']['libelle'],
            'conduite_a_tenir':           edited['conduite_a_tenir']           ?? '',
            'notes_clinicien':            edited['notes_clinicien']            ?? '',
            'valide_par':                 edited['valide_par']                 ?? '',
            'date_validation':            edited['date_validation']            ?? '',
            'statut':                     edited['statut']                     ?? '',
            'prescription_medicale':      edited['prescription_medicale'],
            'examens_complementaires':    edited['examens_complementaires'],
            'interactions_medicamenteuses': edited['interactions_medicamenteuses'],
          }),
        );
      } catch (e) {
        debugPrint('Patch failed: $e');
      }
    }

    final csvB64  = edited['raw_csv']      as String? ?? '';
    final patient = edited['patient_name'] as String? ?? 'Inconnu';
    final recDate = edited['record_date']  as String?
        ?? DateTime.now().toIso8601String().substring(0, 10);

    final response = await http.post(
      Uri.parse('$_base/ecg/export-pdf'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'csv_b64':      csvB64,
        'result':       edited,
        'patient_name': patient,
        'record_date':  recDate,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Export PDF échoué : ${response.statusCode}');
    }

    if (kIsWeb) {
      final blob   = html.Blob([response.bodyBytes], 'application/pdf');
      final url    = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', 'ecg_report.pdf')
        ..click();
      html.Url.revokeObjectUrl(url);
      anchor.remove();
    }
  }
}

// ── Revision Dialog ───────────────────────────────────────────────────────────
class _RevisionDialog extends StatefulWidget {
  final Map<String, dynamic> result;
  const _RevisionDialog({required this.result});
  @override State<_RevisionDialog> createState() => _RevisionDialogState();
}

class _RevisionDialogState extends State<_RevisionDialog>
    with SingleTickerProviderStateMixin {

  late TabController _tabs;

  // ── Tab 1 — Rapport ───────────────────────────────────────────────
  late final TextEditingController _diagnostic;
  late final TextEditingController _conduite;
  late final TextEditingController _notes;
  late final TextEditingController _validePar;
  late final TextEditingController _dateVal;
  String _statut = 'BROUILLON';

  // ── Tab 2 — Prescription ──────────────────────────────────────────
  late List<Map<String, dynamic>> _prescription;

  // ── Tab 3 — Bilan biologique ──────────────────────────────────────
  late List<Map<String, dynamic>> _bilan;

  // ── Tab 4 — Interactions ─────────────────────────────────────────
  late List<Map<String, dynamic>> _interactions;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);

    final dp = widget.result['diagnostic_principal'] as Map? ?? {};
    _diagnostic = TextEditingController(text: dp['libelle']               as String? ?? '');
    _conduite   = TextEditingController(text: widget.result['conduite_a_tenir'] as String? ?? '');
    _notes      = TextEditingController(text: widget.result['notes_clinicien']  as String? ?? '');
    _validePar  = TextEditingController(text: widget.result['valide_par']       as String? ?? '');
    _dateVal    = TextEditingController(
        text: widget.result['date_validation'] as String?
            ?? DateTime.now().toIso8601String().substring(0, 10));
    _statut = widget.result['statut'] as String? ?? 'BROUILLON';

    _prescription = (widget.result['prescription_medicale'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();

    _bilan = (widget.result['examens_complementaires'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();

    _interactions = (widget.result['interactions_medicamenteuses'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _diagnostic.dispose(); _conduite.dispose();
    _notes.dispose(); _validePar.dispose(); _dateVal.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _edited {
    final copy = Map<String, dynamic>.from(widget.result);
    final dp   = Map<String, dynamic>.from(
        (copy['diagnostic_principal'] as Map? ?? {}));
    dp['libelle']                        = _diagnostic.text.trim();
    copy['diagnostic_principal']         = dp;
    copy['conduite_a_tenir']             = _conduite.text.trim();
    copy['notes_clinicien']              = _notes.text.trim();
    copy['valide_par']                   = _validePar.text.trim();
    copy['date_validation']              = _dateVal.text.trim();
    copy['statut']                       = _statut;
    copy['prescription_medicale']        = _prescription;
    copy['examens_complementaires']      = _bilan;
    copy['interactions_medicamenteuses'] = _interactions;
    return copy;
  }

  // ── Tab 1 — Rapport de base ───────────────────────────────────────
  Widget _buildTabRapport() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Diagnostic principal', Icons.monitor_heart,
          const Color(0xFF0D47A1)),
      const SizedBox(height: 6),
      TextFormField(
        controller: _diagnostic,
        decoration: const InputDecoration(
          border: OutlineInputBorder(), hintText: 'Ex: Rythme sinusal normal'),
        maxLines: 2),
      const SizedBox(height: 16),

      _sectionTitle('Conduite à tenir', Icons.medical_services,
          Colors.red.shade700),
      const SizedBox(height: 6),
      TextFormField(
        controller: _conduite,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'Instructions cliniques...'),
        maxLines: 3),
      const SizedBox(height: 16),

      _sectionTitle('Notes clinicien', Icons.edit_note, Colors.teal),
      const SizedBox(height: 6),
      TextFormField(
        controller: _notes,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'Observations, commentaires libres...'),
        maxLines: 3),
      const SizedBox(height: 16),

      _sectionTitle('Statut du rapport', Icons.flag, Colors.orange),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: _statut,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem(value: 'BROUILLON',
            child: Row(children: [
              Icon(Icons.edit_note, size: 16, color: Colors.grey),
              SizedBox(width: 8), Text('Brouillon')])),
          DropdownMenuItem(value: 'VALIDE',
            child: Row(children: [
              Icon(Icons.check_circle, size: 16, color: Colors.green),
              SizedBox(width: 8), Text('Validé')])),
          DropdownMenuItem(value: 'EN_REVISION',
            child: Row(children: [
              Icon(Icons.pending, size: 16, color: Colors.orange),
              SizedBox(width: 8), Text('En révision')])),
        ],
        onChanged: (v) => setState(() => _statut = v!)),
      const SizedBox(height: 16),

      Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('Validé par', Icons.person,
              const Color(0xFF0D47A1)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _validePar,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Dr. Nom Prénom')),
        ])),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('Date de validation', Icons.calendar_today,
              const Color(0xFF0D47A1)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _dateVal,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'YYYY-MM-DD'),
            readOnly: true,
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(_dateVal.text) ?? DateTime.now(),
                firstDate: DateTime(2020), lastDate: DateTime(2030));
              if (d != null) {
                _dateVal.text = d.toIso8601String().substring(0, 10);
              }
            }),
        ])),
      ]),
    ]));

  // ── Tab 2 — Prescription ──────────────────────────────────────────
  Widget _buildTabPrescription() => ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: _prescription.length,
    itemBuilder: (_, i) {
      final m = _prescription[i];
      final rankColors = [
        const Color(0xFF1B5E20),
        const Color(0xFF0D47A1),
        const Color(0xFF4A148C),
      ];
      final color = i < 3 ? rankColors[i] : Colors.grey;
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withOpacity(0.4))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 12, backgroundColor: color,
                child: Text('${i+1}',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 11,
                    fontWeight: FontWeight.bold))),
              const SizedBox(width: 8),
              Expanded(child: Text(m['dci'] as String? ?? '',
                style: TextStyle(fontWeight: FontWeight.bold,
                  fontSize: 13, color: color))),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6)),
                child: Text(m['atc_code'] as String? ?? '',
                  style: TextStyle(fontSize: 10,
                    color: Colors.blue.shade700))),
            ]),
            const SizedBox(height: 10),
            _editField('Posologie', m['posologie'] as String? ?? '',
              (v) => setState(() => _prescription[i]['posologie'] = v)),
            _editField('Durée', m['duree'] as String? ?? '',
              (v) => setState(() => _prescription[i]['duree'] = v)),
            _editField('Indication', m['indication_specifique'] as String? ?? '',
              (v) => setState(() => _prescription[i]['indication_specifique'] = v)),
            _editField('Surveillance', m['surveillance'] as String? ?? '',
              (v) => setState(() => _prescription[i]['surveillance'] = v)),
          ])));
    });

  // ── Tab 3 — Bilan biologique ──────────────────────────────────────
  Widget _buildTabBilan() {
    final urgColors = {
      'STAT':    Colors.red.shade700,
      'URGENT':  Colors.orange.shade700,
      'ROUTINE': Colors.teal.shade700,
    };
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bilan.length,
      itemBuilder: (_, i) {
        final e     = _bilan[i];
        final urg   = e['urgence'] as String? ?? 'ROUTINE';
        final color = urgColors[urg] ?? Colors.teal;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: color.withOpacity(0.3))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6)),
                  child: Text(urg,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 10,
                      fontWeight: FontWeight.bold))),
                const SizedBox(width: 8),
                Expanded(child: Text(e['libelle'] as String? ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12))),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6)),
                  child: Text('LOINC ${e['loinc_code'] ?? ''}',
                    style: TextStyle(fontSize: 9,
                      color: Colors.blue.shade700))),
                if (e['jeune'] == true) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(6)),
                    child: Text('À jeun',
                      style: TextStyle(fontSize: 9,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.bold))),
                ],
              ]),
              const SizedBox(height: 8),
              _editField('Indication', e['indication'] as String? ?? '',
                (v) => setState(() => _bilan[i]['indication'] = v)),
              _editField('Valeur normale', e['valeur_normale'] as String? ?? '',
                (v) => setState(() => _bilan[i]['valeur_normale'] = v)),
            ])));
      });
  }

  // ── Tab 4 — Interactions ─────────────────────────────────────────
  Widget _buildTabInteractions() {
    if (_interactions.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.check_circle_outline,
          size: 48, color: Colors.green.shade300),
        const SizedBox(height: 12),
        Text('Aucune interaction détectée',
          style: TextStyle(color: Colors.green.shade600, fontSize: 14)),
      ]));
    }
    final sevColors = {
      'MAJEURE': Colors.red.shade700,
      'MODEREE': Colors.orange.shade700,
      'MINEURE': Colors.blue.shade600,
    };
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _interactions.length,
      itemBuilder: (_, i) {
        final ix    = _interactions[i];
        final sev   = ix['severite'] as String? ?? 'MINEURE';
        final color = sevColors[sev] ?? Colors.grey;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: color.withOpacity(0.4), width: 1.5)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8)),
                  child: Text(sev,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11))),
                const SizedBox(width: 10),
                Expanded(child: Text(ix['libelle'] as String? ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13))),
              ]),
              const SizedBox(height: 8),
              Text(ix['effet'] as String? ?? '',
                style: TextStyle(fontSize: 12,
                  color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              _editField('Conduite', ix['conduite'] as String? ?? '',
                (v) => setState(() => _interactions[i]['conduite'] = v),
                labelColor: color),
              _editField('Note clinicien',
                ix['notes_clinicien'] as String? ?? '',
                (v) => setState(() => _interactions[i]['notes_clinicien'] = v)),
            ])));
      });
  }

  Widget _sectionTitle(String text, IconData icon, Color color) =>
    Row(children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(
        fontWeight: FontWeight.bold, fontSize: 13, color: color)),
    ]);

  Widget _editField(String label, String initial,
      ValueChanged<String> onChanged, {Color? labelColor}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        initialValue: initial,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            fontSize: 11,
            color: labelColor ?? const Color(0xFF0D47A1)),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 8)),
        style: const TextStyle(fontSize: 12),
        maxLines: null));

  @override
  Widget build(BuildContext context) {
    final hasInteractions =
      (widget.result['interactions_medicamenteuses'] as List? ?? []).isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 760),
        child: Column(children: [

          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(children: [
              const Icon(Icons.rate_review, color: Color(0xFF0D47A1)),
              const SizedBox(width: 10),
              const Expanded(child: Text('Révision & Export PDF',
                style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold))),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context, null)),
            ])),

          // Tabs
          TabBar(
            controller: _tabs,
            labelStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            tabs: [
              const Tab(icon: Icon(Icons.article, size: 16),
                text: 'Rapport'),
              const Tab(icon: Icon(Icons.medication, size: 16),
                text: 'Prescription'),
              const Tab(icon: Icon(Icons.biotech, size: 16),
                text: 'Bilan Bio'),
              Tab(
                icon: Badge(
                  isLabelVisible: hasInteractions,
                  label: Text('${(widget.result['interactions_medicamenteuses']
                    as List? ?? []).length}'),
                  child: const Icon(Icons.warning_rounded, size: 16)),
                text: 'Interactions'),
            ]),

          const Divider(height: 1),

          // Tab content
          Expanded(child: TabBarView(
            controller: _tabs,
            children: [
              _buildTabRapport(),
              _buildTabPrescription(),
              _buildTabBilan(),
              _buildTabInteractions(),
            ])),

          const Divider(height: 1),

          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Annuler')),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('Enregistrer & Télécharger PDF'),
                onPressed: () => Navigator.pop(context, _edited)),
            ])),
        ]),
      ));
  }
}
