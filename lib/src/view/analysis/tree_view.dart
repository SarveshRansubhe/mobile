import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:lichess_mobile/src/model/common/node.dart';
import 'package:lichess_mobile/src/model/common/uci.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/analysis/opening_service.dart';
import 'package:lichess_mobile/src/utils/rate_limit.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';

const kFastReplayDebounceDelay = Duration(milliseconds: 100);
const kOpeningHeaderHeight = 32.0;
const kInlineMoveSpacing = 3.0;

class AnalysisTreeView extends ConsumerStatefulWidget {
  const AnalysisTreeView(
    this.options,
    this.displayMode,
  );

  final AnalysisOptions options;
  final Orientation displayMode;

  @override
  ConsumerState<AnalysisTreeView> createState() => _InlineTreeViewState();
}

class _InlineTreeViewState extends ConsumerState<AnalysisTreeView> {
  final currentMoveKey = GlobalKey();
  final _debounce = Debouncer(kFastReplayDebounceDelay);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (currentMoveKey.currentContext != null) {
        Scrollable.ensureVisible(
          currentMoveKey.currentContext!,
          alignment: 0.5,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      analysisControllerProvider(widget.options),
      (prev, state) {
        if (prev?.currentPath != state.currentPath) {
          _debounce(() {
            if (currentMoveKey.currentContext != null) {
              Scrollable.ensureVisible(
                currentMoveKey.currentContext!,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeIn,
                alignment: 0.5,
                alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              );
            }
          });
        }
      },
    );

    final ctrlProvider = analysisControllerProvider(widget.options);
    final root = ref.watch(ctrlProvider.select((value) => value.root));
    final currentPath =
        ref.watch(ctrlProvider.select((value) => value.currentPath));
    final rootComments = ref.watch(
      ctrlProvider.select((value) => value.pgnRootComments),
    );
    final shouldShowComments = ref.watch(
      ctrlProvider.select((value) => value.shouldShowComments),
    );

    final List<Widget> moveWidgets = _buildTreeWidget(
      ctrlProvider,
      nodes: root.children,
      shouldShowComments: shouldShowComments,
      inMainline: true,
      startSideline: false,
      initialPath: UciPath.empty,
      currentPath: currentPath,
    );

    // trick to make auto-scroll work when returning to the root position
    if (currentPath.isEmpty) {
      moveWidgets.insert(
        0,
        SizedBox.shrink(key: currentMoveKey),
      );
    }

    if (shouldShowComments && rootComments?.isNotEmpty == true) {
      moveWidgets.insert(
        0,
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: _Comments(rootComments!),
        ),
      );
    }

    final content = CustomScrollView(
      slivers: [
        if (kOpeningAllowedVariants.contains(widget.options.variant))
          SliverPersistentHeader(
            delegate: _OpeningHeaderDelegate(
              ctrlProvider,
              displayMode: widget.displayMode,
            ),
          ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            child: Wrap(
              spacing: kInlineMoveSpacing,
              children: moveWidgets,
            ),
          ),
        ),
      ],
    );

    return switch (widget.displayMode) {
      Orientation.landscape => content,
      Orientation.portrait => Expanded(child: content)
    };
  }

  List<Widget> _buildTreeWidget(
    AnalysisControllerProvider ctrlProvider, {
    required IList<ViewBranch> nodes,
    required bool inMainline,
    required bool startSideline,
    required bool shouldShowComments,
    required UciPath initialPath,
    required UciPath currentPath,
  }) {
    if (nodes.isEmpty) return [];
    final List<Widget> widgets = [];

    // add the first node
    final newPath = initialPath + nodes.first.id;
    final currentMove = newPath == currentPath;
    widgets.add(
      InlineMove(
        ctrlProvider,
        path: newPath,
        branch: nodes.first,
        isCurrentMove: currentMove,
        key: currentMove ? currentMoveKey : null,
        shouldShowComments: shouldShowComments,
        isSideline: !inMainline,
        startSideline: startSideline,
        endSideline: !inMainline && nodes.first.children.isEmpty,
      ),
    );

    // add the sidelines if present
    for (var i = 1; i < nodes.length; i++) {
      // start new sideline from mainline on a new line
      if (inMainline) {
        widgets.add(
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: kInlineMoveSpacing,
              children: _buildTreeWidget(
                ctrlProvider,
                nodes: IList([nodes[i]]),
                shouldShowComments: shouldShowComments,
                inMainline: false,
                startSideline: true,
                initialPath: initialPath,
                currentPath: currentPath,
              ),
            ),
          ),
        );
      } else {
        widgets.addAll(
          _buildTreeWidget(
            ctrlProvider,
            nodes: IList([nodes[i]]),
            shouldShowComments: shouldShowComments,
            inMainline: false,
            startSideline: true,
            initialPath: initialPath,
            currentPath: currentPath,
          ),
        );
      }
    }

    // add the children of the first child
    widgets.addAll(
      _buildTreeWidget(
        ctrlProvider,
        nodes: nodes.first.children,
        shouldShowComments: shouldShowComments,
        inMainline: inMainline,
        startSideline: false,
        initialPath: newPath,
        currentPath: currentPath,
      ),
    );

    return widgets;
  }
}

Color? _textColor(BuildContext context, double opacity) {
  return defaultTargetPlatform == TargetPlatform.android
      ? Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(opacity)
      : CupertinoTheme.of(context)
          .textTheme
          .textStyle
          .color
          ?.withOpacity(opacity);
}

class InlineMove extends ConsumerWidget {
  const InlineMove(
    this.ctrlProvider, {
    required this.path,
    required this.branch,
    required this.shouldShowComments,
    required this.isCurrentMove,
    required this.isSideline,
    super.key,
    this.startSideline = false,
    this.endSideline = false,
  });

  final AnalysisControllerProvider ctrlProvider;
  final UciPath path;
  final ViewBranch branch;
  final bool shouldShowComments;
  final bool isCurrentMove;
  final bool isSideline;
  final bool startSideline;
  final bool endSideline;

  static const borderRadius = BorderRadius.all(Radius.circular(4.0));
  static const baseTextStyle = TextStyle(
    fontFamily: 'ChessFont',
    height: 1.5,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final move = branch.sanMove;
    final ply = branch.position.ply;
    final textStyle = isSideline
        ? TextStyle(
            fontFamily: 'ChessFont',
            color: _textColor(context, 0.6),
          )
        : baseTextStyle;

    final indexTextStyle = baseTextStyle.copyWith(
      color: _textColor(context, 0.6),
    );

    final indexWidget = ply.isOdd
        ? Text(
            '${(ply / 2).ceil()}.',
            style: indexTextStyle,
          )
        : (startSideline
            ? Text(
                '${(ply / 2).ceil()}...',
                style: indexTextStyle,
              )
            : null);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (startSideline)
          Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: Text('(', style: textStyle),
          ),
        if (shouldShowComments && branch.startingComments?.isNotEmpty == true)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child:
                  _Comments(branch.startingComments!, isSideline: isSideline),
            ),
          ),
        if (indexWidget != null) indexWidget,
        if (indexWidget != null) const SizedBox(width: 1),
        AdaptiveInkWell(
          borderRadius: borderRadius,
          onTap: () => ref.read(ctrlProvider.notifier).userJump(path),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
            decoration: isCurrentMove
                ? BoxDecoration(
                    color: Theme.of(context).focusColor,
                    shape: BoxShape.rectangle,
                    borderRadius: borderRadius,
                  )
                : null,
            child: Text(
              move.san,
              style: isCurrentMove
                  ? textStyle.copyWith(
                      color: _textColor(context, 1),
                      fontWeight: FontWeight.w600,
                    )
                  : textStyle,
            ),
          ),
        ),
        if (shouldShowComments && branch.comments?.isNotEmpty == true)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: _Comments(branch.comments!, isSideline: isSideline),
            ),
          ),
        if (endSideline) Text(')', style: textStyle),
      ],
    );
  }
}

class _Comments extends StatelessWidget {
  _Comments(this.comments, {this.isSideline = false})
      : assert(comments.isNotEmpty);

  final Iterable<String> comments;
  final bool isSideline;

  @override
  Widget build(BuildContext context) {
    return AdaptiveInkWell(
      onTap: () {
        showAdaptiveBottomSheet<void>(
          context: context,
          isDismissible: true,
          isScrollControlled: true,
          builder: (context) => DraggableScrollableSheet(
            maxChildSize: 0.7,
            initialChildSize: 0.3,
            expand: false,
            builder: (context, scrollController) => SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: comments.map(
                    (comment) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(comment.replaceAll('\n', ' ')),
                      );
                    },
                  ).toList(),
                ),
              ),
            ),
          ),
        );
      },
      child: Text(
        comments.join(' ').replaceAll('\n', ' '),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: isSideline ? _textColor(context, 0.6) : null,
        ),
      ),
    );
  }
}

class _OpeningHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _OpeningHeaderDelegate(
    this.ctrlProvider, {
    required this.displayMode,
  });

  final AnalysisControllerProvider ctrlProvider;
  final Orientation displayMode;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return _Opening(ctrlProvider, displayMode);
  }

  @override
  double get minExtent => kOpeningHeaderHeight;

  @override
  double get maxExtent => kOpeningHeaderHeight;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      true;
}

class _Opening extends ConsumerWidget {
  const _Opening(this.ctrlProvider, this.displayMode);

  final AnalysisControllerProvider ctrlProvider;
  final Orientation displayMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodeOpening =
        ref.watch(ctrlProvider.select((s) => s.currentNode.opening));
    final branchOpening =
        ref.watch(ctrlProvider.select((s) => s.currentBranchOpening));
    final contextOpening =
        ref.watch(ctrlProvider.select((s) => s.contextOpening));
    final opening = nodeOpening ?? branchOpening ?? contextOpening;

    return opening != null
        ? Container(
            height: kOpeningHeaderHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: defaultTargetPlatform == TargetPlatform.iOS
                  ? CupertinoDynamicColor.resolve(
                      CupertinoColors.systemGrey5,
                      context,
                    )
                  : Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: displayMode == Orientation.landscape
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(10.0),
                      topRight: Radius.circular(10.0),
                    )
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Center(
                child: Text(
                  opening.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          )
        : const SizedBox.shrink();
  }
}
