// Conditional export: real web implementation on Flutter Web, no-op stub elsewhere
// (so the app still compiles/analyzes on non-web targets).
export 'repair_web_stub.dart' if (dart.library.html) 'repair_web_impl.dart';
