import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../screens/ecg/ecg_upload_screen.dart';
import '../../screens/eeg/eeg_upload_screen.dart';
import '../../screens/eeg/eeg_rapport_screen.dart';

class PatientDetailScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  const PatientDetailScreen({super.key, required this.patient});

  @override
  State<PatientDetailScreen> createState() => _PatientDetailState();
}

class _PatientDetailState extends State<PatientDetailScreen> {
  late Map<String, dynamic> _patient;
  List<dynamic> _rapports = [];
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _selectedRapport;

  @override
  void initState() {
    super.initState();
    _patient = Map<String, dynamic>.from(widget.patient);
    _loadRapports();
  }

  String _calculateAge(String? dob) {
    if (dob == null || dob.trim().isEmpty) return '';
    try {
      DateTime? d;
      final s = dob.trim();
      if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) {
        d = DateTime.parse(s.substring(0, 10));
      } else if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(s)) {
        final p = s.split('/');
        d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      }
      if (d == null) return '';
      final now = DateTime.now();
      int age = now.year - d.year;
      if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
        age--;
      }
      return age.toString();
    } catch (_) {
      return '';
    }
  }

  String get _ageDisplay {
    final c = _calculateAge(_patient['date_naissance'] as String?);
    return c.isNotEmpty ? '$c ans' : '— ans';
  }

  String get _fullName {
    final p = _patient['prenom'] as String? ?? '';
    final n = _patient['nom'] as String? ?? '';
    final full = '$p $n'.trim();
    return full.isEmpty ? 'Patient' : full;
  }

  void _openEegRapports() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EegRapportScreen(
          patientId: (_patient['id'] ?? '').toString(),
        ),
      ),
    );
  }

  Future<void> _loadRapports() async {
    final pid = (_patient['id'] ?? '').toString().trim();
    if (pid.isEmpty || pid == 'null') {
      if (mounted) {
        setState(() {
          _rapports = [];
          _loading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await ApiClient.get('/ecg/rapports/patient/$pid');
      if (mounted) {
        setState(() {
          _rapports = data as List;
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

  void _openNewEeg() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => EegUploadScreen(
              patientId: (_patient['id'] ?? '').toString(),
              nom: (_patient['nom'] ?? '').toString(),
              prenom: (_patient['prenom'] ?? '').toString(),
              sexe: (_patient['sexe'] ?? 'M').toString(),
              indication: 'Bilan neurologique',
            ),
          ),
        )
        .then((_) => _loadRapports());
  }

  void _openNewEcg() {
    final age = _calculateAge(_patient['date_naissance'] as String?);
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => EcgUploadScreen(
              patientId: (_patient['id'] ?? '').toString(),
              nom: (_patient['nom'] ?? '').toString(),
              prenom: (_patient['prenom'] ?? '').toString(),
              age: age,
              sexe: (_patient['sexe'] ?? 'M').toString(),
              indication: 'Bilan cardiaque',
            ),
          ),
        )
        .then((_) => _loadRapports());
  }

  Future<void> _openEditDialog() async {
    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PatientEditDialog(patient: _patient),
    );
    if (updated == null) return;

    try {
      final pid = (_patient['id'] ?? '').toString();
      final result = await ApiClient.patch('/patients/$pid', updated);
      if (mounted) {
        setState(() {
          _patient = result as Map<String, dynamic>;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Patient mis à jour'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fullName),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Modifier patient'),
            onPressed: _openEditDialog,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.monitor_heart, size: 18),
            label: const Text('Nouvel ECG'),
            onPressed: _openNewEcg,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.psychology_outlined, size: 18),
            label: const Text('Nouvel EEG'),
            onPressed: _openNewEeg,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6a1b9a),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRapports,
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 360,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            child: Text(
                              _fullName.isNotEmpty ? _fullName[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _fullName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      (_patient['sexe'] ?? '—').toString(),
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    const SizedBox(width: 12),
                                    const Icon(Icons.cake_outlined, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      _ageDisplay,
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    if ((_patient['groupe_sanguin'] ?? '').toString().isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          _patient['groupe_sanguin'].toString(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.red.shade700,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if ((_patient['telephone'] ?? '').toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.phone_outlined, size: 13, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(
                                          _patient['telephone'].toString(),
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if ((_patient['comorbidites'] ?? '').toString().isNotEmpty ||
                          (_patient['antecedents'] ?? '').toString().isNotEmpty) ...[
                        const Divider(height: 16),
                        _MedicalChips(patient: _patient),
                      ],
                      if ((_patient['allergies'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 13,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Allergies : ${_patient['allergies']}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.history, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        'Historique ECG (${_rapports.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 8, left: 12, right: 12, bottom: 4),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.psychology_outlined, size: 16),
                    label: const Text('Rapports EEG'),
                    onPressed: _openEegRapports,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6a1b9a),
                      side: const BorderSide(color: Color(0xFF6a1b9a)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.red),
                                  const SizedBox(height: 8),
                                  Text(
                                    _error!,
                                    style: const TextStyle(color: Colors.red, fontSize: 12),
                                  ),
                                  const SizedBox(height: 8),
                                  FilledButton(
                                    onPressed: _loadRapports,
                                    child: const Text('Réessayer'),
                                  ),
                                ],
                              ),
                            )
                          : _rapports.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.monitor_heart_outlined,
                                        size: 48,
                                        color: Colors.grey.shade300,
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Aucun ECG enregistré',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.add),
                                        label: const Text('Analyser un ECG'),
                                        onPressed: _openNewEcg,
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  itemCount: _rapports.length,
                                  itemBuilder: (_, i) {
                                    final r = _rapports[i] as Map<String, dynamic>;
                                    final f = r['findings'] as Map? ?? {};
                                    final dp = r['diagnostic_principal'] as Map? ?? {};
                                    final conf = (f['confidence'] as num?)?.toDouble() ?? 0;
                                    final cc = conf >= 0.88
                                        ? Colors.green
                                        : conf >= 0.65
                                            ? Colors.orange
                                            : Colors.red;
                                    final isSel = _selectedRapport?['report_id'] == r['report_id'];

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      color: isSel
                                          ? Theme.of(context).colorScheme.primaryContainer
                                          : null,
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: cc.withValues(alpha: 0.15),
                                          child: Text(
                                            '${(conf * 100).toInt()}%',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: cc,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          (dp['libelle'] ?? f['rhythm'] ?? 'N/A').toString(),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          r['generated_at']?.toString().substring(0, 10) ?? '—',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        trailing: const Icon(Icons.chevron_right, size: 18),
                                        onTap: () => setState(() => _selectedRapport = r),
                                      ),
                                    );
                                  },
                                ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedRapport == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Sélectionnez un rapport',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : _RapportDetailView(rapport: _selectedRapport!),
          ),
        ],
      ),
    );
  }
}

class _RapportDetailView extends StatelessWidget {
  final Map<String, dynamic> rapport;
  const _RapportDetailView({required this.rapport});

  @override
  Widget build(BuildContext context) {
    final findings = rapport['findings'] as Map? ?? {};
    final dp = rapport['diagnostic_principal'] as Map? ?? {};
    final conf = (findings['confidence'] as num?)?.toDouble() ?? 0;
    final confPct = (conf * 100).toInt();
    final cc = conf >= 0.88 ? Colors.green : conf >= 0.65 ? Colors.orange : Colors.red;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: cc.withValues(alpha: 0.15),
                child: Text(
                  '$confPct%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cc,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (dp['libelle'] ?? findings['rhythm'] ?? 'N/A').toString(),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Généré le : ${rapport['generated_at']?.toString().substring(0, 10) ?? '—'}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          if (dp.isNotEmpty) ...[
            const _SectionTitle('Diagnostic principal'),
            const SizedBox(height: 8),
            _InfoRow('Code', dp['code']?.toString() ?? '—'),
            _InfoRow('Libellé', dp['libelle']?.toString() ?? '—'),
            _InfoRow('Catégorie', dp['categorie']?.toString() ?? '—'),
            const SizedBox(height: 16),
          ],
          const _SectionTitle('Résultats ECG'),
          const SizedBox(height: 8),
          _InfoRow('Rythme', findings['rhythm']?.toString() ?? '—'),
          _InfoRow(
            'Fréquence cardiaque',
            findings['heart_rate'] != null ? '${findings['heart_rate']} bpm' : '—',
          ),
          _InfoRow('Axe QRS', findings['qrs_axis']?.toString() ?? '—'),
          _InfoRow('Intervalle PR', findings['pr_interval']?.toString() ?? '—'),
          _InfoRow('Intervalle QT', findings['qt_interval']?.toString() ?? '—'),
          const SizedBox(height: 16),
          if ((rapport['interpretation'] ?? '').toString().isNotEmpty) ...[
            const _SectionTitle('Interprétation'),
            const SizedBox(height: 8),
            Text(
              rapport['interpretation'].toString(),
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
          ],
          if ((rapport['recommandations'] ?? '').toString().isNotEmpty) ...[
            const _SectionTitle('Recommandations'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                rapport['recommandations'].toString(),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 0.5,
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicalChips extends StatelessWidget {
  final Map<String, dynamic> patient;
  const _MedicalChips({required this.patient});

  List<String> _split(String? s) => (s ?? '')
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          ..._split(patient['comorbidites'] as String?).map(
            (c) => Chip(
              label: Text(c, style: const TextStyle(fontSize: 10)),
              backgroundColor: Colors.purple.shade50,
              side: BorderSide(color: Colors.purple.shade200),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
          ..._split(patient['antecedents'] as String?).map(
            (a) => Chip(
              label: Text(a, style: const TextStyle(fontSize: 10)),
              backgroundColor: Colors.blue.shade50,
              side: BorderSide(color: Colors.blue.shade200),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientEditDialog extends StatefulWidget {
  final Map<String, dynamic> patient;
  const _PatientEditDialog({required this.patient});

  @override
  State<_PatientEditDialog> createState() => _PatientEditDialogState();
}

class _PatientEditDialogState extends State<_PatientEditDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  late final TextEditingController _nom;
  late final TextEditingController _prenom;
  late final TextEditingController _dob;
  late final TextEditingController _tel;
  late final TextEditingController _email;
  late final TextEditingController _adresse;
  late final TextEditingController _antecedents;
  late final TextEditingController _comorbidites;
  late final TextEditingController _traitements;
  late final TextEditingController _allergies;
  late final TextEditingController _notes;

  String? _sexe;
  String? _groupeSanguin;

  static const _groupes = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Inconnu'
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    final p = widget.patient;
    _nom = TextEditingController(text: p['nom'] as String? ?? '');
    _prenom = TextEditingController(text: p['prenom'] as String? ?? '');
    _dob = TextEditingController(text: p['date_naissance'] as String? ?? '');
    _tel = TextEditingController(text: p['telephone'] as String? ?? '');
    _email = TextEditingController(text: p['email'] as String? ?? '');
    _adresse = TextEditingController(text: p['adresse'] as String? ?? '');
    _antecedents = TextEditingController(text: p['antecedents'] as String? ?? '');
    _comorbidites = TextEditingController(text: p['comorbidites'] as String? ?? '');
    _traitements = TextEditingController(text: p['traitements_en_cours'] as String? ?? '');
    _allergies = TextEditingController(text: p['allergies'] as String? ?? '');
    _notes = TextEditingController(text: p['notes_generales'] as String? ?? '');
    _sexe = p['sexe'] as String?;
    _groupeSanguin = p['groupe_sanguin'] as String?;
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _nom,
      _prenom,
      _dob,
      _tel,
      _email,
      _adresse,
      _antecedents,
      _comorbidites,
      _traitements,
      _allergies,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _payload => {
        'nom': _nom.text.trim(),
        'prenom': _prenom.text.trim(),
        'date_naissance': _dob.text.trim(),
        'sexe': _sexe,
        'telephone': _tel.text.trim(),
        'email': _email.text.trim(),
        'adresse': _adresse.text.trim(),
        'groupe_sanguin': _groupeSanguin,
        'antecedents': _antecedents.text.trim(),
        'comorbidites': _comorbidites.text.trim(),
        'traitements_en_cours': _traitements.text.trim(),
        'allergies': _allergies.text.trim(),
        'notes_generales': _notes.text.trim(),
      };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Modifier le patient',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Informations'),
                Tab(text: 'Médical'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _prenom,
                                decoration: const InputDecoration(
                                  labelText: 'Prénom',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _nom,
                                decoration: const InputDecoration(
                                  labelText: 'Nom',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _dob,
                                decoration: const InputDecoration(
                                  labelText: 'Date de naissance',
                                  hintText: 'YYYY-MM-DD',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _sexe,
                                decoration: const InputDecoration(
                                  labelText: 'Sexe',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'M', child: Text('M')),
                                  DropdownMenuItem(value: 'F', child: Text('F')),
                                ],
                                onChanged: (v) => setState(() => _sexe = v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _tel,
                          decoration: const InputDecoration(
                            labelText: 'Téléphone',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _adresse,
                          decoration: const InputDecoration(
                            labelText: 'Adresse',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _groupes.contains(_groupeSanguin) ? _groupeSanguin : null,
                          decoration: const InputDecoration(
                            labelText: 'Groupe sanguin',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _groupes
                              .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                              .toList(),
                          onChanged: (v) => setState(() => _groupeSanguin = v),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _antecedents,
                          decoration: const InputDecoration(
                            labelText: 'Antécédents (séparés par virgule)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _comorbidites,
                          decoration: const InputDecoration(
                            labelText: 'Comorbidités (séparées par virgule)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _traitements,
                          decoration: const InputDecoration(
                            labelText: 'Traitements en cours',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _allergies,
                          decoration: const InputDecoration(
                            labelText: 'Allergies',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notes,
                          decoration: const InputDecoration(
                            labelText: 'Notes générales',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_payload),
                    child: const Text('Enregistrer'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
