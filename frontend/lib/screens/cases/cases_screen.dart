import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../models/clinical_case.dart';

class CasesScreen extends StatefulWidget {
  const CasesScreen({super.key});

  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  List<ClinicalCase> _cases = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiClient.get('/cases');
      _cases = (data as List)
          .map((item) => ClinicalCase.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openLogin() async {
    await context.push('/login');
    if (mounted) _load();
  }

  Future<void> _createCase() async {
    final patient = TextEditingController();
    final title = TextEditingController();
    final indication = TextEditingController();
    String priority = 'ROUTINE';
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouveau dossier clinique'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: patient, decoration: const InputDecoration(labelText: 'ID patient *')),
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Titre')),
            TextField(controller: indication, maxLines: 3, decoration: const InputDecoration(labelText: 'Indication')),
            DropdownButtonFormField<String>(
              initialValue: priority,
              decoration: const InputDecoration(labelText: 'Priorité'),
              items: const [
                DropdownMenuItem(value: 'ROUTINE', child: Text('Routine')),
                DropdownMenuItem(value: 'URGENT', child: Text('Urgent')),
                DropdownMenuItem(value: 'STAT', child: Text('Stat')),
              ],
              onChanged: (value) => setDialogState(() => priority = value ?? 'ROUTINE'),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () async {
              if (patient.text.trim().isEmpty) return;
              await ApiClient.post('/cases', {
                'patient_id': patient.text.trim(),
                'title': title.text.trim().isEmpty ? 'Clinical case' : title.text.trim(),
                'indication': indication.text.trim(),
                'priority': priority,
              });
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            }, child: const Text('Créer')),
          ],
        ),
      ),
    );
    patient.dispose(); title.dispose(); indication.dispose();
    if (created == true && mounted) _load();
  }

  Widget _errorView() {
    final needsLogin = (_error ?? '').contains('401') || (_error ?? '').contains('Authentification');
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(needsLogin ? Icons.lock_outline : Icons.error_outline, size: 48),
      const SizedBox(height: 12),
      Text(needsLogin ? 'Connectez-vous pour accéder aux dossiers.' : _error!, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: needsLogin ? _openLogin : _load, icon: Icon(needsLogin ? Icons.login : Icons.refresh), label: Text(needsLogin ? 'Se connecter' : 'Réessayer')),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dossiers cliniques'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _createCase, icon: const Icon(Icons.add), label: const Text('Nouveau dossier')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? _errorView() : _cases.isEmpty
          ? const Center(child: Text('Aucun dossier clinique.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: _cases.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = _cases[index];
                  return Card(child: ListTile(
                    leading: CircleAvatar(child: Icon(item.status == 'APPROVED' ? Icons.verified : Icons.folder_open)),
                    title: Text(item.title),
                    subtitle: Text('Patient: ${item.patientId}\n${item.priority} · ${item.status}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async { await context.push('/cases/${item.id}', extra: item); if (mounted) _load(); },
                  ));
                },
              ),
            ),
    );
  }
}

class CaseDetailScreen extends StatefulWidget {
  final String caseId;
  final ClinicalCase? initialCase;
  const CaseDetailScreen({super.key, required this.caseId, this.initialCase});

  @override
  State<CaseDetailScreen> createState() => _CaseDetailScreenState();
}

class _CaseDetailScreenState extends State<CaseDetailScreen> {
  ClinicalCase? _case;
  Map<String, dynamic>? _report;
  List<Map<String, dynamic>> _audit = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiClient.get('/cases/${widget.caseId}');
      _case = ClinicalCase.fromJson(Map<String, dynamic>.from(data as Map));
      final report = await ApiClient.get('/cases/${widget.caseId}/report');
      _report = Map<String, dynamic>.from(report as Map);
      final audit = await ApiClient.get('/cases/${widget.caseId}/audit');
      _audit = (audit as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _linkStudy() async {
    final id = TextEditingController();
    String type = 'ECG';
    final linked = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Lier un examen'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: type, items: const [
            DropdownMenuItem(value: 'ECG', child: Text('ECG')),
            DropdownMenuItem(value: 'EEG', child: Text('EEG')),
            DropdownMenuItem(value: 'IMAGING', child: Text('Imagerie')),
          ], onChanged: (value) => setState(() => type = value ?? 'ECG')),
          TextField(controller: id, decoration: const InputDecoration(labelText: 'ID de l’examen *')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(onPressed: () async {
            if (id.text.trim().isEmpty) return;
            await ApiClient.post('/cases/${widget.caseId}/studies', {'study_type': type, 'study_id': id.text.trim()});
            if (dialogContext.mounted) Navigator.pop(dialogContext, true);
          }, child: const Text('Lier')),
        ],
      ),
    ));
    id.dispose();
    if (linked == true && mounted) _load();
  }

  Future<void> _signoff(String decision) async {
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(decision == 'APPROVED' ? 'Approuver le dossier' : 'Demander une action'),
      content: TextField(controller: notes, maxLines: 5, decoration: const InputDecoration(labelText: 'Notes clinicien')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
        FilledButton(onPressed: () async {
          await ApiClient.post('/cases/${widget.caseId}/signoff', {'decision': decision, 'notes': notes.text.trim()});
          if (dialogContext.mounted) Navigator.pop(dialogContext, true);
        }, child: const Text('Enregistrer')),
      ],
    ));
    notes.dispose();
    if (confirmed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(appBar: AppBar(title: const Text('Dossier clinique')), body: Center(child: Text(_error!)));
    final item = _case!;
    final reportStudies = (_report?['studies'] as List<dynamic>? ?? const [])
        .map((study) => Map<String, dynamic>.from(study as Map)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(item.title), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Card(child: ListTile(leading: const Icon(Icons.person), title: Text('Patient ${item.patientId}'), subtitle: Text('${item.priority} · ${item.status}\n${item.indication}'))),
        const SizedBox(height: 16),
        Row(children: [Text('Examens liés', style: Theme.of(context).textTheme.titleLarge), const Spacer(), OutlinedButton.icon(onPressed: _linkStudy, icon: const Icon(Icons.link), label: const Text('Lier'))]),
        const SizedBox(height: 8),
        if (item.studies.isEmpty) const Text('Aucun examen lié.') else ...item.studies.map((study) => Card(child: ListTile(leading: const Icon(Icons.description_outlined), title: Text('${study['study_type']} — ${study['study_id']}'), subtitle: Text('Lié par ${study['linked_by'] ?? '—'}')))),
        const SizedBox(height: 20),
        Text('Rapport unifié', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (reportStudies.isEmpty) const Text('Ajoutez un examen pour construire le rapport.') else ...reportStudies.map((study) => Card(child: ListTile(
          leading: Icon(study['available'] == true ? Icons.analytics_outlined : Icons.warning_amber_outlined),
          title: Text('${study['study_type']} · ${study['status'] ?? '—'}'),
          subtitle: Text('${study['diagnostic'] ?? 'Aucun résultat textuel disponible.'}'),
        ))),
        const SizedBox(height: 20),
        Text('Revue clinicien', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 8, children: [
          FilledButton.icon(onPressed: () => _signoff('APPROVED'), icon: const Icon(Icons.verified), label: const Text('Approuver')),
          OutlinedButton.icon(onPressed: () => _signoff('CHANGES_REQUESTED'), icon: const Icon(Icons.edit_note), label: const Text('Demander corrections')),
          OutlinedButton.icon(onPressed: () => _signoff('REJECTED'), icon: const Icon(Icons.cancel_outlined), label: const Text('Rejeter')),
        ]),
        const SizedBox(height: 20),
        Text('Historique d’audit', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (_audit.isEmpty) const Text('Aucun événement enregistré.') else ..._audit.map((event) => ListTile(dense: true, leading: const Icon(Icons.history), title: Text('${event['action']}'), subtitle: Text('${event['created_at']}\n${event['details']}'))),
      ]),
    );
  }
}
