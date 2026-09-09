import 'dart:async';

import 'package:sororain/common/common.dart';
import 'package:sororain/enum/enum.dart';
import 'package:sororain/models/core.dart';
import 'package:sororain/plugins/service.dart';
import 'package:sororain/providers/providers.dart';
import 'package:sororain/state.dart';

import 'interface.dart';

class CoreLib extends CoreHandlerInterface {
  static CoreLib? _instance;

  Completer<bool> _connectedCompleter = Completer();

  CoreLib._internal();

  @override
  Future<String> preload() async {
    if (_connectedCompleter.isCompleted) {
      return 'core is connected';
    }
    final res = await service?.init();
    if (res?.isEmpty != true) {
      return res ?? '';
    }
    _connectedCompleter.complete(true);
    final syncRes = await service?.syncState(globalState.container.read(sharedStateProvider));
    return syncRes ?? '';
  }

  factory CoreLib() {
    _instance ??= CoreLib._internal();
    return _instance!;
  }

  @override
  destroy() async {
    return true;
  }

  @override
  Future<bool> startListener() async {
    await super.startListener();
    await service?.start();
    return true;
  }

  @override
  Future<bool> stopListener() async {
    await super.stopListener();
    await service?.stop();
    return true;
  }

  @override
  Future<bool> shutdown(_) async {
    if (!_connectedCompleter.isCompleted) {
      return false;
    }
    _connectedCompleter = Completer();
    return service?.shutdown() ?? true;
  }

  @override
  Future<T?> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  }) async {
    final id = '${method.name}#${utils.id}';
    final result = await service
        ?.invokeAction(Action(id: id, method: method, data: data))
        .withTimeout(onTimeout: () => null);
    if (result == null) {
      return null;
    }
    return parasResult<T>(result);
  }

  @override
  Completer get completer => _connectedCompleter;
}

CoreLib? get coreLib => system.isAndroid ? CoreLib() : null;

