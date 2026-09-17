# Sound Bridge

Sound Bridge is a Flutter app for recording short voice input from the device microphone and sending the captured audio to a backend endpoint.

## For Testers (APK + Backend Quickstart)

### 1. Install the test build

1. Open the fork's Actions page: `https://github.com/JStaRFilms/sound_bridge/actions` (GitHub login required).
2. Click the latest successful **Build debug APK** run.
3. Download the **sound-bridge-debug-apk** artifact and unzip it to get `app-debug.apk`.
4. On the Android phone, allow **Install unknown apps** for your browser/files app, then install the APK.

### 2. Start the backend (required)

The app does no analysis on-device. You must run the `audio-event-api` backend:

1. On a computer, open the `audio-event-api` project and follow its README (install deps, set its API keys).
2. Start it bound to the network (not localhost only), e.g.:
   ```text
   uvicorn <module>:app --host 0.0.0.0 --port 8000
   ```
   (Confirm the exact module path in that repo's README.)
3. Sanity-check from that computer:
   ```text
   curl http://<PC-LAN-IP>:8000/v1/audio/classifier/wake
   ```
   It should respond instead of refusing the connection.

### 3. Connect the app to the backend

1. Put the phone on the **same Wi-Fi** as the backend computer.
2. Open Sound Bridge → gear icon (Settings).
3. Set **API endpoint** to your computer's LAN address, e.g.:
   ```text
   http://192.168.1.108:8000/v1/audio/analyze
   ```
4. Set **Target name** (e.g. `Peter`) and tap **Save Settings**.

> Do NOT use `127.0.0.1` on a physical phone — on the phone that address is the phone itself, so uploads always fail with "Connection refused". The app now warns you when the endpoint is a loopback address.

### 4. Test flow

1. Tap **Listen**, speak, tap again to stop.
2. Optional: **Play Recording** to check the clip.
3. Tap **Send Audio** and read the result on screen.

### Troubleshooting

| Symptom | Check |
|---|---|
| `Could not reach ...` / connection refused | Same Wi-Fi? Backend running with `--host 0.0.0.0`? Endpoint uses the PC's LAN IP, not `127.0.0.1`? |
| `Set a target name in Settings` | Target name is empty — fill it in Settings. |
| `Upload timed out` | Backend overloaded or unreachable — check the server logs. |
| Non-2xx status message | Server got the file but rejected it — the message body shown is from the server. |

## Product Goal

The app should provide a simple dashboard with two primary actions:

- A large circular button for starting and stopping microphone recording.
- A regular button for submitting the recorded audio to an API endpoint.

The first version should keep the experience focused and direct: record audio, confirm that audio has been captured, then send it.

## Dashboard Flow

### 1. Record Button

The main dashboard control is a large circular button labeled either **Speak** or **Listen**.

When the user taps this button:

- The app requests microphone permission if permission has not already been granted.
- The app starts recording audio through the device microphone.
- The button changes state to show that recording is active.

When the user taps the same button again:

- The app stops recording.
- The recorded audio is stored locally in the app session.
- The dashboard updates to show that audio is ready to send.

### 2. Submit Button

The second dashboard control is a regular button used to send the collected audio to a backend endpoint.

When the user taps this button:

- The app checks that a recording exists.
- The app uploads the recorded audio file to the configured endpoint.
- The app displays a loading state while the upload is in progress.
- The app displays either a success message or an error message after the request completes.

## Expected Interface

The dashboard should include:

- A prominent circular **Speak** or **Listen** button.
- A regular **Send Audio** button.
- A visible recording state, such as recording, stopped, uploading, success, or error.
- A clear disabled state for **Send Audio** when no recording is available.

## Implementation Notes

Planned implementation areas:

- Microphone permission handling.
- Audio recording start and stop behavior.
- Temporary local storage for the recorded audio file.
- API upload flow for the collected audio.
- Dashboard state management for recording, uploading, success, and error states.

## Configuration

The backend endpoint should be configurable so the app can point to different environments during development and testing.

Example placeholder:

```text
POST https://example.com/audio
```

The final endpoint, request format, and response handling will be defined before implementation.

## Development Status

This README describes the intended first version of the app. Implementation will begin after the dashboard flow and endpoint behavior are confirmed.
