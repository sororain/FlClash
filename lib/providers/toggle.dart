import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 导航栏 商店/工具 共用同一槽位，true=商店，false=工具
class ToggleNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setShowShop(bool value) => state = value;
}

final toggleProvider =
    NotifierProvider<ToggleNotifier, bool>(ToggleNotifier.new);
