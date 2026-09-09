import 'package:sororain/common/context.dart';
import 'package:sororain/views/config/general.dart';
import 'package:sororain/widgets/widgets.dart';
import 'package:flutter/material.dart';

class ConfigView extends StatelessWidget {
  const ConfigView({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: context.appLocalizations.basicConfig,
      body: generateListView(generalItems),
    );
  }
}


