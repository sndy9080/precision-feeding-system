import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

import '../device_scope.dart';

class PakanPage extends StatefulWidget {
  const PakanPage({super.key, required this.scope});

  final DeviceScope scope;

  @override
  State<PakanPage> createState() => _PakanPageState();
}

class _PakanPageState extends State<PakanPage> {
  DatabaseReference get _kategoriRef => widget.scope.ref.child('KategoriPakan');

  Future<void> _buatProfil() async {
    final namaCtrl = TextEditingController();
    final result = await _showProfilDialog(namaCtrl, null);
    if (result == null) return;
    try {
      await _kategoriRef.push().set(result);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Profil pakan berhasil ditambahkan!'),
              backgroundColor: Colors.green),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  Future<void> _editProfil(String id, Map<String, dynamic> data) async {
    final namaCtrl =
        TextEditingController(text: data['nama']?.toString() ?? '');
    final result = await _showProfilDialog(namaCtrl, data);
    if (result == null) return;
    try {
      await _kategoriRef.child(id).update(result);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Profil berhasil diperbarui!'),
              backgroundColor: Colors.green),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  Future<void> _hapusProfil(String id, String nama) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Profil?'),
        content: Text('Hapus profil "$nama"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _kategoriRef.child(id).remove();
  }

  Future<Map<String, dynamic>?> _showProfilDialog(
      TextEditingController namaCtrl, Map<String, dynamic>? existing) async {
    Map<String, dynamic> init(String sub, Map<String, dynamic>? e) {
      if (e == null || e[sub] is! Map) return {};
      return Map<String, dynamic>.from(e[sub] as Map);
    }

    final kering = init('kering', existing);
    final basah = init('basah', existing);

    final ctrl = <String, TextEditingController>{
      'batas_kelembaban': TextEditingController(
          text: existing?['batas_kelembaban']?.toString() ?? '2243'),
      'k_pwm_min':
          TextEditingController(text: kering['pwm_min']?.toString() ?? '95'),
      'k_pwm_max':
          TextEditingController(text: kering['pwm_max']?.toString() ?? '170'),
      'k_pwm_m2': TextEditingController(
          text: kering['pwm_motor2']?.toString() ?? '240'),
      'k_gram_min':
          TextEditingController(text: kering['gram_min']?.toString() ?? '500'),
      'k_gram_max':
          TextEditingController(text: kering['gram_max']?.toString() ?? '1000'),
      'k_durasi': TextEditingController(
          text: kering['durasi_distribusi_ms']?.toString() ?? '4600'),
      'b_pwm_min':
          TextEditingController(text: basah['pwm_min']?.toString() ?? '90'),
      'b_pwm_max':
          TextEditingController(text: basah['pwm_max']?.toString() ?? '150'),
      'b_pwm_m2':
          TextEditingController(text: basah['pwm_motor2']?.toString() ?? '220'),
      'b_gram_min':
          TextEditingController(text: basah['gram_min']?.toString() ?? '500'),
      'b_gram_max':
          TextEditingController(text: basah['gram_max']?.toString() ?? '1000'),
      'b_durasi': TextEditingController(
          text: basah['durasi_distribusi_ms']?.toString() ?? '4600'),
    };

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            existing == null ? 'Tambah Profil Pakan' : 'Edit Profil Pakan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                  controller: namaCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Pakan')),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl['batas_kelembaban'],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Batas Kelembaban ADC (Sensor)'),
              ),
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
              const Text('Kondisi KERING',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              _row('PWM Min (Motor 1)', ctrl['k_pwm_min']!, 'PWM Max (Motor 1)',
                  ctrl['k_pwm_max']!),
              _row('Gram Min', ctrl['k_gram_min']!, 'Gram Max',
                  ctrl['k_gram_max']!),
              TextField(
                controller: ctrl['k_pwm_m2'],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'PWM Motor 2 Kondisi Kering'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl['k_durasi'],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Durasi Distribusi Kering (ms)'),
              ),
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
              const Text('Kondisi BASAH',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              _row('PWM Min (Motor 1)', ctrl['b_pwm_min']!, 'PWM Max (Motor 1)',
                  ctrl['b_pwm_max']!),
              _row('Gram Min', ctrl['b_gram_min']!, 'Gram Max',
                  ctrl['b_gram_max']!),
              TextField(
                controller: ctrl['b_pwm_m2'],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'PWM Motor 2 Kondisi Basah'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl['b_durasi'],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Durasi Distribusi Basah (ms)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              if (namaCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (ok != true) return null;

    int p(String k) => int.tryParse(ctrl[k]!.text.trim()) ?? 0;

    return {
      'nama': namaCtrl.text.trim(),
      'batas_kelembaban': p('batas_kelembaban'),
      'kering': {
        'pwm_min': p('k_pwm_min'),
        'pwm_max': p('k_pwm_max'),
        'pwm_motor2': p('k_pwm_m2'),
        'gram_min': p('k_gram_min'),
        'gram_max': p('k_gram_max'),
        'durasi_distribusi_ms': p('k_durasi'),
      },
      'basah': {
        'pwm_min': p('b_pwm_min'),
        'pwm_max': p('b_pwm_max'),
        'pwm_motor2': p('b_pwm_m2'),
        'gram_min': p('b_gram_min'),
        'gram_max': p('b_gram_max'),
        'durasi_distribusi_ms': p('b_durasi'),
      },
    };
  }

  Widget _row(String l1, TextEditingController c1, String l2,
      TextEditingController c2) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
            child: TextField(
                controller: c1,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l1, isDense: true))),
        const SizedBox(width: 8),
        Expanded(
            child: TextField(
                controller: c2,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l2, isDense: true))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Profil Pakan'),
        actions: [
          IconButton(
            onPressed: _buatProfil,
            icon: const Icon(Icons.add),
            tooltip: 'Tambah Profil',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Katalog Profil Pakan',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<DatabaseEvent>(
                stream: _kategoriRef.onValue,
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final raw = snap.data?.snapshot.value;
                  if (raw == null) {
                    return const Center(
                        child: Text(
                            'Belum ada profil pakan. Tap "Tambah Profil".'));
                  }
                  final list = <MapEntry<String, Map<String, dynamic>>>[];
                  if (raw is Map) {
                    raw.forEach((k, v) {
                      if (v is Map)
                        list.add(MapEntry(
                            k.toString(), Map<String, dynamic>.from(v)));
                    });
                  }
                  list.sort((a, b) => (a.value['nama']?.toString() ?? '')
                      .compareTo(b.value['nama']?.toString() ?? ''));

                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final id = list[i].key;
                      final data = list[i].value;
                      final nama = data['nama']?.toString() ?? id;
                      final bk = data['batas_kelembaban']?.toString() ?? '-';
                      final kering = data['kering'] as Map?;
                      final basah = data['basah'] as Map?;

                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.grass_outlined),
                          title: Text(nama,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            'ADC Kelembaban: $bk\n'
                            'Kering — M1: PWM ${kering?['pwm_min'] ?? '-'}-${kering?['pwm_max'] ?? '-'} | M2: PWM ${kering?['pwm_motor2'] ?? '-'} | ${kering?['durasi_distribusi_ms'] ?? '-'} ms\n'
                            'Basah  — M1: PWM ${basah?['pwm_min'] ?? '-'}-${basah?['pwm_max'] ?? '-'} | M2: PWM ${basah?['pwm_motor2'] ?? '-'} | ${basah?['durasi_distribusi_ms'] ?? '-'} ms',
                          ),
                          isThreeLine: true,
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editProfil(id, data)),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Hapus',
                              onPressed: () => _hapusProfil(id, nama),
                            ),
                          ]),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
