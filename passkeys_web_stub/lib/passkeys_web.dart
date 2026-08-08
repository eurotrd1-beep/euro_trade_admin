import 'package:passkeys_platform_interface/passkeys_platform_interface.dart';
import 'package:passkeys_platform_interface/types/types.dart';

/// No-op web implementation that OVERRIDES the real `passkeys_web` (which is
/// pulled in transitively by supabase_flutter).
///
/// The real `PasskeysWeb.registerWith()` calls `PasskeyAuthenticator.init()` —
/// a Corbado browser SDK (`bundle.js`) that this app never includes — during
/// plugin registration. That throws `Cannot read properties of undefined
/// (reading 'init')`, which aborts ALL plugin registration and leaves a blank
/// white page.
///
/// This override registers a do-nothing platform instead, so the crash is
/// impossible at the Dart level (no JS, no timing, no cache dependency). The app
/// never uses passkeys, so none of these methods are ever invoked.
class PasskeysWeb extends PasskeysPlatform {
  /// Called by Flutter's generated web_plugin_registrant.dart. No JS → no crash.
  static void registerWith([Object? registrar]) {
    PasskeysPlatform.instance = PasskeysWeb();
  }

  @override
  Future<RegisterResponseType> register(RegisterRequestType request) =>
      throw UnimplementedError('passkeys disabled');

  @override
  Future<AuthenticateResponseType> authenticate(
    AuthenticateRequestType request,
  ) =>
      throw UnimplementedError('passkeys disabled');

  @override
  Future<void> cancelCurrentAuthenticatorOperation() async {}

  @override
  Future<AvailabilityType> getAvailability() =>
      throw UnimplementedError('passkeys disabled');
}
