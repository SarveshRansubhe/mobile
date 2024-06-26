import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';

class PuzzleSettingsScreen extends StatelessWidget {
  const PuzzleSettingsScreen({super.key, required this.userId});

  final UserId? userId;

  @override
  Widget build(BuildContext context) {
    return PlatformWidget(
      androidBuilder: _buildAndroid,
      iosBuilder: _buildIos,
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsSettings)),
      body: _Body(userId: userId),
    );
  }

  Widget _buildIos(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(context.l10n.settingsSettings),
      ),
      child: _Body(userId: userId),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.userId});

  final UserId? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoNext = ref.watch(
      PuzzlePreferencesProvider(userId).select((value) => value.autoNext),
    );
    final boardPrefs = ref.watch(boardPreferencesProvider);

    return SafeArea(
      child: ListView(
        children: [
          ListSection(
            hasLeading: true,
            showDivider: true,
            children: [
              SwitchSettingTile(
                title: Text(context.l10n.puzzleJumpToNextPuzzleImmediately),
                value: autoNext,
                onChanged: (value) {
                  ref
                      .read(puzzlePreferencesProvider(userId).notifier)
                      .setAutoNext(value);
                },
              ),
              SwitchSettingTile(
                title: Text(
                  context.l10n.preferencesPieceAnimation,
                ),
                value: boardPrefs.pieceAnimation,
                onChanged: (value) {
                  ref
                      .read(boardPreferencesProvider.notifier)
                      .togglePieceAnimation();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
