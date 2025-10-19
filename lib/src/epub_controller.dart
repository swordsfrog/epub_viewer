import 'dart:async';
import 'dart:convert';

import 'package:flutter_epub_viewer/src/epub_metadata.dart';
import 'package:flutter_epub_viewer/src/helper.dart';
import 'package:flutter_epub_viewer/src/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class EpubController {
  InAppWebViewController? webViewController;

  ///List of chapters from epub
  List<EpubChapter> _chapters = [];

  setWebViewController(InAppWebViewController controller) {
    webViewController = controller;
  }

  ///Move epub view to specific area using Cfi string or chapter href
  display({
    ///Cfi String of the desired location, also accepts chapter href
    required String cfi,
  }) {
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'toCfi("$cfi")');
  }

  ///Moves to next page in epub view
  next() {
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'next()');
  }

  ///Moves to previous page in epub view
  prev() {
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'previous()');
  }

  ///Returns current location of epub viewer
  Future<EpubLocation> getCurrentLocation() async {
    checkEpubLoaded();
    final result = await webViewController?.evaluateJavascript(
        source: 'getCurrentLocation()');

    if (result == null) {
      throw Exception("Epub locations not loaded");
    }

    return EpubLocation.fromJson(result);
  }

  ///Returns list of [EpubChapter] from epub,
  /// should be called after onChaptersLoaded callback, otherwise returns empty list
  List<EpubChapter> getChapters() {
    checkEpubLoaded();
    return _chapters;
  }

  dynamic _normalizeJsValue(dynamic value) {
    if (value == null) return null;

    // If it's a Map with arbitrary key/value types
    if (value is Map) {
      final Map<String, dynamic> out = {};
      value.forEach((k, v) {
        final key = k?.toString() ?? '';
        out[key] = _normalizeJsValue(v);
      });
      return out;
    }

    // If it's a List — normalize its elements recursively
    if (value is List) {
      return value.map((e) => _normalizeJsValue(e)).toList();
    }

    // If it's a String — try parsing JSON (iOS sometimes returns JSON string)
    if (value is String) {
      final trimmed = value.trim();
      if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
          (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
        try {
          final decoded = jsonDecode(trimmed);
          return _normalizeJsValue(decoded);
        } catch (_) {
          // Not JSON — return as is
        }
      }
      return value;
    }

    // Primitive types (num, bool, etc.)
    return value;
  }

  /// Parses chapters from the WebView by calling `getChapters()` JS function.
  /// Automatically handles platform differences between Android and iOS.
  Future<List<EpubChapter>> parseChapters() async {
    // Return cached chapters if already loaded
    if (_chapters.isNotEmpty) return _chapters;

    // Ensure the book is loaded
    checkEpubLoaded();

    dynamic result;
    try {
      // Call JS function in the WebView
      result = await webViewController!.evaluateJavascript(source: 'getChapters()');
    } catch (e, s) {
      debugPrint('❌ evaluateJavascript error: $e\n$s');
      rethrow;
    }

    debugPrint('JS raw result runtimeType: ${result.runtimeType}');

    // Normalize the JS result into Dart-friendly types
    final normalized = _normalizeJsValue(result);
    debugPrint('JS normalized type: ${normalized.runtimeType}');
    // debugPrint('JS normalized sample: $normalized'); // Optional for debugging

    // Convert the normalized result into a List
    List<dynamic> items = [];
    if (normalized is List) {
      items = normalized;
    } else if (normalized is Map && normalized.containsKey('chapters')) {
      // Sometimes JS returns { chapters: [...] }
      final maybe = normalized['chapters'];
      if (maybe is List) items = maybe;
    } else if (normalized == null) {
      items = [];
    } else {
      // Unexpected format — log a warning
      debugPrint('⚠️ Unexpected chapters payload: ${normalized.runtimeType}');
      items = [];
    }

    // Convert each item into EpubChapter
    final List<EpubChapter> chapters = [];
    for (var i = 0; i < items.length; i++) {
      final e = items[i];
      try {
        if (e is Map<String, dynamic>) {
          chapters.add(EpubChapter.fromJson(e));
        } else {
          // If element is still not Map<String,dynamic>, normalize again
          final converted = _normalizeJsValue(e);
          if (converted is Map<String, dynamic>) {
            chapters.add(EpubChapter.fromJson(converted));
          } else {
            debugPrint('⚠️ Skipping chapter #$i — cannot convert to Map: ${converted.runtimeType}');
          }
        }
      } catch (err, st) {
        debugPrint('❌ Error parsing chapter #$i: $err\n$st');
        // Continue parsing other chapters
      }
    }

    // Cache the chapters
    _chapters = chapters;

    return _chapters;
  }

  Future<EpubMetadata> getMetadata() async {
    checkEpubLoaded();
    final result =
        await webViewController!.evaluateJavascript(source: 'getBookInfo()');
    return EpubMetadata.fromJson(result);
  }

  Completer searchResultCompleter = Completer<List<EpubSearchResult>>();

  ///Search in epub using query string
  ///Returns a list of [EpubSearchResult]
  Future<List<EpubSearchResult>> search({
    ///Search query string
    required String query,
    // bool optimized = false,
  }) async {
    searchResultCompleter = Completer<List<EpubSearchResult>>();
    if (query.isEmpty) return [];
    checkEpubLoaded();
    await webViewController?.evaluateJavascript(
        source: 'searchInBook("$query")');
    return await searchResultCompleter.future;
  }

  ///Adds a highlight to epub viewer
  addHighlight({
    ///Cfi string of the desired location
    required String cfi,

    ///Color of the highlight
    Color color = Colors.yellow,

    ///Opacity of the highlight
    double opacity = 0.3,
  }) {
    var colorHex = color.toHex();
    var opacityString = opacity.toString();
    checkEpubLoaded();
    webViewController?.evaluateJavascript(
        source: 'addHighlight("$cfi", "$colorHex", "$opacityString")');
  }

  ///Adds a underline annotation
  addUnderline({required String cfi}) {
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'addUnderLine("$cfi")');
  }

  ///Adds a mark annotation
  // addMark({required String cfi}) {
  //   checkEpubLoaded();
  //   webViewController?.evaluateJavascript(source: 'addMark("$cfi")');
  // }

  ///Removes a highlight from epub viewer
  removeHighlight({required String cfi}) {
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'removeHighlight("$cfi")');
  }

  ///Removes a underline from epub viewer
  removeUnderline({required String cfi}) {
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'removeUnderLine("$cfi")');
  }

  ///Removes a mark from epub viewer
  // removeMark({required String cfi}) {
  //   checkEpubLoaded();
  //   webViewController?.evaluateJavascript(source: 'removeMark("$cfi")');
  // }

  ///Set [EpubSpread] value
  setSpread({required EpubSpread spread}) async {
    await webViewController?.evaluateJavascript(source: 'setSpread("$spread")');
  }

  ///Set [EpubFlow] value
  setFlow({required EpubFlow flow}) async {
    await webViewController?.evaluateJavascript(source: 'setFlow("$flow")');
  }

  ///Set [EpubManager] value
  setManager({required EpubManager manager}) async {
    await webViewController?.evaluateJavascript(
        source: 'setManager("$manager")');
  }

  ///Adjust font size in epub viewer
  setFontSize({required double fontSize}) async {
    await webViewController?.evaluateJavascript(
        source: 'setFontSize("$fontSize")');
  }

  updateTheme({required EpubTheme theme}) async {
    String? backgroundColor = theme.backgroundColor?.toHex();
    String? foregroundColor = theme.foregroundColor?.toHex();
    await webViewController?.evaluateJavascript(
        source: 'updateTheme("$backgroundColor","$foregroundColor")');
  }

  Completer<EpubTextExtractRes> pageTextCompleter =
      Completer<EpubTextExtractRes>();

  ///Extract text from a given cfi range,
  Future<EpubTextExtractRes> extractText({
    ///start cfi
    required startCfi,

    ///end cfi
    required endCfi,
  }) async {
    checkEpubLoaded();
    pageTextCompleter = Completer<EpubTextExtractRes>();
    await webViewController?.evaluateJavascript(
        source: 'getTextFromCfi("$startCfi","$endCfi")');
    return pageTextCompleter.future;
  }

  ///Extracts text content from current page
  Future<EpubTextExtractRes> extractCurrentPageText() async {
    checkEpubLoaded();
    pageTextCompleter = Completer<EpubTextExtractRes>();
    await webViewController?.evaluateJavascript(source: 'getCurrentPageText()');
    return pageTextCompleter.future;
  }

  ///Given a percentage moves to the corresponding page
  ///Progress percentage should be between 0.0 and 1.0
  toProgressPercentage(double progressPercent) {
    assert(progressPercent >= 0.0 && progressPercent <= 1.0,
        'Progress percentage must be between 0.0 and 1.0');
    checkEpubLoaded();
    webViewController?.evaluateJavascript(
        source: 'toProgress($progressPercent)');
  }

  ///Moves to the first page of the epub
  moveToFistPage() {
    toProgressPercentage(0.0);
  }

  ///Moves to the last page of the epub
  moveToLastPage() {
    toProgressPercentage(1.0);
  }

  checkEpubLoaded() {
    if (webViewController == null) {
      throw Exception(
          "Epub viewer is not loaded, wait for onEpubLoaded callback");
    }
  }
}

class LocalServerController {
  final InAppLocalhostServer _localhostServer = InAppLocalhostServer(
      documentRoot: 'packages/flutter_epub_viewer/lib/assets/webpage');

  Future<void> initServer() async {
    if (_localhostServer.isRunning()) return;
    await _localhostServer.start();
  }

  Future<void> disposeServer() async {
    if (!_localhostServer.isRunning()) return;
    await _localhostServer.close();
  }
}
