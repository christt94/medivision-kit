import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';

class PatientFormScreen extends StatefulWidget {
  const PatientFormScreen({super.key});
  @override State<PatientFormScreen> createState() => _State();
}

class _State extends State<PatientFormScreen> {
  final _form   = GlobalKey<FormState>();
  final _nom    = TextEditingController();
  final _prenom = TextEditingController();
  final _dob    = TextEditingController();
  final _tel    = TextEditingController();
  final _email  = TextEditingController();
  String _sexe  = 'M';
  bool _saving  = false;

  @override
  void dispose() {
    _nom.dispose(); _prenom.dispose(); _dob.dispose();
    _tel.dispose(); _email.dispose();
    super.dispose();
  }

  int _computeAge(String dobStr) {
    try {
      final dob = DateTime.parse(dobStr);
      final now = DateTime.now();
      int age   = now.year - dob.year;
      final notYetHadBirthday =
        now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day);
      if (notYetHadBirthday) age--;
      return age;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _pickDate() async {
    final now    = DateTime.now();
    final picked = await showDatePicker(
      context:     context,
      initialDate: DateTime(now.year - 30),
      firstDate:   DateTime(1900),
      lastDate:    now,
      helpText:    'Date de naissance',
    );
    if (picked != null) {
      setState(() {
        _dob.text = picked.toIso8601String().substring(0, 10);
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ApiClient.post('/patients/', {
        'nom':            _nom.text.trim(),
        'prenom':         _prenom.text.trim(),
        'sexe':           _sexe,
        'date_naissance': _dob.text.trim().isEmpty ? null : _dob.text.trim(),
        'telephone':      _tel.text.trim().isEmpty  ? null : _tel.text.trim(),
        'email':          _email.text.trim().isEmpty ? null : _email.text.trim(),
      });
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Patient créé ✓'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final age = _dob.text.isNotEmpty ? _computeAge(_dob.text) : -1;

    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau patient')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Text('Informations patient',
                    style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),

                  // Prénom
                  TextFormField(
                    controller: _prenom,
                    decoration: const InputDecoration(
                      labelText: 'Prénom *',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder()),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requis' : null,
                  ),
                  const SizedBox(height: 16),

                  // Nom
                  TextFormField(
                    controller: _nom,
                    decoration: const InputDecoration(
                      labelText: 'Nom *',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder()),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requis' : null,
                  ),
                  const SizedBox(height: 16),

                  // Sexe
                  DropdownButtonFormField<String>(
                    value: _sexe,
                    decoration: const InputDecoration(
                      labelText: 'Sexe',
                      prefixIcon: Icon(Icons.wc),
                      border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'M', child: Text('Masculin')),
                      DropdownMenuItem(value: 'F', child: Text('Féminin')),
                    ],
                    onChanged: (v) => setState(() => _sexe = v!),
                  ),
                  const SizedBox(height: 16),

                  // Date de naissance
                  TextFormField(
                    controller: _dob,
                    readOnly: true,
                    onTap: _pickDate,
                    decoration: InputDecoration(
                      labelText: 'Date de naissance',
                      hintText:  'Sélectionner une date',
                      prefixIcon: const Icon(Icons.cake_outlined),
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_dob.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () =>
                                setState(() => _dob.clear())),
                          IconButton(
                            icon: const Icon(Icons.calendar_today, size: 18),
                            onPressed: _pickDate),
                        ])),
                  ),

                  // Age preview
                  if (age >= 0) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text('→ $age ans',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600))),
                  ],
                  const SizedBox(height: 16),

                  // Téléphone
                  TextFormField(
                    controller: _tel,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone',
                      hintText:  '+237 6XX XXX XXX',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),

                  // Email
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 32),

                  // Submit
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: _saving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.save),
                      label: Text(
                        _saving ? 'Enregistrement...' : 'Enregistrer'),
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50)),
                    )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
