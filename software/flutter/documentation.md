# DOKUMENTASI SISTEM TERPADU

Dokumen ini adalah ekstrak arsitektur dari source code aktif proyek `pakan_ternak_iot_v2`. Isi mendeskripsikan perilaku yang benar-benar terprogram, bukan target desain.

## 1. Gambaran Arsitektur

```text
Flutter client
  ├─ Firebase Authentication: email/password
  ├─ Firebase Realtime Database (RTDB)
  └─ local notification Android
            │
            ▼
Firebase RTDB
  ├─ users/{uid}/devices/{deviceId}
  └─ devices/{deviceId}/...
            ▲
            │ polling command, telemetry, Riwayat, heartbeat
ESP32 DevKit V1
  ├─ WiFiManager captive portal
  ├─ Firebase anonymous authentication
  ├─ NTP
  ├─ HC-SR04, ADC kelembaban, PIR
  ├─ dua kanal motor PWM
  ├─ LittleFS queue Riwayat offline
  └─ ElegantOTA HTTP LAN
```

Device ID berasal dari eFuse MAC, format `ESP32_<12_HEX_UPPERCASE>`. Semua data operasional diisolasi pada `devices/{deviceId}`. App memilih device melalui `DeviceScope`; firmware menulis/membaca path device yang sama.

---

# Pilar Perangkat Keras (ESP32)

Source utama: `Source_Code_ESP32/Source_Code_ESP32.ino`.

## 2. Perangkat, pin, dan library

| Komponen | Konfigurasi |
|---|---|
| Board | ESP32 DevKit V1 |
| Motor 1 forward/reverse | GPIO 18 / GPIO 19 |
| Motor 2 forward/reverse | GPIO 22 / GPIO 23 |
| Sensor kelembaban analog | GPIO 36, ADC1 |
| PIR | GPIO 34 |
| HC-SR04 trigger/echo | GPIO 26 / GPIO 35 |
| Tombol BOOT/reset | GPIO 0, `INPUT_PULLUP` |
| PWM | LEDC 5 kHz, resolusi 8 bit, channel 0-3 |
| Offline storage | LittleFS |
| OTA | `WebServer` sinkron + ElegantOTA pada HTTP port 80 |

Firmware menggunakan `WiFiManager`, `Firebase_ESP_Client`, NTP, `Preferences`, LittleFS, ESP task watchdog, dan ElegantOTA. Skema partisi yang dinyatakan source: `Minimal SPIFFS (1.9MB APP with OTA/190KB SPIFFS)`.

Tidak ada load-cell, encoder motor, current sensing, jam detector, limit switch, relay hardware cut-off, sensor suhu, RFID, Bluetooth, MQTT, atau FCM pada firmware.

## 3. Urutan boot

1. Membuka serial pada 115200 baud.
2. Mengaktifkan task watchdog dengan timeout 45 detik.
3. Menginisialisasi GPIO sensor/BOOT dan LEDC PWM.
4. Menghentikan semua motor dengan PWM seluruh channel `0`.
5. Membentuk `deviceId` dari eFuse MAC.
6. Membentuk `factoryProof` SHA-256 dari master key internal dan `deviceId`.
7. Mengambil atau membuat pairing code delapan karakter dari NVS `Preferences` namespace `pakan_iot`, key `pair_code`.
8. Mengecek status image OTA rollback.
9. Mount LittleFS; jika gagal, firmware memformat LittleFS lalu mount ulang.
10. Menjalankan WiFiManager.
11. Sinkronisasi NTP memakai offset default WIB.
12. Firebase anonymous sign-in.
13. Sinkronisasi timezone dari RTDB.
14. Memuat kalibrasi serta profil pakan aktif.
15. Menulis status PIR standby, IP LAN, dan `meta/ota_mode=false`.

Firebase bootstrap menulis `meta/factory_proof`, `meta/device_uid`, `meta/pairing_code`, `meta/status=online`, dan `meta/last_seen_epoch`. UID device adalah UID Firebase anonymous, bukan UID pemilik.

## 4. Provisioning Wi-Fi dan tombol fisik

Jika kredensial Wi-Fi belum tersedia atau koneksi gagal, WiFiManager membuka captive portal SSID `PakanTernak-Setup`. Portal menampilkan Device ID dan pairing code. Timeout portal 180 detik; timeout koneksi 30 detik. Gagal koneksi menyebabkan restart.

Wi-Fi power-save dimatikan dan auto reconnect diaktifkan.

| Input GPIO 0 | Aksi |
|---|---|
| Lepas sebelum 3 detik | Batal |
| Tahan 3 sampai kurang dari 10 detik, lalu lepas | Hapus kredensial WiFiManager, restart |
| Tahan minimal 10 detik | Masuk mode OTA |

## 5. Loop utama dan penjadwalan firmware

Firmware memakai single loop, bukan RTOS task terpisah. Operasi motor memakai `delay()`, sehingga loop berhenti selama motor berjalan.

| Proses | Frekuensi/kondisi |
|---|---|
| Evaluasi jadwal pakan | Setiap putaran loop |
| Poll command sensor, pakan instan, test aktuator, OTA | Setiap 3 detik |
| Pull timezone | Setiap 10 menit |
| Pull kalibrasi dan profil | Setiap 10 menit |
| Monitoring PIR pasca-pakan | Setiap putaran loop |
| Sinkron queue LittleFS | Setiap 30 detik |
| Heartbeat `online` | Setiap 2 menit |
| Scan pairing request | Maksimal tiap 5 detik |
| Reset saat Firebase tidak ready | Setelah 15 menit tanpa `Firebase.ready()` |
| Daily restart | Pukul 02:00 berdasarkan NTP |

Saat OTA aktif, loop normal dihentikan total. Firmware hanya memanggil `otaServer.handleClient()` dan `ElegantOTA.loop()` sampai upload selesai atau timeout.

## 6. Pairing dari sisi firmware

1. Pairing code dibuat sekali dan bertahan di NVS sebelum perangkat diklaim.
2. Firmware menulis code ke `devices/{deviceId}/meta/pairing_code`.
3. Firmware membaca seluruh `pairing_requests` setiap maksimal lima detik.
4. Jika nilai request cocok dengan pairing code lokal, key request dianggap UID pemohon.
5. Firmware menulis UID tersebut ke `meta/claim_uid`.
6. Firmware menghapus `meta/pairing_code`, seluruh node `pairing_requests`, dan pairing code NVS.
7. Flag `sudahDiklaim` disimpan pada RAM sampai reboot.

Tidak ada expiry pairing code, rate limit, transaksi atomik claim, atau mekanisme unpair/transfer ownership.

## 7. Sensor

### 7.1 Ultrasonik dan stok

HC-SR04 mengirim trigger 10 mikrodetik. Jarak dihitung `durasi * 0.034 / 2`. Hasil di luar 0-100 cm dipaksa menjadi 100 cm. Nilai ditulis ke `Monitoring/jarak_cm`.

Jarak dipakai untuk:

- persentase stok di app;
- threshold stok minimum sebelum dispensing;
- grafik Riwayat stok;
- data jarak akhir pada Riwayat pakan.

`pulseIn(ECHO_PIN, HIGH)` tidak memakai timeout eksplisit.

### 7.2 Sensor kelembaban

GPIO 36 dibaca dengan `analogRead()`. Nilai raw ADC ditulis ke `Monitoring/kelembaban`.

Threshold keputusan firmware:

1. Default `2243`.
2. Bila `adc_kelembapan_kering` dan `adc_kelembapan_basah` tersedia, threshold menjadi titik tengah dua nilai tersebut.
3. ADC `< threshold` berarti `Basah`; ADC `>= threshold` berarti `Kering`.

Dashboard saat ini selalu memakai threshold `2243`, tanpa membaca kalibrasi atau profil aktif. Label kelembaban UI dapat berbeda dengan keputusan firmware setelah kalibrasi.

### 7.3 PIR

PIR bukan trigger pemberian pakan. PIR aktif hanya setelah dispensing sukses.

- Durasi monitoring: satu jam.
- Cooldown laporan gerakan: lima menit.
- Status RTDB: `(Standby)`, `Memantau Gerakan...`, atau `Kambing Terdeteksi di Palung Pakan!`.

## 8. Aktuator dan dispensing

Motor 1 adalah dosing; Motor 2 conveyor/distribusi. Saat feed normal firmware hanya menggerakkan channel forward Motor 1 dan Motor 2. Channel reverse tersedia tetapi tidak dipakai dalam alur dispensing.

Alur `eksekusiPemberianPakan`:

1. Baca jarak hopper dan ADC kelembaban.
2. Tulis telemetry `Monitoring`.
3. Reload profil pakan aktif.
4. Tentukan kondisi `Basah`/`Kering`.
   - Mode `Auto`: keputusan ADC.
   - Mode `Manual`: nilai `Konfigurasi/profil_manual`.
5. Batalkan bila `jarakAwal >= Kalibrasi/batas_pakan_minimum`.
6. Pilih parameter profil kondisi tersebut.
7. Clamp `target_gram` antara `gram_min` dan `gram_max`.
8. Map gram menjadi PWM Motor 1 antara `pwm_min` dan `pwm_max`.
9. Motor 2 memakai `pwm_motor2` profil.
10. Jalankan kedua motor selama `durasi_distribusi_ms`.
11. Stop semua motor.
12. Baca jarak akhir.
13. Tulis Riwayat.
14. Tulis respons command instan bila dipanggil dari instan.
15. Mode Manual diubah kembali ke `Auto`.
16. Aktifkan monitoring PIR.

Porsi bukan closed-loop weight dispensing. `target_gram` hanya mengatur PWM Motor 1; berat keluaran tidak diukur dan durasi tetap berasal dari profil.

## 9. Jadwal pakan firmware

Jadwal disimpan dalam `Jadwal/{pushId}`. Firmware membutuhkan NTP valid dan Firebase ready untuk mengevaluasinya.

Syarat eksekusi:

- `aktif=true`;
- waktu saat ini berada pada `[jam, jam + toleransi_menit]`;
- belum berjalan dalam 12 jam terakhir menurut `terakhir_epoch`.

Jendela yang melewati tengah malam ditangani. Sesudah eksekusi, firmware memperbarui `terakhir_epoch`. Default data app memakai `toleransi_menit=30`.

Jika Firebase offline, jadwal tidak dijalankan. Firmware tidak menyimpan cache jadwal lokal.

## 10. Command RTDB yang dipoll firmware

| Node | Request app | Aksi firmware |
|---|---|---|
| `Perintah/pakan` | `aktif`, `tipe=INSTAN`, `keterangan`, `target_gram`, `respon` | Feed instan; reset `aktif=false`, kosongkan keterangan |
| `Perintah/sensor` | `minta_update=true`, `respon` | Baca ultrasonik + ADC, update Monitoring, set respons |
| `Perintah/test_aktuator` | `aktif`, `tipe`, `pwm_m1`, `pwm_m2`, `durasi_ms` | Test `M2_ONLY` atau `M1_M2_COMBINED`, simpan waktu hasil dan respons |
| `Perintah/ota` | `aktif=true` | Masuk mode OTA HTTP LAN, reset flag request |

Feed instan gagal bila NTP belum valid. Test aktuator menerima PWM dan durasi langsung dari RTDB tanpa bounds check firmware.

## 11. Riwayat offline LittleFS

Jika push Riwayat gagal, firmware menulis entri NDJSON ke LittleFS. Queue dibatasi 50 entri; saat penuh, entri lama dibuang. Setiap 30 detik firmware mencoba mengirim queue ke RTDB. Sinkronisasi berhenti setelah tiga kegagalan pada satu siklus.

Queue hanya melindungi Riwayat. Telemetry sensor, command, heartbeat, status jadwal, dan pairing tidak diantrikan offline.

## 12. OTA

OTA dapat dipicu dari RTDB atau tombol fisik 10 detik.

1. Firmware mengaktifkan `WebServer` HTTP port 80.
2. `ElegantOTA.begin(&otaServer)` dipanggil.
3. Firmware menulis `meta/ota_mode=true`, `meta/ip_address`, serta mematikan `Perintah/ota/aktif`.
4. Operator membuka `http://{meta.ip_address}/update` pada jaringan Wi-Fi yang sama.
5. Timeout 10 menit menyebabkan `ota_mode=false` dan restart.

OTA tidak memakai HTTPS, password eksplisit, firmware signing eksplisit, Firebase Storage, atau service cloud OTA. Mode OTA menghentikan jadwal, polling command, PIR, heartbeat, pairing, dan sinkronisasi queue.

Firmware memiliki kode validasi/rollback partition OTA, namun image pending ditandai valid segera pada awal setup; cabang rollback berdasarkan batas 30 detik secara praktis tidak menjadi health-check runtime efektif.

---

# Pilar Pangkalan Data (Firebase RTDB)

## 13. Firebase Authentication

Flutter memakai Firebase Auth email/password untuk operator. ESP32 memakai anonymous Firebase sign-in dan menyimpan UID anonymous sebagai `meta/device_uid`.

Tidak ada email verification, MFA, custom claims, role backend, atau lifecycle cleanup anonymous user.

## 14. Struktur RTDB aktual

```text
users/{uid}/devices/{deviceId}
  nama

devices/{deviceId}
  meta/
    device_id
    factory_proof
    device_uid
    pairing_code
    claim_uid
    nama
    status
    last_seen_epoch
    ip_address
    ota_mode

  pairing_requests/{requestUid}: pairingCode

  Kalibrasi/
    batas_pakan_minimum
    jarak_penuh_cm
    adc_kelembapan_kering
    adc_kelembapan_basah

  KategoriPakan/{profileId}/
    nama
    batas_kelembaban
    kering/{durasi_distribusi_ms,pwm_min,pwm_max,pwm_motor2,gram_min,gram_max}
    basah/{durasi_distribusi_ms,pwm_min,pwm_max,pwm_motor2,gram_min,gram_max}

  Konfigurasi/
    mode
    profil_manual
    profil_pakan_aktif
    timezone_offset

  Jadwal/{pushId}/
    jam
    target_gram
    aktif
    keterangan
    terakhir_epoch
    toleransi_menit

  Monitoring/
    jarak_cm
    kelembaban
    aktivitas_pir

  Perintah/
    pakan/{aktif,tipe,keterangan,target_gram,respon}
    sensor/{minta_update,respon}
    test_aktuator/{aktif,tipe,pwm_m1,pwm_m2,durasi_ms,hasil_waktu_ms,respon}
    ota/{aktif}

  Riwayat/{pushId}/
    tanggal
    waktu
    sesi
    keterangan
    mode
    profil_pakan
    durasi_detik
    target_gram
    jarak_cm
    hasil
```

Template export RTDB lebih kecil dari schema runtime: beberapa field firmware seperti `factory_proof`, `device_uid`, `last_seen_epoch`, IP OTA, `ota_mode`, kalibrasi ADC, dan `Perintah/ota` lahir dari source runtime.

## 15. Real-time exchange dan presence

- Flutter mendengar node device dengan stream RTDB untuk dashboard, Riwayat, jadwal, status, dan command response.
- ESP32 melakukan polling command tiap 3 detik, bukan listener streaming.
- ESP32 menulis heartbeat `meta/status=online` dan `meta/last_seen_epoch` tiap dua menit.
- Flutter menampilkan online jika `now - last_seen_epoch <= 300` detik.
- Sebelum daily restart, firmware mencoba menulis `status=offline`.

Tidak ada `onDisconnect()` RTDB. Mati listrik, crash, dan putus Wi-Fi dapat membiarkan nilai `status=online`; UI akhirnya menganggap offline setelah lima menit dari timestamp.

## 16. Rules dan hak akses

Rules aktif berada di `database.rules.json`.

| Node | Read | Write |
|---|---|---|
| `users/{uid}` | UID sendiri | UID sendiri |
| `devices/{id}` root | `device_uid` atau `claim_uid` | root write ditolak |
| `meta` | seluruh user authenticated | dibatasi per field |
| `Monitoring` | mengikuti akses device | hanya `device_uid` |
| `Riwayat` | mengikuti akses device | hanya `device_uid` |
| `Perintah` | owner atau device UID | owner atau device UID |
| `Kalibrasi` | owner atau device UID | hanya owner |
| `Konfigurasi`, `Jadwal` | owner atau device UID | owner atau device UID |
| `KategoriPakan` | owner atau device UID | hanya owner |
| `pairing_requests/{uid}` | hanya device UID | pemohon UID sendiri atau device UID |

Rules mengindeks `Riwayat` pada `tanggal` dan `waktu`. App tidak memakai query; seluruh Riwayat dibaca lalu disort client-side.

## 17. Catatan keamanan RTDB aktual

1. `meta` dapat dibaca setiap user authenticated. Sebelum claim, node memuat `pairing_code`, `factory_proof`, `device_uid`, dan dapat memuat IP LAN.
2. ESP32 anonymous auth juga memenuhi `auth != null`.
3. User authenticated yang mengetahui/menebak device ID dapat membaca pairing code, menulis request memakai UID sendiri, lalu berpotensi menjadi claimant pertama saat firmware memproses request.
4. `factory_proof` dihitung firmware tetapi tidak divalidasi rules untuk otorisasi claim.
5. Owner dapat menulis parameter command test aktuator tanpa validasi value rules; firmware langsung memakai PWM dan durasi.
6. Device anonymous UID memiliki hak write lebih luas daripada kebutuhan normal, termasuk `Konfigurasi`, `Jadwal`, dan `Perintah`.
7. Tidak ada unpair, transfer owner, expiry pairing, rate limit, proof backend, atau transactional ownership claim.

---

# Pilar Perangkat Lunak (Flutter)

## 18. Bootstrap dan navigasi

`main()` menginisialisasi Flutter binding, Firebase, lalu Workmanager sebelum `runApp`. `AuthGate` mendengar `FirebaseAuth.instance.authStateChanges()`.

| Kondisi | Halaman |
|---|---|
| Belum login | `LoginPage` |
| Login, belum memilih alat | `DeviceHomePage` |
| Device aktif | `MainScaffold` |

Tab device aktif: Dashboard, Pengaturan, Riwayat, Teknisi. Semua reference device memakai `DeviceScope.id` dan menargetkan `devices/{id}`.

## 19. Akun pengguna

### Login

Login memakai email dan password Firebase Auth.

### Registrasi

Registrasi membuat Firebase email/password account. Validasi app hanya memastikan password minimal enam karakter.

### Reset password

App memanggil Firebase `sendPasswordResetEmail`.

Tidak ada verifikasi email, profil pengguna RTDB, role admin, atau MFA.

## 20. Pairing pengguna

Flow app:

1. User login dan membuka daftar alat.
2. User memasukkan Device ID `ESP32_[0-9A-F]{12}`, nama hopper, dan pairing code delapan karakter `[A-Z0-9]{8}`.
3. App membaca `meta/claim_uid`.
4. Jika claim milik UID sama, app memulihkan mapping `users/{uid}/devices/{deviceId}`.
5. Jika claim milik UID lain, app menolak pairing.
6. Jika belum claim, app menulis `pairing_requests/{uid}=pairingCode`.
7. App mendengar `meta/claim_uid` maksimal 20 detik.
8. Saat UID sendiri muncul, app menulis nama ke mapping user dan `meta/nama`.

Daftar alat menampilkan online/offline memakai `last_seen_epoch`, bukan nilai `meta/status` secara langsung.

## 21. Dashboard dan operasional harian

Dashboard membaca realtime `Monitoring`, `Kalibrasi`, command state, dan PIR.

Fitur:

- pakan instan dengan target gram dan keterangan;
- refresh sensor manual;
- estimasi stok dari jarak penuh dan batas minimum;
- visual indikator stok;
- label kelembaban;
- status PIR;
- local notification stok kritis.

Command pakan instan:

```json
{
  "tipe": "INSTAN",
  "keterangan": "...",
  "target_gram": 500,
  "aktif": true,
  "respon": "Menunggu"
}
```

App menunggu `aktif=false` atau response firmware. Timeout 60 detik memaksa `aktif=false` dan menandai gagal. Command refresh sensor memakai pola sama dengan `minta_update=true` dan timeout 60 detik.

Input gram app menerima integer; firmware yang melakukan clamp terhadap range profil aktif.

## 22. Pengaturan dan jadwal

Pengaturan menyediakan:

- CRUD Jadwal realtime;
- toggle jadwal aktif;
- konfigurasi mode `Auto`/`Manual`;
- pilihan `profil_manual`;
- pemilihan `profil_pakan_aktif`;
- akses CRUD kategori/profil pakan.

Jadwal baru memiliki `jam`, `target_gram`, `aktif`, `keterangan`, `terakhir_epoch=0`, dan `toleransi_menit=30`. App tidak memvalidasi overlap schedule, batas toleransi, rentang gram, atau konflik antara jadwal dan command lain.

## 23. Profil pakan

`KategoriPakan/{profileId}` memiliki konfigurasi terpisah untuk Basah dan Kering:

- `durasi_distribusi_ms`;
- PWM minimum/maksimum Motor 1;
- PWM Motor 2;
- gram minimum/maksimum;
- threshold kelembaban pada data profil.

Firmware memuat profil aktif saat feed dan tiap 10 menit. Menghapus profil aktif tidak dicegah app. Jika load firmware gagal, firmware mempertahankan profile aktif/default di RAM.

## 24. Riwayat dan grafik

Firmware push Riwayat sukses atau gagal stok habis. App subscribe seluruh node `Riwayat`, menyortirnya di client, dan menyediakan filter Semua, Jadwal, Instan, Kustom, dan Gagal.

Grafik stok menghitung ulang persentase dari `jarak_cm` Riwayat dan nilai kalibrasi. Tidak ada pagination, retention, aggregation, export, atau delete Riwayat. Pertumbuhan log meningkatkan payload dan kerja client.

## 25. Teknisi

Akses Teknisi butuh dua lapis lokal/client:

1. Firebase UID harus sama dengan `meta/claim_uid`.
2. PIN teknisi per device disimpan sebagai SHA-256 di SharedPreferences dengan key `tech_pin_{deviceId}`.

PIN teknisi tidak menjadi boundary RTDB. Rules Firebase tetap menentukan otorisasi nyata.

Fitur teknisi:

- Set offset timezone UTC-12 sampai UTC+14.
- Kalibrasi hopper dari request pembacaan sensor: menetapkan jarak penuh dan batas stok minimum; app memvalidasi `jarakPenuh < batasMin`.
- Kalibrasi ADC kelembaban: sampel Kering/Basah harus keduanya tersedia atau keduanya kosong.
- Test Motor 2 (`M2_ONLY`).
- Test kombinasi Motor 1 dan 2 (`M1_M2_COMBINED`).
- Trigger OTA dan menampilkan URL LAN.

Metadata OTA dimuat sekali setelah autentikasi PIN, bukan stream realtime. Status UI dapat stale setelah restart firmware.

## 26. Notifikasi

Notifikasi terimplementasi hanya local notification Android untuk stok kritis.

- Channel `stok_kritis`.
- Priority/importance tinggi.
- Trigger sekali ketika persentase stok `<=20%`.
- Flag reset ketika stok kembali `>20%`.

Listener berjalan saat Dashboard aktif. Tidak ada FCM, push server-side, request permission runtime Android 13+, notifikasi background stok, notifikasi PIR, device offline, gagal motor, schedule gagal, pairing, atau OTA.

Manifest Android mendeklarasikan `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `POST_NOTIFICATIONS`, dan `VIBRATE`.

## 27. Workmanager

Callback Workmanager `custom_schedule_worker_v1` tersedia dan mampu menulis `Perintah/pakan` tipe `KUSTOM`. Tidak ada `registerOneOffTask`, `registerPeriodicTask`, atau scheduling task ditemukan. Fitur background custom schedule tidak aktif pada source saat ini; jadwal produksi berjalan di ESP32.

## 28. Platform

- Android aktif; label aplikasi `iPakan`.
- Konfigurasi Firebase tersedia untuk Web, Android, iOS, macOS, dan Windows.
- Linux secara eksplisit `UnsupportedError` pada Firebase options.
- `GoogleService-Info.plist` iOS tidak ditemukan.
- iOS tidak memiliki deklarasi local network permission maupun `NSLocalNetworkUsageDescription`, padahal OTA memakai HTTP LAN.
- Android release menggunakan debug signing config dan application ID masih `com.example.pakan_ternak_iot`.

---

# Protokol Kegagalan (Fail-Safe & Edge Cases)

## 29. Mekanisme pertahanan terimplementasi

| Kondisi | Perlindungan aktual |
|---|---|
| Startup/reset | Semua motor di-stop saat init PWM |
| Setelah feed/test | Semua channel PWM diset `0` |
| Hopper stok rendah/kosong | Feed dibatalkan jika `jarak >= batas_pakan_minimum`; Riwayat gagal ditulis |
| Pakan instan tanpa waktu valid | Firmware menolak bila NTP belum valid |
| RTDB Riwayat gagal tulis | NDJSON LittleFS, maksimum 50 entri, sync tiap 30 detik |
| Firebase tidak ready lama | Restart firmware setelah 15 menit |
| Wi-Fi terputus | WiFiManager/autoreconnect; provisioning fallback melalui portal |
| Konfigurasi Wi-Fi salah | Tombol fisik 3-<10 detik menghapus credentials dan restart |
| OTA macet | Timeout 10 menit, keluar mode OTA lalu restart |
| Firmware hang | Task watchdog 45 detik, di-reset setiap loop |
| Akumulasi runtime | Restart harian pukul 02:00 |
| Stok kritis di dashboard | Local notification sekali pada <=20% |
| Jadwal duplikat dekat | `terakhir_epoch` mencegah eksekusi ulang selama 12 jam |

## 30. Batas fail-safe dan edge case aktual

### 30.1 Internet/Firebase putus

- Firmware hanya queue Riwayat, bukan jadwal atau command.
- Schedule return tanpa eksekusi jika Firebase belum ready.
- Offline panjang membuat jadwal terlewat.
- Telemetry dan heartbeat tidak memiliki queue.
- `Firebase.ready()` yang gagal 15 menit memicu restart.

### 30.2 Mati listrik/crash

- Motor berhenti karena daya hilang; boot berikutnya juga stop motor dahulu.
- RTDB tidak memakai `onDisconnect()`.
- `meta/status` dapat tertinggal `online` sampai UI melewati threshold timestamp lima menit.
- Pairing state dan flag claim tidak mendapat recovery workflow khusus.

### 30.3 Sensor abnormal

- Ultrasonik di luar 0-100 cm dipaksa 100 cm, yang dapat dibaca sebagai kondisi stok habis.
- `pulseIn` tidak memiliki timeout eksplisit.
- Tidak ada median filter, debounce, diagnosis kabel putus, atau sensor health status.
- ADC kelembaban tanpa validasi range/disconnect; nilai raw tetap dipakai untuk memilih Basah/Kering.

### 30.4 Motor dan aktuator

- Command test tidak membatasi `pwm_m1`, `pwm_m2`, atau `durasi_ms` pada firmware maupun RTDB Rules.
- Feed/test memakai `delay()`, sehingga loop dan WDT feed tertunda selama durasi operasi.
- Tidak ada current sensing, jam detection, timeout maksimum firmware, limit switch, feedback putaran, atau emergency-stop command.
- Tidak ada verifikasi bahwa pakan keluar; jarak akhir hanya telemetry, bukan interlock hasil dispensing.

### 30.5 Konflik command

- Loop single-thread dan `delay()` membuat command dieksekusi serial secara implisit.
- Tidak ada state machine atau lock eksplisit untuk konflik jadwal, instan, test motor, dan OTA.
- Timeout app 60 detik dapat mengubah `aktif=false` saat device masih menjalankan motor dengan durasi panjang atau belum sempat polling.
- Mode OTA menghentikan operasi normal tanpa antrian atau penolakan command khusus.

### 30.6 Pairing dan hak akses

- `meta` terbaca semua authenticated user, termasuk pairing code pre-claim.
- Anonymous Firebase identity dapat menjadi request UID.
- Pairing takeover mungkin bila pihak lain membaca code dan request diproses lebih dahulu.
- Tidak ada expiry/revoke/transfer ownership.

### 30.7 OTA

- OTA HTTP LAN tidak memakai TLS, password eksplisit, atau signature verification.
- Endpoint bergantung keamanan jaringan lokal.
- Saat OTA, automation berhenti sampai selesai atau timeout.
- Rollback code tidak menghasilkan 30-second post-boot health check yang efektif.

### 30.8 Skala data dan UI

- Riwayat dibaca penuh dan disortir client-side.
- Semakin banyak log, semakin besar bandwidth/memori/latensi halaman Riwayat.
- Rules index ada, tetapi app belum memakai query/pagination.

---

# 31. Batas Sistem Saat Ini

1. Penjadwalan produksi bergantung Firebase dan NTP; tidak offline-capable.
2. Dispensing berbasis PWM/durasi, bukan gram measured feedback.
3. Notification hanya local Android saat Dashboard terbuka.
4. Presence hanya heuristic timestamp, tidak disconnect-aware.
5. OTA hanya LAN HTTP dan menghentikan automation.
6. Rules mengizinkan akses command cukup luas untuk owner/device UID tanpa validation parameter.
7. Pairing belum memiliki proteksi claim yang kuat terhadap user authenticated lain.
8. Tidak ada lifecycle unpair, device ownership recovery, atau transfer ownership.

# 32. Artefak Source Utama

| Artefak | Peran |
|---|---|
| `Source_Code_ESP32/Source_Code_ESP32.ino` | Firmware ESP32, hardware, Firebase, schedule, command, fail-safe, OTA |
| `database.rules.json` | RTDB authorization dan index |
| `RTDB Structure/sistem-otomasi-pakan-ternak-default-rtdb-export.json` | Template struktur RTDB |
| `lib/main.dart` | Bootstrap, AuthGate, tab, Workmanager callback |
| `lib/device_scope.dart` | Scope device aktif |
| `lib/pages/login_page.dart` | Login, registrasi, reset password |
| `lib/pages/device_home_page.dart` | Pairing, daftar alat, online status |
| `lib/pages/dashboard_page.dart` | Operasi harian, command pakan/sensor, stok, PIR, notification |
| `lib/pages/pengaturan_page.dart` | Jadwal, mode, profil aktif |
| `lib/pages/pakan_page.dart` | CRUD profil pakan |
| `lib/pages/riwayat_page.dart` | Riwayat dan grafik stok |
| `lib/pages/teknisi_page.dart` | Kalibrasi, test motor, timezone, PIN, OTA |
| `lib/notification_service.dart` | Local notification stok kritis |
| `firebase.json` | Target Firebase RTDB dan rules |
| `pubspec.yaml` | Dependensi Flutter |

