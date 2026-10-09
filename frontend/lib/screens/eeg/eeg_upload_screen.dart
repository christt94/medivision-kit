import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api_client.dart';
import 'eeg_result_screen.dart';

class EegUploadScreen extends StatefulWidget {
  final String? patientId;
  final String? nom;
  final String? prenom;
  final String? age;
  final String? sexe;
  final String? indication;

  const EegUploadScreen({
    super.key,
    this.patientId,
    this.nom,
    this.prenom,
    this.age,
    this.sexe,
    this.indication,
  });

  @override
  State<EegUploadScreen> createState() => _EegUploadState();
}

class _EegUploadState extends State<EegUploadScreen> {
  Uint8List? _fileBytes;
  String? _fileName;
  final _patientId = TextEditingController();
  final _indication = TextEditingController();
  final _searchCtrl = TextEditingController();

  final _motif = TextEditingController();
  final _dureeCrise = TextEditingController();
  final _traitement = TextEditingController();
  final _technicien = TextEditingController();
  final _dateExamen = TextEditingController();

  List<Map<String, dynamic>> _suggestions = [];
  Map<String, dynamic>? _selectedPatient;

  String _loading_msg = '';
  bool _loading = false;
  bool _searching = false;
  String? _error;

  String _etatVigilance = 'Éveillé';
  String _montage = 'Standard 10-20';
  final _notch = TextEditingController(text: '50');
  final _bandpass = TextEditingController(text: '0.5-70');

  String get _displayName {
    if (_selectedPatient != null) {
      final p = _selectedPatient!['prenom'] as String? ?? '';
      final n = _selectedPatient!['nom'] as String? ?? '';
      return '$p $n'.trim();
    }
    final p = widget.prenom ?? '';
    final n = widget.nom ?? '';
    final full = '$p $n'.trim();
    if (full.isNotEmpty) return full;
    return 'Inconnu';
  }

  @override
  void initState() {
    super.initState();
    final pid = (widget.patientId ?? '').trim();
    if (pid.isNotEmpty) _patientId.text = pid;

    _indication.text = (widget.indication ?? 'Bilan neurologique').trim();
    _dateExamen.text = DateTime.now().toIso8601String().substring(0, 10);
  }

  @override
  void dispose() {
    _patientId.dispose();
    _indication.dispose();
    _searchCtrl.dispose();
    _motif.dispose();
    _dureeCrise.dispose();
    _traitement.dispose();
    _technicien.dispose();
    _dateExamen.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'edf', 'bdf', 'gdf', 'set', 'vhdr', 'eeg', 'cnt', 'mff', 'xdf',
        'dat', 'rec', 'fif', 'mat', 'txt', 'csv'
      ],
      withData: true,
      allowMultiple: false,
    );

    if (result != null && result.files.single.bytes != null) {
      if (mounted) {
        setState(() {
          _fileBytes = result.files.single.bytes;
          _fileName = result.files.single.name;
          _error = null;
        });
      }
    }
  }

  Future<void> _searchPatients(String q) async {
    if (q.length < 2) {
      if (mounted) setState(() => _suggestions = []);
      return;
    }
    if (mounted) setState(() => _searching = true);
    try {
      final data = await ApiClient.get('/patients/?search=$q');
      if (mounted) {
        setState(() {
          _suggestions = List<Map<String, dynamic>>.from(data as List);
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _analyze() async {
    if (_fileBytes == null) {
      if (mounted) {
        setState(() => _error =
            'Veuillez sélectionner un fichier EEG valide (.edf, .bdf, .gdf, .set, .vhdr, .eeg, .cnt, .mff, .xdf, .dat, .rec, .fif, .mat, .txt, .csv)');
      }
      return;
    }

    final pid = _patientId.text.trim();
    if (pid.isEmpty) {
      if (mounted) setState(() => _error = 'Patient requis');
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _loading_msg = 'Analyse EEG en cours…';
      });
    }

    try {
      final result = await ApiClient.uploadFile(
        '/eeg/analyze',
        fileBytes: _fileBytes!,
        fileName: _fileName ?? 'signal.edf',
        fields: {
          'patient_id': pid,
          'patient_name': _displayName,
          'indication': _indication.text.trim(),
          'motif': _motif.text.trim(),
          'duree_crise': _dureeCrise.text.trim(),
          'traitement_en_cours': _traitement.text.trim(),
          'technicien': _technicien.text.trim(),
          'date_examen': _dateExamen.text.trim(),
          'etat_vigilance': _etatVigilance,
          'montage': _montage,
          'notch_hz': _notch.text.trim(),
          'bandpass_hz': _bandpass.text.trim(),
        },
      );

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EegResultScreen(
            result: result['result'] as Map<String, dynamic>,
            patientName: _displayName,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teal = const Color(0xFF01696f);
    final hasPid = widget.patientId != null && widget.patientId!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analyse EEG'),
        backgroundColor: teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF01696f)),
                  const SizedBox(height: 16),
                  Text(_loading_msg, style: theme.textTheme.bodyMedium),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasPid) ...[
                    _SectionCard(
                      icon: Icons.person_outline,
                      title: 'Patient',
                      teal: teal,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: teal.withOpacity(0.1),
                          child: Icon(Icons.person, color: teal),
                        ),
                        title: Text(
                          _displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(widget.patientId ?? ''),
                      ),
                    ),
                  ] else ...[
                    _SectionCard(
                      icon: Icons.search,
                      title: 'Rechercher un patient',
                      teal: teal,
                      child: Column(
                        children: [
                          TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: 'Nom ou prénom…',
                              prefixIcon: _searching
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            onChanged: _searchPatients,
                          ),
                          if (_suggestions.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _suggestions.length,
                                separatorBuilder: (_, __) =>
                                    Divider(height: 1, color: Colors.grey.shade200),
                                itemBuilder: (_, i) {
                                  final p = _suggestions[i];
                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: teal.withOpacity(0.1),
                                      child: Text(
                                        ((p['prenom'] as String? ?? 'X')[0]).toUpperCase(),
                                        style: TextStyle(color: teal, fontSize: 12),
                                      ),
                                    ),
                                    title: Text(
                                      '${p['prenom'] ?? ''} ${p['nom'] ?? ''}'.trim(),
                                    ),
                                    subtitle: Text(p['id'] as String? ?? ''),
                                    onTap: () {
                                      if (mounted) {
                                        setState(() {
                                          _selectedPatient = p;
                                          _patientId.text = p['id'] as String? ?? '';
                                          _suggestions = [];
                                          _searchCtrl.text =
                                              '${p['prenom'] ?? ''} ${p['nom'] ?? ''}'.trim();
                                        });
                                      }
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                          if (_selectedPatient == null) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _patientId,
                              decoration: InputDecoration(
                                labelText: 'ID patient (manuel)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  _SectionCard(
                    icon: Icons.medical_information_outlined,
                    title: 'Indication clinique',
                    teal: teal,
                    child: Column(
                      children: [
                        TextField(
                          controller: _indication,
                          decoration: InputDecoration(
                            hintText: 'Bilan neurologique…',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _motif,
                          decoration: InputDecoration(
                            labelText: 'Motif / suspicion clinique',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _dureeCrise,
                          decoration: InputDecoration(
                            labelText: 'Durée / fréquence des crises',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _traitement,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Traitement en cours',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  _SectionCard(
                    icon: Icons.settings_input_component_outlined,
                    title: 'Paramètres d’acquisition',
                    teal: teal,
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          value: _etatVigilance,
                          decoration: InputDecoration(
                            labelText: 'État de vigilance',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Éveillé', child: Text('Éveillé')),
                            DropdownMenuItem(value: 'Somnolent', child: Text('Somnolent')),
                            DropdownMenuItem(value: 'Endormi', child: Text('Endormi')),
                            DropdownMenuItem(value: 'Sous sédation', child: Text('Sous sédation')),
                          ],
                          onChanged: (v) => setState(() => _etatVigilance = v!),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _montage,
                          decoration: InputDecoration(
                            labelText: 'Montage',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Standard 10-20', child: Text('Standard 10-20')),
                            DropdownMenuItem(value: 'Bipolaire', child: Text('Bipolaire')),
                            DropdownMenuItem(value: 'Référentiel', child: Text('Référentiel')),
                            DropdownMenuItem(value: 'Longitudinal', child: Text('Longitudinal')),
                          ],
                          onChanged: (v) => setState(() => _montage = v!),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _technicien,
                          decoration: InputDecoration(
                            labelText: 'Technicien / opérateur',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _dateExamen,
                          decoration: InputDecoration(
                            labelText: 'Date de l’examen',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notch,
                          decoration: InputDecoration(
                            labelText: 'Notch Hz',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _bandpass,
                          decoration: InputDecoration(
                            labelText: 'Band-pass Hz',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  _SectionCard(
                    icon: Icons.file_upload_outlined,
                    title: 'Signal EEG',
                    teal: teal,
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _pickFile,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 32,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: _fileBytes != null
                                  ? teal.withOpacity(0.05)
                                  : Colors.grey.shade50,
                              border: Border.all(
                                color: _fileBytes != null
                                    ? teal
                                    : Colors.grey.shade300,
                                width: _fileBytes != null ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  _fileBytes != null
                                      ? Icons.check_circle_outline
                                      : Icons.upload_file,
                                  size: 48,
                                  color: _fileBytes != null
                                      ? teal
                                      : Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _fileBytes != null
                                      ? _fileName ?? 'Fichier EEG sélectionné'
                                      : 'Importer un fichier EEG',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _fileBytes != null
                                        ? teal
                                        : Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Formats acceptés : .edf  .bdf  .gdf  .set  .vhdr  .eeg  .cnt  .mff  .xdf  .dat  .rec  .fif  .mat  .txt  .csv',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                if (_fileBytes != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '${(_fileBytes!.length / 1024).toStringAsFixed(1)} KB',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade700, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _fileBytes != null ? _analyze : null,
                      icon: const Icon(Icons.psychology_outlined),
                      label: const Text(
                        'Lancer l\'analyse EEG',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: teal,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color teal;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.teal,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: teal, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: teal,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}