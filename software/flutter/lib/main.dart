import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:workmanager/workmanager.dart';

import 'device_scope.dart';
import 'firebase_options.dart';
import 'pages/dashboard_page.dart';
import 'pages/device_home_page.dart';
import 'pages/pengaturan_page.dart';
import 'pages/riwayat_page.dart';
import 'pages/teknisi_page.dart';
import 'pages/login_page.dart';

const String scheduleWorkerName = 'custom_schedule_worker_v1';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == scheduleWorkerName && inputData != null) {
      try {
        await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform);
        final deviceId = inputData['deviceId']?.toString();
        if (deviceId == null || deviceId.isEmpty) return true;
        await FirebaseDatabase.instance
            .ref('devices/$deviceId/Perintah/pakan')
            .update({
          'tipe': 'KUSTOM',
          'keterangan': inputData['keterangan']?.toString() ?? 'Pakan Tambahan',
          'target_gram':
              int.tryParse(inputData['targetGram']?.toString() ?? '') ?? 500,
          'aktif': true,
          'respon': 'Menunggu',
        });
      } catch (_) {}
    }
    return true;
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  runApp(const PakanTernakApp());
}

class PakanTernakApp extends StatelessWidget {
  const PakanTernakApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Otomasi Pakan Ternak',
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
            useMaterial3: true),
        home: const AuthGate(),
      );
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key, required this.scope, required this.onBack});

  final DeviceScope scope;
  final VoidCallback onBack;

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(scope: widget.scope),
      PengaturanPage(scope: widget.scope),
      RiwayatPage(scope: widget.scope),
      TeknisiPage(scope: widget.scope),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('Alat ${widget.scope.id}'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Daftar alat',
            onPressed: widget.onBack),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Keluar',
              onPressed: FirebaseAuth.instance.signOut)
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.green[700],
        unselectedItemColor: Colors.grey[600],
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined), label: 'Pengaturan'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Riwayat'),
          BottomNavigationBarItem(
              icon: Icon(Icons.engineering_outlined), label: 'Teknisi'),
        ],
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  DeviceScope? _scope;

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Scaffold(
                body: Center(
                    child: CircularProgressIndicator(color: Colors.green)));
          if (!snapshot.hasData) return const LoginPage();
          if (_scope == null)
            return DeviceHomePage(
                onOpenDevice: (scope) => setState(() => _scope = scope));
          return MainScaffold(
              scope: _scope!, onBack: () => setState(() => _scope = null));
        },
      );
}
