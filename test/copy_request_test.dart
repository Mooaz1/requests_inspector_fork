import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:requests_inspector/requests_inspector.dart';
import 'package:requests_inspector/src/enums/share_type_enum.dart';
import 'package:requests_inspector/src/shared_widgets/inspector.dart';

/// Records what the app puts on the platform clipboard.
class FakeClipboard {
  String? text;

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          text = call.arguments['text'] as String?;
        }
        return null;
      },
    );
  }

  void uninstall(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

RequestDetails buildRequest({RequestMethod method = RequestMethod.POST}) =>
    RequestDetails(
      requestMethod: method,
      url: 'https://api.example.com/login',
      statusCode: 200,
      headers: const <String, dynamic>{'authorization': 'Bearer token'},
      requestBody: const <String, dynamic>{'user': 'qc'},
      responseBody: const <String, dynamic>{'ok': true},
    );

Future<InspectorController> pumpInspector(
  WidgetTester tester,
  RequestDetails request,
) async {
  final controller = InspectorController(
    enabled: true,
    // Shaking needs the sensors plugin, which is not available in tests.
    showInspectorOn: ShowInspectorOn.LongPress,
  );
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

Future<void> tapCopy(WidgetTester tester) async {
  // The sections of the details have a copy button of their own.
  await tester.tap(find.widgetWithIcon(FloatingActionButton, Icons.copy));
  await tester.pumpAndSettle();
}

void main() {
  late FakeClipboard clipboard;

  setUp(() => clipboard = FakeClipboard());

  group('Copying the selected request', () {
    testWidgets('copies the cURL command without the share sheet',
        (tester) async {
      await pumpInspector(tester, buildRequest());
      clipboard.install(tester);

      await tapCopy(tester);
      await tester.tap(find.text('cURL Command'));
      await tester.pumpAndSettle();

      expect(clipboard.text, startsWith('curl'));
      expect(clipboard.text, contains('https://api.example.com/login'));
      expect(find.text('cURL command copied'), findsOneWidget);

      clipboard.uninstall(tester);
    });

    testWidgets('copies the HAR as text', (tester) async {
      await pumpInspector(tester, buildRequest());
      clipboard.install(tester);

      await tapCopy(tester);
      await tester.tap(find.text('HAR'));
      await tester.pumpAndSettle();

      // A HAR is copied as text, so the format dialog of the file variant is
      // never asked for.
      expect(find.text('HAR file (.har)'), findsNothing);
      expect(jsonDecode(clipboard.text!), isA<Map<String, dynamic>>());
      expect(find.text('HAR copied'), findsOneWidget);

      clipboard.uninstall(tester);
    });

    testWidgets('copies a non HTTP request without asking for a format',
        (tester) async {
      await pumpInspector(tester, buildRequest(method: RequestMethod.WS));
      clipboard.install(tester);

      await tapCopy(tester);

      // There is no cURL command for a web socket, so there is nothing to ask.
      expect(find.text('cURL Command'), findsNothing);
      expect(clipboard.text, contains('https://api.example.com/login'));
      expect(find.text('Log copied'), findsOneWidget);

      clipboard.uninstall(tester);
    });

    testWidgets('copies nothing when the format dialog is dismissed',
        (tester) async {
      await pumpInspector(tester, buildRequest());
      clipboard.install(tester);

      await tapCopy(tester);
      await tester.tapAt(const Offset(10, 10)); // outside of the dialog
      await tester.pumpAndSettle();

      expect(clipboard.text, isNull);

      clipboard.uninstall(tester);
    });
  });

  group('InspectorController.buildShareContent', () {
    late InspectorController controller;

    setUp(() {
      controller = InspectorController(
        enabled: true,
        showInspectorOn: ShowInspectorOn.LongPress,
      );
      controller.clearAllRequests();
      final request = buildRequest();
      controller.addNewRequest(request);
      controller.selectedRequest = request;
    });

    test('shares and copies the very same text', () {
      for (final shareType in ShareType.values) {
        expect(
          controller.buildShareContent(shareType),
          isNotEmpty,
          reason: '$shareType has no content',
        );
      }
    });

    test('holds both formats in the combined one', () {
      final both = controller.buildShareContent(ShareType.Both);

      expect(both, contains(controller.buildShareContent(ShareType.NormalLog)));
      expect(
        both,
        contains(controller.buildShareContent(ShareType.CurlCommand)),
      );
    });

    test('builds the HAR file out of the HAR text', () {
      expect(
        controller.buildShareContent(ShareType.HarFile),
        controller.buildShareContent(ShareType.Har),
      );
    });
  });
}
