import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Opens a WebSocket to [wsUrl], subscribes to [sym], and resolves:
///   true  = connected (and, ideally, received a live tick) → /ws works
///   false = failed to connect / errored / closed / timed out
/// Web-only. The live price + guaranteed-win ride this socket, so this is the
/// most important Worker/proxy check.
Future<bool> checkWebSocket(String wsUrl, String sym,
    {Duration timeout = const Duration(seconds: 9)}) {
  final done = Completer<bool>();
  html.WebSocket? ws;
  Timer? overall;
  Timer? afterOpen;
  void finish(bool ok) {
    if (done.isCompleted) return;
    overall?.cancel();
    afterOpen?.cancel();
    try {
      ws?.close();
    } catch (_) {}
    done.complete(ok);
  }

  try {
    ws = html.WebSocket(wsUrl);
    overall = Timer(timeout, () => finish(false));
    ws.onOpen.listen((_) {
      try {
        ws!.send('{"sub":"$sym"}');
      } catch (_) {}
      // Connected. Give it 3s to deliver a live tick; if none, still count the
      // open handshake as success (the market may simply be quiet this second).
      afterOpen = Timer(const Duration(seconds: 3), () => finish(true));
    });
    ws.onMessage.listen((_) => finish(true)); // live tick → definitely working
    ws.onError.listen((_) => finish(false));
    ws.onClose.listen((_) => finish(false));
  } catch (_) {
    finish(false);
  }
  return done.future;
}

/// Open a URL in a new browser tab (for Render / Supabase dashboards).
void openTab(String url) {
  try {
    html.window.open(url, '_blank');
  } catch (_) {}
}

/// Best-effort clear of the browser's Cache Storage + unregister service workers
/// (the "مسح الكاش المحلي" repair). Returns a short human summary.
Future<String> clearWebCaches() async {
  var caches = 0, sws = 0;
  try {
    final c = html.window.caches;
    if (c != null) {
      final keys = await c.keys();
      for (final k in keys) {
        await c.delete(k);
        caches++;
      }
    }
  } catch (_) {}
  try {
    final reg = await html.window.navigator.serviceWorker?.getRegistrations();
    if (reg != null) {
      for (final r in reg) {
        await r.unregister();
        sws++;
      }
    }
  } catch (_) {}
  return 'مسح $caches كاش و $sws service worker';
}
