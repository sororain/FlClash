import 'package:sororain/common/app_localizations.dart';
import 'package:sororain/core/controller.dart';
import 'package:sororain/plugins/app.dart';
import 'package:sororain/plugins/tile.dart';
import 'package:sororain/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TileManager extends ConsumerStatefulWidget {
  final Widget child;

  const TileManager({super.key, required this.child});

  @override
  ConsumerState<TileManager> createState() => _TileContainerState();
}

class _TileContainerState extends ConsumerState<TileManager> with TileListener {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  bool get isStart => ref.read(isStartProvider);

  @override
  Future<void> onStart() async {
    if (isStart && coreController.isCompleted) {
      return;
    }
    ref.read(setupActionProvider.notifier).updateStatus(true);
    app?.tip(currentAppLocalizations.startVpn);
    super.onStart();
  }

  @override
  Future<void> onStop() async {
    if (!isStart) {
      return;
    }
    ref.read(setupActionProvider.notifier).updateStatus(false);
    app?.tip(currentAppLocalizations.stopVpn);
    super.onStop();
  }

  @override
  void initState() {
    super.initState();
    tile?.addListener(this);
  }

  @override
  void dispose() {
    tile?.removeListener(this);
    super.dispose();
  }
}

