import 'dart:async';
import 'dart:convert';

import 'package:sororain/common/common.dart';
import 'package:sororain/core/core.dart';
import 'package:sororain/enum/enum.dart';
import 'package:sororain/models/core.dart';

import 'desktop/helper_client.dart';
import 'desktop/launcher.dart';
import 'desktop/manager.dart';
import 'desktop/model.dart';
import 'interface.dart';
import 'transport.dart';

class CoreService extends CoreHandlerInterface {
  static CoreService? _instance;

  late final IPCCoreTransport _transport;
  final Completer<void> _initCompleter = Completer<void>();

  Completer<bool> _shutdownCompleter = Completer();

  final Map<String, Completer> _callbackCompleterMap = {};

  /// Core 进程的拉起与收尾全部交给 [DesktopCoreManager]：它内部按平台/权限
  /// 选 helper（提权 + TUN）或直连启动，并把失败归类成可上报的状态。
  late final DesktopCoreManager _manager;

  factory CoreService() {
    _instance ??= CoreService._internal();
    return _instance!;
  }

  CoreService._internal() {
    _transport = IPCCoreTransport(
      address: system.isWindows ? windowsPipeName : unixSocketPath,
    );
    _manager = DesktopCoreManager(
      launcherResolver: HelperLauncherResolver(
        hasHelper: system.hasHelperService,
        directLauncher: DirectCoreLauncher(),
        helperLauncher: HelperLauncher(helperClient),
        helperReady: () => helperClient.readiness(),
      ),
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
    if (_manager.state is DesktopCoreRunning) {
      await shutdown(false);
    }
    // Wait for the transport server to be ready before getting the address
    await _initCompleter.future;
    // Use the actual bound address (for Windows TCP, this includes the port)
    final coreAddress = _transport.bindAddress;
    final result = await _manager.start(address: coreAddress);
    if (result.session == null) {
      commonPrint.log(
        'Failed to start core process: ${result.outcome.name}',
        logLevel: LogLevel.error,
      );
      _handleInvokeCrashEvent();
      return;
    }
    await _transport.connectionCompleter.future;
  }

  @override
  FutureOr<bool> destroy() async {
    await shutdown(false);
    await _manager.dispose();
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
    // helper 路径由 helper 收掉它拉起的 Core，直连路径由 lease 收掉自己拉起的进程。
    await _manager.stop();
    _transport.disconnected();
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

