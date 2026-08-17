import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leadflow_ai/widgets/launcher_tile.dart';

// Regression test for a real bug: dragging the free-form width/height
// sliders (More screen / Leads List Edit Mode) changed the number shown
// next to the slider but never visibly resized the tile -- reported by
// the user from an on-device screen recording. Root cause: LauncherTile's
// outermost widget is a Stack, and Stack gives its non-positioned child
// LOOSE constraints by default (StackFit.loose), so the decorated
// Container inside always renders at its own intrinsic content size
// (icon + label + padding) no matter what width/height a parent SizedBox
// requests. This test measures the actual rendered size of the tile's
// decorated Container -- not just the outer Stack, which always reports
// the SizedBox's size regardless of the bug -- so it fails under the
// loose-constraint bug and passes once LauncherTile fills its box.
void main() {
  Future<Size> pumpAndMeasure(WidgetTester tester, {required double width, required double height}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: LauncherTile(
                label: 'Team',
                icon: Icons.group,
                color: Colors.indigo,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final containerFinder = find.descendant(
      of: find.byType(LauncherTile),
      matching: find.byType(Container),
    );
    expect(containerFinder, findsWidgets);
    return tester.getSize(containerFinder.first);
  }

  testWidgets('LauncherTile fills an arbitrary parent-provided size', (tester) async {
    final size = await pumpAndMeasure(tester, width: 260, height: 150);
    expect(
      size,
      const Size(260, 150),
      reason: 'LauncherTile must fill the exact box its parent (SizedBox/Wrap cell) '
          'gives it, or the free-form width/height controls have no visible effect.',
    );
  });

  testWidgets('LauncherTile still fills a very small requested size', (tester) async {
    final size = await pumpAndMeasure(tester, width: 100, height: 100);
    expect(size, const Size(100, 100));
  });

  testWidgets('LauncherTile at 32% vs 98% of a 720-wide row are visibly different sizes',
      (tester) async {
    // Mirrors the exact slider range from the bug report (widthFraction
    // 0.32 -> 0.98 of a fixed row width), so this test fails the same way
    // the on-device recording did if the bug regresses.
    const rowWidth = 720.0;
    final narrow = await pumpAndMeasure(tester, width: rowWidth * 0.32, height: 130);
    final wide = await pumpAndMeasure(tester, width: rowWidth * 0.98, height: 130);
    expect(wide.width, greaterThan(narrow.width + 100));
  });
}
