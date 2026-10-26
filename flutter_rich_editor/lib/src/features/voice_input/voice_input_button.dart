import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/controller/rich_editor_controller.dart';
import '../../theme/editor_theme.dart';
import 'voice_input_handler.dart';
import 'voice_insert_mode.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Internal recording state
// ─────────────────────────────────────────────────────────────────────────────

enum _VoiceState {
  idle,       // mic icon, waiting for user tap
  recording,  // red pulsing animation, user is speaking
  processing, // spinner, API call in flight
  error,      // brief error indicator before returning to idle
}

// ─────────────────────────────────────────────────────────────────────────────
// VoiceInputButton
// ─────────────────────────────────────────────────────────────────────────────

/// A self-contained mic button that fits directly into the [EditorToolbar]
/// via [ToolbarItem.customWidget].
///
/// **The plugin owns:**
/// - The button UI and its animated states (idle / recording / processing / error)
/// - Calling [VoiceInputHandler.startRecording] and [stopAndProcess]
/// - Injecting the returned HTML into the editor
///
/// **The consuming app owns (via callbacks):**
/// - Starting and stopping the microphone ([onRecord])
/// - Calling the voice recognition API ([onTranscribe])
/// - Displaying errors ([onError])
///
/// ### Minimal usage (inside your `ToolbarConfig.customItems`):
/// ```dart
/// ToolbarItem(
///   id: 'voice.input',
///   icon: Icons.mic,
///   label: 'Voice Input',
///   customWidget: (ctx, controller, theme) => VoiceInputButton(
///     controller: controller,
///     theme: theme,
///
///     // App owns the mic
///     onRecord: () async {
///       await _recorder.start(const RecordConfig(), path: '/tmp/voice.wav');
///       // This future resolves when stopAndProcess() is called, which
///       // triggers your stop logic and returns the bytes.
///       final String? path = await _recorder.stop();
///       return File(path!).readAsBytes();
///     },
///
///     // App owns the API
///     onTranscribe: (Uint8List bytes) async {
///       final res = await http.post(
///         Uri.parse('https://your-api.com/voice-to-html'),
///         body: bytes,
///       );
///       return (jsonDecode(res.body) as Map<String, dynamic>)['html'] as String;
///     },
///
///     // App owns error display
///     onError: (msg) => ScaffoldMessenger.of(context)
///         .showSnackBar(SnackBar(content: Text(msg))),
///   ),
/// ),
/// ```
class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({
    super.key,
    required this.controller,
    required this.theme,
    this.onRecord,
    this.onTranscribe,
    this.onVoiceInput,
    this.onMicPressed,
    this.onError,
    this.insertMode = VoiceInsertMode.insertAtCursor,
    this.maxRecordingSeconds = 30,
    this.size = 36.0,
  });

  // ── Required ───────────────────────────────────────────────────────────────

  /// The editor controller. Injected automatically when used via
  /// [ToolbarItem.customWidget].
  final RichEditorController controller;

  /// The active editor theme. Injected automatically via [ToolbarItem.customWidget].
  final EditorTheme theme;

  /// Called when using built-in speech recognition tools (e.g. `speech_to_text`).
  /// Must return the HTML string to insert into the editor, or null/empty if cancelled.
  final Future<String?> Function()? onVoiceInput;

  /// Optional direct tap callback for custom mic logic.
  final VoidCallback? onMicPressed;

  /// Called when recording starts for raw audio workflows.
  final Future<Uint8List> Function()? onRecord;

  /// Called with the recorded audio bytes for raw audio workflows.
  final Future<String> Function(Uint8List audioBytes)? onTranscribe;

  // ── Optional ───────────────────────────────────────────────────────────────

  /// Called on any error with a human-readable message.
  final void Function(String error)? onError;

  /// Controls where the HTML is placed in the document.
  final VoiceInsertMode insertMode;

  /// Maximum recording duration in seconds before auto-stop.
  /// Defaults to 30 seconds.
  final int maxRecordingSeconds;

  /// Size of the mic icon button. Defaults to 36.
  final double size;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  _VoiceState _state = _VoiceState.idle;
  VoiceInputHandler? _handler;
  Timer? _autoStopTimer;

  // Animation for the pulsing ring during recording
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.onRecord != null && widget.onTranscribe != null) {
      _handler = VoiceInputHandler(
        controller: widget.controller,
        onRecord: widget.onRecord!,
        onTranscribe: widget.onTranscribe!,
        onError: _handleError,
        insertMode: widget.insertMode,
      );
    }
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Event handlers ────────────────────────────────────────────────────────

  void _handleError(String message) {
    if (!mounted) return;
    setState(() => _state = _VoiceState.error);
    widget.onError?.call(message);

    // Return to idle after a brief error flash
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _state = _VoiceState.idle);
    });
  }

  Future<void> _onTap() async {
    if (widget.onMicPressed != null) {
      widget.onMicPressed!();
      return;
    }

    if (widget.onVoiceInput != null) {
      if (_state == _VoiceState.recording || _state == _VoiceState.processing) {
        return;
      }
      setState(() => _state = _VoiceState.recording);
      try {
        final int cursorNodeIndex = widget.controller.selection.nodeIndex;
        final html = await widget.onVoiceInput!();
        if (mounted && html != null && html.trim().isNotEmpty) {
          _injectHtml(html, cursorNodeIndex);
        }
        if (mounted) {
          setState(() => _state = _VoiceState.idle);
        }
      } catch (e) {
        _handleError(e.toString());
      }
      return;
    }

    if (_handler == null) return;

    switch (_state) {
      case _VoiceState.idle:
      case _VoiceState.error:
        _startRecording();

      case _VoiceState.recording:
        await _stopAndProcess();

      case _VoiceState.processing:
        // Ignore taps while the API is in flight
        break;
    }
  }

  void _injectHtml(String html, int cursorNodeIndex) {
    switch (widget.insertMode) {
      case VoiceInsertMode.replace:
        widget.controller.loadHtml(html);
      case VoiceInsertMode.append:
        widget.controller.appendHtml(html);
      case VoiceInsertMode.insertAtCursor:
        widget.controller.insertHtml(html);
    }
  }

  void _startRecording() {
    setState(() => _state = _VoiceState.recording);
    _handler?.startRecording();

    // Auto-stop after maxRecordingSeconds
    _autoStopTimer = Timer(
      Duration(seconds: widget.maxRecordingSeconds),
      _stopAndProcess,
    );
  }

  Future<void> _stopAndProcess() async {
    _autoStopTimer?.cancel();
    if (_state != _VoiceState.recording || _handler == null) return;

    setState(() => _state = _VoiceState.processing);
    final bool success = await _handler!.stopAndProcess();

    if (mounted) {
      setState(() => _state = success ? _VoiceState.idle : _VoiceState.error);
      if (!success) {
        // Auto-recover from error state
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _state = _VoiceState.idle);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _tooltip,
      child: GestureDetector(
        onTap: _onTap,
        child: SizedBox(
          width: widget.size + 8,
          height: widget.size + 8,
          child: Center(child: _buildIcon()),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    switch (_state) {
      case _VoiceState.idle:
        return Icon(
          Icons.auto_awesome,
          size: widget.size * 0.58,
          color: widget.theme.toolbarItemColor,
        );

      case _VoiceState.recording:
        // Pulsing red mic during recording
        return AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (_, __) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: widget.size * 0.72,
                height: widget.size * 0.72,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mic,
                  size: widget.size * 0.48,
                  color: Colors.red,
                ),
              ),
            );
          },
        );

      case _VoiceState.processing:
        return SizedBox(
          width: widget.size * 0.55,
          height: widget.size * 0.55,
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
            color: widget.theme.toolbarItemActiveColor,
          ),
        );

      case _VoiceState.error:
        return Icon(
          Icons.mic_off_outlined,
          size: widget.size * 0.6,
          color: Colors.red,
        );
    }
  }

  String get _tooltip {
    switch (_state) {
      case _VoiceState.idle:
        return 'Generate with AI (Voice or Text)';
      case _VoiceState.recording:
        return 'Recording… tap to stop';
      case _VoiceState.processing:
        return 'Processing voice…';
      case _VoiceState.error:
        return 'Voice input failed';
    }
  }
}
