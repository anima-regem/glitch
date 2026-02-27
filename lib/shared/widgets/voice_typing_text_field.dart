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
    this.alwaysShowMicButton = false,
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
  final bool alwaysShowMicButton;

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
  static const String _retryingFallbackLabel =
      'Retrying with fallback speech mode...';

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
  bool _fallbackRetryAttempted = false;
  bool _recoveringToFallback = false;
  bool _keyboardGuideShownForAttempt = false;
  bool _modelGuideShownForAttempt = false;

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

  bool get _showMicButton => _voiceAvailable;

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

    final palette = context.glitchPalette;
    final isHighlighted = _listening || _starting;

    final micButton = GestureDetector(
      onTap: _handleMicTap,
      onLongPressStart: _handleMicLongPressStart,
      onLongPressEnd: _handleMicLongPressEnd,
      onLongPressCancel: _handleMicLongPressCancel,
      behavior: HitTestBehavior.opaque,
      child: Tooltip(
        message: _listening ? 'Stop voice typing' : 'Start voice typing',
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: ScaleTransition(
              scale: _pulseController,
              child: AnimatedContainer(
                key: const Key('voice_typing_mic_button'),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.accent,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: palette.accent.withValues(
                        alpha: isHighlighted ? 0.55 : 0.35,
                      ),
                      blurRadius: isHighlighted ? 18 : 12,
                      spreadRadius: isHighlighted ? 2 : 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _listening ? Icons.mic : Icons.mic_none,
                  size: 22,
                  color: palette.amoled,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (existingSuffixIcon == null) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 4),
        child: micButton,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        existingSuffixIcon,
        const SizedBox(width: 4),
        micButton,
        const SizedBox(width: 2),
      ],
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

  Future<void> _handleMicTap() async {
    if (_listening || _sessionOpen || _starting) {
      await _stopOrQueueStop();
      return;
    }
    await _handleMicLongPressStart(
      const LongPressStartDetails(globalPosition: Offset.zero),
    );
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

    _fallbackRetryAttempted = false;
    _recoveringToFallback = false;
    _keyboardGuideShownForAttempt = false;
    _modelGuideShownForAttempt = false;
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
    if (onDeviceResult.supportsFallbackHint) {
      didStartFallback = await _tryFallbackStart(
        onFallbackDeclinedError: onDeviceResult.message,
      );
    }

    if (didStartFallback || !mounted) {
      return;
    }

    _starting = false;
    _setVoiceError(onDeviceResult.message ?? 'Unable to start voice typing.');
    if (_shouldOfferModelGuideForStartResult(onDeviceResult)) {
      unawaited(_showOfflineModelGuide());
    }
    if (_shouldOfferKeyboardGuideForStartResult(onDeviceResult)) {
      unawaited(_showKeyboardDictationGuide());
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
      if (_shouldAttemptRuntimeFallback(event)) {
        unawaited(_recoverFromOnDeviceError(event));
        return;
      }
      if (_sessionOpen || _starting || _recoveringToFallback) {
        _setVoiceError(event.message);
        if (_shouldOfferModelGuideForError(event)) {
          unawaited(_showOfflineModelGuide());
        }
        if (_shouldOfferKeyboardGuideForError(event)) {
          unawaited(_showKeyboardDictationGuide());
        }
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
        if (_sessionOpen || _starting || _listening || _recoveringToFallback) {
          setState(() {
            _sessionOpen = false;
            _listening = false;
            _usingFallback = false;
            if (!_recoveringToFallback) {
              _starting = false;
              _statusText = null;
            }
          });
          _pulseController.stop();
          _pulseController.value = 1;
        }
        return;
      }

      _setVoiceError(
        'Speech recognition service is unavailable on this device.',
      );
      unawaited(_showKeyboardDictationGuide());
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
    _recoveringToFallback = false;
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
      _recoveringToFallback = false;
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

  bool _shouldAttemptRuntimeFallback(VoiceTypingEventError event) {
    return _sessionOpen &&
        !_usingFallback &&
        !_recoveringToFallback &&
        !_fallbackRetryAttempted &&
        event.supportsFallbackHint;
  }

  Future<void> _recoverFromOnDeviceError(VoiceTypingEventError event) async {
    if (_voiceService == null) {
      return;
    }

    _fallbackRetryAttempted = true;
    _recoveringToFallback = true;
    setState(() {
      _starting = true;
      _listening = false;
      _statusText = _retryingFallbackLabel;
    });
    _pulseController.stop();
    _pulseController.value = 1;

    await _voiceService!.stopListening();
    if (!mounted) {
      return;
    }

    setState(() {
      _sessionOpen = false;
      _listening = false;
      _usingFallback = false;
      _statusText = _retryingFallbackLabel;
      _starting = true;
    });

    final didStartFallback = await _tryFallbackStart(
      onFallbackDeclinedError: event.message,
    );
    if (!didStartFallback && _shouldOfferKeyboardGuideForError(event)) {
      await _showKeyboardDictationGuide();
    }
  }

  Future<bool> _tryFallbackStart({String? onFallbackDeclinedError}) async {
    if (_voiceService == null) {
      return false;
    }

    final shouldUseFallback = await _shouldUseNetworkFallback();
    if (!shouldUseFallback) {
      _recoveringToFallback = false;
      _starting = false;
      if (onFallbackDeclinedError != null &&
          onFallbackDeclinedError.isNotEmpty) {
        _setVoiceError(onFallbackDeclinedError);
      }
      return false;
    }

    final fallbackResult = await _voiceService!.startListening(
      onDevicePreferred: false,
      partialResults: true,
    );
    if (!mounted) {
      return false;
    }

    if (fallbackResult.started) {
      _openSession(usingFallback: true);
      _starting = false;
      if (_stopAfterStart) {
        _stopAfterStart = false;
        await _stopSession();
      }
      return true;
    }

    _starting = false;
    _recoveringToFallback = false;
    _setVoiceError(
      fallbackResult.message ?? 'Unable to start fallback speech recognition.',
    );
    if (_shouldOfferKeyboardGuideForStartResult(fallbackResult)) {
      unawaited(_showKeyboardDictationGuide());
    }
    return false;
  }

  bool _shouldOfferKeyboardGuideForStartResult(VoiceTypingStartResult result) {
    return result.errorReason == VoiceTypingErrorReason.recognizerUnavailable ||
        (result.failure == VoiceTypingStartFailure.initializeFailed &&
            result.errorReason == VoiceTypingErrorReason.unknown);
  }

  bool _shouldOfferModelGuideForStartResult(VoiceTypingStartResult result) {
    return result.errorReason == VoiceTypingErrorReason.modelNotInstalled ||
        result.errorReason == VoiceTypingErrorReason.modelDownloading ||
        result.errorReason == VoiceTypingErrorReason.modelDownloadFailed;
  }

  bool _shouldOfferKeyboardGuideForError(VoiceTypingEventError event) {
    return event.reason == VoiceTypingErrorReason.recognizerUnavailable;
  }

  bool _shouldOfferModelGuideForError(VoiceTypingEventError event) {
    return event.reason == VoiceTypingErrorReason.modelNotInstalled ||
        event.reason == VoiceTypingErrorReason.modelDownloading ||
        event.reason == VoiceTypingErrorReason.modelDownloadFailed;
  }

  Future<void> _showOfflineModelGuide() async {
    if (!mounted || _modelGuideShownForAttempt) {
      return;
    }
    _modelGuideShownForAttempt = true;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Offline voice model needed'),
          content: const Text(
            'Offline voice typing beta needs a downloaded model.\n\n'
            'Open Settings -> Voice Typing -> Offline Voice Model (Beta), '
            'download the model, then retry dictation.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showKeyboardDictationGuide() async {
    if (!mounted || _keyboardGuideShownForAttempt) {
      return;
    }
    _keyboardGuideShownForAttempt = true;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Use keyboard voice typing'),
          content: const Text(
            'Speech recognition service is unavailable right now.\n\n'
            'You can still dictate using your keyboard mic:\n'
            '1. Focus this text field.\n'
            '2. Tap the microphone on your keyboard (for example Gboard).\n'
            '3. Speak and continue typing as needed.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
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
