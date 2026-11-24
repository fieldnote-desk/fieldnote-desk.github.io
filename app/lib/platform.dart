import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'model.dart';

String? readPreference(String name) {
  try {
    return web.window.localStorage.getItem(name);
  } catch (_) {
    return null;
  }
}

void writePreference(String name, String value) {
  try {
    web.window.localStorage.setItem(name, value);
  } catch (_) {
    // A private window can disable browser storage.
  }
}

bool get pageIsVisible => !web.document.hidden;

void onVisibilityChange(JSFunction? oldListener, JSFunction? newListener) {
  if (oldListener != null)
    web.document.removeEventListener('visibilitychange', oldListener);
  if (newListener != null)
    web.document.addEventListener('visibilitychange', newListener);
}

Future<Edition> fetchEdition() async {
  final control = web.AbortController();
  final responseFuture = web.window
      .fetch(
        'feed.json'.toJS,
        web.RequestInit(
          cache: 'no-store',
          credentials: 'omit',
          signal: control.signal,
        ),
      )
      .toDart;
  final response = await responseFuture.timeout(
    const Duration(seconds: 15),
    onTimeout: () {
      control.abort();
      throw const FormatException('Edition timed out');
    },
  );
  if (!response.ok) throw FormatException('Edition HTTP ${response.status}');
  final json =
      jsonDecode(
            (await response.text().toDart.timeout(
              const Duration(seconds: 10),
            )).toDart,
          )
          as Json;
  return Edition.fromJson(json);
}

void openLink(Uri link) {
  if (link.scheme != 'https') return;
  web.window.open(link.toString(), '_blank', 'noopener,noreferrer');
}

void saveOffline() {
  final anchor = web.HTMLAnchorElement()
    ..href = 'offline.html'
    ..download = 'fieldnote-offline.html';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
}

Uri googleTranslateLink(Article article) =>
    Uri.https('translate.google.com', '/', {
      'sl': 'auto',
      'tl': 'zh-CN',
      'text': article.translationText,
      'op': 'translate',
    });

@JS('Translator')
external JSObject? get _chromeTranslator;

@JS('Translator.availability')
external JSPromise<JSString> _availability(_LanguagePair options);

@JS('Translator.create')
external JSPromise<_Translator> _createTranslator(_LanguagePair options);

extension type _LanguagePair._(JSObject _) implements JSObject {
  external factory _LanguagePair({
    String sourceLanguage,
    String targetLanguage,
  });
}

extension type _Translator._(JSObject _) implements JSObject {
  external JSPromise<JSString> translate(String text);
  external void destroy();
}

Future<Translation?> translateInChrome(Article article) async {
  if (_chromeTranslator == null || article.lang != 'en') return null;
  final options = _LanguagePair(sourceLanguage: 'en', targetLanguage: 'zh');
  try {
    final availability = (await _availability(options).toDart).toDart;
    if (availability == 'unavailable') return null;
    final translator = await _createTranslator(options).toDart;
    try {
      final title = (await translator.translate(article.title).toDart).toDart;
      final summary = article.summary.isEmpty
          ? ''
          : (await translator.translate(article.summary).toDart).toDart;
      return Translation(title, summary, 'Chrome 内置翻译');
    } finally {
      translator.destroy();
    }
  } catch (_) {
    return null;
  }
}
