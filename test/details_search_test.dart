import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:requests_inspector/requests_inspector.dart';
import 'package:requests_inspector/src/helpers/search_helper.dart';
import 'package:requests_inspector/src/shared_widgets/inspector.dart';

/// Every span the details page currently renders with a highlight background,
/// optionally restricted to the [background] of the active match.
///
/// Node titles of the JSON tree view are rendered with a plain [Text] so that
/// they stay tappable, the rest of the details are selectable.
List<TextSpan> highlightedSpans(WidgetTester tester, {Color? background}) {
  final spans = <TextSpan>[];

  void collectFrom(InlineSpan? span) {
    span?.visitChildren((visited) {
      if (visited is TextSpan) {
        final visitedBackground = visited.style?.backgroundColor;
        if (visitedBackground != null &&
            (background == null || visitedBackground == background)) {
          spans.add(visited);
        }
      }
      return true;
    });
  }

  for (final selectable in tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  )) {
    collectFrom(selectable.textSpan);
  }
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    collectFrom(text.textSpan);
  }

  return spans;
}

/// The whole texts of the widgets holding an active (currently navigated to)
/// match, used to tell which section a match belongs to.
List<String> activeMatchTexts(WidgetTester tester) {
  final texts = <String>[];

  bool holdsActiveMatch(InlineSpan? span) {
    var found = false;
    span?.visitChildren((visited) {
      if (visited is TextSpan &&
          visited.style?.backgroundColor == Colors.orange) {
        found = true;
      }
      return true;
    });
    return found;
  }

  for (final selectable in tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  )) {
    if (holdsActiveMatch(selectable.textSpan)) {
      texts.add(selectable.textSpan!.toPlainText());
    }
  }
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    if (holdsActiveMatch(text.textSpan)) {
      texts.add(text.textSpan!.toPlainText());
    }
  }

  return texts;
}

/// The details as they are rendered, ignoring the highlighting.
List<String> renderedTexts(WidgetTester tester) => [
      for (final selectable in tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      ))
        selectable.textSpan?.toPlainText() ?? '',
    ];

Future<InspectorController> pumpInspector(
  WidgetTester tester,
  RequestDetails request,
) async {
  final controller = InspectorController(
    enabled: true,
    // Shaking needs the sensors plugin, which is not available in tests.
    showInspectorOn: ShowInspectorOn.LongPress,
  );
  // The controller is a singleton, so every test starts from a clean state.
  if (controller.isSearchVisible) controller.toggleSearchVisibility();
  if (!controller.isTreeView) controller.toggleInspectorJsonView();
  if (!controller.expandChildren) controller.toggleExpandChildren();
  controller.clearAllRequests();
  controller.addNewRequest(request);
  controller.selectedRequest = request;

  await tester.pumpWidget(
    ChangeNotifierProvider<InspectorController>.value(
      value: controller,
      child: const Inspector(),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> search(WidgetTester tester, String query) async {
  if (!InspectorController().isSearchVisible) {
    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byType(TextField).first, query);
  await tester.pumpAndSettle();
}

RequestDetails buildRequest({
  dynamic headers,
  dynamic requestBody,
  dynamic responseBody,
}) =>
    RequestDetails(
      requestMethod: RequestMethod.GET,
      url: 'https://api.example.com/items',
      statusCode: 200,
      headers: headers,
      requestBody: requestBody,
      responseBody: responseBody,
    );

void main() {
  group('SearchHelper', () {
    test('matches do not overlap', () {
      expect(SearchHelper.countMatches(text: 'aaaa', query: 'aa'), 2);
    });

    test('is case insensitive', () {
      expect(SearchHelper.countMatches(text: 'Hi hi HI', query: 'hi'), 3);
    });

    test('counts the keys of the JSON tree view nodes', () {
      // `"history" : ` of the node itself and `"history" : "hi",` of the leaf.
      expect(
        SearchHelper.countMatchesInJsonNode(
          <String, dynamic>{
            'history': <String, dynamic>{'history': 'hi'},
          },
          query: 'history',
        ),
        2,
      );
    });

    test('counts an empty section as no match at all', () {
      expect(
        SearchHelper.countMatchesInSection(
          data: <String, dynamic>{},
          query: 'a',
          isTreeView: true,
        ),
        0,
      );
    });

    test('counts a section with the text of the mode it is rendered with', () {
      final data = <String, dynamic>{'a': 'b'};

      // The tree view renders `"a" : "b",`, the plain view renders the pretty
      // printed `{\n  "a": "b"\n}`, so a `"a": ` query only matches the latter.
      expect(
        SearchHelper.countMatchesInSection(
          data: data,
          query: '"a": ',
          isTreeView: true,
        ),
        0,
      );
      expect(
        SearchHelper.countMatchesInSection(
          data: data,
          query: '"a": ',
          isTreeView: false,
        ),
        1,
      );
    });
  });

  group('Request details search', () {
    testWidgets('shows the match counter of the current query', (tester) async {
      final controller = await pumpInspector(
        tester,
        buildRequest(responseBody: const <String, dynamic>{'title': 'hi'}),
      );
      await search(tester, 'hi');

      expect(controller.totalMatches, 1);
      expect(find.text('1 / 1'), findsOneWidget);
    });

    testWidgets('says so when the query matches nothing', (tester) async {
      final controller = await pumpInspector(
        tester,
        buildRequest(responseBody: const <String, dynamic>{'title': 'hi'}),
      );
      await search(tester, 'nothing to be found');

      expect(controller.totalMatches, 0);
      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets('counts exactly the matches it highlights in tree view',
        (tester) async {
      final controller = await pumpInspector(
        tester,
        buildRequest(
          headers: const <String, dynamic>{'x-history': 'hi'},
          responseBody: const <String, dynamic>{
            'history': <String, dynamic>{'title': 'hi there'},
          },
        ),
      );
      await search(tester, 'hi');

      expect(controller.totalMatches, greaterThan(0));
      expect(highlightedSpans(tester).length, controller.totalMatches);
    });

    testWidgets('highlights the key of a nested object', (tester) async {
      final controller = await pumpInspector(
        tester,
        buildRequest(
          responseBody: const <String, dynamic>{
            'history': <String, dynamic>{'total': 2},
          },
        ),
      );
      await search(tester, 'history');

      expect(controller.totalMatches, 1);
      expect(highlightedSpans(tester).single.text, 'history');
    });

    testWidgets('counts exactly the matches it highlights in plain view',
        (tester) async {
      final controller = await pumpInspector(
        tester,
        buildRequest(
          headers: const <String, dynamic>{'x-history': 'hi'},
          responseBody: const <String, dynamic>{
            'title': 'hi there',
            'items': ['hi', 'high'],
          },
        ),
      );
      controller.toggleInspectorJsonView();
      await tester.pumpAndSettle();
      await search(tester, 'hi');

      expect(controller.totalMatches, greaterThan(0));
      expect(highlightedSpans(tester).length, controller.totalMatches);
    });

    testWidgets('keeps the counter in sync when the view mode is toggled',
        (tester) async {
      final controller = await pumpInspector(
        tester,
        buildRequest(
          responseBody: const <String, dynamic>{'title': 'hi there'},
        ),
      );
      await search(tester, 'hi');

      controller.toggleInspectorJsonView();
      await tester.pumpAndSettle();

      expect(highlightedSpans(tester).length, controller.totalMatches);
    });

    testWidgets('does not repeat the characters of overlapping matches',
        (tester) async {
      final controller = await pumpInspector(
        tester,
        buildRequest(responseBody: const <String, dynamic>{'v': 'aaaa'}),
      );
      await search(tester, 'aa');

      expect(controller.totalMatches, 2);
      expect(renderedTexts(tester), contains('"v" : "aaaa",'));
    });

    testWidgets('navigates through the matches of every section',
        (tester) async {
      final controller = await pumpInspector(
        tester,
        buildRequest(
          headers: const <String, dynamic>{'from-header': 'hi'},
          responseBody: const <String, dynamic>{'from-body': 'hi'},
        ),
      );
      await search(tester, 'hi');

      expect(controller.totalMatches, 2);
      expect(controller.currentMatchIndex, 0);
      expect(activeMatchTexts(tester), ['"from-header" : "hi",']);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
      await tester.pumpAndSettle();
      expect(controller.currentMatchIndex, 1);
      expect(activeMatchTexts(tester), ['"from-body" : "hi",']);

      // The next match wraps around to the first one.
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
      await tester.pumpAndSettle();
      expect(controller.currentMatchIndex, 0);
      expect(activeMatchTexts(tester), ['"from-header" : "hi",']);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_up).first);
      await tester.pumpAndSettle();
      expect(controller.currentMatchIndex, 1);
      expect(activeMatchTexts(tester), ['"from-body" : "hi",']);
    });

    testWidgets('expands a collapsed node holding the active match',
        (tester) async {
      final controller = await pumpInspector(
        tester,
        buildRequest(
          headers: const <String, dynamic>{'a': 'hi'},
          responseBody: const <String, dynamic>{
            'deep': <String, dynamic>{'v': 'hi'},
          },
        ),
      );
      controller.toggleExpandChildren();
      await tester.pumpAndSettle();
      await search(tester, 'hi');

      expect(find.text('"v" : "hi",'), findsNothing);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
      await tester.pumpAndSettle();

      expect(activeMatchTexts(tester), ['"v" : "hi",']);
    });

    testWidgets('keeps the tree nodes tappable while highlighting their keys',
        (tester) async {
      await pumpInspector(
        tester,
        buildRequest(
          responseBody: const <String, dynamic>{
            'history': <String, dynamic>{'total': 2},
          },
        ),
      );
      await search(tester, 'history');

      expect(find.text('"total" : 2,'), findsOneWidget);

      // The title of the node, rendered as a highlighted `Text.rich`.
      await tester.tap(find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.textSpan?.toPlainText() == '"history" : ',
      ));
      await tester.pumpAndSettle();

      expect(find.text('"total" : 2,'), findsNothing);
    });

    testWidgets('drops the query and the highlights when it is closed',
        (tester) async {
      final controller = await pumpInspector(
        tester,
        buildRequest(responseBody: const <String, dynamic>{'title': 'hi'}),
      );
      await search(tester, 'hi');
      expect(highlightedSpans(tester), isNotEmpty);

      await tester.tap(find.descendant(
        of: find.byType(TextField),
        matching: find.byIcon(Icons.close),
      ));
      await tester.pumpAndSettle();

      expect(controller.searchQuery, isEmpty);
      expect(controller.totalMatches, 0);
      expect(controller.currentMatchIndex, -1);
      expect(highlightedSpans(tester), isEmpty);
    });

    testWidgets('searches a body that is not a JSON object', (tester) async {
      final controller = await pumpInspector(
        tester,
        buildRequest(responseBody: 42),
      );
      controller.toggleInspectorJsonView();
      await tester.pumpAndSettle();
      await search(tester, '42');

      expect(controller.totalMatches, 1);
      expect(highlightedSpans(tester).length, 1);
    });
  });
}
