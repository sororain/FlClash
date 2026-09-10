part of '../action.dart';

@Riverpod(keepAlive: true)
class ProfilesAction extends _$ProfilesAction {
  @override
  void build() {}

  void updateCurrentSelectedMap(String groupName, String proxyName) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile != null &&
        currentProfile.selectedMap[groupName] != proxyName) {
      final selectedMap = Map<String, String>.from(currentProfile.selectedMap)
        ..[groupName] = proxyName;
      ref
          .read(profilesProvider.notifier)
          .put(currentProfile.copyWith(selectedMap: selectedMap));
    }
  }

  Future<void> deleteProfile(int id) async {
    ref.read(profilesProvider.notifier).del(id);
    clearEffect(id);
    final currentProfileId = ref.read(currentProfileIdProvider);
    if (currentProfileId == id) {
      final profiles = ref.read(profilesProvider);
      if (profiles.isNotEmpty) {
        final updateId = profiles.first.id;
        ref.read(currentProfileIdProvider.notifier).value = updateId;
      } else {
        ref.read(currentProfileIdProvider.notifier).value = null;
        ref.read(setupActionProvider.notifier).updateStatus(false);
      }
    }
  }

  Future<void> autoUpdateProfiles() async {
    for (final profile in ref.read(profilesProvider)) {
      if (!profile.autoUpdate) continue;
      final isNotNeedUpdate = profile.lastUpdateDate
          ?.add(profile.autoUpdateDuration)
          .isBeforeNow;
      if (isNotNeedUpdate == false || profile.type == ProfileType.file) {
        continue;
      }
      try {
        await updateProfile(profile);
      } catch (e) {
        commonPrint.log(e.toString(), logLevel: LogLevel.warning);
      }
    }
  }

  void putProfile(Profile profile) {
    ref.read(profilesProvider.notifier).put(profile);
    if (ref.read(currentProfileIdProvider) != null) return;
    ref.read(currentProfileIdProvider.notifier).value = profile.id;
  }

  Future<void> updateProfiles() async {
    for (final profile in ref.read(profilesProvider)) {
      if (profile.type == ProfileType.file) continue;
      await updateProfile(profile);
    }
  }

  Future<void> updateProfile(
    Profile profile, {
    bool showLoading = false,
  }) async {
    try {
      if (showLoading) {
        ref.read(isUpdatingProvider(profile.updatingKey).notifier).value = true;
      }
      ref.read(profilesProvider.notifier).put(profile);
      final newProfile = await profile.update();
      ref.read(profilesProvider.notifier).put(newProfile);
      if (profile.id == ref.read(currentProfileIdProvider)) {
        ref
            .read(setupActionProvider.notifier)
            .applyProfileDebounce(silence: true);
      }
    } finally {
      ref.read(isUpdatingProvider(profile.updatingKey).notifier).value = false;
    }
  }

  Future<void> addProfileFormFile() async {
    final platformFile = await globalState.safeRun(picker.pickerFile);
    final bytes = platformFile?.bytes;
    if (bytes == null) return;
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    ref.read(currentPageLabelProvider.notifier).toProfiles();
    final profile = await globalState.loadingRun(
      tag: LoadingTag.profiles,
      () async {
        return Profile.normal(label: platformFile?.name).saveFile(bytes);
      },
      title: currentAppLocalizations.addProfile,
    );
    if (profile != null) {
      putProfile(profile);
    }
  }

  Future<void> addProfileFormURL(String url) async {
    if (globalState.navigatorKey.currentState?.canPop() ?? false) {
      globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    ref.read(currentPageLabelProvider.notifier).value = PageLabel.profiles;
    final profile = await globalState.loadingRun(
      tag: LoadingTag.profiles,
      () async {
        return Profile.normal(url: url).update();
      },
      title: currentAppLocalizations.addProfile,
    );
    if (profile != null) {
      putProfile(profile);
    }
  }

  void setProfileAndAutoApply(Profile profile) {
    ref.read(profilesProvider.notifier).put(profile);
    if (profile.id == ref.read(currentProfileIdProvider)) {
      ref.read(setupActionProvider.notifier).applyProfileDebounce();
    }
  }

  Future<void> addProfileFormQrCode() async {
    final url = await globalState.safeRun(picker.pickerConfigQRCode);
    if (url == null) return;
    addProfileFormURL(url);
  }

  void reorder(List<Profile> profiles) {
    ref.read(profilesProvider.notifier).reorder(profiles);
  }

  /// 立即拉取订阅（购买套餐/登录后调用）
  Future<void> syncSubscriptionNow() async {
    try {
      final url = fetchSubscribeUrl();
      if (url == null) return;
      final profile = ref.read(currentProfileProvider);
      if (profile != null) {
        await updateProfile(profile.copyWith(url: url));
      } else {
        final newProfile = await Profile.normal(url: url).update();
        putProfile(newProfile);
        ref.read(setupActionProvider.notifier).applyProfile(force: true);
      }
      globalState.lastSyncTime = DateTime.now();
    } catch (e) {
      commonPrint.log(
        'syncSubscriptionNow error: $e',
        logLevel: LogLevel.warning,
      );
      // 尝试刷新 Token 后重试一次
      try {
        await refreshTokenFromUserInfo();
        final retryUrl = fetchSubscribeUrl();
        if (retryUrl == null) {
          globalState.showNotifier('订阅同步失败: $e');
          return;
        }
        final profile = ref.read(currentProfileProvider);
        if (profile != null) {
          await updateProfile(profile.copyWith(url: retryUrl));
        } else {
          final newProfile = await Profile.normal(url: retryUrl).update();
          putProfile(newProfile);
          ref.read(setupActionProvider.notifier).applyProfile(force: true);
        }
        globalState.lastSyncTime = DateTime.now();
      } catch (retryError) {
        globalState.showNotifier('订阅同步失败: $e');
      }
    }
  }

  /// 同步订阅并重试：最多 [maxAttempts] 次、间隔 5 秒，任一次成功（profile 就绪）即止。
  /// 单次内部失败已由 syncSubscriptionNow 的「刷新 Token 后重试」覆盖，
  /// 这里兜的是外层网络抖动与首次路径未就绪的场景。
  /// 供支付成功、登录、启动等关键节点统一使用
  Future<void> syncSubscriptionWithRetry(
      {int maxAttempts = kSyncSubscribeMaxAttempts}) async {
    for (int i = 0; i < maxAttempts; i++) {
      try {
        // 每次尝试前刷新 Token 与订阅路径：路径未就绪时（url 为 null 的静默
        // 返回不抛异常），重试是唯一能触发 /user/getSubscribe 重新解析的时机
        await refreshTokenFromUserInfo();
        await syncSubscriptionNow();
        if (ref.read(currentProfileProvider) != null) return;
      } catch (e) {
        commonPrint.log(
          'sync subscription attempt ${i + 1}/$maxAttempts failed: $e',
          logLevel: LogLevel.warning,
        );
      }
      if (i < maxAttempts - 1) {
        await Future.delayed(kSyncSubscribeRetryDelay);
      }
    }
  }

  Future<void> clearEffect(int profileId) async {
    final profilePath = await appPath.getProfilePath(profileId.toString());
    final profileFile = File(profilePath);
    final isExists = await profileFile.exists();
    if (isExists) {
      await profileFile.safeDelete(recursive: true);
    }
    await coreController.clearEffect(profileId);
  }
}
