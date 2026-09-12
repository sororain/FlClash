import 'dart:async';

import 'package:sororain/common/common.dart';
import 'package:sororain/enum/enum.dart';

import 'launcher.dart';
import 'model.dart';

/// 桌面 Core 的生命周期编排器。
///
/// 职责边界：
/// - 只负责"把 Core 进程拉起来 / 收干净"以及状态与失败分类；
/// - **不**负责与 Core 的数据连接（socket/管道由调用方自己管），所以
///   [DesktopCoreTimeouts.connection] 留给调用方使用；
/// - 启动与停止串行执行（内部操作链），并用修订号标记"启动期间又来了新请求"
///   的情况：被取代的操作会自己收尾并把 [CoreLifecycleOutcome.superseded]
///   回报给调用者。
final class DesktopCoreManager {
  DesktopCoreManager({
    required DesktopCoreLauncherResolver launcherResolver,
    DesktopCoreTimeouts timeouts = const DesktopCoreTimeouts(),
    String Function() sessionIdFactory = createCoreSessionId,
  }) : _launcherResolver = launcherResolver,
       _timeouts = timeouts,
       _sessionIdFactory = sessionIdFactory;

  final DesktopCoreLauncherResolver _launcherResolver;
  final DesktopCoreTimeouts _timeouts;
  final String Function() _sessionIdFactory;

  final StreamController<DesktopCoreState> _states =
      StreamController<DesktopCoreState>.broadcast();

  DesktopCoreState _state = const DesktopCoreIdle();
  Future<void> _chain = Future<void>.value();
  int _revision = 0;
  bool _disposed = false;

  DesktopCoreState get state => _state;

  Stream<DesktopCoreState> get states => _states.stream;

  Future<void> dispose() async {
    _disposed = true;
    await _states.close();
  }

  /// 拉起 Core 并等待进程就绪（`timeouts.ready` 内）。
  ///
  /// 已经 running 时返回 [CoreLifecycleOutcome.coalesced]，不会重复拉起。
  Future<CoreLifecycleResult> start({
    required String address,
    String? sessionId,
  }) {
    final revision = ++_revision;
    return _enqueue(
      revision,
      () => _start(revision, address: address, sessionId: sessionId),
    );
  }

  /// 停止当前会话；未在运行时返回 [CoreLifecycleOutcome.coalesced]。
  Future<CoreLifecycleResult> stop() {
    final revision = ++_revision;
    return _enqueue(revision, () => _stop(revision));
  }

  Future<CoreLifecycleResult> _enqueue(
    int revision,
    Future<CoreLifecycleResult> Function() operation,
  ) {
    final result = _chain.then((_) => operation());
    // 链上只保留"已结束"的信号，避免一次失败卡死后续操作。
    _chain = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<CoreLifecycleResult> _start(
    int revision, {
    required String address,
    String? sessionId,
  }) async {
    final current = _state;
    if (current is DesktopCoreRunning) {
      return CoreLifecycleResult(
        revision: revision,
        outcome: CoreLifecycleOutcome.coalesced,
        session: current.session,
      );
    }

    final resolvedSessionId = sessionId ?? _sessionIdFactory();
    _emit(DesktopCoreStarting(revision: revision, sessionId: resolvedSessionId));

    final CoreProcessLease lease;
    try {
      final launcher = await _launcherResolver.resolve();
      lease = await launcher
          .start(sessionId: resolvedSessionId, address: address)
          .timeout(_timeouts.ready);
    } on TimeoutException catch (error, stackTrace) {
      _emit(
        DesktopCoreFailed(
          _failure(
            'startTimeout',
            DesktopCorePhase.starting,
            revision,
            sessionId: resolvedSessionId,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
      return CoreLifecycleResult(
        revision: revision,
        outcome: CoreLifecycleOutcome.applied,
      );
    } catch (error, stackTrace) {
      _emit(
        DesktopCoreFailed(
          _failure(
            'startFailed',
            DesktopCorePhase.starting,
            revision,
            sessionId: resolvedSessionId,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
      return CoreLifecycleResult(
        revision: revision,
        outcome: CoreLifecycleOutcome.applied,
      );
    }

    if (revision != _revision) {
      // 启动期间来了更新的请求（典型是 stop）：不进入 running，自己把刚拉起的
      // Core 收干净，并标明被取代。
      await _bestEffortStop(lease);
      return CoreLifecycleResult(
        revision: revision,
        outcome: CoreLifecycleOutcome.superseded,
      );
    }

    final session = DesktopCoreSession(
      sessionId: lease.sessionId,
      lease: lease,
      connectionGeneration: revision,
    );
    _emit(DesktopCoreRunning(session));
    return CoreLifecycleResult(
      revision: revision,
      outcome: CoreLifecycleOutcome.applied,
      session: session,
    );
  }

  Future<CoreLifecycleResult> _stop(int revision) async {
    final current = _state;
    final session = switch (current) {
      DesktopCoreRunning(:final session) => session,
      DesktopCoreStopping(:final session) => session,
      _ => null,
    };
    if (session == null) {
      return CoreLifecycleResult(
        revision: revision,
        outcome: CoreLifecycleOutcome.coalesced,
      );
    }

    _emit(DesktopCoreStopping(revision: revision, session: session));
    final result = await session.lease.stop(_timeouts.disconnection);
    if (!result.exitConfirmed) {
      _emit(
        DesktopCoreFailed(
          _failure(
            'stopUnconfirmed',
            DesktopCorePhase.stopping,
            revision,
            session: session,
            cause: result,
          ),
        ),
      );
      return CoreLifecycleResult(
        revision: revision,
        outcome: CoreLifecycleOutcome.applied,
        session: session,
      );
    }

    if (revision != _revision) {
      return CoreLifecycleResult(
        revision: revision,
        outcome: CoreLifecycleOutcome.superseded,
        session: session,
      );
    }

    _emit(DesktopCoreClosed(revision));
    return CoreLifecycleResult(
      revision: revision,
      outcome: CoreLifecycleOutcome.applied,
      session: session,
    );
  }

  Future<void> _bestEffortStop(CoreProcessLease lease) async {
    try {
      await lease.stop(_timeouts.disconnection);
    } catch (error) {
      commonPrint.log(
        'Failed to release superseded Core session ${lease.sessionId}: '
        '${compactError(error)}',
        logLevel: LogLevel.warning,
      );
    }
  }

  DesktopCoreFailure _failure(
    String code,
    DesktopCorePhase phase,
    int revision, {
    String? sessionId,
    DesktopCoreSession? session,
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return DesktopCoreFailure(
      code: code,
      phase: phase,
      revision: revision,
      sessionId: session?.sessionId ?? sessionId,
      owner: session?.owner,
      pid: session?.pid,
      connectionGeneration: session?.connectionGeneration,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  void _emit(DesktopCoreState next) {
    _state = next;
    if (!_disposed && !_states.isClosed) {
      _states.add(next);
    }
  }
}
