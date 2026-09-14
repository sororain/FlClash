part of '../action.dart';

@Riverpod(keepAlive: true)
class ProxiesAction extends _$ProxiesAction {
  @override
  void build() {
    ref.listen(coreStatusProvider, (_, next) {
      if (next != CoreStatus.connected) {
        cancelDelayTests();
      }
    });
  }

  final TaskPool _delayTestPool = TaskPool(maxConcurrentDelayTests);

  final List<_DelayTestJob> _delayTestJobs = [];

  void cancelDelayTests() {
    for (final job in _delayTestJobs) {
      job.cancelled = true;
      job.held.clear();
    }
    ref.read(pendingDelayTestsProvider.notifier).clear();
  }

  Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) {
    return _runDelayTests([proxy], testUrl);
  }

  Future<void> delayTest(List<Proxy> proxies, [String? testUrl]) async {
    await _runDelayTests(proxies, testUrl);
    ref.read(sortNumProvider.notifier).add();
  }

  void updateGroupsDebounce([Duration? duration]) {
    debouncer.call(FunctionTag.updateGroups, updateGroups, duration: duration);
  }

  void changeProxyDebounce(String groupName, String proxyName) {
    debouncer.call(FunctionTag.changeProxy, (
      String groupName,
      String proxyName,
    ) async {
      await changeProxy(groupName: groupName, proxyName: proxyName);
      updateGroupsDebounce();
    }, args: [groupName, proxyName]);
  }

  Future<void> updateGroups() async {
    try {
      commonPrint.log('updateGroups');
      ref.read(groupsProvider.notifier).value = await retry(
        task: () async {
          final sortType = ref.read(
            proxiesStyleSettingProvider.select((state) => state.sortType),
          );
          final delayMap = ref.read(delayDataSourceProvider);
          final testUrl = ref.read(
            appSettingProvider.select((state) => state.testUrl),
          );
          final selectedMap = ref.read(
            currentProfileProvider.select((state) => state?.selectedMap ?? {}),
          );
          return coreController.getProxiesGroups(
            selectedMap: selectedMap,
            sortType: sortType,
            delayMap: delayMap,
            defaultTestUrl: testUrl,
          );
        },
        retryIf: (res) => res.isEmpty,
      );
    } catch (e) {
      commonPrint.log('updateGroups error: $e');
      ref.read(groupsProvider.notifier).value = [];
    }
  }

  void updateCurrentGroupName(String groupName) {
    final profile = ref.read(currentProfileProvider);
    if (profile == null || profile.currentGroupName == groupName) return;
    ref
        .read(profilesProvider.notifier)
        .put(profile.copyWith(currentGroupName: groupName));
  }

  void updateCurrentUnfoldSet(Set<String> value) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null) return;
    ref
        .read(profilesProvider.notifier)
        .put(currentProfile.copyWith(unfoldSet: value));
  }

  void setDelay(Delay delay) {
    ref.read(delayDataSourceProvider.notifier).setDelay(delay);
  }

  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    await coreController.changeProxy(
      ChangeProxyParams(groupName: groupName, proxyName: proxyName),
    );
    if (ref.read(appSettingProvider).closeConnections) {
      coreController.closeConnections();
    } else {
      coreController.resetConnections();
    }
    ref.read(checkIpNumProvider.notifier).add();
  }

  Future<String> updateProvider(
    ExternalProvider provider, {
    bool showLoading = false,
  }) async {
    try {
      if (showLoading) {
        ref.read(isUpdatingProvider(provider.updatingKey).notifier).value =
            true;
      }
      final message = await coreController.updateExternalProvider(
        providerName: provider.name,
      );
      if (message.isNotEmpty) return message;
      ref
          .read(providersProvider.notifier)
          .setProvider(await coreController.getExternalProvider(provider.name));
      return '';
    } finally {
      ref.read(isUpdatingProvider(provider.updatingKey).notifier).value = false;
    }
  }

  List<_DelayTestTarget> _resolveDelayTestTargets(
    List<Proxy> proxies,
    String? testUrl,
  ) {
    final groups = ref.read(groupsProvider);
    final selectedMap = ref.read(
      currentProfileProvider.select((state) => state?.selectedMap ?? {}),
    );
    final fallbackTestUrl = ref.read(realTestUrlProvider(testUrl));
    final seen = <String>{};
    final targets = <_DelayTestTarget>[];
    for (final proxy in proxies) {
      final state = computeRealSelectedProxyState(
        proxy.name,
        groups: groups,
        selectedMap: selectedMap,
      );
      if (state.proxyName.isEmpty) {
        continue;
      }
      final currentTestUrl = state.testUrl.takeFirstValid([fallbackTestUrl]);
      final key = delayTestKey(currentTestUrl, state.proxyName);
      if (!seen.add(key)) {
        continue;
      }
      targets.add(
        _DelayTestTarget(
          proxyName: state.proxyName,
          testUrl: currentTestUrl,
          key: key,
        ),
      );
    }
    return targets;
  }

  Future<void> _runDelayTests(List<Proxy> proxies, String? testUrl) async {
    final targets = _resolveDelayTestTargets(proxies, testUrl);
    if (targets.isEmpty) {
      return;
    }
    final pending = ref.read(pendingDelayTestsProvider.notifier);
    final job = _DelayTestJob(targets.map((target) => target.key));
    _delayTestJobs.add(job);
    pending.acquire(job.held);
    try {
      await Future.wait(
        targets.map(
          (target) => _delayTestPool.run(() => _runDelayTest(job, target)),
        ),
      );
    } finally {
      _delayTestJobs.remove(job);
      final abandoned = job.held.toList();
      job.held.clear();
      pending.release(abandoned);
    }
  }

  Future<void> _runDelayTest(_DelayTestJob job, _DelayTestTarget target) async {
    if (job.cancelled) {
      return;
    }
    try {
      final delay = await coreController.getDelay(
        target.testUrl,
        target.proxyName,
      );
      if (!job.cancelled) {
        setDelay(delay);
      }
    } catch (error) {
      if (error is CoreMethodException && error.isCoreUnavailable) {
        job.cancelled = true;
      }
      commonPrint.log(
        'Delay test failed for ${target.proxyName}: $error',
        logLevel: coreFailureLogLevel(error),
      );
    } finally {
      if (job.held.remove(target.key)) {
        ref.read(pendingDelayTestsProvider.notifier).release([target.key]);
      }
    }
  }
}

class _DelayTestTarget {
  const _DelayTestTarget({
    required this.proxyName,
    required this.testUrl,
    required this.key,
  });

  final String proxyName;
  final String testUrl;
  final String key;
}

class _DelayTestJob {
  _DelayTestJob(Iterable<String> keys) : held = keys.toSet();

  final Set<String> held;
  bool cancelled = false;
}
