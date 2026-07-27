import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:requests_inspector/requests_inspector.dart';

RequestDetails buildRequest([String path = 'items']) => RequestDetails(
      requestMethod: RequestMethod.GET,
      url: 'https://api.example.com/$path',
      responseBody: const <String, dynamic>{'title': 'hi there'},
    );

Future<InspectorController> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RequestsInspector(
        // Shaking needs the sensors plugin, which is not available in tests.
        showInspectorOn: ShowInspectorOn.LongPress,
        child: Scaffold(
          body: Center(
            child: TextButton(onPressed: () {}, child: const Text('In app')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final controller = InspectorController();
  controller.clearAllRequests();
  final request = buildRequest();
  controller.addNewRequest(request);
  controller.selectedRequest = request;
  await tester.pumpAndSettle();

  return controller;
}

Future<void> openInspectorAndSearch(
  WidgetTester tester,
  InspectorController controller, {
  required bool type,
}) async {
  controller.showInspector();
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.search).first);
  await tester.pumpAndSettle();

  if (type) {
    await tester.enterText(find.byType(TextField).first, 'hi');
    await tester.pumpAndSettle();
  }
}

Future<void> closeInspector(WidgetTester tester) async {
  // The close button of the app bar, the search field has one of its own.
  await tester.tap(find.descendant(
    of: find.byType(AppBar),
    matching: find.byIcon(Icons.close),
  ));
  await tester.pumpAndSettle();
}

/// Reproduces what the framework does for a focused text field whenever the
/// caret moves or the keyboard metrics change: it asks to be scrolled into
/// view, and that request travels up through every enclosing viewport.
Future<void> bringFocusedFieldIntoView(WidgetTester tester) async {
  final editableText = find.byType(EditableText);
  if (editableText.evaluate().isEmpty) return;

  final state = tester.state<EditableTextState>(editableText.first);
  state.bringIntoView(state.textEditingValue.selection.base);
  await tester.pumpAndSettle();
}

void main() {
  group('The closed inspector', () {
    testWidgets('stays closed when the app keeps sending requests',
        (tester) async {
      final controller = await pumpApp(tester);
      await openInspectorAndSearch(tester, controller, type: true);
      await closeInspector(tester);
      expect(controller.pageController.page, 0.0);

      // Anything the app does from here on logs new requests, which rebuild
      // the details page behind it.
      controller.addNewRequest(buildRequest('profile'));
      await tester.pumpAndSettle();

      expect(controller.pageController.page, 0.0);
    });

    testWidgets('stays closed when a request arrives with no search running',
        (tester) async {
      final controller = await pumpApp(tester);
      await openInspectorAndSearch(tester, controller, type: false);
      await closeInspector(tester);

      controller.addNewRequest(buildRequest('profile'));
      await tester.pumpAndSettle();

      expect(controller.pageController.page, 0.0);
    });

    testWidgets('stays closed when the search field asks to be shown',
        (tester) async {
      final controller = await pumpApp(tester);
      await openInspectorAndSearch(tester, controller, type: true);
      await closeInspector(tester);

      await bringFocusedFieldIntoView(tester);

      expect(controller.pageController.page, 0.0);
    });

    testWidgets('takes the keyboard with it', (tester) async {
      final controller = await pumpApp(tester);
      await openInspectorAndSearch(tester, controller, type: true);

      final searchField =
          tester.widget<TextField>(find.byType(TextField).first);
      expect(searchField.focusNode?.hasFocus, isTrue);

      await closeInspector(tester);

      expect(
        searchField.focusNode?.hasFocus,
        isFalse,
        reason: 'the search field kept the focus, and the keyboard with it',
      );
    });
  });

  group('Scrolling to a match', () {
    testWidgets('still reveals a match of a section further down',
        (tester) async {
      final controller = await pumpApp(tester);
      final request = RequestDetails(
        requestMethod: RequestMethod.GET,
        url: 'https://api.example.com/items',
        headers: const <String, dynamic>{'a': 'no match here'},
        responseBody: <String, dynamic>{
          for (var i = 0; i < 40; i++) 'filler$i': 'padding',
          'last': 'hi',
        },
      );
      controller.clearAllRequests();
      controller.addNewRequest(request);
      controller.selectedRequest = request;
      await tester.pumpAndSettle();

      await openInspectorAndSearch(tester, controller, type: true);

      // The match sits below the fold, so the details had to be scrolled for
      // it to be rendered at all.
      expect(find.text('"last" : "hi",'), findsOneWidget);
      expect(controller.totalMatches, 1);
    });
  });
}
