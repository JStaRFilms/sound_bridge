import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vibration_service.dart';

const _uploadEndpoint = String.fromEnvironment(
  'AUDIO_UPLOAD_ENDPOINT',
  defaultValue: 'http://127.0.0.1:8000/v1/audio/analyze',
);
const _legacyUploadEndpoint = 'https://example.com/audio';
const _legacyNameMentionPath = '/v1/audio/name-mention';
const _analyzePath = '/v1/audio/analyze';
const _uploadEndpointKey = 'upload_endpoint';
const _targetNameKey = 'target_name';

class SettingsValues {
  const SettingsValues({required this.endpoint, required this.targetName});

  final String endpoint;
  final String targetName;
}

void main() {
  runApp(const SoundBridgeApp());
}

class SoundBridgeApp extends StatelessWidget {
  const SoundBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sound Bridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: const Color(0xFF0F172A),
          displayColor: const Color(0xFF0F172A),
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

enum DashboardStatus { idle, recording, ready, uploading, success, error }

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.initialRecordingPath});

  /// Used by widget tests to simulate a completed recording.
  final String? initialRecordingPath;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final VibrationService _vibrationService = const VibrationService();

  DashboardStatus _status = DashboardStatus.idle;
  String? _recordingPath;
  String _uploadEndpointUrl = _uploadEndpoint;
  String _targetName = '';
  String _message = 'Tap Listen to record a short audio clip.';
  bool _isPlaying = false;
  StreamSubscription<void>? _playerCompleteSubscription;

  bool get _isRecording => _status == DashboardStatus.recording;
  bool get _isUploading => _status == DashboardStatus.uploading;
  bool get _hasRecording => _recordingPath != null;

  void _showSendAudioError(String message) {
    if (!mounted) return;

    debugPrint('Send Audio Error: $message');

    setState(() {
      _status = DashboardStatus.error;
      _message = message;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFB91C1C),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _formatUploadFailure(int statusCode, String responseBody) {
    final trimmedBody = responseBody.trim();
    if (trimmedBody.isEmpty) {
      return 'Upload failed with status $statusCode. Server returned no response body.';
    }

    return 'Upload failed with status $statusCode: $trimmedBody';
  }

  String _normalizeUploadEndpoint(String endpoint) {
    final uri = Uri.tryParse(endpoint);
    if (uri == null || uri.path != _legacyNameMentionPath) {
      return endpoint;
    }

    return uri.replace(path: _analyzePath).toString();
  }

  String _formatUploadSuccess(String responseBody) {
    const fallbackMessage = 'Audio sent successfully.';
    final trimmedBody = responseBody.trim();

    if (trimmedBody.isEmpty) {
      return fallbackMessage;
    }

    try {
      final decoded = jsonDecode(trimmedBody);
      if (decoded is! Map<String, dynamic>) {
        return fallbackMessage;
      }

      final nameMention = decoded['name_mention'];
      final soundClassification = decoded['sound_classification'];
      final namePayload = nameMention is Map<String, dynamic>
          ? nameMention
          : decoded;
      final soundPayload = soundClassification is Map<String, dynamic>
          ? soundClassification
          : null;
      final targetName = namePayload['target_name']?.toString().trim();
      final text = namePayload['text']?.toString().trim();
      final mentioned = namePayload['mentioned'] == true;
      final category = soundPayload?['category']?.toString().trim();
      final soundMatched = soundPayload?['matched'] == true;
      final lines = <String>[fallbackMessage];

      if (mentioned && targetName != null && targetName.isNotEmpty) {
        lines.add('The user\'s name "$targetName" was mentioned.');
      }

      if (soundMatched && category != null && category.isNotEmpty) {
        lines.add('Detected sound: $category.');
      }

      if (!mentioned && soundMatched != true) {
        lines.add('No target name or known sound was detected.');
      }

      if (mentioned && text != null && text.isNotEmpty) {
        lines.add('Text: $text');
      }

      return lines.join('\n');
    } catch (_) {
      return fallbackMessage;
    }
  }

  @override
  void initState() {
    super.initState();
    final initialRecordingPath = widget.initialRecordingPath;
    if (initialRecordingPath != null) {
      _recordingPath = initialRecordingPath;
      _status = DashboardStatus.ready;
      _message = 'Audio is ready to send.';
    }
    _loadSavedSettings();
    _playerCompleteSubscription = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;

      setState(() {
        _isPlaying = false;
        _message = 'Audio is ready to send.';
      });
    });
  }

  @override
  void dispose() {
    _playerCompleteSubscription?.cancel();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isUploading) return;

    if (_isRecording) {
      await _stopRecording();
      return;
    }

    await _startRecording();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();

    if (!hasPermission) {
      setState(() {
        _status = DashboardStatus.error;
        _message = 'Microphone permission is required to record audio.';
      });
      return;
    }

    await _stopPlayback();
    await _deleteRecording(_recordingPath);

    final tempDirectory = await getTemporaryDirectory();
    final path =
        '${tempDirectory.path}/sound_bridge_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );

    setState(() {
      _recordingPath = null;
      _status = DashboardStatus.recording;
      _message = 'Recording... tap Listen again to stop.';
    });
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    debugPrint('Recorded Audio Path: ${path ?? 'none'}');

    setState(() {
      _recordingPath = path;
      _status = path == null ? DashboardStatus.error : DashboardStatus.ready;
      _message = path == null
          ? 'Recording could not be saved. Please try again.'
          : 'Audio is ready to send.';
    });
  }

  Future<void> _sendAudio() async {
    final path = _recordingPath;

    if (path == null) {
      _showSendAudioError('Record audio before sending.');
      return;
    }

    final targetName = _targetName.trim();

    if (targetName.isEmpty) {
      _showSendAudioError('Set a target name in Settings.');
      return;
    }

    final audioFile = File(path);
    final filename = audioFile.uri.pathSegments.last;

    if (!filename.toLowerCase().endsWith('.wav')) {
      _showSendAudioError(
        'Recorded audio must be a .wav file, but got "$filename". Record a new clip and try again.',
      );
      return;
    }

    if (!await audioFile.exists()) {
      _showSendAudioError('The recorded audio file could not be found.');
      return;
    }

    setState(() {
      _status = DashboardStatus.uploading;
      _message = 'Sending audio...';
    });

    try {
      final endpoint = Uri.tryParse(_uploadEndpointUrl);

      if (!_isValidEndpoint(endpoint)) {
        _showSendAudioError('Set a valid upload endpoint in Settings.');
        return;
      }

      final request = http.MultipartRequest('POST', endpoint!)
        ..headers['accept'] = 'application/json'
        ..fields['target_name'] = targetName
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            path,
            contentType: MediaType('audio', 'wav'),
          ),
        );

      debugPrint('Send Audio Filename: $filename');

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      debugPrint(
        'Analyze Response (${response.statusCode}): $responseBody',
        wrapWidth: 1024,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          _status = DashboardStatus.success;
          _message = _formatUploadSuccess(responseBody);
        });
      } else {
        _showSendAudioError(
          _formatUploadFailure(response.statusCode, responseBody),
        );
      }
    } catch (error) {
      final errorText = error.toString().trim();
      final detail = errorText.isEmpty ? '' : ' - $errorText';
      _showSendAudioError('Upload failed: ${error.runtimeType}$detail');
    }
  }

  Future<void> _loadSavedSettings() async {
    final preferences = await SharedPreferences.getInstance();
    final savedEndpoint = preferences.getString(_uploadEndpointKey);
    final savedTargetName = preferences.getString(_targetNameKey);

    if (!mounted) return;

    setState(() {
      if (savedEndpoint != null && savedEndpoint.trim().isNotEmpty) {
        final trimmedEndpoint = _normalizeUploadEndpoint(savedEndpoint.trim());
        if (trimmedEndpoint != _legacyUploadEndpoint) {
          _uploadEndpointUrl = trimmedEndpoint;
        }
      }
      if (savedTargetName != null) {
        _targetName = savedTargetName.trim();
      }
    });
  }

  Future<void> _saveSettings(SettingsValues settings) async {
    final trimmedEndpoint = _normalizeUploadEndpoint(settings.endpoint.trim());
    final trimmedTargetName = settings.targetName.trim();
    final uri = Uri.tryParse(trimmedEndpoint);

    if (trimmedEndpoint.isEmpty || !_isValidEndpoint(uri)) {
      setState(() {
        _status = DashboardStatus.error;
        _message = 'Enter a valid endpoint URL.';
      });
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_uploadEndpointKey, trimmedEndpoint);
    await preferences.setString(_targetNameKey, trimmedTargetName);

    if (!mounted) return;

    setState(() {
      _uploadEndpointUrl = trimmedEndpoint;
      _targetName = trimmedTargetName;
      _message = 'Settings updated.';
      if (_status == DashboardStatus.error) {
        _status = _hasRecording ? DashboardStatus.ready : DashboardStatus.idle;
      }
    });
  }

  Future<void> _openSettings() async {
    final settings = await showModalBottomSheet<SettingsValues>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SettingsSheet(
          initialEndpoint: _uploadEndpointUrl,
          initialTargetName: _targetName,
        );
      },
    );

    if (settings != null) {
      await _saveSettings(settings);
    }
  }

  Future<void> _openVibrationTester() async {
    if (_isRecording || _isUploading) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return VibrationTestSheet(vibrationService: _vibrationService);
      },
    );
  }

  bool _isValidEndpoint(Uri? uri) {
    if (uri == null) return false;

    return (uri.scheme == 'http' || uri.scheme == 'https') && uri.hasAuthority;
  }

  Future<void> _togglePlayback() async {
    if (_isRecording || _isUploading) return;

    if (_isPlaying) {
      await _stopPlayback();
      setState(() {
        _message = 'Audio is ready to send.';
      });
      return;
    }

    final path = _recordingPath;

    if (path == null) {
      setState(() {
        _status = DashboardStatus.error;
        _message = 'Record audio before playing it back.';
      });
      return;
    }

    final audioFile = File(path);

    if (!await audioFile.exists()) {
      setState(() {
        _recordingPath = null;
        _status = DashboardStatus.error;
        _message = 'The recorded audio file could not be found.';
      });
      return;
    }

    await _player.play(DeviceFileSource(path));

    setState(() {
      _isPlaying = true;
      _message = 'Playing recording...';
    });
  }

  Future<void> _stopPlayback() async {
    if (!_isPlaying) return;

    await _player.stop();

    if (!mounted) return;

    setState(() {
      _isPlaying = false;
    });
  }

  Future<void> _deleteRecording(String? path) async {
    if (path == null) return;

    final audioFile = File(path);

    if (await audioFile.exists()) {
      await audioFile.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const SizedBox.square(dimension: 48),
                              Expanded(
                                child: Text(
                                  'Sound Bridge',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              SizedBox.square(
                                dimension: 48,
                                child: IconButton(
                                  onPressed: _isRecording || _isUploading
                                      ? null
                                      : _openSettings,
                                  tooltip: 'Settings',
                                  icon: const Icon(Icons.settings_rounded),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Record your voice and send it when ready.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: const Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 48),
                          Center(
                            child: ListenButton(
                              isRecording: _isRecording,
                              isDisabled: _isUploading,
                              onPressed: _toggleRecording,
                            ),
                          ),
                          const SizedBox(height: 36),
                          StatusText(status: _status, message: _message),
                          const SizedBox(height: 28),
                          FilledButton.icon(
                            onPressed:
                                _hasRecording && !_isRecording && !_isUploading
                                ? _sendAudio
                                : null,
                            icon: _isUploading
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.upload_rounded),
                            label: Text(
                              _isUploading ? 'Sending' : 'Send Audio',
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed:
                                _hasRecording && !_isRecording && !_isUploading
                                ? _togglePlayback
                                : null,
                            icon: Icon(
                              _isPlaying
                                  ? Icons.stop_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(
                              _isPlaying ? 'Stop Playback' : 'Play Recording',
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _isRecording || _isUploading
                                ? null
                                : _openVibrationTester,
                            icon: const Icon(Icons.vibration_rounded),
                            label: const Text('Test Vibration'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            'Endpoint: $_uploadEndpointUrl',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: const Color(0xFF94A3B8)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _targetName.isEmpty
                                ? 'Target: not set'
                                : 'Target: $_targetName',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: const Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    required this.initialEndpoint,
    required this.initialTargetName,
    super.key,
  });

  final String initialEndpoint;
  final String initialTargetName;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _endpointController;
  late final TextEditingController _targetNameController;

  @override
  void initState() {
    super.initState();
    _endpointController = TextEditingController(text: widget.initialEndpoint);
    _targetNameController = TextEditingController(
      text: widget.initialTargetName,
    );
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _targetNameController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      SettingsValues(
        endpoint: _endpointController.text,
        targetName: _targetNameController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, bottomInset + 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Settings',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _endpointController,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'API endpoint',
                hintText: 'http://127.0.0.1:8000/v1/audio/analyze',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _targetNameController,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Target name',
                hintText: 'john',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save Settings'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VibrationTestSheet extends StatefulWidget {
  const VibrationTestSheet({required this.vibrationService, super.key});

  final VibrationService vibrationService;

  @override
  State<VibrationTestSheet> createState() => _VibrationTestSheetState();
}

class _VibrationTestSheetState extends State<VibrationTestSheet> {
  double _durationMs = 500;
  double _intensity = 128;
  bool _isVibrating = false;
  String? _resultMessage;

  Future<void> _vibrate() async {
    setState(() {
      _isVibrating = true;
      _resultMessage = null;
    });

    VibrationResult result;

    try {
      result = await widget.vibrationService.vibrate(
        durationMs: _durationMs.round(),
        intensity: _intensity.round(),
      );
    } catch (_) {
      result = VibrationResult.failed;
    }

    if (!mounted) return;

    setState(() {
      _isVibrating = false;
      _resultMessage = switch (result) {
        VibrationResult.played => 'Vibration played.',
        VibrationResult.playedWithoutIntensity =>
          'Vibration played without intensity control.',
        VibrationResult.playedFallback =>
          'Basic vibration played. Custom intensity was not available.',
        VibrationResult.unavailable => 'Vibration is unavailable.',
        VibrationResult.timedOut =>
          'Vibration request was sent, but the device did not confirm it.',
        VibrationResult.failed => 'Vibration failed on this device.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final duration = _durationMs.round();
    final intensity = _intensity.round();

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, bottomInset + 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Vibration',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ControlSlider(
              label: 'Length',
              valueLabel: '${duration}ms',
              value: _durationMs,
              min: 50,
              max: 5000,
              divisions: 99,
              onChanged: _isVibrating
                  ? null
                  : (value) => setState(() => _durationMs = value),
            ),
            const SizedBox(height: 14),
            ControlSlider(
              label: 'Intensity',
              valueLabel: '$intensity',
              value: _intensity,
              min: 1,
              max: 255,
              divisions: 254,
              onChanged: _isVibrating
                  ? null
                  : (value) => setState(() => _intensity = value),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _isVibrating ? null : _vibrate,
              icon: _isVibrating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.vibration_rounded),
              label: Text(_isVibrating ? 'Vibrating' : 'Vibrate'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (_resultMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _resultMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ControlSlider extends StatelessWidget {
  const ControlSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              valueLabel,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: const Color(0xFF64748B)),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class ListenButton extends StatelessWidget {
  const ListenButton({
    required this.isRecording,
    required this.isDisabled,
    required this.onPressed,
    super.key,
  });

  final bool isRecording;
  final bool isDisabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isRecording
        ? const Color(0xFFDC2626)
        : isDisabled
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF0F172A);

    return SizedBox.square(
      dimension: 176,
      child: Material(
        color: backgroundColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: isDisabled ? null : onPressed,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(height: 10),
              Text(
                isRecording ? 'Stop' : 'Listen',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusText extends StatelessWidget {
  const StatusText({required this.status, required this.message, super.key});

  final DashboardStatus status;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DashboardStatus.recording => const Color(0xFFDC2626),
      DashboardStatus.success => const Color(0xFF15803D),
      DashboardStatus.error => const Color(0xFFB91C1C),
      _ => const Color(0xFF475569),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Text(
        message,
        key: ValueKey(message),
        textAlign: TextAlign.center,
        softWrap: true,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
