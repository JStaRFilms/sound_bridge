# Sound Bridge — How It Works

Sound Bridge is a **Flutter mobile app** that records voice, sends the audio to the **Audio Event API** for analysis, and forwards the result to an **ESP32 over Bluetooth Low Energy (BLE)**.

The app answers one practical question end to end:

> **"Did someone say a specific name — and if so, trigger the hardware?"**

Sound classification results (fire alarm, doorbell, phone ring) are shown on screen but do not drive BLE output in the current flow.

---

## High-Level Flow

```
┌──────────────┐     WAV upload      ┌─────────────────────┐
│  Microphone  │ ──────────────────► │  Audio Event API    │
│  (device)    │   POST /analyze     │  (backend service)  │
└──────────────┘                     └─────────────────────┘
       ▲                                       │
       │ record / stop                         │ JSON response
       │                                       ▼
┌──────────────┐                     name_mention.mentioned?
│  Sound Bridge│ ◄─────────────────────────────────────────┘
│  (Flutter)   │
└──────────────┘
       │
       │ BLE write (if name mentioned)
       ▼
┌──────────────┐
│  ESP32-D4    │  PWM output on GPIO 4
│  (hardware)  │
└──────────────┘
```

**Typical user flow:**

1. Connect to the ESP32 in **Settings → ESP32 Bluetooth**
2. Set the **target name** and **API endpoint** in Settings
3. Tap **Listen** to start recording, tap again to stop
4. Tap **Send Audio** to upload
5. If the API reports the name was mentioned, the app pulses the hardware three times over BLE

---

## Integration 1: Microphone Recording

**What it is:** On-device audio capture using the `record` package.

**What it's used for:**

- Capturing a voice clip from the device microphone
- Saving it as a local WAV file before upload

**How it works in this project:**

1. The app requests microphone permission on first use.
2. Tapping **Listen** starts recording; tapping again stops.
3. Audio is saved as WAV at 44.1 kHz, 128 kbps.
4. The file is stored in the app temp directory (`sound_bridge_{timestamp}.wav`).
5. The user can play back the clip locally before sending.

**Recording settings:**

| Property    | Value              |
|-------------|--------------------|
| Format      | WAV                |
| Sample rate | 44,100 Hz          |
| Bit rate    | 128,000            |
| Duration    | User-controlled (manual start/stop) |

---

## Integration 2: Audio Event API (Backend)

**What it is:** The FastAPI service in the `audio-event-api` project.

**What it's used for:**

- Transcribing speech and checking whether the **target name** was spoken
- Classifying environmental sounds (fire alarm, doorbell, phone ring)

**Why this integration:** The phone does not run AI models locally. All speech and sound analysis happens on the backend.

**How it works in this project:**

1. After recording, the user taps **Send Audio**.
2. The app sends a multipart `POST` request with the WAV file and the configured target name.
3. On HTTP 2xx, the app parses the JSON response and updates the dashboard.
4. If `name_mention.mentioned` is `true`, the BLE handler runs automatically.

**Endpoint:**

```
POST {upload_endpoint}
```

Default: `http://127.0.0.1:8000/v1/audio/analyze`

**Request format:**

```
Headers:
  accept: application/json

Fields:
  target_name: string   (from Settings)

Files:
  file: audio/wav
```

**Example response:**

```json
{
  "name_mention": {
    "target_name": "Adesh",
    "mentioned": true,
    "text": "Hey Adesh, can you come here?",
    "model": "whisper-large-v3"
  },
  "sound_classification": {
    "category": "doorbell",
    "matched": true,
    "threshold": 0.2,
    "predictions": [...]
  }
}
```

**What triggers hardware:**

| API field                         | Shown in UI | Triggers BLE |
|-----------------------------------|-------------|--------------|
| `name_mention.mentioned == true`  | Yes         | **Yes**      |
| `sound_classification.matched`    | Yes         | No           |

**Configuration:**

| Mechanism              | Key / constant              | Default                                      |
|------------------------|-----------------------------|----------------------------------------------|
| Compile-time define    | `AUDIO_UPLOAD_ENDPOINT`     | `http://127.0.0.1:8000/v1/audio/analyze`     |
| Runtime (Settings)     | `upload_endpoint`           | Overrides compile-time default when saved    |
| Runtime (Settings)     | `target_name`               | Required before upload                       |

**Physical device note:** `127.0.0.1` only works on emulator or desktop. On a real phone, point Settings at your machine's LAN IP, for example `http://192.168.1.10:8000/v1/audio/analyze`.

---

## Integration 3: ESP32 over BLE

**What it is:** Bluetooth Low Energy link to an ESP32 running the `esp32_ble_d4` firmware.

**What it's used for:**

- Turning API results into a physical output when a name is detected
- Driving PWM on GPIO 4 (for example a motor, LED, or buzzer circuit)

**Why this integration:** The backend returns text and labels; the ESP32 turns that into something the user can feel or see in the physical world.

**How it works in this project:**

1. User connects to `ESP32-D4-BLE` from Settings before recording.
2. After a successful upload, `ServerResponseBleEventHandler` checks the response.
3. If the name was mentioned, it sends **3 pulses** to the ESP32:
   - Intensity: 255
   - Duration: 2 seconds each
   - Gap between pulses: 500 ms
4. Each pulse waits for the hardware to report it has finished before sending the next.

If BLE is not connected, the pulse sequence is skipped silently.

**BLE protocol:**

| Role                    | UUID                                   |
|-------------------------|----------------------------------------|
| Service                 | `19b10000-e8f2-537e-4f6c-d104768a1214` |
| State (read + notify)   | `19b10001-e8f2-537e-4f6c-d104768a1214` |
| Control (write)         | `19b10002-e8f2-537e-4f6c-d104768a1214` |

**Control write (app → ESP32):** 2 bytes

```
[intensity (0–255), durationSeconds (0–255)]
```

- `intensity=0, duration=0` → stop
- `duration=0` with `intensity > 0` → defaults to 5 seconds on the device

**State notification (ESP32 → app):** 2 bytes

```
[pwmValue, durationSeconds]
```

---

## Project Structure

```
lib/
├── main.dart                              # Dashboard, recording, upload, settings
└── ble/
    ├── esp32_ble_controller.dart          # Scan, connect, write, state notifications
    ├── server_response_ble_event_handler.dart  # API response → BLE pulse sequence
    └── ble_output_commands.dart           # BLE output interface and hardware state model
```

---

## Suggested Setup

For the full pipeline:

```
1. Start audio-event-api on your machine or server
2. Flash esp32_ble_d4 firmware to the ESP32
3. In Sound Bridge Settings:
   - Set API endpoint (LAN IP on a physical phone)
   - Set target name
   - Connect to ESP32-D4-BLE
4. Record → Send Audio → hardware pulses if the name was spoken
```

See also:

- **audio-event-api** → `docs/api_documentation.md` — backend AI services (Groq + Hugging Face)
- **esp32_ble_d4** → `docs/hardware_documentation.md` — ESP32 BLE firmware and GPIO 4 output
