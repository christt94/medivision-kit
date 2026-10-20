import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api_client.dart';
import '../../widgets/ecg_grid_chart.dart';
import '../../services/pdf_report_service.dart';
import '../patients/patient_detail_screen.dart';

class EcgUploadScreen extends StatefulWidget {
  final String? patientId;
  final String? nom;
  final String? prenom;
  final String? age;
  final String? sexe;
  final String? indication;
  const EcgUploadScreen({
    super.key,
    this.patientId,
    this.nom,
    this.prenom,
    this.age,
    this.sexe,
    this.indication,
  });
  @override State<EcgUploadScreen> createState() => _State();
}

class _State extends State<EcgUploadScreen> {
  Uint8List? _fileBytes;
  String?    _fileName;
  final _patientId  = TextEditingController();
  final _indication = TextEditingController();
  final _age        = TextEditingController();
  String _sexe    = 'M';
  bool   _loading = false;
  Map<String, dynamic>? _result;
  String? _error;

  // Patient search state
  final _searchCtrl         = TextEditingController();
  List<Map<String,dynamic>> _suggestions = [];
  Map<String,dynamic>?      _selectedPatient;
  bool _searching = false;

  // Resolved display name (covers all cases)
  String get _displayName {
    if (_selectedPatient != null) {
      final p = _selectedPatient!['prenom'] as String? ?? '';
      final n = _selectedPatient!['nom']    as String? ?? '';
      return '$p $n'.trim();
    }
    final p = widget.prenom ?? '';
    final n = widget.nom    ?? '';
    final full = '$p $n'.trim();
    if (full.isNotEmpty) return full;
    return 'Inconnu';
  }

  @override
  void initState() {
    super.initState();
    final pid = (widget.patientId ?? '').trim();
    if (pid.isNotEmpty) _patientId.text = pid;

    final sexe = (widget.sexe ?? 'M').trim();
    if (['M', 'F'].contains(sexe)) _sexe = sexe;

    _indication.text = (widget.indication ?? 'Bilan cardiaque').trim();

    final passedAge = (widget.age ?? '').trim();
    _age.text = (passedAge.isNotEmpty && passedAge != '—') ? passedAge : '';
  }

  @override
  void dispose() {
    _patientId.dispose(); _indication.dispose();
    _age.dispose(); _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchPatients(String query) async {
    if (query.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final all = await ApiClient.get('/patients/') as List;
      final q   = query.toLowerCase();
      setState(() {
        _suggestions = all
          .cast<Map<String,dynamic>>()
          .where((p) =>
            ('${p['prenom']} ${p['nom']}').toLowerCase().contains(q) ||
            ('${p['nom']} ${p['prenom']}').toLowerCase().contains(q))
          .toList();
        _searching = false;
      });
    } catch (_) {
      setState(() => _searching = false);
    }
  }

  void _selectPatient(Map<String,dynamic> p) {
    _searchCtrl.clear();
    setState(() {
      _selectedPatient = p;
      _patientId.text  = (p['id'] as String? ?? '').trim();
      _suggestions     = [];
    });
    // Auto-fill age
    final dob = p['date_naissance'] as String?;
    if (dob != null && dob.isNotEmpty && _age.text.isEmpty) {
      try {
        final parts = dob.substring(0, 10).split('-');
        final d   = DateTime(int.parse(parts[0]), int.parse(parts[1]),
                             int.parse(parts[2]));
        final now = DateTime.now();
        int age   = now.year - d.year;
        if (now.month < d.month ||
            (now.month == d.month && now.day < d.day)) {
          age--;
        }
        setState(() => _age.text = age.toString());
      } catch (_) {}
    }
    // Auto-fill sexe
    final sexe = p['sexe'] as String? ?? 'M';
    if (['M', 'F'].contains(sexe)) setState(() => _sexe = sexe);
  }

  Future<void> _pickFile() async {
    setState(() { _fileBytes = null; _fileName = null; _error = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'edf', 'bdf'],
        withData: true, allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _error = 'Aucun fichier sélectionné.'); return;
      }
      final file = result.files.first;
      if (file.bytes == null || file.bytes!.isEmpty) {
        setState(() => _error = 'Fichier vide. Réessayez.'); return;
      }
      setState(() { _fileBytes = file.bytes; _fileName = file.name; });
    } catch (e) {
      setState(() => _error = 'Erreur: $e');
    }
  }

  Future<void> _analyze() async {
    if (_patientId.text.trim().isEmpty) {
      setState(() => _error = '⚠️ Sélectionnez un patient avant d\'analyser.');
      return;
    }
    if (_age.text.trim().isEmpty) {
      setState(() => _error = '⚠️ Âge obligatoire.'); return;
    }
    if (_fileBytes == null) {
      setState(() => _error = '⚠️ Fichier ECG non chargé.'); return;
    }
    setState(() { _loading = true; _result = null; _error = null; });
    try {
      final res = await ApiClient.postMultipartBytes(
        '/ecg/analyze',
        {
          'patient_id':   _patientId.text.trim(),
          'patient_name': _displayName,
          'age':          _age.text.trim(),
          'sexe':         _sexe,
          'indication':   _indication.text.trim(),
        },
        'file', _fileBytes!, _fileName!,
      );
      // Inject resolved values so PDF and display are always correct
      res['patient_name'] = _displayName;
      res['patient_id']   = _patientId.text.trim();
      res.putIfAbsent('patient_context', () => <String, dynamic>{});
      final ctx = res['patient_context'] as Map;
      ctx['patient_id']   = _patientId.text.trim();
      ctx['patient_name'] = _displayName;
      ctx['age']          = _age.text.trim();
      ctx['sexe']         = _sexe;
      ctx['indication']   = _indication.text.trim();
      setState(() { _result = res; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileLoaded   = _fileBytes != null;
    final isPreFilled  = widget.patientId != null &&
                         widget.patientId!.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Analyse ECG')),
      body: Row(children: [

        // ── Left panel ────────────────────────────────────────────────────
        SizedBox(width: 380, child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [

            Text('Acquisition ECG',
              style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),

            // ── Patient block ─────────────────────────────────────────────
            if (isPreFilled) ...[
              // Opened from patient profile — show name banner
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                    .colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.3))),
                child: Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor:
                      Theme.of(context).colorScheme.primary,
                    child: Text(
                      _displayName.isNotEmpty
                        ? _displayName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(_displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(widget.patientId ?? '',
                      style: const TextStyle(
                        fontSize: 10, color: Colors.grey),
                      overflow: TextOverflow.ellipsis),
                  ])),
                  const Icon(Icons.lock_outline, size: 14,
                    color: Colors.grey),
                ])),
              const SizedBox(height: 16),

            ] else ...[
              // Standalone — show patient search
              Text('Patient *',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.6))),
              const SizedBox(height: 6),

              if (_selectedPatient != null) ...[
                // Selected patient chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300)),
                  child: Row(children: [
                    const Icon(Icons.check_circle,
                      color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Text(_displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(_patientId.text,
                        style: const TextStyle(
                          fontSize: 10, color: Colors.grey),
                        overflow: TextOverflow.ellipsis),
                    ])),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Changer de patient',
                      onPressed: () => setState(() {
                        _selectedPatient = null;
                        _patientId.clear();
                        _age.clear();
                      })),
                  ])),
              ] else ...[
                // Search input
                TextField(
                  controller: _searchCtrl,
                  onChanged: _searchPatients,
                  decoration: InputDecoration(
                    hintText: 'Rechercher par nom ou prénom...',
                    prefixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2)))
                      : const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _suggestions = []);
                          })
                      : null,
                    border: const OutlineInputBorder()),
                ),
                // Suggestions dropdown
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline
                          .withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8, offset: const Offset(0, 4))]),
                    child: ListView(
                      shrinkWrap: true,
                      children: _suggestions.map((p) => ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: Theme.of(context)
                            .colorScheme.primaryContainer,
                          child: Text(
                            (p['prenom'] as String? ?? '?')[0]
                              .toUpperCase(),
                            style: TextStyle(fontSize: 12,
                              color: Theme.of(context)
                                .colorScheme.onPrimaryContainer))),
                        title: Text(
                          '${p['prenom'] ?? ''} ${p['nom'] ?? ''}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Text(
                          '${p['sexe'] ?? '—'}  •  '
                          '${p['date_naissance'] ?? '—'}',
                          style: const TextStyle(fontSize: 11)),
                        onTap: () => _selectPatient(p),
                      )).toList())),
                if (_suggestions.isEmpty && _searchCtrl.text.length >= 2
                    && !_searching)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Aucun patient trouvé',
                      style: TextStyle(fontSize: 12,
                        color: Colors.grey.shade500))),
              ],
              const SizedBox(height: 16),
            ],

            // ── Age ───────────────────────────────────────────────────────
            TextField(
              controller: _age,
              decoration: const InputDecoration(
                labelText: 'Âge *',
                hintText: 'Ex: 45',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.cake_outlined)),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),

            // ── Sexe ──────────────────────────────────────────────────────
            DropdownButtonFormField<String>(
              initialValue: _sexe,
              decoration: const InputDecoration(
                labelText: 'Sexe',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wc)),
              items: const [
                DropdownMenuItem(value: 'M', child: Text('Masculin')),
                DropdownMenuItem(value: 'F', child: Text('Féminin')),
              ],
              onChanged: (v) => setState(() => _sexe = v!),
            ),
            const SizedBox(height: 12),

            // ── Indication ────────────────────────────────────────────────
            TextField(
              controller: _indication,
              decoration: const InputDecoration(
                labelText: 'Indication',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes)),
            ),
            const SizedBox(height: 24),

            // ── File picker ───────────────────────────────────────────────
            OutlinedButton.icon(
              icon: Icon(
                fileLoaded ? Icons.check_circle : Icons.upload_file,
                color: fileLoaded ? Colors.green : null),
              label: Text(
                fileLoaded ? _fileName! : 'Sélectionner CSV / EDF',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fileLoaded ? Colors.green : null)),
              onPressed: _pickFile,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: BorderSide(
                  color: fileLoaded ? Colors.green : Colors.grey)),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Icon(
                fileLoaded ? Icons.circle : Icons.radio_button_unchecked,
                size: 10,
                color: fileLoaded ? Colors.green : Colors.grey),
              const SizedBox(width: 6),
              Text(
                fileLoaded
                  ? '${(_fileBytes!.length/1024).toStringAsFixed(1)} KB chargés'
                  : 'Aucun fichier chargé',
                style: TextStyle(fontSize: 11,
                  color: fileLoaded ? Colors.green : Colors.grey)),
            ]),

            // ── Error ─────────────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200)),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                    color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!,
                    style: const TextStyle(
                      color: Colors.red, fontSize: 12))),
                ])),
            ],
            const SizedBox(height: 16),

            // ── Analyze button ────────────────────────────────────────────
            FilledButton.icon(
              icon: _loading
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.analytics),
              label: Text(_loading ? 'Analyse...' : 'Analyser'),
              onPressed: (_loading || !fileLoaded) ? null : _analyze,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48)),
            ),
          ]),
        )),

        const VerticalDivider(width: 1),

        // ── Right panel ───────────────────────────────────────────────────
        Expanded(child: _result == null
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.monitor_heart_outlined,
                size: 80, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text('Le rapport apparaîtra ici après analyse',
                style: TextStyle(
                  color: Colors.grey.shade400, fontSize: 16)),
            ]))
          : _ReportView(
              result:      _result!,
              fileBytes:   _fileBytes!,
              patientData: _selectedPatient ??
                (widget.patientId != null ? {
                  'id':     widget.patientId,
                  'nom':    widget.nom    ?? '',
                  'prenom': widget.prenom ?? '',
                  'sexe':   widget.sexe   ?? 'M',
                  'date_naissance': null,
                } : null),
            )),
      ]),
    );
  }
}

// ── Report View ───────────────────────────────────────────────────────────────
class _ReportView extends StatelessWidget {
  final Map<String, dynamic>  result;
  final Uint8List             fileBytes;
  final Map<String,dynamic>?  patientData;
  const _ReportView({
    required this.result,
    required this.fileBytes,
    this.patientData,
  });

  @override
  Widget build(BuildContext context) {
    final f           = result['findings']             as Map<String,dynamic>? ?? {};
    final dp          = result['diagnostic_principal'] as Map<String,dynamic>? ?? {};
    final cs          = Theme.of(context).colorScheme;
    final confidence  = (f['confidence'] as num?)?.toDouble() ?? 0;
    final confColor   = confidence >= 0.88 ? Colors.green
                      : confidence >= 0.65 ? Colors.orange : Colors.red;
    final reviewLevel = result['review_level'] as String? ?? '—';
    final reviewColor = reviewLevel == 'AUTO'             ? Colors.green
                      : reviewLevel == 'REVIEW_REQUIRED'  ? Colors.orange
                      : Colors.red;
    final diffDx  = result['diagnostics_differentiels'] as List? ?? [];
    final examens = result['examens_complementaires']   as List? ?? [];
    final ctx     = result['patient_context']           as Map?  ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header row
        Row(children: [
          Expanded(child: Text('Compte rendu ECG',
            style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold))),
          Chip(
            label: Text(reviewLevel,
              style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white)),
            backgroundColor: reviewColor),
          const SizedBox(width: 8),
          // ── VIEW PATIENT button ───────────────────────────────────────
          if (patientData != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.person, size: 16),
              label: const Text('Voir le patient',
                style: TextStyle(fontSize: 12)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) =>
                  PatientDetailScreen(
                    patient: Map<String,dynamic>.from(patientData!)))),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Télécharger PDF',
            color: Colors.red.shade700,
            onPressed: () =>
              PdfReportService.downloadReport(context, result),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Patient : ${result['patient_name'] ?? '—'}',
          style: TextStyle(fontSize: 13,
            fontWeight: FontWeight.w600, color: cs.primary)),
        if ((ctx['age'] as String?) != null)
          Text(
            'Âge : ${ctx['age']} ans  •  '
            'Sexe : ${ctx['sexe'] ?? '—'}  •  '
            '${ctx['indication'] ?? ''}',
            style: TextStyle(
              fontSize: 11, color: cs.onSurfaceVariant)),
        Text('ID: ${result['report_id'] ?? '—'}',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        Text('Généré: ${result['generated_at'] ?? '—'}',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 24),

        // Diagnostic principal
        Card(color: cs.primaryContainer, child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Diagnostic principal',
              style: TextStyle(fontWeight: FontWeight.bold,
                color: cs.onPrimaryContainer)),
            const SizedBox(height: 8),
            Text(dp['libelle'] ?? '—',
              style: TextStyle(fontSize: 20,
                fontWeight: FontWeight.bold,
                color: cs.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text('CIM-11: ${dp['cim11_code'] ?? '—'}',
              style: TextStyle(
                color: cs.onPrimaryContainer, fontSize: 13)),
            const SizedBox(height: 4),
            Text(dp['description'] ?? '',
              style: TextStyle(
                color: cs.onPrimaryContainer, fontSize: 12)),
          ]))),
        const SizedBox(height: 16),

        // Metrics
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Paramètres & confiance IA',
              style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              Text('${(confidence*100).toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 28,
                  fontWeight: FontWeight.bold, color: confColor)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text('Confiance — ${f['model_used'] ?? '—'}',
                  style: const TextStyle(
                    fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: confidence, color: confColor,
                  backgroundColor: Colors.grey.shade200,
                  minHeight: 8),
              ])),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 8, children: [
              _Param('FC',          '${f['heart_rate_bpm'] ?? '—'} bpm'),
              _Param('Dérivations', '${f['n_channels']     ?? '—'}'),
              _Param('Durée',       '${f['duration_sec']   ?? '—'}s'),
              _Param('PR',          '${f['pr_interval_ms'] ?? '—'} ms'),
              _Param('QRS',         '${f['qrs_duration_ms']?? '—'} ms'),
              _Param('QT',          '${f['qt_interval_ms'] ?? '—'} ms'),
              _Param('Classe IA',    f['predicted_class']  ?? '—'),
              _Param('ST changes',
                f['st_changes'] == true ? 'Oui ⚠️' : 'Non'),
            ]),
          ]))),
        const SizedBox(height: 16),

        // ECG chart
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: EcgGridChart(csvBytes: fileBytes))),
        const SizedBox(height: 16),

        // Differential diagnoses
        if (diffDx.isNotEmpty) ...[
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.compare_arrows,
                  size: 18, color: Colors.orange),
                SizedBox(width: 8),
                Text('Diagnostics différentiels',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              ...diffDx.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text(d['libelle'] ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    'CIM-11: ${d['cim11_code']}  •  ${d['condition']}',
                    style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600)),
                ]))),
            ]))),
          const SizedBox(height: 16),
        ],

        // Examens complémentaires
        if (examens.isNotEmpty) ...[
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.biotech, size: 18, color: Colors.teal),
                SizedBox(width: 8),
                Text('Examens complémentaires',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              ...examens.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text(e['libelle'] ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    'LOINC: ${e['loinc_code']}  •  ${e['indication']}',
                    style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600)),
                ]))),
            ]))),
          const SizedBox(height: 16),
        ],


        // Interactions médicamenteuses
        () {
          final ixs = result['interactions_medicamenteuses'] as List? ?? [];
          if (ixs.isEmpty) return const SizedBox.shrink();
          final sevColor = {
            'MAJEURE':  Colors.red.shade700,
            'MODEREE':  Colors.orange.shade700,
            'MINEURE':  Colors.blue.shade600,
          };
          final sevIcon = {
            'MAJEURE':  Icons.dangerous,
            'MODEREE':  Icons.warning_amber,
            'MINEURE':  Icons.info_outline,
          };
          return Column(children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.red.shade200)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Row(children: [
                    Icon(Icons.warning_rounded,
                      color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text('Interactions médicamenteuses',
                      style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15,
                        color: Colors.red.shade800)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10)),
                      child: Text('\${ixs.length} détectée(s)',
                        style: TextStyle(fontSize: 10,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold))),
                  ]),
                  const SizedBox(height: 12),
                  ...ixs.map((ix) {
                    final sev   = ix['severite'] as String? ?? 'MINEURE';
                    final color = sevColor[sev] ?? Colors.grey;
                    final icon  = sevIcon[sev]  ?? Icons.info_outline;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: color.withValues(alpha: 0.3))),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Icon(icon, size: 18, color: color),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(6)),
                              child: Text(sev,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold))),
                            const SizedBox(width: 8),
                            Expanded(child: Text(
                              ix['libelle'] as String? ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12))),
                          ]),
                          const SizedBox(height: 4),
                          Text(ix['effet'] as String? ?? '',
                            style: TextStyle(fontSize: 11,
                              color: Colors.grey.shade700)),
                          const SizedBox(height: 4),
                          Row(children: [
                            Icon(Icons.medical_services_outlined,
                              size: 11, color: color),
                            const SizedBox(width: 4),
                            Expanded(child: Text(
                              ix['conduite'] as String? ?? '',
                              style: TextStyle(fontSize: 11,
                                color: color,
                                fontWeight: FontWeight.w500))),
                          ]),
                        ])),
                      ]));
                  }),
                ]))),
            const SizedBox(height: 16),
          ]);
        }(),
        // Prescription médicale
        () {
          final rx = result['prescription_medicale'] as List? ?? [];
          if (rx.isEmpty) return const SizedBox.shrink();
          final rankColors = [
            const Color(0xFF1B5E20),
            const Color(0xFF0D47A1),
            const Color(0xFF4A148C),
          ];
          final rankBg = [
            const Color(0xFFF9FFF9),
            const Color(0xFFF0F4FF),
            const Color(0xFFFAF0FF),
          ];
          final rankLabels = [
            '1re intention',
            '2e intention',
            '3e intention',
          ];
          return Column(children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.green.shade300)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Row(children: [
                    Icon(Icons.medication,
                      color: Colors.green.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text('Prescription médicale',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.green.shade800)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12)),
                      child: Text('OMS — LME 23e éd.',
                        style: TextStyle(fontSize: 10,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    '⚠️ Ordonnance à valider et signer par un médecin habilité.',
                    style: TextStyle(fontSize: 11,
                      color: Colors.orange.shade700,
                      fontStyle: FontStyle.italic)),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: rx.asMap().entries.map((entry) {
                      final i = entry.key;
                      final m = entry.value as Map<String, dynamic>;
                      if (i > 2) return const SizedBox.shrink();
                      final ci = (m['contre_indications'] as List? ?? [])
                        .join(', ');
                      return Expanded(child: Container(
                        margin: EdgeInsets.only(
                          left: i == 0 ? 0 : 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: rankBg[i],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: rankColors[i].withValues(alpha: 0.5),
                            width: 1.5)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 4),
                            decoration: BoxDecoration(
                              color: rankColors[i],
                              borderRadius: BorderRadius.circular(6)),
                            child: Text(rankLabels[i],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11))),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            Expanded(child: Text(
                              m['dci'] as String? ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13))),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                m['atc_code'] as String? ?? '',
                                style: TextStyle(fontSize: 9,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w600))),
                          ]),
                          Text(
                            m['nom_commercial_exemple'] as String? ?? '',
                            style: TextStyle(fontSize: 11,
                              color: Colors.grey.shade600)),
                          Text(
                            m['classe'] as String? ?? '',
                            style: TextStyle(fontSize: 10,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic)),
                          const Divider(height: 12),
                          _PrescRow(Icons.local_pharmacy_outlined,
                            'Posologie',
                            m['posologie'] as String? ?? '—',
                            rankColors[i]),
                          _PrescRow(Icons.schedule,
                            'Durée',
                            m['duree'] as String? ?? '—',
                            rankColors[i]),
                          _PrescRow(Icons.info_outline,
                            'Indication',
                            m['indication_specifique'] as String? ?? '—',
                            rankColors[i]),
                          if (ci.isNotEmpty)
                            _PrescRow(Icons.block,
                              'Contre-ind.',
                              ci,
                              Colors.red.shade700),
                          _PrescRow(Icons.monitor_heart_outlined,
                            'Surveillance',
                            m['surveillance'] as String? ?? '—',
                            Colors.orange.shade700),
                        ])));
                    }).toList()),
                ]))),
            const SizedBox(height: 16),
          ]);
        }(),
        // Conduite à tenir
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.medical_services, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Conduite à tenir',
                style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            Text(result['conduite_a_tenir'] ?? '—'),
          ]))),
        const SizedBox(height: 24),

        // Disclaimer
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200)),
          child: const Row(children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Rapport généré par IA. Validation obligatoire par un '
              'clinicien qualifié avant tout acte thérapeutique.',
              style: TextStyle(color: Colors.orange, fontSize: 12))),
          ])),
        const SizedBox(height: 16),
      ]),
    );
  }
}

class _Param extends StatelessWidget {
  final String label, value;
  const _Param(this.label, this.value);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8)),
    child: Column(children: [
      Text(label,
        style: const TextStyle(fontSize: 10, color: Colors.grey)),
      Text(value,
        style: const TextStyle(fontWeight: FontWeight.bold)),
    ]));
}

class _PrescRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;
  const _PrescRow(this.icon, this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        SizedBox(width: 72,
          child: Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.grey))),
        Expanded(child: Text(value,
          style: TextStyle(
            fontSize: 10, color: color,
            fontWeight: FontWeight.w500))),
      ]));
  }
}

