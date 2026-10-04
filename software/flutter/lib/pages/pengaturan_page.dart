import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

import '../device_scope.dart';
import 'pakan_page.dart';

class PengaturanPage extends StatefulWidget {
  const PengaturanPage({super.key, required this.scope});

  final DeviceScope scope;

  @override
  State<PengaturanPage> createState() => _PengaturanPageState();
}

class _PengaturanPageState extends State<PengaturanPage> {
  DatabaseReference get _jadwalRef => widget.scope.ref.child('Jadwal');
  DatabaseReference get _konfigurasiRef =>
      widget.scope.ref.child('Konfigurasi');
  DatabaseReference get _kategoriRef => widget.scope.ref.child('KategoriPakan');

  String _mode = 'Auto';
  String _profilManual = 'Kering';
  String _profilAktifId = '';

  @override
  void initState() {
    super.initState();
    _loadKonfigurasi();
  }

  Future<void> _loadKonfigurasi() async {
    try {
      final snapshot = await _konfigurasiRef.get();
      if (!snapshot.exists) return;

      final data = snapshot.value;
      if (data is! Map) return;

      final map = Map<String, dynamic>.from(data);

      setState(() {
        final modeVal = map['mode']?.toString();
        final profilVal = map['profil_manual']?.toString();
        _profilAktifId = map['profil_pakan_aktif']?.toString() ?? '';

        if (modeVal == 'Auto' || modeVal == 'Manual') _mode = modeVal!;
        if (profilVal == 'Basah' || profilVal == 'Kering')
          _profilManual = profilVal!;
      });
    } catch (_) {}
  }

  Future<void> _setProfilAktif(String id) async {
    setState(() => _profilAktifId = id);
    await _konfigurasiRef.update({'profil_pakan_aktif': id});
  }

  Future<void> _setMode(String v) async {
    setState(() => _mode = v);
    await _konfigurasiRef.update({'mode': v});
  }

  Future<void> _setProfilManual(String v) async {
    setState(() => _profilManual = v);
    await _konfigurasiRef.update({'profil_manual': v});
  }

  Future<void> _buatJadwal() async {
    final ketController = TextEditingController(text: 'Jadwal Baru');
    final gramController = TextEditingController(text: '500');
    final toleransiController = TextEditingController(text: '30');
    TimeOfDay? jamPilih;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Buat Jadwal Baru'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ketController,
                decoration: const InputDecoration(
                  labelText: 'Keterangan',
                  hintText: 'Misal: Pagi / Siang / Tambahan',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: gramController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Target Dosis (Gram)',
                  hintText: '500',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: toleransiController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Toleransi Keterlambatan (Menit)',
                  hintText: '30',
                  helperText: 'Jendela waktu eksekusi setelah jam terjadwal',
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.access_time),
                title: const Text('Jam Eksekusi'),
                subtitle: Text(jamPilih == null
                    ? 'Belum dipilih'
                    : '${jamPilih!.hour.toString().padLeft(2, '0')}:${jamPilih!.minute.toString().padLeft(2, '0')}'),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 7, minute: 0),
                  );
                  if (picked != null) {
                    setState(() => jamPilih = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                if (jamPilih == null) return;
                Navigator.pop(context, true);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    if (result != true || jamPilih == null) return;

    final jam =
        '${jamPilih!.hour.toString().padLeft(2, '0')}:${jamPilih!.minute.toString().padLeft(2, '0')}';
    final targetGram = int.tryParse(gramController.text.trim()) ?? 500;
    final toleransi = int.tryParse(toleransiController.text.trim()) ?? 30;
    final keterangan = ketController.text.trim();

    try {
      await _jadwalRef.push().set({
        'jam': jam,
        'target_gram': targetGram,
        'aktif': true,
        'keterangan': keterangan.isEmpty ? 'Jadwal Baru' : keterangan,
        'terakhir_epoch': 0,
        'toleransi_menit': toleransi,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Jadwal berhasil ditambahkan!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menambahkan jadwal: $e')),
        );
      }
    }
  }

  Future<void> _editJadwal(String id, Map<String, dynamic> data) async {
    final ketController =
        TextEditingController(text: data['keterangan']?.toString() ?? '');
    final gramController =
        TextEditingController(text: data['target_gram']?.toString() ?? '500');
    final toleransiController = TextEditingController(
        text: data['toleransi_menit']?.toString() ?? '30');

    final jamStr = data['jam']?.toString() ?? '07:00';
    final parts = jamStr.split(':');
    TimeOfDay? jamPilih = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 7,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Jadwal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ketController,
                decoration: const InputDecoration(labelText: 'Keterangan'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: gramController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Target Dosis (Gram)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: toleransiController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Toleransi Keterlambatan (Menit)',
                  hintText: '30',
                  helperText: 'Jendela waktu eksekusi setelah jam terjadwal',
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.access_time),
                title: const Text('Jam Eksekusi'),
                subtitle: Text(jamPilih == null
                    ? 'Belum dipilih'
                    : '${jamPilih!.hour.toString().padLeft(2, '0')}:${jamPilih!.minute.toString().padLeft(2, '0')}'),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime:
                        jamPilih ?? const TimeOfDay(hour: 7, minute: 0),
                  );
                  if (picked != null) {
                    setState(() => jamPilih = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    if (result != true || jamPilih == null) return;

    final jam =
        '${jamPilih!.hour.toString().padLeft(2, '0')}:${jamPilih!.minute.toString().padLeft(2, '0')}';
    final targetGram = int.tryParse(gramController.text.trim()) ?? 500;
    final toleransi = int.tryParse(toleransiController.text.trim()) ?? 30;
    final keterangan = ketController.text.trim();

    try {
      await _jadwalRef.child(id).update({
        'jam': jam,
        'target_gram': targetGram,
        'keterangan': keterangan.isEmpty ? 'Jadwal' : keterangan,
        'toleransi_menit': toleransi,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Jadwal berhasil diperbarui!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui jadwal: $e')),
        );
      }
    }
  }

  Future<void> _hapusJadwal(String id, String keterangan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Jadwal?'),
        content: Text('Yakin ingin menghapus jadwal "$keterangan"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _jadwalRef.child(id).remove();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Jadwal berhasil dihapus!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus jadwal: $e')),
        );
      }
    }
  }

  Future<void> _toggleAktif(String id, bool currentValue) async {
    try {
      await _jadwalRef.child(id).update({'aktif': !currentValue});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengubah status: $e')),
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pengaturan Jadwal',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _buatJadwal,
                icon: const Icon(Icons.add),
                label: const Text('Buat Jadwal'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: _jadwalRef.onValue,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final raw = snapshot.data?.snapshot.value;
                if (raw == null) {
                  return const Center(
                      child: Text(
                          'Belum ada jadwal. Tap tombol "Buat Jadwal" untuk menambahkan.'));
                }

                final List<MapEntry<String, Map<String, dynamic>>> jadwalList =
                    [];

                if (raw is Map) {
                  final map = Map<String, dynamic>.from(raw);
                  map.forEach((key, value) {
                    if (value is Map) {
                      jadwalList
                          .add(MapEntry(key, Map<String, dynamic>.from(value)));
                    }
                  });
                }

                jadwalList.sort((a, b) {
                  final jamA = a.value['jam']?.toString() ?? '00:00';
                  final jamB = b.value['jam']?.toString() ?? '00:00';
                  return jamA.compareTo(jamB);
                });

                if (jadwalList.isEmpty) {
                  return const Center(child: Text('Belum ada jadwal.'));
                }

                return ListView.separated(
                  itemCount: jadwalList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = jadwalList[index];
                    final id = entry.key;
                    final data = entry.value;

                    final jam = data['jam']?.toString() ?? '-';
                    final targetGram = data['target_gram']?.toString() ?? '0';
                    final aktif = data['aktif'] == true;
                    final keterangan =
                        data['keterangan']?.toString() ?? 'Jadwal';
                    final terakhirEpoch = int.tryParse(
                            data['terakhir_epoch']?.toString() ?? '') ??
                        0;
                    String displayTerakhir = 'Belum pernah dieksekusi';
                    if (terakhirEpoch > 0) {
                      final dt = DateTime.fromMillisecondsSinceEpoch(
                          terakhirEpoch * 1000);
                      displayTerakhir =
                          'Terakhir: ${dt.day.toString().padLeft(2, '0')}-'
                          '${dt.month.toString().padLeft(2, '0')}-'
                          '${dt.year} '
                          '${dt.hour.toString().padLeft(2, '0')}:'
                          '${dt.minute.toString().padLeft(2, '0')}';
                    }

                    return Card(
                      child: ListTile(
                        leading: Switch(
                          value: aktif,
                          onChanged: (v) => _toggleAktif(id, aktif),
                        ),
                        title: Text(
                          '$keterangan ($jam)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: aktif ? null : Colors.grey,
                          ),
                        ),
                        subtitle: Text(
                          'Target: $targetGram gram\n'
                          '$displayTerakhir',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editJadwal(id, data),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              onPressed: () => _hapusJadwal(id, keterangan),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          const Divider(thickness: 2),
          const SizedBox(height: 8),
          const Text(
            'Mode Operasi Sistem',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pilih mode keputusan'),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Auto (Sensor)'),
                          value: 'Auto',
                          groupValue: _mode,
                          onChanged: (v) {
                            if (v != null) _setMode(v);
                          },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Manual'),
                          value: 'Manual',
                          groupValue: _mode,
                          onChanged: (v) {
                            if (v != null) _setMode(v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('Profil durasi mode manual'),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Basah'),
                          value: 'Basah',
                          groupValue: _profilManual,
                          onChanged: (v) {
                            if (v != null) _setProfilManual(v);
                          },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Kering'),
                          value: 'Kering',
                          groupValue: _profilManual,
                          onChanged: (v) {
                            if (v != null) _setProfilManual(v);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(thickness: 2),
          const SizedBox(height: 8),
          const Text(
            'Profil Pakan Aktif',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pilih profil pakan yang dimuat di dalam Hopper:'),
                  const SizedBox(height: 8),
                  StreamBuilder<DatabaseEvent>(
                    stream: _kategoriRef.onValue,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const LinearProgressIndicator();
                      }
                      final raw = snapshot.data?.snapshot.value;
                      if (raw == null || raw is! Map) {
                        return const Text('Belum ada profil pakan tersedia.');
                      }

                      final items = <DropdownMenuItem<String>>[];
                      raw.forEach((key, value) {
                        if (value is Map) {
                          final k = key.toString();
                          final nama = value['nama']?.toString() ?? k;
                          items.add(
                              DropdownMenuItem(value: k, child: Text(nama)));
                        }
                      });

                      items.sort((a, b) => (a.child as Text)
                          .data!
                          .compareTo((b.child as Text).data!));

                      return DropdownButtonFormField<String>(
                        value: items.any((e) => e.value == _profilAktifId)
                            ? _profilAktifId
                            : null,
                        decoration:
                            const InputDecoration(border: OutlineInputBorder()),
                        items: items,
                        onChanged: (val) {
                          if (val != null) _setProfilAktif(val);
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PakanPage(scope: widget.scope)),
            ),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Kelola Profil Pakan'),
          ),
        ],
      ),
    );
  }
}
