part of '../state.dart';

@riverpod
CustomOverwriteDate customOverwriteDate(Ref ref, int profileId) {
  final vm3 = ref.watch(
    clashConfigProvider(profileId).select((state) {
      return VM3(
        state.value?.proxies ?? [],
        state.value?.subRules ?? [],
        state.value?.proxyProviders ?? [],
      );
    }),
  );
  final proxies = vm3.a;
  final subRules = vm3.b.toSet();
  final proxyProviders = vm3.c.toSet();
  final proxyGroups =
      ref
          .watch(
            proxyGroupsProvider(profileId).select((state) {
              return VM(state.value);
            }),
          )
          .a ??
      [];
  final ruleTargets = {
    ...RuleTarget.baseTargets,
    ...proxies.map((item) => item.name),
    ...proxyGroups.map((item) => item.name),
  };
  return CustomOverwriteDate(
    proxyProviders: proxyProviders,
    proxies: proxies,
    proxyGroups: proxyGroups,
    ruleTargets: ruleTargets,
    subRules: subRules,
  );
}

@riverpod
bool customOverwriteTargetIsValid(Ref ref, int profileId, String? target) {
  final valid = ref.watch(
    customOverwriteDateProvider(
      profileId,
    ).select((state) => state.ruleTargets.contains(target)),
  );
  return valid;
}

@riverpod
bool customOverwriteProxyProviderIsValid(
  Ref ref,
  int profileId,
  String? providerName,
) {
  final valid = ref.watch(
    customOverwriteDateProvider(
      profileId,
    ).select((state) => state.proxyProviders.contains(providerName)),
  );
  return valid;
}

@riverpod
bool customOverwriteUseIsValid(Ref ref, int profileId, List<String> use) {
  final valid = ref.watch(
    customOverwriteDateProvider(
      profileId,
    ).select((state) => state.proxyProviders.containsAll(use)),
  );
  return valid;
}

@riverpod
bool customOverwriteProxiesIsValid(
  Ref ref,
  int profileId,
  List<String> proxies,
) {
  final valid = ref.watch(
    customOverwriteDateProvider(
      profileId,
    ).select((state) => state.ruleTargets.containsAll(proxies)),
  );
  return valid;
}

@riverpod
bool customOverwriteGroupIsValid(
  Ref ref,
  int profileId,
  ProxyGroup proxyGroup,
) {
  final proxies = proxyGroup.proxies ?? [];
  final use = proxyGroup.use ?? [];
  final valid = ref.watch(
    customOverwriteDateProvider(profileId).select(
      (state) =>
          state.ruleTargets.containsAll(proxies) &&
          state.proxyProviders.containsAll(use),
    ),
  );
  return valid;
}

@Riverpod(name: 'proxyGroupProvider')
class ProxyGroupProvider extends _$ProxyGroupProvider
    with AutoDisposeNotifierMixin {
  @override
  ProxyGroup build() {
    throw 'Initialization proxyGroupProvider error';
  }
}

@Riverpod(name: 'ruleProvider')
class RuleProvider extends _$RuleProvider with AutoDisposeNotifierMixin {
  @override
  Rule build() {
    return throw 'Initialization RuleProvider error';
  }
}
