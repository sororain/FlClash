import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sororain/common/constant.dart';
import 'package:sororain/core/desktop/helper_client.dart';

const _sessionId = '0123456789abcdef0123456789abcdef';
const _coreSha256 =
    '883550ec98814ede3c065cfc8b84ce67d3af99af4fa16b3cd0044371c0259852';
const _helperPath = r'C:\App\SororainHelperService.exe';
const _baseUrl = 'http://helper.test';

void main() {
  group('HelperClient.readiness', () {
    test('manifest 不可用 -> manifestMissing，且不发起请求', () async {
      final adapter = _FakeAdapter((_) => _json(''));
      final client = _client(adapter, coreSha256: '');

      final readiness = await client.readiness(logFailure: false);

      expect(readiness, HelperReadiness.manifestMissing);
      expect(adapter.requests, isEmpty);
    });

    test('ping 200 + 协议版本一致 + helper 路径一致 -> ready', () async {
      final adapter = _FakeAdapter(
        (_) => _text(
          _helperPath,
          headers: {
            helperProtocolVersionHeader: [helperProtocolVersion],
          },
        ),
      );
      final client = _client(adapter);

      expect(await client.readiness(logFailure: false), HelperReadiness.ready);
      expect(adapter.requests.single.queryParameters['coreSha256'], _coreSha256);
    });

    test('ping 200 但协议版本不符 -> notReady', () async {
      final adapter = _FakeAdapter(
        (_) => _text(_helperPath, headers: {helperProtocolVersionHeader: ['5']}),
      );

      expect(
        await _client(adapter).readiness(logFailure: false),
        HelperReadiness.notReady,
      );
    });

    test('ping 200 但返回的 helper 路径与预期不一致 -> notReady', () async {
      final adapter = _FakeAdapter(
        (_) => _text(
          r'C:\Other\SororainHelperService.exe',
          headers: {
            helperProtocolVersionHeader: [helperProtocolVersion],
          },
        ),
      );

      expect(
        await _client(adapter).readiness(logFailure: false),
        HelperReadiness.notReady,
      );
    });

    test('ping 409 coreSha256Mismatch -> notReady（不降级为直接启动的判据由上层决定）', () async {
      final adapter = _FakeAdapter(
        (_) => _json(
          '{"code":"coreSha256Mismatch"}',
          statusCode: 409,
          headers: {
            helperProtocolVersionHeader: [helperProtocolVersion],
          },
        ),
      );

      expect(
        await _client(adapter).readiness(logFailure: false),
        HelperReadiness.notReady,
      );
    });
  });

  group('HelperClient.start', () {
    test('正常响应 -> 返回 sessionId 与 pid，并带上 address/sessionId 请求体', () async {
      final adapter = _FakeAdapter(
        (_) => _json('{"sessionId":"$_sessionId","pid":4242}'),
      );

      final response = await _client(
        adapter,
      ).start(address: r'\\.\pipe\SororainCore_x', sessionId: _sessionId);

      expect(response.sessionId, _sessionId);
      expect(response.pid, 4242);
      final body = adapter.requests.single.data as Map<String, Object?>;
      expect(body['sessionId'], _sessionId);
      expect(body['address'], r'\\.\pipe\SororainCore_x');
    });

    test('pid 非法 -> invalidResponse', () async {
      final adapter = _FakeAdapter(
        (_) => _json('{"sessionId":"$_sessionId","pid":0}'),
      );

      await expectLater(
        _client(adapter).start(address: 'a', sessionId: _sessionId),
        throwsA(
          isA<HelperException>().having((e) => e.code, 'code', 'invalidResponse'),
        ),
      );
    });

    test('sessionId 回显不一致 -> invalidResponse', () async {
      final adapter = _FakeAdapter(
        (_) => _json('{"sessionId":"${'b' * 32}","pid":4242}'),
      );

      await expectLater(
        _client(adapter).start(address: 'a', sessionId: _sessionId),
        throwsA(
          isA<HelperException>().having((e) => e.code, 'code', 'invalidResponse'),
        ),
      );
    });

    test('409 + code -> 保留 Helper 给出的失败码（回退策略依赖它）', () async {
      final adapter = _FakeAdapter(
        (_) => _json(
          '{"code":"coreVerificationFailed","message":"core hash mismatch"}',
          statusCode: 409,
        ),
      );

      await expectLater(
        _client(adapter).start(address: 'a', sessionId: _sessionId),
        throwsA(
          isA<HelperException>()
              .having((e) => e.code, 'code', 'coreVerificationFailed')
              .having((e) => e.message, 'message', 'core hash mismatch'),
        ),
      );
    });

    test('非法 sessionId -> invalidSessionId，且不发起请求', () async {
      final adapter = _FakeAdapter((_) => _json('{}'));

      await expectLater(
        _client(adapter).start(address: 'a', sessionId: 'not-a-session'),
        throwsA(
          isA<HelperException>()
              .having((e) => e.code, 'code', 'invalidSessionId'),
        ),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('HelperClient.stop', () {
    test('stopped=true 且无 reason -> 正常', () async {
      final adapter = _FakeAdapter(
        (_) => _json('{"sessionId":"$_sessionId","stopped":true}'),
      );

      final response = await _client(adapter).stop(_sessionId);

      expect(response.stopped, isTrue);
      expect(response.reason, isNull);
    });

    test('stopped=false 且 reason=notRunning -> 正常（Helper 认为没在跑）', () async {
      final adapter = _FakeAdapter(
        (_) => _json(
          '{"sessionId":"$_sessionId","stopped":false,"reason":"notRunning"}',
        ),
      );

      final response = await _client(adapter).stop(_sessionId);

      expect(response.stopped, isFalse);
      expect(response.reason, 'notRunning');
    });

    test('stopped=true 却带 reason -> invalidResponse（组合非法）', () async {
      final adapter = _FakeAdapter(
        (_) => _json(
          '{"sessionId":"$_sessionId","stopped":true,"reason":"weird"}',
        ),
      );

      await expectLater(
        _client(adapter).stop(_sessionId),
        throwsA(
          isA<HelperException>().having((e) => e.code, 'code', 'invalidResponse'),
        ),
      );
    });

    test('409 + reason -> 转成同码 HelperException', () async {
      final adapter = _FakeAdapter(
        (_) => _json('{"reason":"sessionMismatch"}', statusCode: 409),
      );

      await expectLater(
        _client(adapter).stop(_sessionId),
        throwsA(
          isA<HelperException>()
              .having((e) => e.code, 'code', 'sessionMismatch'),
        ),
      );
    });
  });
}

HelperClient _client(
  _FakeAdapter adapter, {
  String coreSha256 = _coreSha256,
  String helperPath = _helperPath,
}) {
  return HelperClient(
    dio: Dio()..httpClientAdapter = adapter,
    baseUrl: _baseUrl,
    readCoreSha256: () async => coreSha256,
    expectedHelperPath: () => helperPath,
  );
}

ResponseBody _json(
  String body, {
  int statusCode = 200,
  Map<String, List<String>> headers = const {},
}) {
  return ResponseBody.fromString(
    body,
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    },
  );
}

/// 真实 Helper 的 /ping 返回纯文本（helper 可执行文件路径），不是 JSON。
ResponseBody _text(
  String body, {
  int statusCode = 200,
  Map<String, List<String>> headers = const {},
}) {
  return ResponseBody.fromString(
    body,
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['text/plain'],
      ...headers,
    },
  );
}

final class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final ResponseBody Function(RequestOptions options) _handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
