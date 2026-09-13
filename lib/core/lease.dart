import 'dart:async';
import 'dart:io';

/// Result of a core-process stop request.
///
/// [stopped] mirrors `Process.kill()`'s return value (the process existed and
/// the signal was delivered); [exitConfirmed] is only true when the process
/// was observed to exit within the requested timeout.
class CoreProcessStopResult {
  final bool stopped;
  final bool exitConfirmed;

  const CoreProcessStopResult({
    required this.stopped,
    required this.exitConfirmed,
  });

  @override
  String toString() =>
      'CoreProcessStopResult(stopped: $stopped, exitConfirmed: $exitConfirmed)';
}

/// Owns a running core process and provides an idempotent, exit-confirming
/// stop operation (mirrors 0.8.96's DirectCoreLease contract).
abstract interface class CoreProcessLease {
  int get pid;

  Future<CoreProcessStopResult> stop(Duration timeout);
}

final class DirectCoreLease implements CoreProcessLease {
  @override
  final int pid;

  final Process _process;
  Future<CoreProcessStopResult>? _stopOperation;

  DirectCoreLease({required Process process})
    : _process = process,
      pid = process.pid;

  @override
  Future<CoreProcessStopResult> stop(Duration timeout) {
    final stopOperation = _stopOperation;
    if (stopOperation != null) {
      // Already stopping (or stopped): hand back the same future so repeated
      // stop calls are idempotent and never kill twice.
      return stopOperation;
    }
    final nextOperation = _stop(timeout).then((result) {
      if (!result.exitConfirmed) {
        // Exit not confirmed within the timeout: allow a later retry.
        _stopOperation = null;
      }
      return result;
    });
    _stopOperation = nextOperation;
    return nextOperation;
  }

  Future<CoreProcessStopResult> _stop(Duration timeout) async {
    final stopped = _process.kill();
    try {
      await _process.exitCode.timeout(timeout);
      return CoreProcessStopResult(stopped: stopped, exitConfirmed: true);
    } on TimeoutException {
      return CoreProcessStopResult(stopped: stopped, exitConfirmed: false);
    }
  }
}
