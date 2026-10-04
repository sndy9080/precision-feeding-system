/*
  =========================================================
  SISTEM OTOMASI PAKAN RUMPUT CACAH - DOUBLE STAGE CONVEYOR
  Oleh      : Sendy Tegar Mahendra [TK0122004]
  Versi     : V8.1 (WebServer Architecture Pivot)
  Platform  : ESP32 DEVKIT V1
  =========================================================

  CHANGELOG V8.1:
  - [FIX] Pivot arsitektur OTA: ESPAsyncWebServer → WebServer standar bawaan ESP32
  - [FIX] ElegantOTA kini berjalan di mode WebServer sinkron (default & stabil)
  - [PRESERVED] Semua fitur V8.0 dipertahankan

  PARTISI WAJIB (satu kali via Arduino IDE sebelum flash):
  Tools -> Partition Scheme -> Minimal SPIFFS (1.9MB APP with OTA/190KB SPIFFS)

  LIBRARY TAMBAHAN (install via Library Manager):
  - LittleFS (built-in ESP32 Arduino - sudah tersedia)
  - ElegantOTA by ayushsharma82
*/

#include <WiFi.h>
#include <WiFiManager.h>
#include <Preferences.h>
#include <mbedtls/md.h>
#include <esp_task_wdt.h>
#include <esp_wifi.h>
#include <Firebase_ESP_Client.h>
#include "time.h"
#include <LittleFS.h>
#include <vector>
#include <WebServer.h>
#include <ElegantOTA.h>
#include <esp_ota_ops.h>

#define WDT_TIMEOUT 45

// PROVIDE CREDENTIALS FOR FIREBASE
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

// 1. PENGATURAN FIREBASE (WiFi dikelola WiFiManager, tanpa hardcode)
#define DATABASE_URL ""
#define API_KEY ""

const char* FACTORY_MASTER_KEY = ""; //ex: PROJECT_TK_UMUKA_SENDY_IOT_2026_X9
String factoryProof;
String pairingCode;
String anonymousUid;

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// 2. PEMETAAN PIN (PIN MAPPING)
#define M1_RPWM 18
#define M1_LPWM 19
#define M2_RPWM 22
#define M2_LPWM 23
#define SOIL_PIN 36 // ADC1
#define PIR_PIN 34  // Input Only
#define TRIG_PIN 26
#define ECHO_PIN 35 // Input Only
#define RESET_PIN 0

// 3. KONFIGURASI PWM (seberapa cepat sinyal on-off dalam satu detik (Hz))
const int pwmFreq = 5000;
const int pwmResolution = 8;
const int chM1_R = 0; const int chM1_L = 1;
const int chM2_R = 2; const int chM2_L = 3;

// =======================================================
// KALIBRASI GLOBAL & PROFIL PAKAN AKTIF (dibaca dari RTDB)
// =======================================================
int batasPakanMinimum = 32;
int jarakHopperPenuh  = 3;
int adcKelembapanKering = -1;
int adcKelembapanBasah  = -1;

struct KondisiPakan {
  int durasiDistribusiMs;
  int pwmMin;
  int pwmMax;
  int pwmMotor2;
  int gramMin;
  int gramMax;
};

struct ProfilPakan {
  String id;
  String nama;
  int batasKelembaban;
  KondisiPakan kering;
  KondisiPakan basah;
};

ProfilPakan profilPakanAktif = {
  "", "Default", 2243,
  {4600, 95, 170, 240, 500, 1000},
  {4600, 90, 150, 220, 500, 1000}
};

// 4. VARIABEL GLOBAL WAKTU
const char* ntpServer = "time.google.com";
long  gmtOffset_sec = 25200;  // default WIB (GMT+7), akan ditimpa dari RTDB
const int   daylightOffset_sec = 0;

// 5. VARIABEL GLOBAL SISTEM
unsigned long waktuTerakhirSukses = 0;
unsigned long lastCheckFirebase = 0;

// 6. VARIABEL PIR POST-FEED COOLDOWN
bool pirAktif = false;
unsigned long pirMulaiWaktu = 0;
unsigned long pirTerakhirDeteksi = 0;
const unsigned long DURASI_PANTAU_PIR = 3600000;
const unsigned long COOLDOWN_PIR = 300000;

// =========
// PATH RTDB
// =========
String deviceId;
String deviceRoot;

const char* devicePath(const char* suffix) {
  static String path;
  path = deviceRoot + "/" + suffix;
  return path.c_str();
}

// Path helpers — fungsi (bukan macro) agar tidak ada UB saat evaluasi argumen
// dan tidak membebani preprocessor dengan nested function call expansion
static inline String pCfgMode()        { return deviceRoot + "/Konfigurasi/mode"; }
static inline String pCfgProfil()      { return deviceRoot + "/Konfigurasi/profil_manual"; }
static inline String pCfgPakan()       { return deviceRoot + "/Konfigurasi/profil_pakan_aktif"; }
static inline String pCfgTimezone()    { return deviceRoot + "/Konfigurasi/timezone_offset"; }
static inline String pKalibrasi()      { return deviceRoot + "/Kalibrasi"; }
static inline String pKategoriPakan()  { return deviceRoot + "/KategoriPakan"; }
static inline String pJadwal()         { return deviceRoot + "/Jadwal"; }
static inline String pCmdPakanAktif()  { return deviceRoot + "/Perintah/pakan/aktif"; }
static inline String pCmdPakanGram()   { return deviceRoot + "/Perintah/pakan/target_gram"; }
static inline String pCmdPakanKet()    { return deviceRoot + "/Perintah/pakan/keterangan"; }
static inline String pCmdPakanResp()   { return deviceRoot + "/Perintah/pakan/respon"; }
static inline String pCmdSensReq()     { return deviceRoot + "/Perintah/sensor/minta_update"; }
static inline String pCmdSensResp()    { return deviceRoot + "/Perintah/sensor/respon"; }
static inline String pCmdTestAktif()   { return deviceRoot + "/Perintah/test_aktuator/aktif"; }
static inline String pCmdTestTipe()    { return deviceRoot + "/Perintah/test_aktuator/tipe"; }
static inline String pCmdTestPwmM1()   { return deviceRoot + "/Perintah/test_aktuator/pwm_m1"; }
static inline String pCmdTestPwmM2()   { return deviceRoot + "/Perintah/test_aktuator/pwm_m2"; }
static inline String pCmdTestDurasi()  { return deviceRoot + "/Perintah/test_aktuator/durasi_ms"; }
static inline String pCmdTestHasil()   { return deviceRoot + "/Perintah/test_aktuator/hasil_waktu_ms"; }
static inline String pCmdTestResp()    { return deviceRoot + "/Perintah/test_aktuator/respon"; }
static inline String pCmdOtaAktif()    { return deviceRoot + "/Perintah/ota/aktif"; }
static inline String pMonJarak()       { return deviceRoot + "/Monitoring/jarak_cm"; }
static inline String pMonKelem()       { return deviceRoot + "/Monitoring/kelembaban"; }
static inline String pMonPir()         { return deviceRoot + "/Monitoring/aktivitas_pir"; }
static inline String pLog()            { return deviceRoot + "/Riwayat"; }
static inline String pMetaIp()         { return deviceRoot + "/meta/ip_address"; }
static inline String pMetaOta()        { return deviceRoot + "/meta/ota_mode"; }

// ============================
// OTA SERVER
// ============================
WebServer otaServer(80);
bool otaModeAktif = false;
unsigned long otaMulaiWaktu = 0;
const unsigned long OTA_TIMEOUT_MS = 600000; // 10 menit auto-exit

// ============================
// OFFLINE LOG (LittleFS)
// ============================
#define OFFLINE_LOG_PATH "/offline_log.ndjson"
#define OFFLINE_LOG_MAX_ENTRIES 50

// ============================
// PROTOTYPE FUNGSI
// ============================
void initPins();
void initPWM();
void initWiFiManager();
void cekTombolReset();
String buatFactoryProof();
String buatKodePairing();
void cekPairing();
void initNTP();
void initFirebase();
void muatKalibrasi();
void muatProfilPakanAktif();
void sinkronTimezone();
void cekAntiBootloop();

void cekJadwalPakan();
void cekPerintahSensor();
void cekPerintahPakan();
void cekPerintahTestAktuator();
void cekPerintahOTA();
void cekAktivitasPIR();

void eksekusiPemberianPakan(String kodeSesi, String keterangan, String tanggal, String jam, int targetGram);

int bacaUltrasonik();
void stopSemuaMotor();

String bacaStringDenganDefault(const String& path, const String& defaultValue);

void simpanKeOfflineLog(FirebaseJson& jsonData);
void cekDanSinkronOfflineLog();

void aktifkanModeOTA();
void loopOTA();

// ============================
// SETUP
// ============================
void setup() {
  Serial.begin(115200);

  // Watchdog Timer (auto-recovery)
  esp_task_wdt_init(WDT_TIMEOUT, true);
  esp_task_wdt_add(NULL);

  initPins();
  initPWM();
  uint64_t mac = ESP.getEfuseMac();
  char macText[13];
  snprintf(macText, sizeof(macText), "%012llX", mac);
  deviceId = String("ESP32_") + macText;
  deviceRoot = String("devices/") + deviceId;
  factoryProof = buatFactoryProof();
  pairingCode = buatKodePairing();

  cekAntiBootloop();

  if (!LittleFS.begin(true)) {
    Serial.println("[LittleFS] Gagal mount, format ulang...");
    LittleFS.format();
    LittleFS.begin();
  }
  Serial.println("[LittleFS] Siap.");

  initWiFiManager();
  initNTP();
  initFirebase();
  sinkronTimezone();
  muatKalibrasi();

  Serial.println("\n[SISTEM] V8.1 Siap Beroperasi!");
  Firebase.RTDB.setString(&fbdo, pMonPir().c_str(), "(Standby)");
  Firebase.RTDB.setString(&fbdo, pMetaIp().c_str(), WiFi.localIP().toString());
  Firebase.RTDB.setBool(&fbdo, pMetaOta().c_str(), false);
}

// ============================
// LOOP UTAMA
// ============================

unsigned long lastSinkronTimezone = 0;
unsigned long lastMuatKalibrasi = 0;
unsigned long lastSinkronOffline = 0;
unsigned long lastHeartbeat = 0;

void loop() {
  esp_task_wdt_reset();

  if (otaModeAktif) {
    loopOTA();
    return;
  }

  cekTombolReset();

  // 1) Cek jadwal harian real-time
  cekJadwalPakan();

  // 2) Cek perintah dari aplikasi tiap 3 detik
  if (millis() - lastCheckFirebase > 3000) {
    cekPerintahSensor();
    cekPerintahPakan();
    cekPerintahTestAktuator();
    cekPerintahOTA();
    lastCheckFirebase = millis();
  }

  // 3) Sinkronisasi timezone tiap 10 menit
  if (millis() - lastSinkronTimezone > 600000) {
    sinkronTimezone();
    lastSinkronTimezone = millis();
  }

  // 4) Muat ulang kalibrasi & profil aktif tiap 10 menit
  if (millis() - lastMuatKalibrasi > 600000) {
    muatKalibrasi();
    lastMuatKalibrasi = millis();
  }

  // 5) PIR monitoring pasca pakan
  cekAktivitasPIR();

  // 6) Sinkron offline log tiap 30 detik
  if (millis() - lastSinkronOffline > 30000) {
    cekDanSinkronOfflineLog();
    lastSinkronOffline = millis();
  }

  // 7) Heartbeat status online tiap 2 menit
  if (millis() - lastHeartbeat > 120000) {
    if (Firebase.ready()) {
      time_t now;
      time(&now);
      Firebase.RTDB.setString(&fbdo, devicePath("meta/status"), "online");
      Firebase.RTDB.setInt(&fbdo, devicePath("meta/last_seen_epoch"), (int)now);
    }
    lastHeartbeat = millis();
  }

  // Catat waktu jika firebase ready
  if (Firebase.ready()) {
    cekPairing();
    waktuTerakhirSukses = millis();
  }

  // Jika 15 menit firebase hang -> restart paksa
  if (millis() - waktuTerakhirSukses > 900000) {
    Serial.println("[ERROR] Firebase Timeout! Force Restart...");
    ESP.restart();
  }
}

// ==========================================
// MODUL 1: INISIALISASI HARDWARE & JARINGAN
// ==========================================
void initPins() {
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(PIR_PIN, INPUT);
  pinMode(RESET_PIN, INPUT_PULLUP);
}

void cekTombolReset() {
  static unsigned long waktuMulaiTekan = 0;
  static bool sedangDitekan = false;
  static bool otaTriggered = false;

  bool tombolLow = (digitalRead(RESET_PIN) == LOW);

  if (tombolLow) {
    if (!sedangDitekan) {
      sedangDitekan = true;
      otaTriggered = false;
      waktuMulaiTekan = millis();
      Serial.println("[SISTEM] Tombol BOOT ditekan, menahan...");
    } else {
      unsigned long durasi = millis() - waktuMulaiTekan;
      if (durasi >= 10000 && !otaTriggered) {
        otaTriggered = true;
        Serial.println("[OTA] Tombol ditahan 10 detik -> Aktifkan Mode OTA");
        aktifkanModeOTA();
      } else if (durasi >= 3000 && durasi < 10000) {
        // 3 detik: reset WiFi (ditampilkan sebagai progress)
      }
    }
  } else {
    if (sedangDitekan) {
      unsigned long durasi = millis() - waktuMulaiTekan;
      if (durasi >= 3000 && durasi < 10000) {
        Serial.println("[SISTEM] Mereset Kredensial WiFi...");
        WiFiManager wm;
        wm.resetSettings();
        ESP.restart();
      } else if (durasi < 3000) {
        Serial.println("[SISTEM] Batal reset, tombol dilepas.");
      }
    }
    sedangDitekan = false;
    otaTriggered = false;
    waktuMulaiTekan = 0;
  }
}

void initPWM() {
  ledcSetup(chM1_R, pwmFreq, pwmResolution);
  ledcSetup(chM1_L, pwmFreq, pwmResolution);
  ledcSetup(chM2_R, pwmFreq, pwmResolution);
  ledcSetup(chM2_L, pwmFreq, pwmResolution);

  ledcAttachPin(M1_RPWM, chM1_R);
  ledcAttachPin(M1_LPWM, chM1_L);
  ledcAttachPin(M2_RPWM, chM2_R);
  ledcAttachPin(M2_LPWM, chM2_L);

  stopSemuaMotor();
}

void initWiFiManager() {
  Serial.println("[WiFi] Memulai WiFiManager...");
  esp_task_wdt_delete(NULL);

  WiFiManager wm;
  wm.setConfigPortalTimeout(180);
  wm.setConnectTimeout(30);

  // Custom HTML untuk portal
  String html = "<br/><hr/><br/><h3>Status Alat</h3>"
                "<b>ID Alat:</b> " + deviceId + "<br/>"
                "<b>Kode Pairing:</b> <span style='background:#ffeb3b;padding:2px 5px;border-radius:4px'>" + pairingCode + "</span><br/><br/>"
                "<small>Salin ID dan Kode di atas ke aplikasi Pakan Ternak untuk melakukan klaim perangkat.</small><br/><hr/>";
  
  WiFiManagerParameter customInfo(html.c_str());
  wm.addParameter(&customInfo);

  bool connected = wm.autoConnect("PakanTernak-Setup");

  esp_task_wdt_add(NULL);
  esp_task_wdt_reset();

  if (!connected) {
    Serial.println("[WiFi] Gagal terhubung setelah portal. Restart...");
    delay(1000);
    ESP.restart();
  }

  esp_wifi_set_ps(WIFI_PS_NONE);
  WiFi.setAutoReconnect(true);

  Serial.println("[WiFi] BERHASIL terhubung!");
  Serial.print("[WiFi] IP: ");
  Serial.println(WiFi.localIP());
}

String buatFactoryProof() {
  mbedtls_md_context_t ctx;
  mbedtls_md_type_t md_type = MBEDTLS_MD_SHA256;

  String payloadStr = String(FACTORY_MASTER_KEY) + deviceId;
  const char* payload = payloadStr.c_str();
  size_t payloadLength = payloadStr.length();

  byte shaResult[32];
  mbedtls_md_init(&ctx);
  mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(md_type), 0);
  mbedtls_md_starts(&ctx);
  mbedtls_md_update(&ctx, (const unsigned char*)payload, payloadLength);
  mbedtls_md_finish(&ctx, shaResult);
  mbedtls_md_free(&ctx);

  char hex[65];
  for (int i = 0; i < 32; i++) {
    sprintf(hex + (i * 2), "%02x", shaResult[i]);
  }
  return String(hex);
}

String buatKodePairing() {
  Preferences pref;
  pref.begin("pakan_iot", false);
  String kode = pref.getString("pair_code", "");
  
  if (kode == "") {
    const char charset[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    for (int i = 0; i < 8; i++) {
      kode += charset[random(0, 36)];
    }
    pref.putString("pair_code", kode);
  }
  pref.end();
  return kode;
}

void initNTP() {
  configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
}

void initFirebase() {
  Serial.print("[FIREBASE] Meminta akses ke server... ");
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;

  config.token_status_callback = tokenStatusCallback;

  auth.user.email = "";
  auth.user.password = "";

  Serial.print("[FIREBASE] Sign in anonymously... ");
  if (Firebase.signUp(&config, &auth, "", "")) {
    Serial.println("OK");
  } else {
    Serial.print("GAGAL: ");
    Serial.println(config.signer.signupError.message.c_str());
  }

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  unsigned long start = millis();
  while (!Firebase.ready() && millis() - start < 15000) {
    Serial.print(".");
    delay(250);
  }
  Serial.println(Firebase.ready() ? " BERHASIL!" : " TIMEOUT!");
  
  if (Firebase.ready()) {
    anonymousUid = auth.token.uid.c_str();
    
    // Tulis bootstrap data (hanya berhasil jika belum diklaim atau factoryProof valid)
    Firebase.RTDB.setString(&fbdo, devicePath("meta/factory_proof"), factoryProof);
    Firebase.RTDB.setString(&fbdo, devicePath("meta/device_uid"), anonymousUid);
    time_t now;
    time(&now);
    Firebase.RTDB.setString(&fbdo, devicePath("meta/pairing_code"), pairingCode);
    Firebase.RTDB.setString(&fbdo, devicePath("meta/status"), "online");
    Firebase.RTDB.setInt(&fbdo, devicePath("meta/last_seen_epoch"), (int)now);
    lastHeartbeat = millis();
  }
}

// ==========================================
// ANTI-BOOTLOOP CHECK (OTA Safety)
// ==========================================
void cekAntiBootloop() {
  const esp_partition_t* running = esp_ota_get_running_partition();
  const esp_partition_t* boot    = esp_ota_get_boot_partition();

  if (running == NULL || boot == NULL) return;

  esp_ota_img_states_t otaState;
  if (esp_ota_get_state_partition(running, &otaState) != ESP_OK) return;

  if (otaState == ESP_OTA_IMG_PENDING_VERIFY) {
    if (millis() < 30000) {
      Serial.println("[OTA] Firmware baru terdeteksi, menandai VALID...");
      esp_ota_mark_app_valid_cancel_rollback();
      Serial.println("[OTA] Firmware V8.1 dinyatakan VALID. Rollback dibatalkan.");
    } else {
      Serial.println("[OTA] Firmware baru gagal boot dalam 30 detik, ROLLBACK!");
      esp_ota_mark_app_invalid_rollback_and_reboot();
    }
  }
}

void cekPairing() {
  static unsigned long lastCheck = 0;
  static bool sudahDiklaim = false;

  // Jika sudah diklaim di sesi ini, tidak perlu cek lagi
  if (sudahDiklaim) return;

  if (millis() - lastCheck < 5000) return;
  lastCheck = millis();

  // Cek apakah sudah diklaim
  if (Firebase.RTDB.getString(&fbdo, devicePath("meta/claim_uid"))) {
    String currentClaim = fbdo.stringData();
    if (currentClaim.length() > 0) {
      // Sudah diklaim — bersihkan artefak pairing sekali saja
      sudahDiklaim = true;
      Serial.println("[PAIRING] Perangkat telah diklaim oleh UID: " + currentClaim);

      Preferences pref;
      pref.begin("pakan_iot", false);
      bool kodeAda = pref.getString("pair_code", "") != "";
      if (kodeAda) {
        pref.putString("pair_code", "");
        // Hapus node RTDB hanya jika masih ada (agar tidak flood write)
        Firebase.RTDB.deleteNode(&fbdo, devicePath("meta/pairing_code"));
        Firebase.RTDB.deleteNode(&fbdo, devicePath("pairing_requests"));
        Serial.println("[PAIRING] Artefak pairing dibersihkan.");
      }
      pref.end();
      return;
    }
  }

  // Belum diklaim — cek request pairing yang masuk
  if (!Firebase.RTDB.getJSON(&fbdo, devicePath("pairing_requests"))) return;

  FirebaseJson &json = fbdo.jsonObject();
  size_t len = json.iteratorBegin();
  String key, value;
  int type = 0;

  for (size_t i = 0; i < len; i++) {
    json.iteratorGet(i, type, key, value);
    // Strip tanda kutip ganda yang dibawa FirebaseJson iterator untuk tipe string
    if (value.length() >= 2 && value.startsWith("\"") && value.endsWith("\"")) {
      value = value.substring(1, value.length() - 1);
    }

    if (value != pairingCode) continue;

    Serial.println("[PAIRING] Permintaan valid dari UID: " + key);

    // Set claim_uid dulu — ini yang ditunggu aplikasi
    if (!Firebase.RTDB.setString(&fbdo, devicePath("meta/claim_uid"), key)) {
      Serial.println("[PAIRING] Gagal tulis claim_uid: " + fbdo.errorReason());
      break;
    }

    Serial.println("[PAIRING] claim_uid berhasil ditulis. Alat diklaim!");
    sudahDiklaim = true;

    // Beri jeda singkat agar stream di sisi app sempat menerima claim_uid
    // sebelum pairing_requests dihapus (tidak kritis, tapi mengurangi race)
    delay(500);

    // Bersihkan artefak pairing
    Firebase.RTDB.deleteNode(&fbdo, devicePath("meta/pairing_code"));
    Firebase.RTDB.deleteNode(&fbdo, devicePath("pairing_requests"));

    Preferences pref;
    pref.begin("pakan_iot", false);
    pref.putString("pair_code", "");
    pref.end();

    Serial.println("[PAIRING] Selesai. Artefak dibersihkan.");
    break;
  }
  json.iteratorEnd();
}

void muatKalibrasi() {
  Serial.print("[KALIBRASI] Memuat parameter global... ");
  if (!Firebase.ready()) return;

  if (Firebase.RTDB.getJSON(&fbdo, pKalibrasi().c_str())) {
    FirebaseJson &json = fbdo.jsonObject();
    FirebaseJsonData data;
    if (json.get(data, "batas_pakan_minimum") && data.success)
      batasPakanMinimum = data.intValue;
    if (json.get(data, "jarak_penuh_cm") && data.success)
      jarakHopperPenuh = data.intValue;
    if (json.get(data, "adc_kelembapan_kering") && data.success)
      adcKelembapanKering = data.intValue;
    if (json.get(data, "adc_kelembapan_basah") && data.success)
      adcKelembapanBasah = data.intValue;
    Serial.printf("BERHASIL! (kosong=%dcm, penuh=%dcm, adcKering=%d, adcBasah=%d)\n",
                  batasPakanMinimum, jarakHopperPenuh, adcKelembapanKering, adcKelembapanBasah);
  } else {
    Serial.println("GAGAL (Gunakan nilai default)");
  }

  muatProfilPakanAktif();
}

void muatProfilPakanAktif() {
  if (!Firebase.ready()) return;

  if (!Firebase.RTDB.getString(&fbdo, pCfgPakan().c_str())) {
    Serial.println("[PAKAN] Pointer profil aktif tidak ditemukan.");
    return;
  }

  String idBaru = fbdo.stringData();
  String pathProfil = pKategoriPakan() + "/" + idBaru;

  if (!Firebase.RTDB.getJSON(&fbdo, pathProfil.c_str())) {
    Serial.println("[PAKAN] Profil aktif gagal dimuat.");
    return;
  }

  FirebaseJson &json = fbdo.jsonObject();
  FirebaseJsonData data;
  ProfilPakan kandidat = profilPakanAktif;
  kandidat.id = idBaru;

  if (json.get(data, "nama") && data.success) kandidat.nama = data.stringValue;
  if (json.get(data, "batas_kelembaban") && data.success) kandidat.batasKelembaban = data.intValue;

  if (json.get(data, "kering/durasi_distribusi_ms") && data.success) kandidat.kering.durasiDistribusiMs = data.intValue;
  if (json.get(data, "kering/pwm_min") && data.success) kandidat.kering.pwmMin = data.intValue;
  if (json.get(data, "kering/pwm_max") && data.success) kandidat.kering.pwmMax = data.intValue;
  if (json.get(data, "kering/pwm_motor2") && data.success) kandidat.kering.pwmMotor2 = data.intValue;
  if (json.get(data, "kering/gram_min") && data.success) kandidat.kering.gramMin = data.intValue;
  if (json.get(data, "kering/gram_max") && data.success) kandidat.kering.gramMax = data.intValue;

  if (json.get(data, "basah/durasi_distribusi_ms") && data.success) kandidat.basah.durasiDistribusiMs = data.intValue;
  if (json.get(data, "basah/pwm_min") && data.success) kandidat.basah.pwmMin = data.intValue;
  if (json.get(data, "basah/pwm_max") && data.success) kandidat.basah.pwmMax = data.intValue;
  if (json.get(data, "basah/pwm_motor2") && data.success) kandidat.basah.pwmMotor2 = data.intValue;
  if (json.get(data, "basah/gram_min") && data.success) kandidat.basah.gramMin = data.intValue;
  if (json.get(data, "basah/gram_max") && data.success) kandidat.basah.gramMax = data.intValue;

  profilPakanAktif = kandidat;
  Serial.println("[PAKAN] Profil aktif: " + profilPakanAktif.nama);
}

// ==========================================
// SINKRONISASI TIMEZONE DARI RTDB
// ==========================================
void sinkronTimezone() {
  if (!Firebase.ready()) return;

  Serial.print("[TIMEZONE] Mengambil offset dari RTDB... ");

  if (Firebase.RTDB.getInt(&fbdo, pCfgTimezone().c_str())) {
    long offsetBaru = (long)fbdo.intData();

    if (offsetBaru != gmtOffset_sec) {
      gmtOffset_sec = offsetBaru;
      configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
      Serial.printf("BERHASIL! Offset: %ld detik (GMT%+.1f)\n",
                    gmtOffset_sec, gmtOffset_sec / 3600.0);
    } else {
      Serial.println("Tidak berubah.");
    }
  } else {
    Serial.println("GAGAL (pakai offset saat ini)");
  }
}

// ================================
// HELPER: BACA DATA DENGAN DEFAULT
// ================================
String bacaStringDenganDefault(const String& path, const String& defaultValue) {
  if (Firebase.RTDB.getString(&fbdo, path.c_str())) return fbdo.stringData();
  return defaultValue;
}

int bacaUltrasonik() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);

  long durasiUltra = pulseIn(ECHO_PIN, HIGH);
  int jarak = durasiUltra * 0.034 / 2;
  if (jarak < 0 || jarak > 100) jarak = 100;
  return jarak;
}

// ==========================================
// MODUL OFFLINE LOG: LittleFS NDJSON
// ==========================================

void simpanKeOfflineLog(FirebaseJson& jsonData) {
  String baris;
  jsonData.toString(baris, false);
  baris.trim();

  // Hitung jumlah baris yang ada
  int jumlahEntri = 0;
  if (LittleFS.exists(OFFLINE_LOG_PATH)) {
    File f = LittleFS.open(OFFLINE_LOG_PATH, "r");
    if (f) {
      while (f.available()) {
        String l = f.readStringUntil('\n');
        l.trim();
        if (l.length() > 0) jumlahEntri++;
      }
      f.close();
    }
  }

  // Jika sudah penuh, hapus baris pertama (entri terlama)
  if (jumlahEntri >= OFFLINE_LOG_MAX_ENTRIES) {
    Serial.println("[OFFLINE] Log penuh, hapus entri terlama...");
    File fOld = LittleFS.open(OFFLINE_LOG_PATH, "r");
    File fNew = LittleFS.open("/offline_tmp.ndjson", "w");
    if (fOld && fNew) {
      bool skip = true;
      while (fOld.available()) {
        String l = fOld.readStringUntil('\n');
        l.trim();
        if (l.length() == 0) continue;
        if (skip) { skip = false; continue; }
        fNew.println(l);
      }
    }
    if (fOld) fOld.close();
    if (fNew) fNew.close();
    LittleFS.remove(OFFLINE_LOG_PATH);
    LittleFS.rename("/offline_tmp.ndjson", OFFLINE_LOG_PATH);
  }

  File f = LittleFS.open(OFFLINE_LOG_PATH, "a");
  if (f) {
    f.println(baris);
    f.close();
    Serial.println("[OFFLINE] Entri disimpan lokal: " + baris.substring(0, 60) + "...");
  } else {
    Serial.println("[OFFLINE] ERROR: Gagal membuka file log!");
  }
}

void cekDanSinkronOfflineLog() {
  if (!LittleFS.exists(OFFLINE_LOG_PATH)) return;
  if (!Firebase.ready() || WiFi.status() != WL_CONNECTED) return;

  Serial.println("[OFFLINE] Memulai sinkronisasi offline log...");

  File f = LittleFS.open(OFFLINE_LOG_PATH, "r");
  if (!f) {
    Serial.println("[OFFLINE] Gagal buka file untuk sync.");
    return;
  }

  int sukses = 0;
  int gagal = 0;
  std::vector<String> barisGagal;

  while (f.available()) {
    String baris = f.readStringUntil('\n');
    baris.trim();
    if (baris.length() == 0) continue;

    FirebaseJson json;
    json.setJsonData(baris);

    if (Firebase.RTDB.pushJSON(&fbdo, pLog().c_str(), &json)) {
      sukses++;
      Serial.println("[OFFLINE] Sync entri ke-" + String(sukses) + " SUKSES.");
    } else {
      Serial.println("[OFFLINE] Sync GAGAL: " + fbdo.errorReason());
      barisGagal.push_back(baris);
      gagal++;
      if (gagal >= 3) break; // Hentikan jika 3 gagal berturut-turut
    }
    json.clear();
    delay(200); // Hindari flood Firebase
  }
  f.close();

  if (gagal == 0) {
    LittleFS.remove(OFFLINE_LOG_PATH);
    Serial.printf("[OFFLINE] Sync selesai. %d entri berhasil, file dihapus.\n", sukses);
  } else {
    // Tulis ulang hanya entri yang gagal
    File fWrite = LittleFS.open(OFFLINE_LOG_PATH, "w");
    if (fWrite) {
      for (const String& b : barisGagal) fWrite.println(b);
      fWrite.close();
    }
    Serial.printf("[OFFLINE] Sync parsial: %d sukses, %d gagal (dicoba lagi nanti).\n", sukses, gagal);
  }
}

// ==========================================
// MODUL OTA: ElegantOTA via WebServer (sinkron)
// ==========================================

void aktifkanModeOTA() {
  if (otaModeAktif) return;
  otaModeAktif = true;
  otaMulaiWaktu = millis();

  esp_task_wdt_delete(NULL);

  ElegantOTA.begin(&otaServer);
  otaServer.begin();

  String ip = WiFi.localIP().toString();
  Serial.println("[OTA] Mode OTA AKTIF!");
  Serial.println("[OTA] Buka browser: http://" + ip + "/update");

  if (Firebase.ready()) {
    Firebase.RTDB.setBool(&fbdo, pMetaOta().c_str(), true);
    Firebase.RTDB.setString(&fbdo, pMetaIp().c_str(), ip);
    Firebase.RTDB.setBool(&fbdo, pCmdOtaAktif().c_str(), false);
  }
}

void loopOTA() {
  otaServer.handleClient();
  ElegantOTA.loop();

  // Auto-exit setelah timeout
  if (millis() - otaMulaiWaktu > OTA_TIMEOUT_MS) {
    Serial.println("[OTA] Timeout 10 menit. Keluar dari mode OTA, restart...");
    if (Firebase.ready()) {
      Firebase.RTDB.setBool(&fbdo, pMetaOta().c_str(), false);
    }
    delay(500);
    ESP.restart();
  }
}

// ==========================================
// MODUL 2: JADWAL DINAMIS (UNLIMITED)
// ==========================================
void cekJadwalPakan() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo) || !Firebase.ready()) return;

  char timeStr[6]; strftime(timeStr, sizeof(timeStr), "%H:%M", &timeinfo);
  String jamSekarang = String(timeStr);

  // Untuk riwayat (log) dan daily reboot — tetap format string tanggal
  char dateStr[11]; strftime(dateStr, sizeof(dateStr), "%d-%m-%Y", &timeinfo);
  String tanggalSekarang = String(dateStr);

  if (jamSekarang == "02:00") {
    Serial.println("[MAINTENANCE] Melakukan Restart Harian Terjadwal...");
    if (Firebase.ready()) Firebase.RTDB.setString(&fbdo, devicePath("meta/status"), "offline");
    delay(1000);
    ESP.restart();
  }

  if (!Firebase.RTDB.getJSON(&fbdo, pJadwal().c_str())) return;

  FirebaseJson &json = fbdo.jsonObject();
  FirebaseJsonData result;
  size_t len = json.iteratorBegin();
  String key, path;
  int type = 0;

  int waktuSekarangMenit = timeinfo.tm_hour * 60 + timeinfo.tm_min;

  for (size_t i = 0; i < len; i++) {
    json.iteratorGet(i, type, key, path);

    if (type != FirebaseJson::JSON_OBJECT) continue;
    if (key.indexOf('/') >= 0) continue;
    
    FirebaseJsonData dataAktif, dataJam, dataGram, dataKet, dataTerakhir, dataToleransi;
    
    if (!json.get(dataAktif, key + "/aktif")) continue;
    if (!dataAktif.success || dataAktif.boolValue != true) continue;

    if (!json.get(dataJam, key + "/jam")) continue;
    if (!dataJam.success) continue;
    String jamJadwal = dataJam.stringValue;

    int jamJadwalInt = 0, menitJadwalInt = 0;
    if (sscanf(jamJadwal.c_str(), "%d:%d", &jamJadwalInt, &menitJadwalInt) != 2) continue;
    int waktuJadwalMenit = jamJadwalInt * 60 + menitJadwalInt;

    int toleransiMenit = 30;
    if (json.get(dataToleransi, key + "/toleransi_menit") && dataToleransi.success) {
      toleransiMenit = dataToleransi.intValue;
    }

    int waktuAkhirMenit = waktuJadwalMenit + toleransiMenit;
    bool dalamJendela = false;

    if (waktuAkhirMenit <= 1440) {
      dalamJendela = (waktuSekarangMenit >= waktuJadwalMenit && waktuSekarangMenit <= waktuAkhirMenit);
    } else {
      dalamJendela = (waktuSekarangMenit >= waktuJadwalMenit) || (waktuSekarangMenit <= (waktuAkhirMenit % 1440));
    }

    if (!dalamJendela) continue;

    unsigned long epochSekarang;
    time_t now;
    time(&now);
    epochSekarang = (unsigned long)now;

    unsigned long epochTerakhir = 0;
    if (json.get(dataTerakhir, key + "/terakhir_epoch") && dataTerakhir.success) {
      epochTerakhir = (unsigned long)dataTerakhir.intValue;
    }

    if (epochTerakhir > 0 && (epochSekarang - epochTerakhir) < 43200) {
      continue;
    }

    int targetGram = 500;
    if (json.get(dataGram, key + "/target_gram") && dataGram.success) {
      targetGram = dataGram.intValue;
    }

    String keterangan = "";
    if (json.get(dataKet, key + "/keterangan") && dataKet.success) {
      keterangan = dataKet.stringValue;
    }

    Serial.println("[JADWAL] Eksekusi jadwal: " + key + " (" + keterangan + ")");
    
    eksekusiPemberianPakan(key, keterangan, tanggalSekarang, jamSekarang, targetGram);

    time_t nowEpoch;
    time(&nowEpoch);
    String pathEpoch = pJadwal() + "/" + key + "/terakhir_epoch";
    Firebase.RTDB.setInt(&fbdo, pathEpoch.c_str(), (int)nowEpoch);
  }

  json.iteratorEnd();
}

// ==========================================
// MODUL 3: EKSEKUSI PEMBERIAN PAKAN (UMUM)
// ==========================================
void eksekusiPemberianPakan(String kodeSesi, String keterangan, String tanggal, String jam, int targetGram) {
  Serial.println("\n--- [EKSEKUSI] SESI " + kodeSesi + " ---");

  // 1) FAIL-SAFE STOK + BACA SENSOR
  Serial.print("[FAIL-SAFE] Mengecek jarak pakan... ");
  int jarakAwal = bacaUltrasonik();
  int kelembaban = analogRead(SOIL_PIN);

  int rentang = max(batasPakanMinimum - jarakHopperPenuh, 1);
  int jarakClamped = constrain(jarakAwal, jarakHopperPenuh, batasPakanMinimum);
  int stokPersen = (batasPakanMinimum - jarakClamped) * 100 / rentang;

  Firebase.RTDB.setInt(&fbdo, pMonJarak().c_str(), jarakAwal);
  Firebase.RTDB.setInt(&fbdo, pMonKelem().c_str(), kelembaban);
  Serial.printf("Jarak: %d cm | Stok: %d%%\n", jarakAwal, stokPersen);

  muatProfilPakanAktif();
  String modeAlat = bacaStringDenganDefault(pCfgMode(), "Auto");
  String profilManual = modeAlat == "Manual"
      ? bacaStringDenganDefault(pCfgProfil(), "Kering")
      : "Kering";

  // 2) Jika stok tidak mencukupi -> batalkan
  if (jarakAwal >= batasPakanMinimum) {
    Serial.println("[WARNING] EKSEKUSI DIBATALKAN! Stok pakan tidak mencukupi.");

    FirebaseJson jsonGagal;
    jsonGagal.set("tanggal", tanggal);
    jsonGagal.set("waktu", jam);
    jsonGagal.set("sesi", kodeSesi);
    jsonGagal.set("keterangan", keterangan);
    jsonGagal.set("mode", "Dibatalkan");
    jsonGagal.set("durasi_detik", 0);
    jsonGagal.set("target_gram", 0);
    jsonGagal.set("jarak_cm", jarakAwal);
    jsonGagal.set("hasil", "GAGAL - HABIS");

    if (!Firebase.RTDB.pushJSON(&fbdo, pLog().c_str(), &jsonGagal)) {
      Serial.println("[OFFLINE] Push GAGAL, simpan lokal...");
      simpanKeOfflineLog(jsonGagal);
    }
    jsonGagal.clear();

    if (kodeSesi == "INSTAN") {
      Firebase.RTDB.setString(&fbdo, pCmdPakanResp().c_str(), "GAGAL: Stok Pakan Habis!");
    }

    if (modeAlat == "Manual") {
      Firebase.RTDB.setString(&fbdo, pCfgMode().c_str(), "Auto");
    }

    return;
  }

  int batasKelembapan = profilPakanAktif.batasKelembaban;
  if (adcKelembapanKering >= 0 && adcKelembapanBasah >= 0) {
    batasKelembapan = (adcKelembapanKering + adcKelembapanBasah) / 2;
  }
  bool profilBasah = (modeAlat == "Manual" && profilManual == "Basah") ||
                     (modeAlat == "Auto" && kelembaban < batasKelembapan);
  const KondisiPakan &kondisi = profilBasah
      ? profilPakanAktif.basah
      : profilPakanAktif.kering;

  String keputusanProfil = profilBasah ? "Basah" : "Kering";
  int durasiOperasional = kondisi.durasiDistribusiMs;
  int targetAman = constrain(targetGram, kondisi.gramMin, kondisi.gramMax);
  int speedM1 = map(targetAman, kondisi.gramMin, kondisi.gramMax,
                    kondisi.pwmMin, kondisi.pwmMax);
  int speedM2 = kondisi.pwmMotor2;

  Serial.printf("[HYBRID] Pakan: %s | Mode: %s | Kondisi: %s | Target: %dg\n",
                profilPakanAktif.nama.c_str(), modeAlat.c_str(),
                keputusanProfil.c_str(), targetGram);
  Serial.printf("[AKTUATOR] Motor1 PWM: %d | Motor2 PWM: %d | Waktu: %d ms\n",
                speedM1, speedM2, durasiOperasional);

  // 6) Jalankan motor
  Serial.println("[AKTUATOR] Motor 1 & 2 ON");
  ledcWrite(chM1_R, speedM1);
  ledcWrite(chM2_R, speedM2);
  delay(durasiOperasional);

  stopSemuaMotor();
  Serial.println("[AKTUATOR] Selesai Distribusi.");

  int jarakAkhir = bacaUltrasonik();
  Firebase.RTDB.setInt(&fbdo, pMonJarak().c_str(), jarakAkhir);

  FirebaseJson jsonRiwayat;
  jsonRiwayat.set("tanggal", tanggal);
  jsonRiwayat.set("waktu", jam);
  jsonRiwayat.set("sesi", kodeSesi);
  jsonRiwayat.set("keterangan", keterangan);
  jsonRiwayat.set("mode", modeAlat);
  jsonRiwayat.set("profil_pakan", profilPakanAktif.nama);
  jsonRiwayat.set("durasi_detik", durasiOperasional / 1000.0);
  jsonRiwayat.set("target_gram", targetGram);
  jsonRiwayat.set("jarak_cm", jarakAkhir);
  jsonRiwayat.set("hasil", "SUKSES");

  if (!Firebase.RTDB.pushJSON(&fbdo, pLog().c_str(), &jsonRiwayat)) {
    Serial.println("[OFFLINE] Push GAGAL, simpan lokal...");
    simpanKeOfflineLog(jsonRiwayat);
  }
  jsonRiwayat.clear();

  if (kodeSesi == "INSTAN") {
    Firebase.RTDB.setString(&fbdo, pCmdPakanResp().c_str(), "SUKSES: Pakan Berhasil Diberikan");
  }

  if (modeAlat == "Manual") {
    Firebase.RTDB.setString(&fbdo, pCfgMode().c_str(), "Auto");
  }

  pirAktif = true;
  pirMulaiWaktu = millis();
  pirTerakhirDeteksi = 0;
  Firebase.RTDB.setString(&fbdo, pMonPir().c_str(), "Memantau Gerakan...");
}

// ==========================================
// MODUL 4: PERINTAH SENSOR (ON-DEMAND) + RESPON
// ==========================================
void cekPerintahSensor() {
  if (!Firebase.ready()) return;

  if (Firebase.RTDB.getBool(&fbdo, pCmdSensReq().c_str()) && fbdo.boolData() == true) {
    Firebase.RTDB.setString(&fbdo, pCmdSensResp().c_str(), "Menunggu");

    int jarak = bacaUltrasonik();
    int kelembaban = analogRead(SOIL_PIN);

    Firebase.RTDB.setInt(&fbdo, pMonJarak().c_str(), jarak);
    Firebase.RTDB.setInt(&fbdo, pMonKelem().c_str(), kelembaban);

    Firebase.RTDB.setBool(&fbdo, pCmdSensReq().c_str(), false);
    Firebase.RTDB.setString(&fbdo, pCmdSensResp().c_str(), "SUKSES: Sensor diperbarui");
  }
}

// ==========================================
// MODUL 5: PERINTAH PAKAN INSTAN
// ==========================================
void cekPerintahPakan() {
  if (!Firebase.ready()) return;

  if (Firebase.RTDB.getBool(&fbdo, pCmdPakanAktif().c_str()) && fbdo.boolData() == true) {
    Firebase.RTDB.setString(&fbdo, pCmdPakanResp().c_str(), "Menunggu");

    String ket = bacaStringDenganDefault(pCmdPakanKet(), "");
    int targetGram = 500;
    if (Firebase.RTDB.getInt(&fbdo, pCmdPakanGram().c_str())) {
      targetGram = fbdo.intData();
    }

    struct tm timeinfo;
    if (getLocalTime(&timeinfo)) {
      char timeStr[6]; strftime(timeStr, sizeof(timeStr), "%H:%M", &timeinfo);
      char dateStr[11]; strftime(dateStr, sizeof(dateStr), "%d-%m-%Y", &timeinfo);

      eksekusiPemberianPakan("INSTAN", ket, String(dateStr), String(timeStr), targetGram);
    } else {
      Firebase.RTDB.setString(&fbdo, pCmdPakanResp().c_str(), "GAGAL: Waktu NTP tidak tersedia");
    }

    Firebase.RTDB.setBool(&fbdo, pCmdPakanAktif().c_str(), false);
    Firebase.RTDB.setString(&fbdo, pCmdPakanKet().c_str(), "");
  }
}

// ==========================================
// MODUL 5B: PERINTAH TEST AKTUATOR
// ==========================================
void cekPerintahTestAktuator() {
  if (!Firebase.ready()) return;

  if (Firebase.RTDB.getBool(&fbdo, pCmdTestAktif().c_str()) && fbdo.boolData() == true) {
    Firebase.RTDB.setString(&fbdo, pCmdTestResp().c_str(), "Menunggu");

    String tipe = bacaStringDenganDefault(pCmdTestTipe(), "");
    int pwmM1 = 0, pwmM2 = 240, durasi = 5000;

    if (Firebase.RTDB.getInt(&fbdo, pCmdTestPwmM1().c_str())) pwmM1 = fbdo.intData();
    if (Firebase.RTDB.getInt(&fbdo, pCmdTestPwmM2().c_str())) pwmM2 = fbdo.intData();
    if (Firebase.RTDB.getInt(&fbdo, pCmdTestDurasi().c_str())) durasi = fbdo.intData();

    Serial.println("\n[TEST AKTUATOR] Tipe: " + tipe);
    Serial.printf("PWM M1: %d | PWM M2: %d | Durasi: %d ms\n", pwmM1, pwmM2, durasi);

    unsigned long startTime = millis();

    if (tipe == "M2_ONLY") {
      Serial.println("[TEST] Menjalankan Motor 2 saja...");
      ledcWrite(chM2_R, pwmM2);
      delay(durasi);
      stopSemuaMotor();
      
      unsigned long elapsed = millis() - startTime;
      Serial.printf("[TEST] Motor 2 selesai. Waktu aktual: %lu ms\n", elapsed);
      
      Firebase.RTDB.setInt(&fbdo, pCmdTestHasil().c_str(), elapsed);
      Firebase.RTDB.setString(&fbdo, pCmdTestResp().c_str(), "SUKSES: Motor 2 test selesai");
      
    } else if (tipe == "M1_M2_COMBINED") {
      Serial.println("[TEST] Menjalankan Motor 1 + Motor 2...");
      ledcWrite(chM1_R, pwmM1);
      ledcWrite(chM2_R, pwmM2);
      delay(durasi);
      stopSemuaMotor();
      
      unsigned long elapsed = millis() - startTime;
      Serial.printf("[TEST] Kombinasi selesai. Waktu aktual: %lu ms\n", elapsed);
      
      Firebase.RTDB.setInt(&fbdo, pCmdTestHasil().c_str(), elapsed);
      Firebase.RTDB.setString(&fbdo, pCmdTestResp().c_str(), "SUKSES: Test kombinasi selesai");
      
    } else {
      Serial.println("[TEST] Tipe tidak dikenali!");
      Firebase.RTDB.setString(&fbdo, pCmdTestResp().c_str(), "GAGAL: Tipe test tidak valid");
    }

    Firebase.RTDB.setBool(&fbdo, pCmdTestAktif().c_str(), false);
  }
}

// ==========================================
// MODUL 5C: PERINTAH OTA DARI FIREBASE
// ==========================================
void cekPerintahOTA() {
  if (!Firebase.ready()) return;
  if (otaModeAktif) return;

  if (Firebase.RTDB.getBool(&fbdo, pCmdOtaAktif().c_str()) && fbdo.boolData() == true) {
    Serial.println("[OTA] Perintah OTA diterima dari Firebase!");
    aktifkanModeOTA();
  }
}

// ==========================================
// MODUL 6: PIR & COOLDOWN
// ==========================================
void cekAktivitasPIR() {
  if (!pirAktif) return;

  // 1) Jika sudah lewat 1 jam, matikan pantauan
  if (millis() - pirMulaiWaktu > DURASI_PANTAU_PIR) {
    pirAktif = false;
    Firebase.RTDB.setString(&fbdo, pMonPir().c_str(), "(Standby)");
    Serial.println("[PIR] Waktu pantau 1 jam selesai.");
    return;
  }

  // 2) Baca sensor PIR
  int gerakan = digitalRead(PIR_PIN);
  if (gerakan == HIGH) {
    if (millis() - pirTerakhirDeteksi > COOLDOWN_PIR || pirTerakhirDeteksi == 0) {
      Firebase.RTDB.setString(&fbdo, pMonPir().c_str(), "Kambing Terdeteksi di Palung Pakan!");
      Serial.println("[PIR] Gerakan Terdeteksi!");
      pirTerakhirDeteksi = millis();
    }
  } else {
    // Idle reset
    if (pirTerakhirDeteksi != 0 && (millis() - pirTerakhirDeteksi > COOLDOWN_PIR)) {
      Firebase.RTDB.setString(&fbdo, pMonPir().c_str(), "Memantau Gerakan...");
      Serial.println("[PIR] Cooldown selesai, kembali memantau.");
      pirTerakhirDeteksi = 0;
    }
  }
}

// ==========================================
// FUNGSI: STOP MOTOR
// ==========================================
void stopSemuaMotor() {
  ledcWrite(chM1_R, 0); ledcWrite(chM1_L, 0);
  ledcWrite(chM2_R, 0); ledcWrite(chM2_L, 0);
}
