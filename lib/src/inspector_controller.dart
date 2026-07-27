import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:requests_inspector/src/shake.dart';
import 'package:requests_inspector/src/stopper_filter.dart';
import 'package:share_plus/share_plus.dart';

import '../requests_inspector.dart';
import 'curl_command_generator.dart';
import 'har_generator.dart';
import 'json_pretty_converter.dart';
import 'helpers/inspector_helper.dart';
import 'helpers/search_helper.dart';
import 'enums/share_type_enum.dart';
import 'requests_filter.dart';

typedef StoppingRequestCallback = Future<RequestDetails?> Function(
    RequestDetails requestDetails);

typedef StoppingResponseCallback = Future<ResponseDetails?> Function(
    ResponseDetails responseDetails);

///Singleton
class InspectorController extends ChangeNotifier {
  factory InspectorController({
    bool enabled = false,
    ShowInspectorOn showInspectorOn = ShowInspectorOn.Shaking,
    StoppingRequestCallback? onStoppingRequest,
    StoppingResponseCallback? onStoppingResponse,
    bool defaultTreeViewEnabled = true,
    bool defaultExpandChildren = true,
    bool defaultIsDarkMode = true,
  }) =>
      _singleton ??= InspectorController._internal(
        enabled: enabled,
        showInspectorOn: showInspectorOn,
        onStoppingRequest: onStoppingRequest,
        onStoppingResponse: onStoppingResponse,
        defaultTreeViewEnabled: defaultTreeViewEnabled,
        defaultExpandChildren: defaultExpandChildren,
        defaultIsDarkMode: defaultIsDarkMode,
      );

  InspectorController._internal({
    required bool enabled,
    required ShowInspectorOn showInspectorOn,
    StoppingRequestCallback? onStoppingRequest,
    StoppingResponseCallback? onStoppingResponse,
    required bool defaultTreeViewEnabled,
    required bool defaultExpandChildren,
    required bool defaultIsDarkMode,
  })  : _enabled = enabled,
        _showInspectorOn = showInspectorOn,
        _onStoppingRequest = onStoppingRequest,
        _isTreeView = defaultTreeViewEnabled,
        _expandChildren = defaultExpandChildren,
        _isDarkMode = defaultIsDarkMode,
        _onStoppingResponse = onStoppingResponse {
    if (_enabled && _allowShaking)
      _shakeDetector = ShakeDetector.autoStart(
        onPhoneShake: showInspector,
        minimumShakeCount: 3,
      );
  }

  static InspectorController? _singleton;

  late final bool _enabled;
  late final ShowInspectorOn _showInspectorOn;
  late final ShakeDetector _shakeDetector;
  StoppingRequestCallback? _onStoppingRequest;
  StoppingResponseCallback? _onStoppingResponse;

  final _dio = Dio(BaseOptions(validateStatus: (_) => true));
  final pageController = PageController(
    initialPage: 0,
    // if the viewportFraction is 1.0, the child pages will rebuild automatically
    // but if it less than 1.0, the pages will stay alive
    viewportFraction: 0.9999999,
  );

  int _selectedTab = 0;
  bool _requestStopperEnabled = false;
  bool _responseStopperEnabled = false;
  bool _isDarkMode;
  bool _isTreeView;
  bool _expandChildren;

  final _requestsList = <RequestDetails>[];
  RequestDetails? _selectedRequest;

  bool _isSearchVisible = false;
  String _searchQuery = '';
  int _totalMatches = 0;
  int _currentMatchIndex = -1;

  // Search & Filters state
  String _searchUrlQuery = '';
  RequestMethod? _filterRequestMethod;
  int? _filterStatusCode;

  // ------------------------------

  // Stoppers Filter State
  /// TODO: Would be better if we used the [RequestStopperFilter] and [ResponseStopperFilter] classes instead of these separate fields.
  RequestMethod? _requestStopperFilterMethod;
  String? _requestStopperFilterUrl;
  int? _responseStopperFilterStatusCode;
  String? _responseStopperFilterUrl;
  // ------------------------------

  RequestMethod? get requestStopperFilterMethod => _requestStopperFilterMethod;
  String? get requestStopperFilterUrl => _requestStopperFilterUrl;
  int? get responseStopperFilterStatusCode => _responseStopperFilterStatusCode;
  String? get responseStopperFilterUrl => _responseStopperFilterUrl;

  bool get hasRequestStopperFilters =>
      _requestStopperFilterMethod != null ||
      (_requestStopperFilterUrl != null &&
          _requestStopperFilterUrl!.trim().isNotEmpty);

  bool get hasResponseStopperFilters =>
      _responseStopperFilterStatusCode != null ||
      (_responseStopperFilterUrl != null &&
          _responseStopperFilterUrl!.trim().isNotEmpty);

  int get selectedTab => _selectedTab;

  bool get requestStopperEnabled => _requestStopperEnabled;

  bool get responseStopperEnabled => _responseStopperEnabled;

  bool get isDarkMode => _isDarkMode;

  bool get isTreeView => _isTreeView;

  bool get expandChildren => _expandChildren;

  List<RequestDetails> get requestsList => _requestsList;

  RequestDetails? get selectedRequest => _selectedRequest;

  bool get isSearchVisible => _isSearchVisible;

  String get searchQuery => _searchQuery;

  int get totalMatches => _totalMatches;

  int get currentMatchIndex => _currentMatchIndex;

  String get searchUrlQuery => _searchUrlQuery;

  RequestMethod? get filterRequestMethod => _filterRequestMethod;

  int? get filterStatusCode => _filterStatusCode;

  bool get areAnyFiltersApplied =>
      searchUrlQuery.trim().isNotEmpty ||
      filterRequestMethod != null ||
      filterStatusCode != null;

  // Computed filtered + searched list
  List<RequestDetails> get filteredRequestsList {
    Iterable<RequestDetails> list = [..._requestsList];

    if (_filterRequestMethod != null)
      list =
          list.where(RequestMethodFilter(_filterRequestMethod!).requestFilter);

    if (_filterStatusCode != null)
      list =
          list.where(RequestStatusCodeFilter(_filterStatusCode!).requestFilter);

    if (_searchUrlQuery.trim().isNotEmpty)
      list = list.where(RequestUrlFilter(_searchUrlQuery).requestFilter);

    return list.toList(growable: false);
  }

  bool get _allowShaking => [
        ShowInspectorOn.Shaking,
        ShowInspectorOn.Both,
      ].contains(_showInspectorOn);

  set selectedTab(int value) {
    if (_selectedTab == value) return;
    _selectedTab = value;
    notifyListeners();
  }

  set requestStopperEnabled(bool value) {
    if (_requestStopperEnabled == value) return;
    _requestStopperEnabled = value;
    notifyListeners();
  }

  set responseStopperEnabled(bool value) {
    if (_responseStopperEnabled == value) return;
    _responseStopperEnabled = value;
    notifyListeners();
  }

  set selectedRequest(RequestDetails? value) {
    if (_selectedRequest == value && _selectedTab == 1) return;
    _selectedRequest = value;
    _selectedTab = 1;
    _currentMatchIndex = 0;
    _updateTotalMatches();
    notifyListeners();
  }

  // setters for search & filters
  void searchForRequests(String value) {
    if (_searchUrlQuery == value) return;
    _searchUrlQuery = value;
    notifyListeners();
  }

  void setRequestMethodFilter(RequestMethod? method) {
    if (_filterRequestMethod == method) return;
    _filterRequestMethod = method;
    notifyListeners();
  }

  void setStatusCodeFilter(int? statusCode) {
    if (_filterStatusCode == statusCode) return;
    _filterStatusCode = statusCode;
    notifyListeners();
  }

  void clearFilters() {
    _filterRequestMethod = null;
    _filterStatusCode = null;
    notifyListeners();
  }

  void clearSearch() {
    if (_searchUrlQuery.isEmpty) return;
    _searchUrlQuery = '';
    notifyListeners();
  }

  void setRequestStopperFilterMethod(RequestMethod? method) {
    if (_requestStopperFilterMethod == method) return;
    _requestStopperFilterMethod = method;
    notifyListeners();
  }

  void setRequestStopperFilterUrl(String? url) {
    url = url?.trim();
    if (url != null && url.isEmpty) {
      url = null;
    }
    if (_requestStopperFilterUrl == url) return;
    _requestStopperFilterUrl = url;
    notifyListeners();
  }

  void setResponseStopperFilterStatusCode(int? statusCode) {
    if (_responseStopperFilterStatusCode == statusCode) return;
    _responseStopperFilterStatusCode = statusCode;
    notifyListeners();
  }

  void setResponseStopperFilterUrl(String? url) {
    url = url?.trim();
    if (url != null && url.isEmpty) {
      url = null;
    }
    if (_responseStopperFilterUrl == url) return;
    _responseStopperFilterUrl = url;
    notifyListeners();
  }

  void clearRequestStopperFilters() {
    _requestStopperFilterMethod = null;
    _requestStopperFilterUrl = null;
    notifyListeners();
  }

  void clearResponseStopperFilters() {
    _responseStopperFilterStatusCode = null;
    _responseStopperFilterUrl = null;
    notifyListeners();
  }

  bool shouldStopRequest(RequestDetails requestDetails) {
    final filter = RequestStopperFilter(
      requestMethod: _requestStopperFilterMethod,
      urlPattern: _requestStopperFilterUrl,
    );
    return filter.shouldStop(requestDetails);
  }

  bool shouldStopResponse(ResponseDetails responseDetails) {
    final filter = ResponseStopperFilter(
      statusCode: _responseStopperFilterStatusCode,
      urlPattern: _responseStopperFilterUrl,
    );
    return filter.shouldStop(responseDetails);
  }

  void showInspector() => pageController.jumpToPage(1);

  void hideInspector() {
    // Whatever the inspector had focused, the search field above all, would
    // otherwise keep the keyboard up over the app it has just been hidden
    // behind.
    FocusManager.instance.primaryFocus?.unfocus();
    pageController.jumpToPage(0);
  }

  void addNewRequest(RequestDetails request) {
    if (!_enabled) return;
    _requestsList.insert(0, request);
    notifyListeners();
  }

  void clearAllRequests() {
    if (_requestsList.isEmpty && _selectedRequest == null) return;
    _requestsList.clear();
    _selectedRequest = null;
    notifyListeners();
  }

  Future<void> runAgain() async {
    if (_selectedRequest == null) return;

    var currentRequest = _selectedRequest!;
    final sentTime = DateTime.now();
    final response = await _dio.request(
      currentRequest.url,
      queryParameters: currentRequest.queryParameters,
      data: currentRequest.requestBody,
      options: Options(
        method: currentRequest.requestMethod.name,
        headers: currentRequest.headers,
      ),
    );
    if (currentRequest != _selectedRequest) return;

    _selectedRequest = currentRequest.copyWith(
      responseBody: response.data,
      statusCode: response.statusCode,
      sentTime: sentTime,
      receivedTime: DateTime.now(),
    );

    notifyListeners();
  }

  void shareSelectedRequest({
    Rect? sharePositionOrigin,
    ShareType shareType = ShareType.NormalLog,
  }) {
    final request = _selectedRequest;
    if (request == null) return;

    if (shareType == ShareType.HarFile) {
      final file = XFile.fromData(
        utf8.encode(buildShareContent(ShareType.Har, request: request)),
        name: 'request.har',
        mimeType: 'application/json',
      );

      Share.shareXFiles(
        [file],
        sharePositionOrigin: sharePositionOrigin,
      );
      return;
    }

    Share.share(
      buildShareContent(shareType, request: request),
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Puts the selected request on the clipboard.
  ///
  /// The share sheet is not always usable: emulators such as BlueStacks list
  /// no target that can take the text, so the log has to be copyable without
  /// leaving the inspector.
  Future<bool> copySelectedRequest({
    ShareType shareType = ShareType.NormalLog,
  }) async {
    final request = _selectedRequest;
    if (request == null) return false;

    await Clipboard.setData(
      ClipboardData(text: buildShareContent(shareType, request: request)),
    );
    return true;
  }

  /// The text shared, or copied, for [shareType].
  ///
  /// [ShareType.HarFile] has no text of its own: it is the HAR of the request,
  /// shared as a file instead of as text.
  String buildShareContent(ShareType shareType, {RequestDetails? request}) {
    final sharedRequest = request ?? _selectedRequest!;

    String curlCommand() => CurlCommandGenerator(sharedRequest).generate();
    String normalLog() => _formatMap(sharedRequest.toMap());

    switch (shareType) {
      case ShareType.CurlCommand:
        return curlCommand();
      case ShareType.NormalLog:
        return normalLog();
      case ShareType.Har:
      case ShareType.HarFile:
        return HarGenerator().generate(
          request: sharedRequest,
          curlCommand: curlCommand(),
        );
      case ShareType.Both:
        return '================[cURL Command]=================\n'
            '${curlCommand()}\n\n'
            '==================[Normal Log]===================\n'
            '${normalLog()}';
    }
  }

  @override
  void dispose() {
    if (_allowShaking) _shakeDetector.stopListening();
    _singleton = null;
    super.dispose();
  }

  String _formatMap(Map<String, dynamic> requestMap) {
    final converter = JsonPrettyConverter();
    final listOfContent = [
      for (final entry in requestMap.entries) ...[
        '=[ ${entry.key} ]===================\n',
        converter.convert(entry.value),
        '\n\n',
      ],
    ];

    return listOfContent.join();
  }

  Future<RequestDetails?> editRequest(RequestDetails requestDetails) {
    if (!_enabled || _onStoppingRequest == null) return Future.value(null);
    return _onStoppingRequest!(requestDetails);
  }

  Future<ResponseDetails?> editResponse(ResponseDetails responseDetails) {
    if (!_enabled || _onStoppingResponse == null) return Future.value(null);

    if (!['Map', 'String', 'List'].any((e) => responseDetails
        .responseBody.runtimeType
        .toString()
        .replaceFirst('_', '')
        .startsWith(e))) return Future.value(null);

    return _onStoppingResponse!(responseDetails);
  }

  void toggleInspectorTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void toggleInspectorJsonView() {
    _isTreeView = !_isTreeView;
    // The two view modes render different text, so they match differently.
    _updateTotalMatches();
    notifyListeners();
  }

  void toggleSearchVisibility() {
    _isSearchVisible = !_isSearchVisible;
    if (!_isSearchVisible) {
      _searchQuery = '';
      _totalMatches = 0;
      _currentMatchIndex = -1;
    }
    notifyListeners();
  }

  void updateSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    // A new query starts over from its first match.
    _currentMatchIndex = 0;
    _updateTotalMatches();
    notifyListeners();
  }

  void nextMatch() {
    if (_totalMatches == 0) return;
    _currentMatchIndex = (_currentMatchIndex + 1) % _totalMatches;
    notifyListeners();
  }

  void previousMatch() {
    if (_totalMatches == 0) return;
    _currentMatchIndex =
        (_currentMatchIndex - 1 + _totalMatches) % _totalMatches;
    notifyListeners();
  }

  /// Recomputes how many matches the details page renders for the current
  /// query, section by section and in the same order the page renders them.
  ///
  /// It must stay in sync with `RequestDetailsPage`: the page hands each
  /// section the index its first match has, so counting the sections
  /// differently here would make [currentMatchIndex] point at a match the page
  /// never highlights.
  void _updateTotalMatches() {
    final request = _selectedRequest;
    if (_searchQuery.isEmpty || request == null) {
      _totalMatches = 0;
      _currentMatchIndex = -1;
      return;
    }

    var count = SearchHelper.countMatches(
      text: _timeAndUrlText(request),
      query: _searchQuery,
    );

    for (final section in [
      request.headers,
      request.queryParameters,
      request.requestBody,
      request.graphqlRequestVars,
      request.responseBody,
    ]) {
      count += SearchHelper.countMatchesInSection(
        data: section,
        query: _searchQuery,
        isTreeView: _isTreeView,
      );
    }

    _totalMatches = count;
    // Keep the highlighted match when the total only grew or shrank around it.
    _currentMatchIndex =
        count == 0 ? -1 : _currentMatchIndex.clamp(0, count - 1);
  }

  /// The text of the first (always plain) section of the details page.
  String _timeAndUrlText(RequestDetails request) {
    final sentTimeText = InspectorHelper.extractTimeText(request.sentTime);
    var text = 'Sent at: $sentTimeText';

    if (request.receivedTime != null) {
      final receivedTimeText =
          InspectorHelper.extractTimeText(request.receivedTime!);
      final durationText = InspectorHelper.calculateDuration(
          request.sentTime, request.receivedTime!);
      text += '\nReceived at: $receivedTimeText\nDuration: $durationText';
    }

    return '$text\n\nURL: ${request.url}';
  }

  void toggleExpandChildren() {
    _expandChildren = !_expandChildren;
    notifyListeners();
  }
}
