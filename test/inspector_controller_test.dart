import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:requests_inspector/requests_inspector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InspectorController', () {
    late InspectorController inspectorController;

    setUp(() {
      inspectorController = InspectorController(
        enabled: true,
        // Shaking needs the sensors plugin, which is not available in tests.
        showInspectorOn: ShowInspectorOn.LongPress,
      );
    });

    test('Initial values should be as expected', () {
      expect(inspectorController.isDarkMode, true);
      expect(inspectorController.isTreeView, true);
      expect(inspectorController.requestsList, isEmpty);
    });

    test('Should add new request', () {
      var request = RequestDetails(
          requestMethod: RequestMethod.GET, url: 'http://example.com');
      inspectorController.addNewRequest(request);
      expect(inspectorController.requestsList.length, 1);
      expect(inspectorController.requestsList.first.url, 'http://example.com');
    });

    test('Should clear all requests', () {
      var request = RequestDetails(
          requestMethod: RequestMethod.GET, url: 'http://example.com');
      inspectorController.addNewRequest(request);
      inspectorController.clearAllRequests();
      expect(inspectorController.requestsList, isEmpty);
      expect(inspectorController.selectedRequest, isNull);
    });

    test('JSON export holds only the requests still listed', () {
      inspectorController.clearAllRequests();
      inspectorController.addNewRequest(RequestDetails(
          requestMethod: RequestMethod.GET, url: 'http://cleared.com'));
      inspectorController.clearAllRequests();
      inspectorController.addNewRequest(RequestDetails(
          requestMethod: RequestMethod.POST,
          url: 'http://kept.com',
          requestBody: {'bytes': Object()}));

      final json = jsonDecode(inspectorController
          .buildRequestsJson(inspectorController.filteredRequestsList));

      expect(json['count'], 1);
      expect(json['requests'].single['url'], 'http://kept.com');
      expect(json['requests'].single['requestMethod'], 'POST');
    });

    test('Toggle dark mode should change state', () {
      inspectorController.toggleInspectorTheme();
      expect(inspectorController.isDarkMode, false);
      inspectorController.toggleInspectorTheme();
      expect(inspectorController.isDarkMode, true);
    });

    test('Search functionality works correctly', () {
      var request1 = RequestDetails(
          requestMethod: RequestMethod.GET, url: 'http://test1.com');
      var request2 = RequestDetails(
          requestMethod: RequestMethod.GET, url: 'http://test2.com');
      inspectorController.addNewRequest(request1);
      inspectorController.addNewRequest(request2);
      inspectorController.searchForRequests('test1');

      expect(inspectorController.filteredRequestsList.length, 1);
      expect(inspectorController.filteredRequestsList.first.url,
          'http://test1.com');
    });
  });
}
