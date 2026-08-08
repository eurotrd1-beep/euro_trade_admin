// Non-web stub (the admin runs on Flutter Web, but this keeps analyze/compile
// green on other targets).
Future<bool> checkWebSocket(String wsUrl, String sym,
        {Duration timeout = const Duration(seconds: 9)}) async =>
    false;

void openTab(String url) {}

Future<String> clearWebCaches() async => 'غير متاح';
