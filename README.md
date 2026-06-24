# Sound Bridge

Sound Bridge is a Flutter app for recording short voice input from the device microphone and sending the captured audio to a backend endpoint.

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
