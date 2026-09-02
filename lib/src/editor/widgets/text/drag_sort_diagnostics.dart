import 'package:flutter/foundation.dart';

/// Content-safe diagnostics for the paragraph drag-sort lifecycle.
///
/// One operation id connects gesture ownership, magnifier gating, overlay
/// presentation, document mutation, and termination without logging note text.
/// Debug builds print to the console; apps may attach a persisted log sink.
final class QuillDragSortDiagnostics {
  QuillDragSortDiagnostics._();

  /// Optional application-owned sink for persisted diagnostics.
  ///
  /// Sink failures are ignored so diagnostics can never break editor input.
  static ValueChanged<String>? logSink;

  static int _nextOperationId = 0;
  static int? _operationId;
  static DateTime? _lastMovementLogAt;
  static bool _sinkActivated = false;
  static final List<String> _pendingSinkMessages = <String>[];

  static void beginAttempt() {
    _operationId = ++_nextOperationId;
    _lastMovementLogAt = null;
    _sinkActivated = false;
    _pendingSinkMessages.clear();
    event(phase: 'gesture_candidate', result: 'started');
  }

  static void event({
    required String phase,
    required String result,
    String? reason,
    bool activateSink = false,
  }) {
    final sink = logSink;
    if (!kDebugMode && sink == null) return;
    if (activateSink && _operationId == null) {
      _operationId = ++_nextOperationId;
      _lastMovementLogAt = null;
      _sinkActivated = false;
      _pendingSinkMessages.clear();
    }
    final fields = <String>[
      '[QuillDragSort]',
      'operation=${_operationId ?? 0}',
      'phase=$phase',
      'result=$result',
      if (reason != null) 'reason=$reason',
    ];
    final message = fields.join(' ');
    if (kDebugMode) debugPrint(message);
    if (activateSink) {
      _sinkActivated = true;
      for (final pendingMessage in _pendingSinkMessages) {
        _sendToSink(sink, pendingMessage);
      }
      _pendingSinkMessages.clear();
    }
    if (_sinkActivated) {
      _sendToSink(sink, message);
    } else {
      _pendingSinkMessages.add(message);
    }
  }

  static void movement() {
    if (!kDebugMode && logSink == null) return;
    final now = DateTime.now();
    final lastLogAt = _lastMovementLogAt;
    if (lastLogAt != null &&
        now.difference(lastLogAt) < const Duration(milliseconds: 250)) {
      return;
    }
    _lastMovementLogAt = now;
    event(phase: 'drag_update', result: 'accepted');
  }

  static void finish({
    required String result,
    String? reason,
    String phase = 'drag_end',
  }) {
    if (_operationId == null) return;
    event(phase: phase, result: result, reason: reason);
    _operationId = null;
    _lastMovementLogAt = null;
    _sinkActivated = false;
    _pendingSinkMessages.clear();
  }

  static void _sendToSink(ValueChanged<String>? sink, String message) {
    try {
      sink?.call(message);
    } catch (_) {
      // Diagnostics must never change editor behavior.
    }
  }
}
