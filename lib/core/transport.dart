import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';

/// Binary frame protocol: 4-byte LE length prefix + JSON payload
/// Mirrors the protocol in core/server.go
class IPCCoreTransport {
  final String address;
  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>();
  ServerSocket? _server;
  Socket? _socket;
  Completer<void> _completer = Completer<void>();

  void Function()? onDisconnect;

  IPCCoreTransport({required this.address});

  /// The actual address the server is bound to.
  /// For Unix sockets: the socket file path.
  /// For Windows TCP: "127.0.0.1:port".
  String get bindAddress {
    if (_server == null) return address;
    if (!system.isWindows) return address;
    return '127.0.0.1:${_server!.port}';
  }

  Completer<void> get connectionCompleter => _completer;

  Stream<Uint8List> get dataStream => _dataController.stream;

  Future<void> init() async {
    try {
      if (!system.isWindows) {
        await _deleteSocketFile();
      }
      final addr = !system.isWindows
          ? InternetAddress(address, type: InternetAddressType.unix)
          : InternetAddress(localhost, type: InternetAddressType.IPv4);
      _server = await ServerSocket.bind(addr, 0, shared: true);
      _server!.listen((socket) {
        if (_socket != null) {
          _socket?.close();
        }
        _socket = socket;
        _completer.complete();
        socket.listen(
          (data) => _handleRawData(data),
          onDone: () {
            _completer = Completer<void>();
            onDisconnect?.call();
          },
          onError: (error) {
            commonPrint.log(
              'Transport error: $error',
              logLevel: LogLevel.error,
            );
          },
          cancelOnError: false,
        );
      });
    } catch (e) {
      commonPrint.log(
        'Failed to start IPC server: $e',
        logLevel: LogLevel.error,
      );
      rethrow;
    }
  }

  // Buffer for incomplete frames
  final List<int> _buffer = [];
  int _expectedLength = -1;

  void _handleRawData(List<int> data) {
    _buffer.addAll(data);

    while (true) {
      if (_expectedLength < 0) {
        if (_buffer.length < 4) break;
        _expectedLength = ByteData.view(
          Uint8List.fromList(_buffer.sublist(0, 4)).buffer,
        ).getUint32(0, Endian.little);
        _buffer.removeRange(0, 4);
      }

      if (_buffer.length < _expectedLength) break;

      final payload = Uint8List.fromList(
        _buffer.sublist(0, _expectedLength),
      );
      _buffer.removeRange(0, _expectedLength);
      _expectedLength = -1;

      if (!_completer.isCompleted) {
        _completer.complete();
      }
      _dataController.add(payload);
    }
  }

  void send(String message) {
    if (_socket == null) return;
    final bytes = utf8.encode(message);
    final frame = Uint8List(4 + bytes.length);
    ByteData.view(frame.buffer)
        .setUint32(0, bytes.length, Endian.little);
    frame.setRange(4, frame.length, bytes);
    _socket?.add(frame);
  }

  void disconnected() {
    _completer = Completer<void>();
  }

  Future<void> close() async {
    await _socket?.close();
    _socket = null;
    await _server?.close();
    _server = null;
    _completer = Completer<void>();
    await _dataController.close();
  }

  Future<void> _deleteSocketFile() async {
    final file = File(unixSocketPath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

