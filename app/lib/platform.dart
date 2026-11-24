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
        'feed.json?check=${DateTime.now().millisecondsSinceEpoch ~/ 1000}'.toJS,
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
