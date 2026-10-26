// ============================================
// TX - JOYSTICK (Kontrol Arah & Kecepatan untuk VFD)
// Pin Map:
//   nRF24 CE   -> 49
//   nRF24 CSN  -> 48
//   Joystick Y -> A1
// ============================================

#include <SPI.h>
#include <RF24.h>

#define CE_PIN   9
#define CSN_PIN 10

RF24 radio(49, 48);  // CE=49, CSN=48
const byte address[6] = "00001";

const int VRy      = A1;
const int CENTER   = 512;
const int DEADZONE = 80;

// ── Batas frekuensi VFD (Hz) ───────────────
// Sesuaikan dengan d1-02 (Max Output Frequency) dan L2-00 di VFD
#define FREQ_MIN   5     // Hz minimum saat joystick baru keluar deadzone
#define FREQ_MAX   50    // Hz maksimum saat joystick full deflection

struct JoyData {
  int8_t  arah;   // 1 = maju (forward), -1 = mundur (reverse), 0 = stop
  uint8_t speed;  // frekuensi VFD dalam Hz (5-50)
};

void setup() {
  Serial.begin(115200);

  if (!radio.begin()) {
    Serial.println("nRF tidak terdeteksi! Cek wiring.");
    while (1);
  }

  radio.openWritingPipe(address);
  radio.setPALevel(RF24_PA_LOW);
  radio.setDataRate(RF24_250KBPS);
  radio.stopListening();

  Serial.println("TX Joystick (VFD Control) siap.");
}

void loop() {
  int joyY = analogRead(VRy);
  int dev  = joyY - CENTER;

  JoyData data;

  if (abs(dev) < DEADZONE) {
    // Di dalam deadzone -> motor benar-benar diam
    data.arah  = 0;
    data.speed = 0;
  } else {
    data.arah = (dev < 0) ? 1 : -1;  // atas = maju, bawah = mundur

    // PENTING: mapping dihitung dari 0 (bukan dari DEADZONE) sampai CENTER,
    // supaya proporsional LINEAR MURNI terhadap posisi fisik joystick.
    // Contoh: dev = CENTER/2 (setengah posisi fisik) -> speed = FREQ_MAX/2
    // (tepat setengah), bukan sekadar mendekati.
    data.speed = (uint8_t)constrain(
                    map(abs(dev), 0, CENTER, 0, FREQ_MAX),
                    FREQ_MIN, FREQ_MAX);
  }

  bool ok = radio.write(&data, sizeof(data));

  Serial.print("Arah: ");   Serial.print(data.arah);
  Serial.print("  Freq: "); Serial.print(data.speed);
  Serial.print(" Hz  TX: ");Serial.println(ok ? "OK" : "GAGAL");

  delay(50);
}
