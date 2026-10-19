import 'package:go_router/go_router.dart';
import '../shell/app_shell.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/patients/patients_screen.dart';
import '../screens/patients/patient_form_screen.dart';
import '../screens/patients/patient_detail_screen.dart';
import '../screens/ecg/ecg_upload_screen.dart';
import '../screens/eeg/eeg_upload_screen.dart';
import '../screens/eeg/eeg_rapport_screen.dart';
import '../screens/ecg/ecg_list_screen.dart' as ecg;
import '../screens/eeg/eeg_list_screen.dart' as eeg;
import '../screens/imaging/imaging_screen.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (c, s) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/patients',
            builder: (c, s) => const PatientsScreen(),
          ),
          GoRoute(
            path: '/patients/new',
            builder: (c, s) => const PatientFormScreen(),
          ),
          GoRoute(
            path: '/patients/:id',
            builder: (c, s) {
              final extra = s.extra;
              if (extra is! Map<String, dynamic>) {
                return const PatientsScreen();
              }
              return PatientDetailScreen(patient: extra);
            },
          ),
          GoRoute(
            path: '/ecg',
            builder: (c, s) {
              final extra = s.extra as Map<String, dynamic>?;
              return EcgUploadScreen(
                patientId: extra?['patient_id'] as String?,
                nom: extra?['nom'] as String?,
                prenom: extra?['prenom'] as String?,
                age: extra?['age'] as String?,
                sexe: extra?['sexe'] as String?,
                indication: extra?['indication'] as String?,
              );
            },
          ),
          GoRoute(
            path: '/eeg',
            builder: (c, s) {
              final extra = s.extra as Map<String, dynamic>?;
              return EegUploadScreen(
                patientId: extra?['patient_id'] as String?,
                nom: extra?['nom'] as String?,
                prenom: extra?['prenom'] as String?,
                age: extra?['age'] as String?,
                sexe: extra?['sexe'] as String?,
                indication: extra?['indication'] as String?,
              );
            },
          ),
          GoRoute(
            path: '/imaging',
            builder: (c, s) => const ImagingScreen(),
          ),
          GoRoute(
            path: '/eeg/rapports/:patientId',
            builder: (c, s) => EegRapportScreen(
              patientId: s.pathParameters['patientId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/ecgs/all',
            builder: (c, s) => const ecg.EcgListScreen(
              title: 'Tous les ECGs',
              endpoint: '/stats/ecgs',
            ),
          ),
          GoRoute(
            path: '/ecgs/today',
            builder: (c, s) => const ecg.EcgListScreen(
              title: "ECGs d'aujourd'hui",
              endpoint: '/stats/ecgs/today',
            ),
          ),
          GoRoute(
            path: '/ecgs/revision',
            builder: (c, s) => const ecg.EcgListScreen(
              title: 'File de Révision',
              endpoint: '/stats/ecgs/revision',
              showRevisionBadge: true,
            ),
          ),
          GoRoute(
            path: '/eegs/all',
            builder: (c, s) => const eeg.EegListScreen(
              title: 'Tous les EEGs',
              endpoint: '/eeg/rapports',
            ),
          ),
          GoRoute(
            path: '/eegs/today',
            builder: (c, s) => const eeg.EegListScreen(
              title: "EEGs d'aujourd'hui",
              endpoint: '/stats/eegs/today',
            ),
          ),
        ],
      ),
    ],
  );
}
