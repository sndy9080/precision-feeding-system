import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../device_scope.dart';

/// RiwayatPage menampilkan:
/// - Tab 1: daftar log riwayat (Riwayat/<pushKey>)
/// - Tab 2: grafik tren stok dari jarak_cm yang tersimpan di log
///
/// Analogi Arduino:
/// - Node RTDB "Riwayat" = tempat menyimpan data historis (append-only),
///   mirip log di SD card.
/// - Flutter membaca log tersebut realtime dan menampilkannya sebagai list + chart.
class RiwayatPage extends StatefulWidget {
  const RiwayatPage({super.key, required this.scope});

  final DeviceScope scope;

  @override
  State<RiwayatPage> createState() => _RiwayatPageState();
}

class _RiwayatPageState extends State<RiwayatPage>
    with SingleTickerProviderStateMixin {
  /// Filter yang dipilih user untuk Tab Catatan Pakan.
  /// Nilainya: Semua / Jadwal / Instan / Kustom / Gagal
  String _selectedFilter = 'Semua';

  /// Reference ke root node /Riwayat di Firebase RTDB
  DatabaseReference get _riwayatRef => widget.scope.ref.child('Riwayat');

  DatabaseReference get _kalibrasiRef => widget.scope.ref.child('Kalibrasi');

  /// Mengubah kode sesi internal menjadi label UI.
  String _labelSesi(String kode) {
    switch (kode.toUpperCase()) {
      case 'INSTAN':
        return 'Instan';
      case 'KUSTOM':
        return 'Kustom';
      default:
        return 'Jadwal';
    }
  }

  /// Mengecek apakah item cocok dengan filter yang dipilih.
  bool _matchFilter(RiwayatItem item) {
    if (_selectedFilter == 'Semua') return true;

    final sesiUpper = item.sesi.toUpperCase();
    final isGagal = item.hasil.toUpperCase().contains('GAGAL') ||
        item.mode == 'Dibatalkan';

    switch (_selectedFilter) {
      case 'Jadwal':
        return sesiUpper != 'INSTAN' && sesiUpper != 'KUSTOM';
      case 'Instan':
        return sesiUpper == 'INSTAN';
      case 'Kustom':
        return sesiUpper == 'KUSTOM';
      case 'Gagal':
        return isGagal;
      default:
        return true;
    }
  }

  /// Menggabungkan string tanggal+waktu menjadi DateTime.
  /// Format sistem: dd-MM-yyyy + HH:mm
  /// Contoh: "31-05-2026" + "16:05" -> DateTime
  DateTime? _parseTanggalWaktu(String tanggal, String waktu) {
    final fmt = DateFormat('dd-MM-yyyy HH:mm');
    try {
      return fmt.parse('$tanggal $waktu');
    } catch (_) {
      // jika format tidak sesuai, kembalikan null
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // DefaultTabController mengatur TabBar + TabBarView
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Riwayat & Analisis Stok',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Tab bar (2 tab)
            const TabBar(
              tabs: [
                Tab(text: 'Catatan Pakan'),
                Tab(text: 'Tren Stok'),
              ],
            ),
            const SizedBox(height: 12),

            // Expanded supaya konten TabBarView bisa mengisi sisa ruang layar
            Expanded(
              child: StreamBuilder<DatabaseEvent>(
                // onValue = stream realtime: update setiap data di /Riwayat berubah
                stream: _riwayatRef.onValue,
                builder: (context, snapshot) {
                  // Loading awal
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Error stream
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  // Data mentah dari RTDB
                  final raw = snapshot.data?.snapshot.value;
                  if (raw == null) {
                    return const Center(
                        child: Text('Belum ada riwayat pakan.'));
                  }

                  // List hasil parsing dari Map -> List<RiwayatItem>
                  final List<RiwayatItem> items = [];

                  // Struktur /Riwayat biasanya Map:
                  // {
                  //   "-OtJxxx": { ...data... },
                  //   "-OtJyyy": { ...data... }
                  // }
                  if (raw is Map) {
                    final map = Map<String, dynamic>.from(raw);
                    map.forEach((key, value) {
                      if (value is Map) {
                        final v = Map<String, dynamic>.from(value);

                        items.add(
                          RiwayatItem(
                            id: key,
                            tanggal: v['tanggal']?.toString() ?? '-',
                            waktu: v['waktu']?.toString() ?? '-',
                            sesi: v['sesi']?.toString() ??
                                '-', // kode: PAGI/SIANG/...
                            keterangan: v['keterangan']?.toString() ?? '',
                            mode: v['mode']?.toString() ?? '-',
                            profilPakan: v['profil_pakan']?.toString() ?? '',
                            durasiDetik: (v['durasi_detik'] is num)
                                ? (v['durasi_detik'] as num).toDouble()
                                : double.tryParse(
                                        v['durasi_detik']?.toString() ?? '') ??
                                    0.0,
                            targetGram: int.tryParse(
                                    v['target_gram']?.toString() ?? '') ??
                                0,
                            jarakCm:
                                int.tryParse(v['jarak_cm']?.toString() ?? '') ??
                                    0,
                            hasil: v['hasil']?.toString() ?? '',
                          ),
                        );
                      }
                    });
                  }

                  // Sort: terbaru di atas (descending)
                  // Jika DateTime gagal parse -> item tersebut diprioritaskan di bawah.
                  items.sort((a, b) {
                    final ta = _parseTanggalWaktu(a.tanggal, a.waktu);
                    final tb = _parseTanggalWaktu(b.tanggal, b.waktu);

                    if (ta == null && tb == null) return 0;
                    if (ta == null) return 1;
                    if (tb == null) return -1;

                    return tb.compareTo(ta);
                  });

                  if (items.isEmpty) {
                    return const Center(
                        child: Text('Belum ada riwayat pakan.'));
                  }

                  // TabBarView menampilkan konten sesuai tab yang dipilih
                  return TabBarView(
                    children: [
                      _buildCatatanTab(context, items),
                      _buildTrenStokTab(context, items),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TAB 1: Catatan Pakan (List) + filter (ChoiceChip)
  // ============================================================
  Widget _buildCatatanTab(BuildContext context, List<RiwayatItem> items) {
    // Filter sesuai chip yang dipilih
    final filtered = items.where((item) => _matchFilter(item)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Chip filter bisa di-scroll horizontal
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip('Semua'),
              const SizedBox(width: 8),
              _buildFilterChip('Jadwal'),
              const SizedBox(width: 8),
              _buildFilterChip('Instan'),
              const SizedBox(width: 8),
              _buildFilterChip('Kustom'),
              const SizedBox(width: 8),
              _buildFilterChip('Gagal'),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // List log riwayat
        Expanded(
          child: ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = filtered[index];

              // Deteksi gagal:
              // - hasil mengandung "GAGAL"
              // - atau mode == "Dibatalkan" (kasus fail-safe stok habis)
              final hasilUpper = item.hasil.toUpperCase();
              final isGagal =
                  hasilUpper.contains('GAGAL') || item.mode == 'Dibatalkan';

              final sesiLabel = _labelSesi(item.sesi);

              // Judul card: Sesi • Mode • (Keterangan)
              final title = item.keterangan.isNotEmpty
                  ? '$sesiLabel • ${item.mode} • ${item.keterangan}'
                  : '$sesiLabel • ${item.mode}';

              return Card(
                // Warna pink muda kalau gagal
                color: isGagal ? Colors.pink.shade50 : null,
                child: ListTile(
                  leading: Icon(
                    Icons.feed_outlined,
                    color: isGagal ? Colors.red : null,
                  ),
                  title: Text(title),
                  subtitle: Text(
                    '${item.tanggal} • ${item.waktu}\n'
                    'Hasil: ${item.hasil.isEmpty ? '-' : item.hasil}\n'
                    '${item.profilPakan.isNotEmpty ? 'Profil: ${item.profilPakan}\n' : ''}'
                    'Target: ${item.targetGram} Gram\n'
                    'Durasi: ${item.durasiDetik.toStringAsFixed(1)} detik\n'
                    'Jarak: ${item.jarakCm} cm',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// ChoiceChip untuk filter sesi
  Widget _buildFilterChip(String label) {
    final selected = _selectedFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _selectedFilter = label;
        });
      },
    );
  }

  // ============================================================
  // TAB 2: Tren stok pakan (%) dari data jarak_cm dalam riwayat
  // ============================================================
  Widget _buildTrenStokTab(BuildContext context, List<RiwayatItem> items) {
    final stokItems = items.where((e) => e.jarakCm > 0).toList();

    if (stokItems.isEmpty) {
      return const Center(
          child: Text('Belum ada data stok untuk ditampilkan.'));
    }

    stokItems.sort((a, b) {
      final da = _parseTanggalWaktu(a.tanggal, a.waktu);
      final db = _parseTanggalWaktu(b.tanggal, b.waktu);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    return FutureBuilder<DataSnapshot>(
      future: _kalibrasiRef.get(),
      builder: (context, snap) {
        double batasKosongCm = 38.0;
        double batasPenuhCm = 3.0;

        if (snap.hasData && snap.data!.exists && snap.data!.value is Map) {
          final map =
              Map<String, dynamic>.from(snap.data!.value as Map);
          batasKosongCm =
              double.tryParse(map['batas_pakan_minimum']?.toString() ?? '') ??
                  38.0;
          batasPenuhCm =
              double.tryParse(map['jarak_penuh_cm']?.toString() ?? '') ?? 3.0;
        }

        final rentangCm = batasKosongCm - batasPenuhCm;
        if (rentangCm <= 0) {
          return const Center(
              child: Text('Data kalibrasi tidak valid. Periksa halaman Teknisi.'));
        }

        final spots = <FlSpot>[];
        for (final item in stokItems) {
          final dt = _parseTanggalWaktu(item.tanggal, item.waktu);
          if (dt == null) continue;
          final x = dt.millisecondsSinceEpoch.toDouble();
          final jarakValid =
              item.jarakCm.toDouble().clamp(batasPenuhCm, batasKosongCm);
          final persen =
              ((batasKosongCm - jarakValid) / rentangCm * 100).clamp(0.0, 100.0);
          spots.add(FlSpot(x, persen));
        }

        if (spots.length < 2) {
          return const Center(
              child: Text('Data belum cukup untuk membuat grafik.'));
        }

        final xs = spots.map((e) => e.x);
        final minX = xs.reduce((a, b) => a < b ? a : b);
        final maxX = xs.reduce((a, b) => a > b ? a : b);

        final screenWidth = MediaQuery.of(context).size.width;
        const pointWidth = 56.0;
        final chartWidth =
            (spots.length * pointWidth).clamp(screenWidth, screenWidth * 4);

        const labelEvery = Duration(hours: 2);
        final xIntervalMs = labelEvery.inMilliseconds.toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analisis Volume Pakan (%) — Penuh: ${batasPenuhCm.toStringAsFixed(0)} cm, Kosong: ${batasKosongCm.toStringAsFixed(0)} cm',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width: chartWidth.toDouble(),
                  child: Padding(
                    padding: const EdgeInsets.only(
                        right: 24.0, left: 8.0, bottom: 8.0),
                    child: LineChart(
                      LineChartData(
                        minX: minX,
                        maxX: maxX,
                        minY: 0,
                        maxY: 100,
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(
                              y: 20,
                              color: Colors.redAccent,
                              strokeWidth: 2,
                              dashArray: [5, 5],
                              label: HorizontalLineLabel(
                                show: true,
                                alignment: Alignment.topRight,
                                padding: const EdgeInsets.only(
                                    right: 6, bottom: 6),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                                labelResolver: (_) => 'BATAS KRITIS (20%)',
                              ),
                            ),
                          ],
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 20,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: Colors.grey.withOpacity(0.2),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 42,
                              interval: 25,
                              getTitlesWidget: (value, meta) => Text(
                                '${value.toInt()}%',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                              interval: xIntervalMs,
                              getTitlesWidget: (value, meta) {
                                final dt =
                                    DateTime.fromMillisecondsSinceEpoch(
                                  value.toInt(),
                                );
                                return Padding(
                                  padding: const EdgeInsets.only(top: 10.0),
                                  child: Text(
                                    DateFormat('dd/MM\nHH:mm').format(dt),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            preventCurveOverShooting: true,
                            color: Theme.of(context).colorScheme.primary,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.25),
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.0),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ],
                        lineTouchData: LineTouchData(
                          handleBuiltInTouches: true,
                          touchTooltipData: LineTouchTooltipData(
                            tooltipPadding: const EdgeInsets.all(8),
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((barSpot) {
                                final dt =
                                    DateTime.fromMillisecondsSinceEpoch(
                                  barSpot.x.toInt(),
                                );
                                final timeStr = DateFormat(
                                        'dd MMM yyyy • HH:mm')
                                    .format(dt);
                                return LineTooltipItem(
                                  '$timeStr\nVolume: ${barSpot.y.toStringAsFixed(1)}%',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Model data 1 item riwayat.
/// Analogi C++: seperti struct RiwayatItem { ... }
class RiwayatItem {
  final String id;
  final String tanggal;
  final String waktu;

  /// Kode sesi internal: PAGI/SIANG/SORE/INSTAN/KUSTOM
  final String sesi;

  final String keterangan;

  /// Mode sistem saat eksekusi (Auto/Manual/Dibatalkan)
  final String mode;

  /// Nama profil pakan yang digunakan
  final String profilPakan;

  /// Durasi eksekusi motor (detik)
  final double durasiDetik;

  /// Target porsi (gram)
  final int targetGram;

  /// Jarak ultrasonik (cm) sebagai indikator stok
  final int jarakCm;

  /// SUKSES / GAGAL - HABIS / dll
  final String hasil;

  RiwayatItem({
    required this.id,
    required this.tanggal,
    required this.waktu,
    required this.sesi,
    required this.keterangan,
    required this.mode,
    required this.profilPakan,
    required this.durasiDetik,
    required this.targetGram,
    required this.jarakCm,
    required this.hasil,
  });
}
