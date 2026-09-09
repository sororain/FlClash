import 'package:sororain/common/common.dart';
import 'package:sororain/core/controller.dart';
import 'package:sororain/enum/enum.dart';
import 'package:sororain/models/common.dart';
import 'package:sororain/providers/action.dart';
import 'package:sororain/providers/app.dart';
import 'package:sororain/providers/config.dart';
import 'package:sororain/state.dart';
import 'package:sororain/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeveloperView extends ConsumerWidget {
  const DeveloperView({super.key});

  Widget _getDeveloperList(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    return generateSectionV2(
      title: appLocalizations.options,
      items: [
        ListItem(
          title: Text(appLocalizations.messageTest),
          minVerticalPadding: 12,
          onTap: () {
            context.showNotifier(appLocalizations.messageTestTip);
          },
        ),
        ListItem(
          title: Text(appLocalizations.logsTest),
          minVerticalPadding: 12,
          onTap: () {
            for (int i = 0; i < 1000; i++) {
              globalState.container
                  .read(logsProvider.notifier)
                  .add(
                    Log.app(
                      '[$i]${utils.generateRandomString(maxLength: 200, minLength: 20)}',
                    ),
                  );
            }
          },
        ),
        if (globalState.isPre)
          ListItem(
            title: Text(appLocalizations.crashTest),
            minVerticalPadding: 12,
            onTap: () async {
              final res = await globalState.showMessage(
                message: TextSpan(text: appLocalizations.confirmForceCrashCore),
              );
              if (res != true) {
                return;
              }
              coreController.crash();
            },
          ),
        ListItem(
          title: Text(appLocalizations.clearData),
          minVerticalPadding: 12,
          onTap: () async {
            final res = await globalState.showMessage(
              message: TextSpan(text: appLocalizations.confirmClearAllData),
            );
            if (res != true) {
              return;
            }
            await globalState.container
                .read(storeActionProvider.notifier)
                .handleClear();
          },
        ),
        // ListItem(
        //   title: Text(appLocalizations.loadTest),
        //   minVerticalPadding: 12,
        //   onTap: () {
        //     ref.read(loadingProvider.notifier).value = !ref.read(
        //       loadingProvider,
        //     );
        //   },
        // ),
        ListItem(
          title: Text(appLocalizations.pruneCache),
          minVerticalPadding: 12,
          onTap: () async {
            await globalState.container
                .read(storeActionProvider.notifier)
                .shakingStore();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final enable = ref.watch(
      appSettingProvider.select((state) => state.developerMode),
    );
    return BaseScaffold(
      title: appLocalizations.developerMode,
      body: SingleChildScrollView(
        padding: baseInfoEdgeInsets,
        child: Column(
          children: [
            CommonCard(
              type: CommonCardType.filled,
              radius: 18,
              child: ListItem.switchItem(
                padding: const EdgeInsets.only(left: 16, right: 16),
                title: Text(currentAppLocalizations.developerMode),
                delegate: SwitchDelegate(
                  value: enable,
                  onChanged: (value) {
                    ref
                        .read(appSettingProvider.notifier)
                        .update(
                          (state) => state.copyWith(developerMode: value),
                        );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            _getDeveloperList(context, ref),
          ],
        ),
      ),
    );
  }
}


