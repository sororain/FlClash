part of '../state.dart';

@riverpod
UpdateParams updateParams(Ref ref) {
  final routeMode = ref.watch(
    networkSettingProvider.select((state) => state.routeMode),
  );
  return ref.watch(
    patchClashConfigProvider.select(
      (state) => UpdateParams(
        tun: state.tun.getRealTun(routeMode),
        allowLan: state.allowLan,
        findProcessMode: state.findProcessMode,
        mode: state.mode,
        logLevel: state.logLevel,
        ipv6: state.ipv6,
        tcpConcurrent: state.tcpConcurrent,
        externalController: state.externalController,
        unifiedDelay: state.unifiedDelay,
        mixedPort: state.mixedPort,
      ),
    ),
  );
}

@riverpod
TrayState trayState(Ref ref) {
  final isStart = ref.watch(runTimeProvider.select((state) => state != null));
  final systemProxy = ref.watch(
    networkSettingProvider.select((state) => state.systemProxy),
  );
  final clashConfigVm3 = ref.watch(
    patchClashConfigProvider.select(
      (state) => VM3(state.mode, state.mixedPort, state.tun.enable),
    ),
  );
  final appSettingVm3 = ref.watch(
    appSettingProvider.select(
      (state) => VM3(state.autoLaunch, state.locale, state.showTrayTitle),
    ),
  );
  final groups = ref.watch(currentGroupsStateProvider).value;
  final brightness = ref.watch(systemBrightnessProvider);
  final selectedMap = ref.watch(selectedMapProvider);

  return TrayState(
    mode: clashConfigVm3.a,
    port: clashConfigVm3.b,
    autoLaunch: appSettingVm3.a,
    systemProxy: systemProxy,
    tunEnable: clashConfigVm3.c,
    isStart: isStart,
    locale: appSettingVm3.b,
    brightness: brightness,
    groups: groups,
    selectedMap: selectedMap,
    showTrayTitle: appSettingVm3.c,
  );
}

@riverpod
TrayTitleState trayTitleState(Ref ref) {
  final showTrayTitle = ref.watch(
    appSettingProvider.select((state) => state.showTrayTitle),
  );
  final traffic = ref.watch(
    trafficsProvider.select((state) => state.list.safeLast(const Traffic())),
  );
  return TrayTitleState(showTrayTitle: showTrayTitle, traffic: traffic);
}

@riverpod
VpnState vpnState(Ref ref) {
  final vpnProps = ref.watch(vpnSettingProvider);
  final stack = ref.watch(
    patchClashConfigProvider.select((state) => state.tun.stack),
  );
  return VpnState(stack: stack, vpnProps: vpnProps);
}

@riverpod
PackageListSelectorState packageListSelectorState(Ref ref) {
  final packages = ref.watch(packagesProvider);
  final accessControlProps = ref.watch(
    vpnSettingProvider.select((state) => state.accessControlProps),
  );
  return PackageListSelectorState(
    packages: packages,
    accessControlProps: accessControlProps,
  );
}

@riverpod
HotKeyAction getHotKeyAction(Ref ref, HotAction hotAction) {
  return ref.watch(
    hotKeyActionsProvider.select((state) {
      final index = state.indexWhere((item) => item.action == hotAction);
      return index != -1 ? state[index] : HotKeyAction(action: hotAction);
    }),
  );
}

@riverpod
VM3<bool, int, bool> checkIp(Ref ref) {
  final isInit = ref.watch(initProvider);
  final checkIpNum = ref.watch(checkIpNumProvider);
  final containsDetection = ref.watch(
    dashboardStateProvider.select(
      (state) =>
          state.dashboardWidgets.contains(DashboardWidget.networkDetection),
    ),
  );
  return VM3(isInit, checkIpNum, containsDetection);
}

@riverpod
VM2<bool, bool> autoSetSystemDnsState(Ref ref) {
  final isStart = ref.watch(runTimeProvider.select((state) => state != null));
  final realTunEnable = ref.watch(realTunEnableProvider);
  final autoSetSystemDns = ref.watch(
    networkSettingProvider.select((state) => state.autoSetSystemDns),
  );
  return VM2(isStart ? realTunEnable : false, autoSetSystemDns);
}

@riverpod
SharedState sharedState(Ref ref) {
  ref.watch((appSettingProvider).select((state) => state.locale));
  final currentProfileVM2 = ref.watch(
    currentProfileProvider.select(
      (state) => VM2(state?.label ?? '', state?.selectedMap ?? {}),
    ),
  );
  final appSettingVM3 = ref.watch(
    appSettingProvider.select(
      (state) =>
          VM2(state.onlyStatisticsProxy, state.testUrl),
    ),
  );
  final bypassDomain = ref.watch(
    networkSettingProvider.select((state) => state.bypassDomain),
  );
  final clashConfigVM2 = ref.watch(
    patchClashConfigProvider.select(
      (state) => VM2(state.tun.stack.name, state.mixedPort),
    ),
  );
  final vpnSetting = ref.watch(vpnSettingProvider);
  final currentProfileName = currentProfileVM2.a;
  final selectedMap = currentProfileVM2.b;
  final onlyStatisticsProxy = appSettingVM3.a;
  final testUrl = appSettingVM3.b;
  final stack = clashConfigVM2.a;
  final port = clashConfigVM2.b;
  return SharedState(
    currentProfileName: currentProfileName,
    onlyStatisticsProxy: onlyStatisticsProxy,
    stopText: currentAppLocalizations.stop,
    stopTip: currentAppLocalizations.stopVpn,
    startTip: currentAppLocalizations.startVpn,
    setupParams: SetupParams(selectedMap: selectedMap, testUrl: testUrl),
    vpnOptions: VpnOptions(
      enable: vpnSetting.enable,
      stack: stack,
      systemProxy: vpnSetting.systemProxy,
      port: port,
      ipv6: vpnSetting.ipv6,
      dnsHijacking: vpnSetting.dnsHijacking,
      accessControlProps: vpnSetting.accessControlProps,
      allowBypass: vpnSetting.allowBypass,
      bypassDomain: bypassDomain,
    ),
  );
}

@riverpod
class AccessControlState extends _$AccessControlState
    with AutoDisposeNotifierMixin {
  @override
  AccessControlProps build() => const AccessControlProps();
}

@riverpod
bool suspend(Ref ref) {
  final currentSSID = ref.watch(currentSSIDProvider);
  final excludeSSIDs = ref.watch(excludeSSIDsProvider);
  return excludeSSIDs.contains(currentSSID);
}
