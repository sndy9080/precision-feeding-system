import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:flutter/material.dart';

import '../device_scope.dart';

class DeviceHomePage extends StatefulWidget {
  const DeviceHomePage({super.key, required this.onOpenDevice});

  final ValueChanged<DeviceScope> onOpenDevice;

  @override
  State<DeviceHomePage> createState() => _DeviceHomePageState();
}

class _DeviceHomePageState extends State<DeviceHomePage> {
  bool _isPairing = false;

  DatabaseReference get _devicesRef {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseDatabase.instance.ref('users/$uid/devices');
  }

  Future<void> _pair(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pair alat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: idCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'ID alat', hintText: 'ESP32_A1B2C3D4E5F6')),
            TextField(
                controller: nameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Nama kandang / hopper')),
            TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Kode pairing dari portal')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Pair')),
        ],
      ),
    );
    if (accepted != true) return;

    final deviceId = idCtrl.text.trim().toUpperCase();
    final label = nameCtrl.text.trim();
    final pairingCode = codeCtrl.text.trim().toUpperCase();

    if (!RegExp(r'^ESP32_[0-9A-F]{12}$').hasMatch(deviceId) ||
        !RegExp(r'^[A-Z0-9]{8}$').hasMatch(pairingCode)) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Masukkan ID alat dan kode pairing 8 karakter dari portal.')));
      return;
    }

    setState(() => _isPairing = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final deviceRef = FirebaseDatabase.instance.ref('devices/$deviceId');
    final requestRef = deviceRef.child('pairing_requests/$uid');
    final claimRef = deviceRef.child('meta/claim_uid');
    final namaAlat = label.isEmpty ? deviceId : label;

    String? snackMsg;
    Color snackColor = Colors.green;

    StreamSubscription<DatabaseEvent>? sub;
    Timer? timeoutTimer;

    try {
      // 1. Cek dulu: apakah alat sudah diklaim user ini (recover dari race condition)
      final existingClaim = await claimRef.get();
      if (existingClaim.value?.toString() == uid) {
        // Alat sudah diklaim (mungkin timeout sisi app, tapi ESP32 berhasil)
        // Langsung daftarkan saja ke users/$uid/devices
        await Future.wait([
          FirebaseDatabase.instance
              .ref('users/$uid/devices/$deviceId')
              .set({'nama': namaAlat}),
          deviceRef.child('meta/nama').set(namaAlat),
        ]);
        snackMsg = 'Alat $deviceId berhasil dipasangkan!';
        return;
      }

      // 2. Cek apakah alat sudah diklaim user lain
      if (existingClaim.value != null &&
          existingClaim.value.toString().isNotEmpty) {
        snackMsg = 'Alat ini sudah diklaim oleh pengguna lain.';
        snackColor = Colors.red;
        return;
      }

      // 3. Tulis pairing request
      await requestRef.set(pairingCode);

      // 4. Tunggu ESP32 set claim_uid — gunakan Completer agar bisa di-complete
      //    dari timer atau dari listener, tidak ada race.
      final completer = Completer<bool>();

      sub = claimRef.onValue.listen((event) {
        final val = event.snapshot.value?.toString() ?? '';
        if (val == uid && !completer.isCompleted) {
          completer.complete(true);
        }
      }, onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      });

      timeoutTimer = Timer(const Duration(seconds: 20), () {
        if (!completer.isCompleted) completer.complete(false);
      });

      final claimed = await completer.future;
      await sub.cancel();
      sub = null;
      timeoutTimer.cancel();
      timeoutTimer = null;

      if (!claimed) {
        // Timeout — cek sekali lagi secara langsung (ESP32 mungkin sudah klaim
        // tapi stream lambat sampai ke client)
        final recheck = await claimRef.get();
        if (recheck.value?.toString() == uid) {
          // ESP32 sudah klaim, cukup daftarkan
        } else {
          // Benar-benar gagal — bersihkan request
          await requestRef.remove();
          snackMsg =
              'Perangkat tidak merespons (20 detik). Pastikan alat menyala dan kode pairing benar.';
          snackColor = Colors.red;
          return;
        }
      }

      // 5. Simpan nama alat di kedua lokasi
      await Future.wait([
        FirebaseDatabase.instance
            .ref('users/$uid/devices/$deviceId')
            .set({'nama': namaAlat}),
        deviceRef.child('meta/nama').set(namaAlat),
      ]);

      snackMsg = 'Alat $deviceId berhasil dipasangkan!';
    } catch (e) {
      await sub?.cancel();
      timeoutTimer?.cancel();
      // Coba bersihkan request jika gagal sebelum diklaim
      try {
        final c = await claimRef.get();
        if (c.value?.toString() != uid) await requestRef.remove();
      } catch (_) {}
      snackMsg = 'Pair gagal: $e';
      snackColor = Colors.red;
    } finally {
      if (mounted) {
        setState(() => _isPairing = false);
        if (snackMsg != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(snackMsg!),
              backgroundColor: snackColor,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Daftar Alat'), actions: [
          IconButton(
              onPressed: FirebaseAuth.instance.signOut,
              icon: const Icon(Icons.logout))
        ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _isPairing ? null : () => _pair(context),
            icon: _isPairing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_link),
            label: Text(_isPairing ? 'Menghubungkan...' : 'Pair alat')),
        body: _isPairing
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Menunggu konfirmasi dari perangkat...'),
                    SizedBox(height: 4),
                    Text('Maks. 20 detik',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            : StreamBuilder<DatabaseEvent>(
                stream: _devicesRef.onValue,
                builder: (context, snapshot) {
                  final raw = snapshot.data?.snapshot.value;
                  if (raw is! Map || raw.isEmpty) {
                    return const Center(
                        child: Text('Belum ada alat. Pair ESP32 baru.'));
                  }
                  final devices = Map<String, dynamic>.from(raw);
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final entry = devices.entries.elementAt(index);
                      final value = entry.value is Map
                          ? Map<String, dynamic>.from(entry.value)
                          : <String, dynamic>{};
                      final deviceId = entry.key;
                      return Card(
                        child: ListTile(
                          leading: const Icon(
                              Icons.precision_manufacturing_outlined),
                          title: Text(value['nama']?.toString() ?? deviceId),
                          subtitle: Row(
                            children: [
                              Text(deviceId,
                                  style: const TextStyle(fontSize: 11)),
                              const SizedBox(width: 8),
                              _DeviceStatus(deviceId: deviceId),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              widget.onOpenDevice(DeviceScope(deviceId)),
                        ),
                      );
                    },
                  );
                },
              ),
      );
}

class _DeviceStatus extends StatelessWidget {
  const _DeviceStatus({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) => StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance.ref('devices/$deviceId/meta').onValue,
        builder: (context, snapshot) {
          final raw = snapshot.data?.snapshot.value;
          final meta = raw is Map
              ? Map<String, dynamic>.from(raw)
              : <String, dynamic>{};
          final lastSeen =
              int.tryParse(meta['last_seen_epoch']?.toString() ?? '') ?? 0;
          final isOnline =
              DateTime.now().millisecondsSinceEpoch ~/ 1000 - lastSeen <= 300;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isOnline ? Colors.green.shade50 : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isOnline ? Colors.green : Colors.grey),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 10,
                    color: isOnline ? Colors.green.shade700 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          );
        },
      );
}
