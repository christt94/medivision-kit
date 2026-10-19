import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';

class ImagingScreen extends StatefulWidget {
  const ImagingScreen({super.key});

  @override
  State<ImagingScreen> createState() => _ImagingScreenState();
}

class _ImagingScreenState extends State<ImagingScreen> {
  final _patientController = TextEditingController();
  final _indicationController = TextEditingController();
  String _modality = 'XRAY';
  List<dynamic> _studies = [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStudies();
  }

  @override
  void dispose() {
    _patientController.dispose();
    _indicationController.dispose();
    super.dispose();
  }

  Future<void> _loadStudies() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.get('/imaging/studies');
      if (!mounted) return;
      setState(() {
        _studies = data is List ? data : [];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _pickAndUpload() async {
    if (_patientController.text.trim().isEmpty) {
      _showMessage('Saisissez l’identifiant du patient.');
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['dcm', 'dicom', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (picked == null || picked.files.single.bytes == null) return;

    final file = picked.files.single;
    setState(() => _uploading = true);
    try {
      await ApiClient.uploadFile(
        '/imaging/studies',
        fileBytes: file.bytes!,
        fileName: file.name,
        fields: {
          'patient_id': _patientController.text.trim(),
          'modality': _modality,
          'indication': _indicationController.text.trim(),
        },
      );
      if (!mounted) return;
      _showMessage('Étude d’imagerie enregistrée pour revue clinique.');
      await _loadStudies();
    } catch (error) {
      if (mounted) _showMessage('Erreur lors de l’envoi : $error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showStudyReview(Map<String, dynamic> study) async {
    final result = study['result'] is Map
        ? Map<String, dynamic>.from(study['result'] as Map)
        : <String, dynamic>{};
    final existingReview = study['clinician_review'] is Map
        ? Map<String, dynamic>.from(study['clinician_review'] as Map)
        : <String, dynamic>{};
    final notesController = TextEditingController(
      text: existingReview['notes']?.toString() ?? '',
    );
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> saveReview() async {
            setDialogState(() => saving = true);
            try {
              await ApiClient.patch('/imaging/studies/${study['id']}', {
                'status': 'REVIEWED',
                'notes': notesController.text,
                'reviewed_by': 'clinician',
              });
              if (!mounted) return;
              Navigator.of(dialogContext).pop();
              _showMessage('Revue clinique enregistrée.');
              await _loadStudies();
            } catch (error) {
              setDialogState(() => saving = false);
              _showMessage('Erreur lors de la revue : $error');
            }
          }

          Future<void> exportPdf() async {
            try {
              await ApiClient.downloadPdf(
                '/imaging/export-pdf',
                fields: {'study_id': study['id'].toString()},
                fileName: 'rapport_imagerie_${study['id'].toString().substring(0, 8)}.pdf',
              );
            } catch (error) {
              _showMessage('Erreur PDF : $error');
            }
          }

          return AlertDialog(
            title: Text('${study['modality'] ?? 'Imagerie'} — revue'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Patient : ${study['patient_id'] ?? '—'}'),
                    const SizedBox(height: 12),
                    const Text('Résultat préliminaire', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    SelectableText(
                      result['text']?.toString() ?? result['message']?.toString() ?? 'Aucun résultat disponible.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notes du clinicien',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: saving ? null : exportPdf, child: const Text('Exporter PDF')),
              TextButton(onPressed: saving ? null : () => Navigator.of(dialogContext).pop(), child: const Text('Fermer')),
              FilledButton(
                onPressed: saving ? null : saveReview,
                child: Text(saving ? 'Enregistrement…' : 'Marquer comme revu'),
              ),
            ],
          );
        },
      ),
    );
    notesController.dispose();
  }

  String _formatBytes(dynamic value) {
    final bytes = (value as num?)?.toDouble() ?? 0;
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Imagerie médicale'),
        actions: [
          IconButton(onPressed: _loadStudies, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 850;
          final form = _uploadCard(primary);
          final list = Expanded(child: _studyList());
          return Padding(
            padding: const EdgeInsets.all(20),
            child: compact
                ? Column(children: [form, const SizedBox(height: 16), list])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 330, child: form),
                      const SizedBox(width: 20),
                      list,
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _uploadCard(Color primary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nouvelle étude', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Formats acceptés : DICOM, PNG et JPEG. Une revue clinique est requise.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _patientController,
              decoration: const InputDecoration(
                labelText: 'Identifiant patient *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _modality,
              decoration: const InputDecoration(
                labelText: 'Modalité',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'XRAY', child: Text('Radiographie / X-ray')),
                DropdownMenuItem(value: 'CT', child: Text('Scanner / CT')),
                DropdownMenuItem(value: 'MRI', child: Text('IRM / MRI')),
                DropdownMenuItem(value: 'ULTRASOUND', child: Text('Échographie')),
                DropdownMenuItem(value: 'FUNDUS', child: Text('Fond d’œil')),
                DropdownMenuItem(value: 'DERMATOSCOPY', child: Text('Dermoscopie')),
              ],
              onChanged: (value) => setState(() => _modality = value ?? 'XRAY'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _indicationController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Indication clinique',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_uploading ? 'Envoi…' : 'Choisir une image'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _studyList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    if (_studies.isEmpty) {
      return const Center(child: Text('Aucune étude d’imagerie enregistrée.'));
    }
    return ListView.separated(
      itemCount: _studies.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final study = Map<String, dynamic>.from(_studies[index] as Map);
        final metadata = study['metadata'] is Map
            ? Map<String, dynamic>.from(study['metadata'] as Map)
            : <String, dynamic>{};
        final result = study['result'] is Map
            ? Map<String, dynamic>.from(study['result'] as Map)
            : <String, dynamic>{};
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.image_outlined)),
            title: Text('${study['modality'] ?? 'IMAGING'} · ${study['original_filename'] ?? ''}'),
            subtitle: Text(
              'Patient: ${study['patient_id'] ?? '—'} · ${_formatBytes(study['size_bytes'])}\n'
              '${metadata['format'] ?? ''} · ${study['status'] ?? '—'}\n'
              '${result['message'] ?? ''}',
            ),
            isThreeLine: true,
            trailing: Chip(label: Text(study['status'] == 'REVIEWED' ? 'Revu' : 'Revue clinique')),
            onTap: () => _showStudyReview(study),
          ),
        );
      },
    );
  }
}
