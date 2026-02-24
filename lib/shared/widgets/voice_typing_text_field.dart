import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/voice_typing_service.dart';
import '../../core/theme/app_theme.dart';
import '../state/app_controller.dart';

class VoiceTypingTextField extends ConsumerStatefulWidget {
  const VoiceTypingTextField({
    super.key,
    required this.controller,
    required this.decoration,
    required this.voiceTypingEnabled,
    required this.allowNetworkFallback,
    this.onAllowNetworkFallbackChanged,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.minLines,
    this.maxLines = 1,
    this.autofocus = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.voiceTypingEligible = true,
    this.textCapitalization = TextCapitalization.none,
    this.scrollPadding = const EdgeInsets.all(20),
    this.onTapOutside,
    this.onChanged,
    this.onSubmitted,
    this.platformSupportOverride,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final bool voiceTypingEnabled;
  final bool allowNetworkFallback;
  final Future<void> Function(bool value)? onAllowNetworkFallbackChanged;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? minLines;
  final int? maxLines;
  final bool autofocus;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool voiceTypingEligible;
  final TextCapitalization textCapitalization;
  final EdgeInsets scrollPadding;
  final TapRegionCallback? onTapOutside;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  // Useful for widget tests where Platform.isAndroid is false.
  final bool? platformSupportOverride;

  @override
  ConsumerState<VoiceTypingTextField> createState() =>
      _VoiceTypingTextFieldState();
}

class _VoiceTypingTextFieldState extends ConsumerState<VoiceTypingTextField>
    with SingleTickerProviderStateMixin {
  static const String _listeningLabel = 'Listening...';
  static const String _finalizingLabel = 'Finishing dictation...';
  static const String _fallbackLabel =
      'Listening in fallback mode (speech may use network).';

  late final FocusNode _effectiveFocusNode;
  late final bool _ownsFocusNode;
  late final AnimationController _pulseController;

  StreamSubscription<VoiceTypingEvent>? _voiceEventsSubscription;
  VoiceTypingService? _voiceService;

  bool _fieldFocused = false;
  bool _listening = false;
  bool _sessionOpen = false;
  bool _starting = false;
  bool _stopAfterStart = false;
  bool _usingFallback = false;

  String? _statusText;
  String? _voiceErrorText;

  String _baselineText = '';
  int _baselineSelectionStart = 0;
  int _baselineSelectionEnd = 0;

  bool get _platformSupported {
    return widget.platformSupportOverride ?? Platform.isAndroid;
  }

  bool get _voiceAvailable {
    return _platformSupported &&
        widget.voiceTypingEligible &&
        widget.voiceTypingEnabled &&
        widget.enabled &&
        !widget.readOnly &&
        !widget.obscureText;
  }

  bool get _showMicButton => _voiceAvailable && _fieldFocused;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _effectiveFocusNode = widget.focusNode ?? FocusNode();
    _effectiveFocusNode.addListener(_handleFocusChanged);
    _fieldFocused = _effectiveFocusNode.hasFocus;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 0.95,
      upperBound: 1.15,
      value: 1,
    );
    _ensureVoiceSubscription();
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _effectiveFocusNode.dispose();
    }
    _voiceEventsSubscription?.cancel();
    if (_sessionOpen || _starting || _listening) {
      unawaited(_voiceService?.cancel());
    }
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.glitchPalette;
    final decoration = widget.decoration.copyWith(
      suffixIcon: _buildSuffixIcon(widget.decoration.suffixIcon),
    );

    final helperText = _voiceErrorText ?? _statusText;
    final helperColor = _voiceErrorText != null
        ? palette.warning
        : (_usingFallback ? palette.warning : palette.textMuted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: widget.controller,
          focusNode: _effectiveFocusNode,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          autofocus: widget.autofocus,
          autocorrect: widget.autocorrect,
          enableSuggestions: widget.enableSuggestions,
          obscureText: widget.obscureText,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          textCapitalization: widget.textCapitalization,
          scrollPadding: widget.scrollPadding,
          onTapOutside: widget.onTapOutside,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          decoration: decoration,
        ),
        if (helperText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12, right: 12),
            child: Text(
              helperText,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: helperColor),
            ),
          ),
      ],
    );
  }

  Widget? _buildSuffixIcon(Widget? existingSuffixIcon) {
    if (!_showMicButton) {
      return existingSuffixIcon;
    }

    final micButton = GestureDetector(
      onLongPressStart: _handleMicLongPressStart,
      onLongPressEnd: _handleMicLongPressEnd,
      onLongPressCancel: _handleMicLongPressCancel,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Center(
          child: ScaleTransition(
            scale: _pulseController,
            child: Icon(
              _listening ? Icons.mic : Icons.mic_none,
              size: 20,
              color: _listening
                  ? Theme.of(context).colorScheme.secondary
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );

    if (existingSuffixIcon == null) {
      return micButton;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[existingSuffixIcon, micButton],
    );
  }

  void _ensureVoiceSubscription() {
    final service = ref.read(voiceTypingServiceProvider);
    if (identical(_voiceService, service)) {
      return;
    }

    _voiceEventsSubscription?.cancel();
    _voiceService = service;
    _voiceEventsSubscription = service.events.listen(_handleVoiceEvent);
  }

  Future<void> _handleMicLongPressStart(LongPressStartDetails _) async {
    if (!_voiceAvailable ||
        _sessionOpen ||
        _starting ||
        _voiceService == null) {
      return;
    }

    setState(() {
      _voiceErrorText = null;
      _statusText = 'Starting voice typing...';
      _starting = true;
      _stopAfterStart = false;
      _usingFallback = false;
    });

    _captureBaseline();
    final onDeviceResult = await _voiceService!.startListening(
      onDevicePreferred: true,
      partialResults: true,
    );

    if (!mounted) {
      return;
    }

    if (onDeviceResult.started) {
      _openSession(usingFallback: false);
      _starting = false;
      if (_stopAfterStart) {
        _stopAfterStart = false;
        await _stopSession();
      }
      return;
    }

    var didStartFallback = false;
    var failureHandled = false;
    if (onDeviceResult.supportsFallbackHint) {
      final shouldUseFallback = await _shouldUseNetworkFallback();
      if (shouldUseFallback) {
        final fallbackResult = await _voiceService!.startListening(
          onDevicePreferred: false,
          partialResults: true,
        );
        if (!mounted) {
          return;
        }
        if (fallbackResult.started) {
          _openSession(usingFallback: true);
          didStartFallback = true;
          _starting = false;
          if (_stopAfterStart) {
            _stopAfterStart = false;
            await _stopSession();
          }
        } else {
          _setVoiceError(
            fallbackResult.message ??
                'Unable to start fallback speech recognition.',
          );
          failureHandled = true;
        }
      }
    }

    if (!didStartFallback && !failureHandled && mounted) {
      _starting = false;
      _setVoiceError(onDeviceResult.message ?? 'Unable to start voice typing.');
    }
  }

  Future<void> _handleMicLongPressEnd(LongPressEndDetails _) async {
    await _stopOrQueueStop();
  }

  Future<void> _handleMicLongPressCancel() async {
    await _stopOrQueueStop();
  }

  Future<void> _stopOrQueueStop() async {
    if (_starting) {
      _stopAfterStart = true;
      return;
    }
    await _stopSession();
  }

  Future<void> _stopSession() async {
    if (!_sessionOpen && !_listening) {
      return;
    }

    setState(() {
      _listening = false;
      _statusText = _finalizingLabel;
    });
    _pulseController.stop();
    _pulseController.value = 1;
    await _voiceService?.stopListening();
  }

  void _handleVoiceEvent(VoiceTypingEvent event) {
    if (!mounted) {
      return;
    }

    if (event is VoiceTypingEventPartial) {
      if (_sessionOpen) {
        _applyTranscript(event.text);
      }
      return;
    }

    if (event is VoiceTypingEventFinal) {
      if (_sessionOpen) {
        _applyTranscript(event.text);
      }
      return;
    }

    if (event is VoiceTypingEventError) {
      if (_sessionOpen || _starting) {
        _setVoiceError(event.message);
      }
      return;
    }

    if (event is VoiceTypingEventStatus) {
      if (event.status == VoiceTypingStatus.listening) {
        if (_sessionOpen) {
          setState(() {
            _listening = true;
            _statusText = _usingFallback ? _fallbackLabel : _listeningLabel;
          });
          _pulseController.repeat(reverse: true);
        }
        return;
      }

      if (event.status == VoiceTypingStatus.stopped) {
        if (_sessionOpen || _starting || _listening) {
          setState(() {
            _sessionOpen = false;
            _starting = false;
            _listening = false;
            _usingFallback = false;
            _statusText = null;
          });
          _pulseController.stop();
          _pulseController.value = 1;
        }
        return;
      }

      _setVoiceError('Speech recognition is unavailable on this device.');
    }
  }

  void _openSession({required bool usingFallback}) {
    setState(() {
      _sessionOpen = true;
      _listening = true;
      _usingFallback = usingFallback;
      _voiceErrorText = null;
      _statusText = usingFallback ? _fallbackLabel : _listeningLabel;
    });
    _pulseController.repeat(reverse: true);
  }

  void _setVoiceError(String message) {
    if (!mounted) {
      return;
    }

    _pulseController.stop();
    _pulseController.value = 1;
    setState(() {
      _starting = false;
      _sessionOpen = false;
      _listening = false;
      _usingFallback = false;
      _statusText = null;
      _voiceErrorText = message;
    });
    _showErrorSnackbar(message);
  }

  void _showErrorSnackbar(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _captureBaseline() {
    final text = widget.controller.text;
    final selection = _normalizedSelection(widget.controller.selection, text);
    _baselineText = text;
    _baselineSelectionStart = selection.start;
    _baselineSelectionEnd = selection.end;
  }

  TextSelection _normalizedSelection(TextSelection selection, String text) {
    if (!selection.isValid) {
      return TextSelection.collapsed(offset: text.length);
    }

    final safeStart = selection.start.clamp(0, text.length).toInt();
    final safeEnd = selection.end.clamp(0, text.length).toInt();
    return TextSelection(baseOffset: safeStart, extentOffset: safeEnd);
  }

  void _applyTranscript(String transcript) {
    if (!_sessionOpen) {
      return;
    }

    final normalizedTranscript = transcript.trim();
    if (normalizedTranscript.isEmpty) {
      return;
    }

    final prefix = _baselineText.substring(0, _baselineSelectionStart);
    final suffix = _baselineText.substring(_baselineSelectionEnd);
    final mergedText = '$prefix$normalizedTranscript$suffix';
    final cursor = (prefix.length + normalizedTranscript.length)
        .clamp(0, mergedText.length)
        .toInt();

    widget.controller.value = TextEditingValue(
      text: mergedText,
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );
    widget.onChanged?.call(mergedText);
  }

  Future<bool> _shouldUseNetworkFallback() async {
    if (widget.allowNetworkFallback) {
      return true;
    }

    final confirmed = await _confirmFallbackDialog();
    if (!confirmed) {
      return false;
    }

    if (widget.onAllowNetworkFallbackChanged != null) {
      await widget.onAllowNetworkFallbackChanged!(true);
    }
    return true;
  }

  Future<bool> _confirmFallbackDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Fallback speech mode?'),
          content: const Text(
            'On-device recognition is unavailable right now. '
            'Fallback speech mode may send audio to the device speech provider '
            'over network. Continue?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Allow fallback'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _handleFocusChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _fieldFocused = _effectiveFocusNode.hasFocus;
      if (_fieldFocused) {
        _voiceErrorText = null;
      } else if (!_listening && !_starting) {
        _statusText = null;
      }
    });
  }
}
