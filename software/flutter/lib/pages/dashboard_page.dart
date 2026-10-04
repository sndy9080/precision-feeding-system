import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

import '../device_scope.dart';
import '../notification_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.scope});

  final DeviceScope scope;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DatabaseReference get _perintahRef => widget.scope.ref.child('Perintah');
  DatabaseReference get _monitoringRef => widget.scope.ref.child('Monitoring');

  StreamSubscription<DatabaseEvent>? _stokSub;
  bool _notifStokSudahDikirim = false;

  @override
  void initState() {
    super.initState();
    NotificationService.init();
    _mulaiPantauStok();
  }

  @override
  void dispose() {
    _stokSub?.cancel();
    super.dispose();
  }

  Future<void> _mulaiPantauStok() async {
    final kalSnap = await widget.scope.ref.child('Kalibrasi').get();
    int jarakPenuh = 3;
    int jarakKosong = 32;
    if (kalSnap.exists && kalSnap.value is Map) {
      final m = Map<String, dynamic>.from(kalSnap.value as Map);
      jarakPenuh = int.tryParse(m['jarak_penuh_cm']?.toString() ?? '') ?? 3;
      jarakKosong =
          int.tryParse(m['batas_pakan_minimum']?.toString() ?? '') ?? 32;
    }

    _stokSub = _monitoringRef.child('jarak_cm').onValue.listen((event) async {
      final jarakCm = int.tryParse(event.snapshot.value?.toString() ?? '');
      if (jarakCm == null) return;

      final rentang = (jarakKosong - jarakPenuh).clamp(1, 200).toDouble();
      final jarakClamped = jarakCm.clamp(jarakPenuh, jarakKosong).toDouble();
      final persen = ((jarakKosong - jarakClamped) / rentang * 100).round();

      if (persen <= 20 && !_notifStokSudahDikirim) {
        _notifStokSudahDikirim = true;
        await NotificationService.kirimNotifStokKritis(
            widget.scope.id, persen);
      } else if (persen > 20) {
        _notifStokSudahDikirim = false;
      }
    });
  }

  Future<void> _kirimPakanInstan(BuildContext context) async {
    final ketController = TextEditingController(text: '');
    final gramController = TextEditingController(text: '500');

    final hasilDialog = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kirim Pakan Instan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ketController,
                decoration: const InputDecoration(
                  labelText: 'Keterangan (opsional)',
                  hintText: 'Misal: Suplemen siang / Vitamin',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: gramController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Target Dosis (Gram)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop({
                  'ket': ketController.text.trim(),
                  'gram': gramController.text.trim().isEmpty
                      ? '500'
                      : gramController.text.trim(),
                });
              },
              child: const Text('Kirim'),
            ),
          ],
        );
      },
    );

    if (hasilDialog == null) return;

    final targetGramInt = int.tryParse(hasilDialog['gram']!) ?? 500;
    final keterangan = hasilDialog['ket'] ?? '';

    try {
      await _perintahRef.child('pakan').update({
        'tipe': 'INSTAN',
        'keterangan': keterangan,
        'target_gram': targetGramInt,
        'aktif': true,
        'respon': 'Menunggu',
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Mengirim perintah pakan instan $targetGramInt gram...'),
          ),
        );
      }

      bool isResponded = false;
      StreamSubscription<DatabaseEvent>? subscription;

      subscription = _perintahRef
          .child('pakan')
          .child('aktif')
          .onValue
          .listen((event) async {
        final value = event.snapshot.value;
        if (value == false || value == null) {
          isResponded = true;
          await subscription?.cancel();

          final responSnap =
              await _perintahRef.child('pakan').child('respon').get();
          final hasil = responSnap.value?.toString() ?? 'SUKSES';

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(hasil),
                backgroundColor:
                    hasil.contains('GAGAL') ? Colors.red : Colors.green,
              ),
            );
          }
        }
      });

      Timer(const Duration(seconds: 60), () async {
        if (!isResponded) {
          await subscription?.cancel();
          await _perintahRef.child('pakan').update({
            'aktif': false,
            'respon': 'GAGAL: Timeout!',
            'target_gram': 500,
            'keterangan': '',
          });

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('GAGAL: Timeout!'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim perintah: $e')),
        );
      }
    }
  }

  Future<void> _requestUpdateSensor(BuildContext context) async {
    try {
      await _perintahRef.child('sensor').update({
        'minta_update': true,
        'respon': 'Menunggu',
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Meminta update sensor, menunggu alat...')),
        );
      }

      bool isResponded = false;
      StreamSubscription<DatabaseEvent>? subscription;

      subscription = _perintahRef
          .child('sensor')
          .child('minta_update')
          .onValue
          .listen((event) async {
        final value = event.snapshot.value;
        if (value == false || value == null) {
          isResponded = true;
          await subscription?.cancel();

          final responSnap =
              await _perintahRef.child('sensor').child('respon').get();
          final hasil = responSnap.value?.toString() ??
              'SUKSES: Data sensor berhasil diperbarui!';

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(hasil),
                backgroundColor:
                    hasil.contains('GAGAL') ? Colors.red : Colors.green,
              ),
            );
          }
        }
      });

      Timer(const Duration(seconds: 60), () async {
        if (!isResponded) {
          await subscription?.cancel();

          await _perintahRef.child('sensor').update({
            'minta_update': false,
            'respon': 'GAGAL: Timeout!',
          });

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('GAGAL: Alat Offline atau koneksi buruk (Timeout)!'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim permintaan: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Dashboard Pakan',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _kirimPakanInstan(context),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Pakan Instan'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _requestUpdateSensor(context),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh cek stok & kelembaban'),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _SensorStatusSection(
              monitoringRef: _monitoringRef,
              kalibrasiRef: widget.scope.ref.child('Kalibrasi'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorStatusSection extends StatelessWidget {
  final DatabaseReference monitoringRef;
  final DatabaseReference kalibrasiRef;

  const _SensorStatusSection(
      {required this.monitoringRef, required this.kalibrasiRef});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Status Sensor (Realtime):',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<DatabaseEvent>(
            future: kalibrasiRef.once(),
            builder: (context, kalSnap) {
              int jarakPenuh = 3;
              int jarakKosong = 32;
              if (kalSnap.hasData && kalSnap.data!.snapshot.value is Map) {
                final m = Map<String, dynamic>.from(
                    kalSnap.data!.snapshot.value as Map);
                jarakPenuh =
                    int.tryParse(m['jarak_penuh_cm']?.toString() ?? '') ?? 3;
                jarakKosong =
                    int.tryParse(m['batas_pakan_minimum']?.toString() ?? '') ??
                        32;
              }

              return StreamBuilder<DatabaseEvent>(
                stream: monitoringRef.onValue,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  final data = snapshot.data?.snapshot.value;

                  int? jarakCm;
                  int? kelembabanInt;
                  String aktivitasPir = '-';

                  if (data is Map) {
                    final map = Map<String, dynamic>.from(data);
                    jarakCm =
                        int.tryParse(map['jarak_cm']?.toString() ?? '');
                    kelembabanInt =
                        int.tryParse(map['kelembaban']?.toString() ?? '');
                    aktivitasPir = map['aktivitas_pir']?.toString() ?? '-';
                  }

                  double stokPercent = 0.0;
                  if (jarakCm != null) {
                    final rentang = (jarakKosong - jarakPenuh)
                        .clamp(1, 200)
                        .toDouble();
                    final jarakClamped =
                        jarakCm.clamp(jarakPenuh, jarakKosong).toDouble();
                    stokPercent =
                        (jarakKosong - jarakClamped) / rentang;
                  }

                  String kelembabanLabel = 'Tidak diketahui';
                  Color kelembabanColor = Colors.grey;
                  if (kelembabanInt != null) {
                    // Threshold default 2243 (akan diganti dengan kalibrasi jika ada)
                    final threshold = 2243;
                    if (kelembabanInt < threshold) {
                      kelembabanLabel = 'Basah';
                      kelembabanColor = Colors.blue;
                    } else {
                      kelembabanLabel = 'Kering';
                      kelembabanColor = Colors.orange;
                    }
                  }

                  Color pirColor;
                  if (aktivitasPir.contains('Kambing Terdeteksi')) {
                    pirColor = Colors.green;
                  } else if (aktivitasPir.contains('Standby')) {
                    pirColor = Colors.grey;
                  } else {
                    pirColor = Colors.blueGrey;
                  }

                  return Card(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.inventory_2_outlined),
                                const SizedBox(width: 8),
                                const Text(
                                  'Perkiraan Stok Pakan',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: stokPercent.clamp(0.0, 1.0),
                              minHeight: 8,
                              backgroundColor: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              jarakCm == null
                                  ? 'Belum ada data jarak ultrasonik.'
                                  : 'Jarak sensor: $jarakCm cm '
                                      '(stok ${(stokPercent * 100).toStringAsFixed(0)}%'
                                      ' | penuh=$jarakPenuh cm, kosong=$jarakKosong cm)',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Icon(Icons.water_drop_outlined),
                                const SizedBox(width: 8),
                                const Text(
                                  'Kelembaban Pakan',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color:
                                        kelembabanColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: kelembabanColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(kelembabanLabel),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                if (kelembabanInt != null)
                                  Text('ADC: $kelembabanInt',
                                      style:
                                          const TextStyle(fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Icon(Icons.visibility_outlined),
                                const SizedBox(width: 8),
                                const Text(
                                  'Aktivitas PIR',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Chip(
                                backgroundColor:
                                    pirColor.withOpacity(0.15),
                                avatar: CircleAvatar(
                                  backgroundColor: pirColor,
                                  radius: 8,
                                ),
                                label: Text(
                                  aktivitasPir,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
