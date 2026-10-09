import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../models/patient.dart';

class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key});
  @override State<PatientsScreen> createState() => _State();
}

class _State extends State<PatientsScreen> {
  List<Patient> _patients = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.get('/patients/') as List;
      setState(() {
        _patients = data.map((j) => Patient.fromJson(j)).toList();
        _loading  = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Patients (${_patients.length})'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Nouveau patient'),
            onPressed: () async { await context.push('/patients/new'); _load(); },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _patients.isEmpty
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.people_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Aucun patient enregistré',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Ajouter le premier patient'),
                onPressed: () async { await context.push('/patients/new'); _load(); },
              ),
            ]))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _patients.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final p = _patients[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(p.initials)),
                    title: Text(p.fullName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${p.sexe ?? "?"} · ${p.dateNais ?? "date inconnue"} · ${p.paysCode}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(
                      '/patients/${p.id}',
                      extra: p.toMap(),
                    ),
                  ));
              },
            ),
    );
  }
}
