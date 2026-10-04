import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../device_scope.dart';

class TeknisiPage extends StatefulWidget {
  const TeknisiPage({super.key, required this.scope});

  final DeviceScope scope;

  @override
  State<TeknisiPage> createState() => _TeknisiPageState();
}

class _TeknisiPageState extends State<TeknisiPage> {
  DatabaseReference get _kalibrasiRef => widget.scope.ref.child('Kalibrasi');
  DatabaseReference get _testRef =>
      widget.scope.ref.child('Perintah/test_aktuator');
  DatabaseReference get _konfigurasiRef =>
      widget.scope.ref.child('Konfigurasi');
  DatabaseReference get _otaRef => widget.scope.ref.child('Perintah/ota');
  DatabaseReference get _metaRef => widget.scope.ref.child('meta');

  bool _isAuthenticated = false;
  bool _isLoading = false;

  final _batasPakanController = TextEditingController();
  final _jarakPenuhController = TextEditingController();
  final _adcKeringController = TextEditingController();
  final _adcBasahController = TextEditingController();
  int _timezoneOffsetDetik = 25200;
  String _deviceIp = '';
  bool _otaMode = false;

  @override
  void dispose() {
    _batasPakanController.dispose();
    _jarakPenuhController.dispose();
    _adcKeringController.dispose();
    _adcBasahController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      
      final claimSnap = await widget.scope.ref.child('meta/claim_uid').get();
      if (claimSnap.value?.toString() != uid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hanya pemilik device yang dapat mengakses halaman teknisi.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Owner verified, check PIN
      final prefs = await SharedPreferences.getInstance();
      final pinKey = 'tech_pin_${widget.scope.id}';
      final savedPinHash = prefs.getString(pinKey);

      if (savedPinHash == null) {
        // First time, create PIN
        await _showCreatePinDialog();
      } else {
        // Verify PIN
        await _showVerifyPinDialog(savedPinHash);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memeriksa akses: $e')),
        );
      }
    }
  }

  Future<void> _showCreatePinDialog() async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Buat PIN Teknisi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Buat PIN 4-6 digit untuk akses cepat halaman teknisi.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'PIN Baru (4-6 digit)',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Konfirmasi PIN',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              final pin = pinController.text.trim();
              final confirm = confirmController.text.trim();
              if (pin.length < 4 || pin.length > 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN harus 4-6 digit')),
                );
                return;
              }
              if (pin != confirm) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN tidak sama')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (result == true) {
      final pin = pinController.text.trim();
      final hash = sha256.convert(utf8.encode(pin)).toString();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tech_pin_${widget.scope.id}', hash);
      setState(() => _isAuthenticated = true);
      await _loadData();
    }
  }

  Future<void> _showVerifyPinDialog(String savedHash) async {
    final pinController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Masukkan PIN Teknisi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'PIN Teknisi',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              onSubmitted: (val) => Navigator.pop(ctx, val),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'FORGOT'),
            child: const Text('Lupa PIN?'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, pinController.text.trim()),
            child: const Text('Masuk'),
          ),
        ],
      ),
    );

    if (result == null) return;

    if (result == 'FORGOT') {
      await _showForgotPinDialog();
      return;
    }

    final inputHash = sha256.convert(utf8.encode(result)).toString();
    if (inputHash == savedHash) {
      setState(() => _isAuthenticated = true);
      await _loadData();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN salah!'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showForgotPinDialog() async {
    final emailController = TextEditingController(
      text: FirebaseAuth.instance.currentUser?.email ?? '',
    );
    final passwordController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset PIN Teknisi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Masukkan email dan password untuk reset PIN.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verifikasi'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      final email = emailController.text.trim();
      final password = passwordController.text.trim();

      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await FirebaseAuth.instance.currentUser
          ?.reauthenticateWithCredential(credential);

      await _lanjutResetPin();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String errorMsg;
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          errorMsg = 'Email atau password salah.';
        } else if (e.code == 'user-not-found') {
          errorMsg = 'Email tidak terdaftar.';
        } else if (e.code == 'too-many-requests') {
          errorMsg = 'Terlalu banyak percobaan. Coba lagi nanti.';
        } else {
          errorMsg = 'Verifikasi gagal: ${e.message}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('PigeonUserDetails') ||
          msg.contains('List<Object?>') ||
          msg.contains('type cast')) {
        // Bug internal plugin Firebase versi lama:
        // error ini hanya muncul jika password BENAR
        // (reauthenticate berhasil di native, parse return type di Dart gagal)
        await _lanjutResetPin();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Terjadi kesalahan: $msg'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _lanjutResetPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tech_pin_${widget.scope.id}');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verifikasi berhasil. Silakan buat PIN baru.'),
          backgroundColor: Colors.green,
        ),
      );
    }
    await _showCreatePinDialog();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final kalibrasiSnap = await _kalibrasiRef.get();
      final konfSnap = await _konfigurasiRef.get();
      final metaSnap = await _metaRef.get();

      if (konfSnap.exists && konfSnap.value is Map) {
        final konfMap = Map<String, dynamic>.from(konfSnap.value as Map);
        _timezoneOffsetDetik =
            int.tryParse(konfMap['timezone_offset']?.toString() ?? '') ?? 25200;
      }

      if (kalibrasiSnap.exists && kalibrasiSnap.value is Map) {
        final map = Map<String, dynamic>.from(kalibrasiSnap.value as Map);
        _batasPakanController.text =
            map['batas_pakan_minimum']?.toString() ?? '32';
        _jarakPenuhController.text =
            map['jarak_penuh_cm']?.toString() ?? '3';
        _adcKeringController.text =
            map['adc_kelembapan_kering']?.toString() ?? '';
        _adcBasahController.text =
            map['adc_kelembapan_basah']?.toString() ?? '';
      }

      if (metaSnap.exists && metaSnap.value is Map) {
        final metaMap = Map<String, dynamic>.from(metaSnap.value as Map);
        setState(() {
          _deviceIp = metaMap['ip_address']?.toString() ?? '';
          _otaMode = metaMap['ota_mode'] == true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat data: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _simpanParameter() async {
    final batasMin = int.tryParse(_batasPakanController.text) ?? 32;
    final jarakPenuh = int.tryParse(_jarakPenuhController.text) ?? 3;
    final adcKering = int.tryParse(_adcKeringController.text);
    final adcBasah = int.tryParse(_adcBasahController.text);

    if (jarakPenuh >= batasMin) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Jarak saat penuh harus LEBIH KECIL dari batas minimum (kosong).'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if ((adcKering == null) != (adcBasah == null) ||
        (adcKering != null && (adcKering < 0 || adcBasah! < 0))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Isi kedua nilai ADC kelembaban atau kosongkan keduanya.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      await _kalibrasiRef.update({
        'batas_pakan_minimum': batasMin,
        'jarak_penuh_cm': jarakPenuh,
        'adc_kelembapan_kering': adcKering,
        'adc_kelembapan_basah': adcBasah,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Parameter berhasil disimpan!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e')),
        );
      }
    }
  }

  Future<void> _bacaSensorUntukKalibrasi() async {
    final monRef = widget.scope.ref.child('Perintah/sensor');
    try {
      await monRef.update({'minta_update': true, 'respon': 'Menunggu'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meminta ESP32 baca sensor...')),
        );
      }

      bool done = false;
      for (int i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final snap =
            await widget.scope.ref.child('Perintah/sensor/minta_update').get();
        if (snap.value == false || snap.value == null) {
          done = true;
          break;
        }
      }

      if (!done || !mounted) return;

      final jarakSnap =
          await widget.scope.ref.child('Monitoring/jarak_cm').get();
      final jarak = jarakSnap.value?.toString() ?? '-';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Jarak sensor saat ini: $jarak cm'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 5),
          ),
        );

        final konfirmasi = await showDialog<_IsiKalibrasi>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Gunakan nilai ini?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Jarak sensor sekarang: $jarak cm',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text(
                    'Isi ke field kalibrasi mana?\n'
                    '• "Penuh" → posisi hopper terisi pakan penuh\n'
                    '• "Kosong" → posisi hopper nyaris habis',
                    style: TextStyle(fontSize: 13)),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal')),
              OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(ctx, _IsiKalibrasi.penuh),
                  child: const Text('Isi ke Penuh')),
              ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(ctx, _IsiKalibrasi.kosong),
                  child: const Text('Isi ke Kosong')),
            ],
          ),
        );

        if (konfirmasi == _IsiKalibrasi.penuh) {
          _jarakPenuhController.text = jarak;
        } else if (konfirmasi == _IsiKalibrasi.kosong) {
          _batasPakanController.text = jarak;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal baca sensor: $e')),
        );
      }
    }
  }

  Future<void> _bacaAdcUntukKalibrasi() async {
    final monRef = widget.scope.ref.child('Perintah/sensor');
    try {
      await monRef.update({'minta_update': true, 'respon': 'Menunggu'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meminta ESP32 baca ADC kelembaban...')),
        );
      }

      bool done = false;
      for (int i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final snap =
            await widget.scope.ref.child('Perintah/sensor/minta_update').get();
        if (snap.value == false || snap.value == null) {
          done = true;
          break;
        }
      }

      if (!done || !mounted) return;

      final adcSnap =
          await widget.scope.ref.child('Monitoring/kelembaban').get();
      final adc = adcSnap.value?.toString() ?? '-';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ADC kelembaban saat ini: $adc'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 5),
          ),
        );

        final konfirmasi = await showDialog<_IsiKalibrasi>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Gunakan nilai ADC ini?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ADC kelembaban sekarang: $adc',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text(
                    'Kondisi pakan saat ini:\n'
                    '• "Kering" → pakan kering (ADC tinggi ~3000-4000)\n'
                    '• "Basah" → pakan basah (ADC rendah ~1000-2000)\n\n'
                    'PENTING: Pastikan kondisi pakan sudah benar sebelum membaca!',
                    style: TextStyle(fontSize: 13)),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal')),
              OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(ctx, _IsiKalibrasi.basah),
                  child: const Text('Isi ke ADC Basah')),
              ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(ctx, _IsiKalibrasi.kering),
                  child: const Text('Isi ke ADC Kering')),
            ],
          ),
        );

        if (konfirmasi == _IsiKalibrasi.kering) {
          _adcKeringController.text = adc;
        } else if (konfirmasi == _IsiKalibrasi.basah) {
          _adcBasahController.text = adc;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal baca ADC kelembaban: $e')),
        );
      }
    }
  }

  static const _timezoneOptions = <MapEntry<int, String>>[
    MapEntry(-43200, 'UTC-12:00 — Baker Island'),
    MapEntry(-39600, 'UTC-11:00 — American Samoa'),
    MapEntry(-36000, 'UTC-10:00 — Hawaii'),
    MapEntry(-34200, 'UTC-09:30 — Marquesas'),
    MapEntry(-32400, 'UTC-09:00 — Alaska'),
    MapEntry(-28800, 'UTC-08:00 — Los Angeles'),
    MapEntry(-25200, 'UTC-07:00 — Denver'),
    MapEntry(-21600, 'UTC-06:00 — Chicago'),
    MapEntry(-18000, 'UTC-05:00 — New York'),
    MapEntry(-14400, 'UTC-04:00 — Caracas'),
    MapEntry(-10800, 'UTC-03:00 — Buenos Aires'),
    MapEntry(-7200, 'UTC-02:00 — South Georgia'),
    MapEntry(-3600, 'UTC-01:00 — Azores'),
    MapEntry(0, 'UTC+00:00 — London'),
    MapEntry(3600, 'UTC+01:00 — Paris'),
    MapEntry(7200, 'UTC+02:00 — Cairo'),
    MapEntry(10800, 'UTC+03:00 — Moscow'),
    MapEntry(12600, 'UTC+03:30 — Tehran'),
    MapEntry(14400, 'UTC+04:00 — Dubai'),
    MapEntry(16200, 'UTC+04:30 — Kabul'),
    MapEntry(18000, 'UTC+05:00 — Karachi'),
    MapEntry(19800, 'UTC+05:30 — New Delhi'),
    MapEntry(20700, 'UTC+05:45 — Kathmandu'),
    MapEntry(21600, 'UTC+06:00 — Dhaka'),
    MapEntry(23400, 'UTC+06:30 — Yangon'),
    MapEntry(25200, 'UTC+07:00 — Jakarta (WIB)'),
    MapEntry(28800, 'UTC+08:00 — Makassar (WITA)'),
    MapEntry(31500, 'UTC+08:45 — Eucla'),
    MapEntry(32400, 'UTC+09:00 — Jayapura (WIT)'),
    MapEntry(34200, 'UTC+09:30 — Adelaide'),
    MapEntry(36000, 'UTC+10:00 — Sydney'),
    MapEntry(37800, 'UTC+10:30 — Lord Howe'),
    MapEntry(39600, 'UTC+11:00 — Noumea'),
    MapEntry(43200, 'UTC+12:00 — Auckland'),
    MapEntry(45900, 'UTC+12:45 — Chatham Islands'),
    MapEntry(46800, 'UTC+13:00 — Samoa'),
    MapEntry(50400, 'UTC+14:00 — Kiritimati'),
  ];

  Future<void> _simpanTimezone() async {
    try {
      await _konfigurasiRef.update({'timezone_offset': _timezoneOffsetDetik});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zona waktu kandang berhasil diterapkan.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan zona waktu: $e')),
        );
      }
    }
  }

  Future<void> _testMotor2() async {
    final pwmController = TextEditingController(text: '240');
    final durasiController = TextEditingController(text: '5000');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test Motor 2 (Distribusi)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pwmController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PWM Motor 2',
                hintText: '240',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: durasiController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Durasi (ms)',
                hintText: '5000',
                border: OutlineInputBorder(),
              ),
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
            child: const Text('Jalankan Test'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final pwm = int.tryParse(pwmController.text) ?? 240;
    final durasi = int.tryParse(durasiController.text) ?? 5000;

    try {
      await _testRef.update({
        'aktif': true,
        'tipe': 'M2_ONLY',
        'pwm_m1': 0,
        'pwm_m2': pwm,
        'durasi_ms': durasi,
        'respon': 'Menunggu',
        'hasil_waktu_ms': 0,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perintah test dikirim ke ESP32...')),
        );
      }
      await _pantauResponTest();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim test: $e')),
        );
      }
    }
  }

  Future<void> _testMotor1Motor2() async {
    final pwmM1Controller = TextEditingController(text: '95');
    final pwmM2Controller = TextEditingController(text: '240');
    final durasiController = TextEditingController(text: '4600');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test Motor 1 + Motor 2'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pwmM1Controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PWM Motor 1 (Dosing)',
                hintText: '95',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pwmM2Controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PWM Motor 2 (Distribusi)',
                hintText: '240',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: durasiController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Durasi (ms)',
                hintText: '4600',
                border: OutlineInputBorder(),
              ),
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
            child: const Text('Jalankan Test'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final pwmM1 = int.tryParse(pwmM1Controller.text) ?? 95;
    final pwmM2 = int.tryParse(pwmM2Controller.text) ?? 240;
    final durasi = int.tryParse(durasiController.text) ?? 4600;

    try {
      await _testRef.update({
        'aktif': true,
        'tipe': 'M1_M2_COMBINED',
        'pwm_m1': pwmM1,
        'pwm_m2': pwmM2,
        'durasi_ms': durasi,
        'respon': 'Menunggu',
        'hasil_waktu_ms': 0,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perintah test dikirim ke ESP32...')),
        );
      }
      await _pantauResponTest();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim test: $e')),
        );
      }
    }
  }

  Future<void> _aktifkanOTA() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aktifkan Mode OTA?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ESP32 akan masuk ke mode update firmware selama 10 menit.',
            ),
            if (_deviceIp.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Setelah aktif, buka browser di jaringan LAN yang sama:',
                        style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 4),
                    SelectableText(
                      'http://$_deviceIp/update',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Pastikan file .bin firmware tersedia sebelum melanjutkan.',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aktifkan OTA',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _otaRef.update({'aktif': true});
      setState(() => _otaMode = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_deviceIp.isNotEmpty
                ? 'Mode OTA aktif. Buka: http://$_deviceIp/update'
                : 'Perintah OTA dikirim ke ESP32...'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim perintah OTA: $e')),
        );
      }
    }
  }

  Future<void> _pantauResponTest() async {
    final subscription = _testRef.child('aktif').onValue.listen((event) async {
      final value = event.snapshot.value;
      if (value == false || value == null) {
        final responSnap = await _testRef.child('respon').get();
        final hasil = responSnap.value?.toString() ?? 'Selesai';
        if (mounted) {
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
    await Future.delayed(const Duration(seconds: 60));
    await subscription.cancel();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Halaman Teknisi',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Halaman ini hanya untuk pemilik device.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _authenticate,
                      child: const Text('Verifikasi Akses'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Konfigurasi Kandang',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () => setState(() => _isAuthenticated = false),
                tooltip: 'Keluar',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            icon: Icons.public,
            title: 'Zona Waktu Kandang',
            children: [
              DropdownButtonFormField<int>(
                value: _timezoneOffsetDetik,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Zona Waktu Lokasi Kandang',
                  border: OutlineInputBorder(),
                ),
                items: _timezoneOptions
                    .map((option) => DropdownMenuItem(
                          value: option.key,
                          child: Text(option.value),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null)
                    setState(() => _timezoneOffsetDetik = value);
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _simpanTimezone,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Terapkan Zona Waktu'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            icon: Icons.tune,
            title: 'Parameter Fisik Kandang',
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cara kalibrasi hopper:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '1. Isi hopper penuh → tekan "Baca Sensor" → pilih "Isi ke Penuh"\n'
                      '2. Biarkan hopper hampir kosong → tekan "Baca Sensor" → pilih "Isi ke Kosong"\n'
                      '3. Tekan Simpan.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _bacaSensorUntukKalibrasi,
                  icon: const Icon(Icons.sensors),
                  label: const Text('Baca Sensor Ultrasonik Sekarang'),
                ),
              ),
              const SizedBox(height: 14),
              _buildTextField(
                controller: _jarakPenuhController,
                label: 'Jarak saat Hopper PENUH (cm)',
                hint: '3',
                helperText: 'Jarak ultrasonik ke pakan saat hopper terisi penuh',
              ),
              _buildTextField(
                controller: _batasPakanController,
                label: 'Jarak saat Hopper KOSONG / Batas Minimum (cm)',
                hint: '32',
                helperText: 'Jarak ultrasonik saat pakan habis — pemberian akan diblokir',
              ),
              const Text(
                'Kalibrasi Kelembaban (opsional)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Baca nilai ADC saat sampel pakan kering dan basah. ESP32 memakai titik tengah kedua nilai.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _bacaAdcUntukKalibrasi,
                  icon: const Icon(Icons.water_drop_outlined),
                  label: const Text('Baca ADC Kelembaban Sekarang'),
                ),
              ),
              const SizedBox(height: 14),
              _buildTextField(
                controller: _adcKeringController,
                label: 'ADC pakan KERING',
                hint: '3000',
              ),
              _buildTextField(
                controller: _adcBasahController,
                label: 'ADC pakan BASAH',
                hint: '1500',
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _simpanParameter,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Simpan Parameter'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            icon: Icons.build_circle_outlined,
            title: 'Pengujian Mekanik',
            children: [
              const Text(
                'Jalankan aktuator secara langsung untuk verifikasi hardware.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _testMotor2,
                  icon: const Icon(Icons.settings_input_antenna),
                  label: const Text('Test Motor 2 — Konveyor Distribusi'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _testMotor1Motor2,
                  icon: const Icon(Icons.settings_input_composite),
                  label: const Text('Test Motor 1 + Motor 2 — Kombinasi'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            icon: Icons.system_update_alt,
            title: 'Pembaruan Firmware (OTA)',
            children: [
              if (_otaMode)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_tethering, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Mode OTA sedang aktif di ESP32',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange)),
                            if (_deviceIp.isNotEmpty)
                              SelectableText(
                                'http://$_deviceIp/update',
                                style: const TextStyle(
                                    fontSize: 13, fontFamily: 'monospace'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                'Kirim perintah ke ESP32 untuk masuk mode update firmware.\n'
                'ESP32 dan HP/laptop harus dalam jaringan WiFi yang sama.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              if (_deviceIp.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.router, size: 16, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    Text('IP Alat: $_deviceIp',
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13)),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _otaMode ? null : _aktifkanOTA,
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                      _otaMode ? 'Mode OTA Sedang Aktif...' : 'Aktifkan Mode OTA'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Mode OTA akan otomatis nonaktif setelah 10 menit atau setelah upload selesai.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? helperText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          border: const OutlineInputBorder(),
          isDense: false,
        ),
      ),
    );
  }
}

enum _IsiKalibrasi { penuh, kosong, kering, basah }
