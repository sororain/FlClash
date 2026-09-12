import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sororain/core/desktop/launcher.dart';
import 'package:sororain/core/desktop/manager.dart';
import 'package:sororain/core/desktop/model.dart';

void main() {
  group('DesktopCoreManager.start', () {
    test('成功启动：状态 idle -> starting -> running，结果 applied', () async {
      final launcher = _FakeLauncher();
      final manager = DesktopCoreManager(launcherResolver: _FakeResolver(launcher));
      final phases = <DesktopCorePhase>[];
      manager.states.listen((state) => phases.add(state.phase));

      final result = await manager.start(address: 'pipe');
      // 广播流的事件是异步派发的，等一个事件循环再断言状态序列。
      await Future<void>.delayed(Duration.zero);

      expect(result.outcome, CoreLifecycleOutcome.applied);
      expect(result.session?.owner, CoreProcessOwner.direct);
      expect(manager.state.phase, DesktopCorePhase.running);
      expect(phases, [DesktopCorePhase.starting, DesktopCorePhase.running]);
      expect(launcher.startCalls, 1);
    });

    test('已 running 时重复 start -> coalesced，且不重复拉起', () async {
      final launcher = _FakeLauncher();
      final manager = DesktopCoreManager(launcherResolver: _FakeResolver(launcher));

      final first = await manager.start(address: 'pipe');
      final second = await manager.start(address: 'pipe');

      expect(first.outcome, CoreLifecycleOutcome.applied);
      expect(second.outcome, CoreLifecycleOutcome.coalesced);
      expect(second.session, first.session);
      expect(launcher.startCalls, 1);
    });

    test('启动抛异常 -> failed(startFailed) 且 phase 为 starting', () async {
      final launcher = _FakeLauncher()..errorToThrow = StateError('no helper');
      final manager = DesktopCoreManager(launcherResolver: _FakeResolver(launcher));

      final result = await manager.start(address: 'pipe');

      expect(result.outcome, CoreLifecycleOutcome.applied);
      final state = manager.state;
      expect(state, isA<DesktopCoreFailed>());
      final failure = (state as DesktopCoreFailed).failure;
      expect(failure.code, 'startFailed');
      expect(failure.phase, DesktopCorePhase.starting);
      expect(failure.cause, isA<StateError>());
    });

    test('启动超时 -> failed(startTimeout)', () async {
      final launcher = _FakeLauncher()..pending = Completer<CoreProcessLease>();
      final manager = DesktopCoreManager(
        launcherResolver: _FakeResolver(launcher),
        timeouts: const DesktopCoreTimeouts(
          ready: Duration(milliseconds: 20),
        ),
      );

      await manager.start(address: 'pipe');

      expect(
        (manager.state as DesktopCoreFailed).failure.code,
        'startTimeout',
      );
    });

    test('启动期间 stop -> start 报告 superseded 并自行收尾', () async {
      final pending = Completer<CoreProcessLease>();
      final lease = _FakeLease(sessionId: 'session-1');
      final launcher = _FakeLauncher()..pending = pending;
      final manager = DesktopCoreManager(launcherResolver: _FakeResolver(launcher));

      final startFuture = manager.start(address: 'pipe');
      final stopFuture = manager.stop();
      pending.complete(lease);

      final startResult = await startFuture;
      final stopResult = await stopFuture;

      expect(startResult.outcome, CoreLifecycleOutcome.superseded);
      expect(startResult.session, isNull);
      expect(lease.stopCalls, 1, reason: '被取代的启动必须自己把 Core 收干净');
      expect(stopResult.outcome, CoreLifecycleOutcome.coalesced);
    });
  });

  group('DesktopCoreManager.stop', () {
    test('未运行时 stop -> coalesced', () async {
      final manager = DesktopCoreManager(launcherResolver: _FakeResolver(_FakeLauncher()));

      final result = await manager.stop();

      expect(result.outcome, CoreLifecycleOutcome.coalesced);
      expect(manager.state.phase, DesktopCorePhase.idle);
    });

    test('成功停止 -> closed', () async {
      final launcher = _FakeLauncher();
      final manager = DesktopCoreManager(launcherResolver: _FakeResolver(launcher));
      await manager.start(address: 'pipe');

      final result = await manager.stop();

      expect(result.outcome, CoreLifecycleOutcome.applied);
      expect(manager.state.phase, DesktopCorePhase.closed);
      expect(launcher.leases.single.stopCalls, 1);
    });

    test('退出未确认 -> failed(stopUnconfirmed)', () async {
      final launcher = _FakeLauncher();
      final manager = DesktopCoreManager(launcherResolver: _FakeResolver(launcher));
      await manager.start(address: 'pipe');
      launcher.leases.single.stopResult = const CoreProcessStopResult(
        stopped: true,
        exitConfirmed: false,
      );

      await manager.stop();

      final state = manager.state;
      expect(state, isA<DesktopCoreFailed>());
      final failure = (state as DesktopCoreFailed).failure;
      expect(failure.code, 'stopUnconfirmed');
      expect(failure.phase, DesktopCorePhase.stopping);
      expect(failure.owner, CoreProcessOwner.direct);
    });

    test('失败后仍可重试 start（错误不会卡死操作链）', () async {
      final launcher = _FakeLauncher()..errorToThrow = StateError('boom');
      final manager = DesktopCoreManager(launcherResolver: _FakeResolver(launcher));

      await manager.start(address: 'pipe');
      launcher.errorToThrow = null;
      final retry = await manager.start(address: 'pipe');

      expect(retry.outcome, CoreLifecycleOutcome.applied);
      expect(manager.state.phase, DesktopCorePhase.running);
    });
  });
}

final class _FakeResolver implements DesktopCoreLauncherResolver {
  _FakeResolver(this._launcher);

  final CoreProcessLauncher _launcher;

  @override
  Future<CoreProcessLauncher> resolve() async => _launcher;
}

final class _FakeLauncher implements CoreProcessLauncher {
  Completer<CoreProcessLease>? pending;
  Object? errorToThrow;
  int startCalls = 0;
  final List<_FakeLease> leases = [];

  @override
  Future<CoreProcessLease> start({
    required String sessionId,
    required String address,
  }) async {
    startCalls++;
    final error = errorToThrow;
    if (error != null) {
      throw error;
    }
    final completer = pending;
    if (completer != null) {
      return completer.future;
    }
    final lease = _FakeLease(sessionId: sessionId);
    leases.add(lease);
    return lease;
  }
}

final class _FakeLease implements CoreProcessLease {
  _FakeLease({required this.sessionId});

  @override
  final String sessionId;

  CoreProcessStopResult stopResult = const CoreProcessStopResult(
    stopped: true,
    exitConfirmed: true,
  );
  int stopCalls = 0;

  @override
  CoreProcessOwner get owner => CoreProcessOwner.direct;

  @override
  int get pid => 4242;

  @override
  Future<CoreProcessStopResult> stop(Duration timeout) async {
    stopCalls++;
    return stopResult;
  }
}
