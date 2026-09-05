import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/core.dart';

import 'interface.dart';
import 'transport.dart';

class CoreService extends CoreHandlerInterface {
  static CoreService? _instance;

  late final IPCCoreTransport _transport;
  final Completer<void> _initCompleter = Completer<void>();

  Completer<bool> _shutdownCompleter = Completer();

  final Map<String, Completer> _callbackCompleterMap = {};

  Process? _process;

  factory CoreService() {
    _instance ??= CoreService._internal();
    return _instance!;
  }

  CoreService._internal() {
    _transport = IPCCoreTransport(
      address: system.isWindows ? windowsPipeName : unixSocketPath,
    );
    _initServer().then((_) => _initCompleter.complete());
  }

  Future<void> handleResult(ActionResult result) async {
    final completer = _callbackCompleterMap[result.id];
    final data = await parasResult(result);
    if (completer?.isCompleted == true) {
      return;
    }
    completer?.complete(data);
  }

  Future<void> _initServer() async {
    await _transport.init();

    _transport.onDisconnect = () {
      _handleInvokeCrashEvent();
      if (!_shutdownCompleter.isCompleted) {
        _shutdownCompleter.complete(true);
      }
    };

    _transport.dataStream
        .transform(uint8ListToListIntConverter)
        .transform(utf8.decoder)
        .listen(
          (data) async {
            try {
              final dataJson =
                  await data.trim().commonToJSON<dynamic>();
              if (dataJson is Map &&
                  dataJson['method'] == ActionMethod.message.name) {
                // 0.8.96 core batches events into one message call
                final arguments = dataJson['arguments'];
                if (arguments is List) {
                  for (final message in arguments) {
                    coreEventManager.sendEvent(
                      CoreEvent.fromJson(
                        Map<String, dynamic>.from(message as Map),
                      ),
                    );
                  }
                }
                return;
              }
              handleResult(
                actionResultFromWireJson(
                  Map<String, dynamic>.from(dataJson as Map),
                ),
              );
            } catch (e) {
              commonPrint.log(
                'Failed to parse transport data: $e',
                logLevel: LogLevel.error,
              );
            }
          },
          onError: (error) {
            commonPrint.log(
              'Transport data stream error: $error',
              logLevel: LogLevel.error,
            );
          },
        );
  }

  void _handleInvokeCrashEvent() {
    coreEventManager.sendEvent(
      const CoreEvent(type: CoreEventType.crash, data: 'core done'),
    );
  }

  Future<void> start() async {
    if (_process != null) {
      await shutdown(false);
    }
    // Wait for the transport server to be ready before getting the address
    await _initCompleter.future;
    // Use the actual bound address (for Windows TCP, this includes the port)
    final coreAddress = _transport.bindAddress;
    if (system.isWindows && await system.checkIsAdmin()) {
      final isSuccess = await request.startCoreByHelper(coreAddress);
      if (isSuccess) {
        await _transport.connectionCompleter.future;
        return;
      }
    }
    try {
      _process = await Process.start(appPath.corePath, [coreAddress]);
    } catch (e) {
      commonPrint.log(
        'Failed to start core process: $e',
        logLevel: LogLevel.error,
      );
      _handleInvokeCrashEvent();
      return;
    }
    _process?.stdout.listen((_) {});
    _process?.stderr.listen((e) {
      final error = utf8.decode(e);
      if (error.isNotEmpty) {
        commonPrint.log(error, logLevel: LogLevel.warning);
      }
    });
    await _transport.connectionCompleter.future;
  }

  @override
  FutureOr<bool> destroy() async {
    await shutdown(false);
    await _transport.close();
    return true;
  }

  Future<void> sendMessage(String message) async {
    await _transport.connectionCompleter.future;
    _transport.send(message);
  }

  @override
  Future<bool> shutdown(bool isUser) async {
    _shutdownCompleter = Completer();
    if (system.isWindows) {
      await request.stopCoreByHelper();
    }
    _transport.disconnected();
    _process?.kill();
    _process = null;
    _clearCompleter();
    if (isUser) {
      return _shutdownCompleter.future;
    } else {
      return true;
    }
  }

  void _clearCompleter() {
    for (final completer in _callbackCompleterMap.values) {
      completer.safeCompleter(null);
    }
  }

  @override
  Future<String> preload() async {
    await start();
    return '';
  }

  @override
  Future<T?> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  }) async {
    final id = '${method.name}#${utils.id}';
    _callbackCompleterMap[id] = Completer<T?>();
    sendMessage(json.encode(coreMethodCallToJson(id, method, data)));
    return (_callbackCompleterMap[id] as Completer<T?>).future.withTimeout(
      timeout: timeout,
      onLast: () {
        final completer = _callbackCompleterMap[id];
        completer?.safeCompleter(null);
        _callbackCompleterMap.remove(id);
      },
      tag: id,
      onTimeout: () => null,
    );
  }

  @override
  Completer get completer => _transport.connectionCompleter;
}

final coreService = system.isDesktop ? CoreService() : null;

