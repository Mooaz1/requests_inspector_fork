import 'package:dio/dio.dart';

import '../json_pretty_converter.dart';

class SearchHelper {
  /// Finds the non-overlapping, case-insensitive matches of [query] in [text].
  ///
  /// Matches must not overlap, otherwise the highlighted spans built from them
  /// would repeat the overlapping characters (searching `aa` in `aaaa` would
  /// render `aaaaaa`).
  static List<SearchMatch> findMatches({
    required String text,
    required String query,
  }) {
    if (query.isEmpty || text.isEmpty) {
      return [];
    }

    final searchText = text.toLowerCase();
    final searchQuery = query.toLowerCase();

    final matches = <SearchMatch>[];
    var startIndex = 0;

    while (true) {
      final index = searchText.indexOf(searchQuery, startIndex);
      if (index == -1) break;

      matches.add(SearchMatch(
        start: index,
        end: index + searchQuery.length,
      ));
      startIndex = index + searchQuery.length;
    }

    return matches;
  }

  static int countMatches({required String text, required String query}) =>
      findMatches(text: text, query: query).length;

  /// The number of matches rendered for one details section (Headers, Request
  /// Body, ...) with the view mode the section is currently rendered with.
  ///
  /// The details page, the JSON tree view and the `InspectorController` must
  /// all agree on this number, otherwise the match indices they exchange point
  /// at different pieces of text.
  static int countMatchesInSection({
    required dynamic data,
    required String query,
    required bool isTreeView,
  }) {
    if (query.isEmpty || data == null) return 0;

    // Mirrors `RequestDetailsPage._buildDataBlock`, which renders nothing for
    // an empty section.
    if ((data is Map || data is String || data is List) && data.isEmpty) {
      return 0;
    }

    return isTreeView
        ? countMatchesInJsonNode(data, query: query)
        : countMatches(text: prettyTextOf(data), query: query);
  }

  /// The text a section is rendered with while the JSON tree view is off.
  static String prettyTextOf(dynamic data) =>
      data == null ? '' : '${JsonPrettyConverter().convert(data)}';

  /// The title the JSON tree view renders for an expandable node.
  static String jsonTreeNodeTitle(String? key) =>
      key != null ? '"$key" : ' : '';

  /// The text the JSON tree view renders for a leaf node.
  static String jsonTreeLeafText(String? key, dynamic value) {
    final String formattedValue;
    if (value is String && (value == '{}' || value == '[]')) {
      formattedValue = value;
    } else if (value is String) {
      formattedValue = '"$value"';
    } else {
      formattedValue = '$value';
    }

    return '${jsonTreeNodeTitle(key)}$formattedValue${key != null ? ',' : ''}';
  }

  /// The text the JSON tree view renders for a file of a [FormData].
  static String jsonTreeFormDataFileText(MultipartFile file) {
    final sizeInMb = file.length ~/ 1024;
    final fileSizeString = '${sizeInMb.toStringAsFixed(1)} kb';
    return '($fileSizeString) - ${file.filename}';
  }

  /// The number of matches the JSON tree view renders for [node], including the
  /// node's own title and all of its descendants.
  ///
  /// Nodes are counted in the same order they are rendered in: a node's title
  /// first, then its children.
  static int countMatchesInJsonNode(
    dynamic node, {
    String? key,
    required String query,
  }) {
    if (query.isEmpty) return 0;

    // Only a `Map<String, dynamic>` is expanded into a node by the tree view,
    // any other map is rendered as a leaf.
    if (node is Map<String, dynamic> && node.isNotEmpty) {
      var count = countMatches(text: jsonTreeNodeTitle(key), query: query);
      for (final entry in node.entries) {
        count += countMatchesInJsonNode(
          entry.value,
          key: entry.key,
          query: query,
        );
      }
      return count;
    }

    if (node is List && node.isNotEmpty) {
      var count = countMatches(text: jsonTreeNodeTitle(key), query: query);
      for (final item in node) {
        count += countMatchesInJsonNode(item, query: query);
      }
      return count;
    }

    if (node is FormData && (node.fields.isNotEmpty || node.files.isNotEmpty)) {
      var count = countMatches(text: jsonTreeNodeTitle(key), query: query);
      for (final field in node.fields) {
        count += countMatchesInJsonNode(
          field.value,
          key: field.key,
          query: query,
        );
      }
      for (final file in node.files) {
        count += countMatchesInJsonNode(
          jsonTreeFormDataFileText(file.value),
          key: file.key,
          query: query,
        );
      }
      return count;
    }

    // Empty containers are rendered as `{}` / `[]` leaves.
    final leafValue = (node is Map<String, dynamic> || node is FormData)
        ? '{}'
        : (node is List ? '[]' : node);

    return countMatches(text: jsonTreeLeafText(key, leafValue), query: query);
  }
}

class SearchMatch {
  final int start;
  final int end;

  SearchMatch({required this.start, required this.end});

  int get length => end - start;

  @override
  String toString() => 'SearchMatch(start: $start, end: $end)';
}
