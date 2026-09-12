import 'package:flutter_test/flutter_test.dart';
import 'package:sororain/core/desktop/helper_client.dart';
import 'package:sororain/core/desktop/launcher.dart';
import 'package:sororain/core/desktop/model.dart';

void main() {
  group('FallbackCoreLauncher', () {
    test('Helper 在 spawn Core 之前失败 -> 回退到直接启动', () async {
      final direct = _FakeLauncher(CoreProcessOwner.direct);
      final launcher = FallbackCoreLauncher(
        primary: _ThrowingLauncher(
          const HelperException(
            code: 'coreVerificationFailed',
            message: 'core hash mismatch',
          ),
        ),
        fallback: direct,
      );

      final lease = await launcher.start(sessionId: 's1', address: 'a1');

      expect(lease.owner, CoreProcessOwner.direct);
      expect(direct.startCalls, 1);
    });

    test('processLaunchFailed 同样回退（Helper 未留下受管 Core）', () async {
      final direct = _FakeLauncher(CoreProcessOwner.direct);
      final launcher = FallbackCoreLauncher(
        primary: _ThrowingLauncher(
          const HelperException(
            code: 'processLaunchFailed',
            message: 'CreateProcess failed',
          ),
        ),
        fallback: direct,
      );

      final lease = await launcher.start(sessionId: 's1', address: 'a1');

      expect(lease.owner, CoreProcessOwner.direct);
      expect(direct.startCalls, 1);
    });

    test('其他失败码不回退，直接抛给上层', () async {
      final direct = _FakeLauncher(CoreProcessOwner.direct);
      final launcher = FallbackCoreLauncher(
        primary: _ThrowingLauncher(
          const HelperException(
            code: 'transportError',
            message: 'helper unreachable',
          ),
        ),
        fallback: direct,
      );

      await expectLater(
        launcher.start(sessionId: 's1', address: 'a1'),
        throwsA(isA<HelperException>()),
      );
      expect(direct.startCalls, 0, reason: '失败码不在白名单内时不应静默降级');
    });

    test('Helper 启动成功则不触碰 fallback', () async {
      final helper = _FakeLauncher(CoreProcessOwner.helper);
      final direct = _FakeLauncher(CoreProcessOwner.direct);
      final launcher = FallbackCoreLauncher(
        primary: helper,
        fallback: direct,
      );

      final lease = await launcher.start(sessionId: 's1', address: 'a1');

      expect(lease.owner, CoreProcessOwner.helper);
      expect(helper.startCalls, 1);
      expect(direct.startCalls, 0);
    });
  });

  group('HelperLauncherResolver', () {
    test('没有 Helper 时直接返回直接启动器，且不做 readiness 探测', () async {
      var probes = 0;
      final direct = _FakeLauncher(CoreProcessOwner.direct);
      final resolver = HelperLauncherResolver(
        hasHelper: false,
        directLauncher: direct,
        helperLauncher: _FakeLauncher(CoreProcessOwner.helper),
        helperReady: () async {
          probes++;
          return HelperReadiness.ready;
        },
      );

      final lease = await (await resolver.resolve()).start(
        sessionId: 's1',
        address: 'a1',
      );

      expect(lease.owner, CoreProcessOwner.direct);
      expect(probes, 0);
    });

    test('Helper ready -> 返回 Helper(+回退) 组合', () async {
      final resolver = HelperLauncherResolver(
        hasHelper: true,
        directLauncher: _FakeLauncher(CoreProcessOwner.direct),
        helperLauncher: _FakeLauncher(CoreProcessOwner.helper),
        helperReady: () async => HelperReadiness.ready,
      );

      final lease = await (await resolver.resolve()).start(
        sessionId: 's1',
        address: 'a1',
      );

      expect(lease.owner, CoreProcessOwner.helper);
    });

    test('Helper 未就绪 -> 直接启动', () async {
      final resolver = HelperLauncherResolver(
        hasHelper: true,
        directLauncher: _FakeLauncher(CoreProcessOwner.direct),
        helperLauncher: _FakeLauncher(CoreProcessOwner.helper),
        helperReady: () async => HelperReadiness.notReady,
      );

      final lease = await (await resolver.resolve()).start(
        sessionId: 's1',
        address: 'a1',
      );

      expect(lease.owner, CoreProcessOwner.direct);
    });

    test('manifest 缺失/不可用 -> 直接启动', () async {
      final resolver = HelperLauncherResolver(
        hasHelper: true,
        directLauncher: _FakeLauncher(CoreProcessOwner.direct),
        helperLauncher: _FakeLauncher(CoreProcessOwner.helper),
        helperReady: () async => HelperReadiness.manifestMissing,
      );

      final lease = await (await resolver.resolve()).start(
        sessionId: 's1',
        address: 'a1',
      );

      expect(lease.owner, CoreProcessOwner.direct);
    });
  });
}

final class _FakeLauncher implements CoreProcessLauncher {
  _FakeLauncher(this.owner);

  final CoreProcessOwner owner;
  int startCalls = 0;

  @override
  Future<CoreProcessLease> start({
    required String sessionId,
    required String address,
  }) async {
    startCalls++;
    return _FakeLease(sessionId: sessionId, owner: owner);
  }
}

final class _ThrowingLauncher implements CoreProcessLauncher {
  _ThrowingLauncher(this.error);

  final HelperException error;

  @override
  Future<CoreProcessLease> start({
    required String sessionId,
    required String address,
  }) async {
    throw error;
  }
}

final class _FakeLease implements CoreProcessLease {
  _FakeLease({required this.sessionId, required this.owner});

  @override
  final String sessionId;

  @override
  final CoreProcessOwner owner;

  @override
  int get pid => 4242;

  @override
  Future<CoreProcessStopResult> stop(Duration timeout) async {
    return const CoreProcessStopResult(stopped: true, exitConfirmed: true);
  }
}
