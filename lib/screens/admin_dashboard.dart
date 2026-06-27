import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../utils/js_bridge.dart';

// Notification plugin instance — initialized once in initState
final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  // Theme styling constants
  static const Color spaceBackground = Color(0xFF030712);
  static const Color cardBgColor = Color(0xFF111827);
  static const Color borderGlow = Color(0xFF1F2937);
  static const Color accentCyan = Color(0xFF06B6D4);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color callGreen    = Color(0xFF10B981);
  static const Color putRed       = Color(0xFFEF4444);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color textPrimary = Color(0xFFF9FAFB);
  static const Color textSecondary = Color(0xFF9CA3AF);

  String _searchQuery = '';
  String _selectedPlatformFilter =
      'all'; // 'all', 'Quotex', 'Pocket Option', 'Expert Option'
  String _selectedRoleFilter = 'all'; // 'all', 'vip', 'standard'
  int _activeTabIndex = 0;

  // ── Push Notifications state ────────────────────────────────────
  final _pushTitleCtrl   = TextEditingController();
  final _pushBodyCtrl    = TextEditingController();
  final _pushSaJsonCtrl  = TextEditingController();
  bool _pushSending      = false;
  String _pushStatusMsg  = '';
  bool _pushStatusOk     = false;

  // ── New user live alerts ─────────────────────────────────────────
  StreamSubscription<QuerySnapshot>? _newUserSubscription;
  final List<Map<String, dynamic>> _liveNewUsers = [];
  OverlayEntry? _newUserOverlay;

  // Controllers for Global VIP
  final _globalVipValueController = TextEditingController(text: '30');
  String _globalVipUnit = 'days';

  // ── Broker Management state ─────────────────────────────────────
  final _brNameCtrl     = TextEditingController();
  final _brLogoCtrl     = TextEditingController();
  final _brLinkCtrl     = TextEditingController();
  final _brChartUrlCtrl = TextEditingController(); // trading page URL for OTC scraper
  final _brPromoCtrl    = TextEditingController();
  final _brBonusCtrl    = TextEditingController(text: '0');
  final _brMinDepCtrl   = TextEditingController(text: '0');
  final _brOrderCtrl    = TextEditingController(text: '1');
  final _brClickKeyCtrl = TextEditingController();
  bool _brIsRecommended = false;
  bool _brIsActive      = true;
  String? _editingBrokerId;
  String _brLogoPreview = '';
  Color _brThemeColor   = const Color(0xFF06B6D4);
  final _brColorCtrl    = TextEditingController();

  // ── App Update state ────────────────────────────────────────────
  final _updVersionCtrl  = TextEditingController();
  final _updFeaturesCtrl = TextEditingController();
  final _updLinkCtrl     = TextEditingController();
  bool _updIsForced      = false;

  // ── App Control / Maintenance state ─────────────────────────────
  final _maintMsgCtrl   = TextEditingController(text: 'التطبيق متوقف مؤقتاً للصيانة، سنعود قريباً');
  final _maintHoursCtrl = TextEditingController(text: '2');

  // ── Pairs management (TradingView pairs only — OTC is auto-detected by scraper)
  void _showAddPairDialog() {
    final symCtrl      = TextEditingController();
    final chartSymCtrl = TextEditingController();
    final labelCtrl    = TextEditingController();
    String selCategory = 'forex';

    const categories = ['forex', 'metals', 'commodities', 'crypto'];
    const catLabels  = {'forex': 'فوركس', 'metals': 'معادن', 'commodities': 'سلع', 'crypto': 'كريبتو'};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, dlgSet) => AlertDialog(
          backgroundColor: cardBgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('إضافة زوج (TradingView)',
              style: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _pairField(symCtrl, 'اسم الزوج (للعرض)', 'EUR/USD', Icons.label_rounded),
                const SizedBox(height: 10),
                _pairField(chartSymCtrl, 'رمز الشارت', 'EURUSD', Icons.show_chart_rounded),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '✅ بدون exchange: EURUSD / XAUUSD (OANDA تلقائياً)\n'
                    '✅ بـ exchange: OANDA:XAUUSD / TVC:GOLD / FXCM:EURUSD',
                    style: GoogleFonts.outfit(fontSize: 10, color: callGreen, height: 1.5),
                  ),
                ),
                const SizedBox(height: 10),
                _pairField(labelCtrl, 'تصنيف فرعي (اختياري)', 'OANDA / futures', Icons.tag_rounded),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: spaceBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderGlow),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selCategory,
                      isExpanded: true,
                      dropdownColor: cardBgColor,
                      style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
                      items: categories.map((c) => DropdownMenuItem(
                        value: c, child: Text(catLabels[c]!),
                      )).toList(),
                      onChanged: (v) { if (v != null) dlgSet(() => selCategory = v); },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.outfit(color: textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accentCyan, foregroundColor: spaceBackground),
              onPressed: () {
                final sym      = symCtrl.text.trim();
                final chartSym = chartSymCtrl.text.trim().toUpperCase();
                if (sym.isEmpty || chartSym.isEmpty) return;
                FirebaseFirestore.instance.collection('pairs').add({
                  'symbol':      sym,
                  'chartSymbol': chartSym,
                  'category':    selCategory,
                  'type':        selCategory,
                  'label':       labelCtrl.text.trim(),
                  'order':       DateTime.now().millisecondsSinceEpoch,
                });
                Navigator.pop(ctx);
              },
              child: Text('إضافة', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pairField(TextEditingController ctrl, String label, String hint, IconData icon) {
    return TextField(
      controller: ctrl,
      style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 12),
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: textSecondary.withAlpha(100), fontSize: 11),
        prefixIcon: Icon(icon, color: textSecondary, size: 18),
        filled: true, fillColor: spaceBackground,
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderGlow)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderGlow)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentCyan)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildPairsSection() {
    const catLabels = {
      'forex': 'فوركس', 'otc': 'OTC',
      'metals': 'معادن', 'commodities': 'سلع', 'crypto': 'كريبتو',
    };
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('pairs').orderBy('order').snapshots(),
      builder: (context, snap) {
        final pairs = snap.hasData
            ? snap.data!.docs.map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>}).toList()
            : <Map<String, dynamic>>[];

        return Container(
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderGlow),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentCyan.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.currency_exchange_rounded, color: accentCyan, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('أزواج التداول',
                              style: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('${pairs.length} زوج',
                              style: GoogleFonts.outfit(color: textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentCyan, foregroundColor: spaceBackground,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text('إضافة زوج', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: _showAddPairDialog,
                    ),
                  ],
                ),
              ),
              if (pairs.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text('لا توجد أزواج بعد — اضغط إضافة زوج للبدء',
                      style: GoogleFonts.outfit(color: textSecondary, fontSize: 12)),
                )
              else ...[
                const Divider(height: 1, color: Color(0xFF1F2937)),
                ...['forex', 'otc', 'metals', 'commodities', 'crypto'].expand((cat) {
                  final catPairs = pairs.where((p) => p['category'] == cat).toList();
                  if (catPairs.isEmpty) return <Widget>[];
                  return [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                      child: Text(catLabels[cat] ?? cat,
                          style: GoogleFonts.outfit(color: textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    ...catPairs.map((pair) => ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      title: Row(
                        children: [
                          Text(pair['symbol'] as String? ?? '',
                              style: GoogleFonts.outfit(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                          if ((pair['label'] as String? ?? '').isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: accentBlue.withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: accentBlue.withAlpha(80)),
                              ),
                              child: Text(pair['label'] as String,
                                  style: GoogleFonts.outfit(color: accentBlue, fontSize: 9, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(pair['chartSymbol'] as String? ?? '',
                          style: GoogleFonts.outfit(color: textSecondary, fontSize: 10)),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline_rounded, color: putRed, size: 18),
                        onPressed: () => FirebaseFirestore.instance
                            .collection('pairs')
                            .doc(pair['id'] as String)
                            .delete(),
                      ),
                    )),
                  ];
                }),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }

  // Helper to calculate VIP Duration from a unit and value
  Duration _calculateVipDuration(String unit, int value) {
    switch (unit) {
      case 'months':
        return Duration(days: value * 30);
      case 'days':
        return Duration(days: value);
      case 'hours':
        return Duration(hours: value);
      case 'minutes':
        return Duration(minutes: value);
      default:
        return Duration(days: value);
    }
  }

  String _unitLabel(String unit) {
    switch (unit) {
      case 'months':
        return 'شهور';
      case 'days':
        return 'أيام';
      case 'hours':
        return 'ساعات';
      case 'minutes':
        return 'دقائق';
      default:
        return unit;
    }
  }

  @override
  void initState() {
    super.initState();
    _initAdminFcm();
    _startNewUserListener();
    _loadFcmCredentials();
  }

  Future<void> _initAdminFcm() async {
    try {
      if (!kIsWeb) {
        // Android only: init local notifications + create channel
        const android = AndroidInitializationSettings('@mipmap/ic_launcher');
        await _localNotif.initialize(
          const InitializationSettings(android: android),
        );
        const channel = AndroidNotificationChannel(
          'admin_alerts',
          'تنبيهات الأدمن',
          description: 'إشعارات التسجيل الجديد',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        );
        await _localNotif
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // Web needs VAPID key; Android does not
      final token = kIsWeb
          ? null // web token saving handled separately if VAPID key configured
          : await messaging.getToken();

      if (token != null && token.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('configs')
            .doc('adminFcmToken')
            .set({'token': token, 'updatedAt': FieldValue.serverTimestamp()},
                SetOptions(merge: true));
      }

      if (!kIsWeb) {
        messaging.onTokenRefresh.listen((newToken) {
          FirebaseFirestore.instance
              .collection('configs')
              .doc('adminFcmToken')
              .set(
                  {'token': newToken, 'updatedAt': FieldValue.serverTimestamp()},
                  SetOptions(merge: true));
        });
      }

      // Handle FCM messages arriving while app is in foreground
      FirebaseMessaging.onMessage.listen((msg) {
        final title = msg.notification?.title ?? 'مستخدم جديد';
        final body  = msg.notification?.body  ?? '';
        if (!kIsWeb) _showLocalNotification(title, body);
      });
    } catch (e) {
      debugPrint('Admin FCM init error: $e');
    }
  }

  Future<void> _showLocalNotification(String title, String body) async {
    if (kIsWeb) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'admin_alerts',
        'تنبيهات الأدمن',
        channelDescription: 'إشعارات التسجيل الجديد',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
      ),
    );
    await _localNotif.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
      title,
      body,
      details,
    );
  }

  void _startNewUserListener() {
    final startTime = Timestamp.now();
    _newUserSubscription = FirebaseFirestore.instance
        .collection('users')
        .where('createdAt', isGreaterThan: startTime)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;
          final id     = data['accountId'] as String? ?? change.doc.id;
          final broker = data['broker']    as String? ?? '';
          _onNewUser(id, broker);
        }
      }
    });
  }

  void _onNewUser(String accountId, String broker) {
    _playAdminBeep();
    setState(() {
      _liveNewUsers.insert(0, {
        'accountId': accountId,
        'broker':    broker,
        'time':      DateTime.now(),
      });
      if (_liveNewUsers.length > 50) _liveNewUsers.removeLast();
    });
    _showNewUserBanner(accountId, broker);
  }

  void _playAdminBeep() {
    if (kIsWeb) {
      try {
        jsEval(r'''(function(){try{var C=new(window.AudioContext||window.webkitAudioContext)();function tone(f,s,d){var o=C.createOscillator(),g=C.createGain();o.type="sine";o.frequency.value=f;g.gain.setValueAtTime(0.35,C.currentTime+s);g.gain.exponentialRampToValueAtTime(0.001,C.currentTime+s+d);o.connect(g);g.connect(C.destination);o.start(C.currentTime+s);o.stop(C.currentTime+s+d+0.01);}tone(880,0,0.12);tone(1100,0.15,0.18);}catch(e){}})();''');
      } catch (_) {}
    } else {
      // Android: show heads-up notification which plays system alert sound
      _showLocalNotification('🔔 مستخدم جديد!', 'تحقق من قائمة المستخدمين الجديدة');
    }
  }

  void _showNewUserBanner(String accountId, String broker) {
    _newUserOverlay?.remove();
    _newUserOverlay = null;
    if (!mounted) return;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: callGreen.withAlpha(180), width: 1.5),
                boxShadow: [BoxShadow(color: callGreen.withAlpha(40), blurRadius: 20)],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: callGreen.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_add_rounded, color: callGreen, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('مستخدم جديد سجّل! 🎉',
                            style: GoogleFonts.outfit(
                                color: callGreen, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text('ID: $accountId',
                            style: GoogleFonts.outfit(color: textPrimary, fontSize: 11)),
                        Text(broker,
                            style: GoogleFonts.outfit(color: textSecondary, fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    _newUserOverlay = entry;
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 5), () {
      entry.remove();
      if (_newUserOverlay == entry) _newUserOverlay = null;
    });
  }

  Future<void> _loadFcmCredentials() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('configs').doc('fcm').get();
      if (doc.exists) {
        final email = doc.data()?['clientEmail'] as String? ?? '';
        if (email.isNotEmpty && mounted) {
          setState(() => _pushSaJsonCtrl.text = '✅ بيانات محفوظة: $email');
        }
      }
    } catch (_) {}
  }

  Future<void> _saveFcmCredentials() async {
    final raw = _pushSaJsonCtrl.text.trim();
    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final email   = parsed['client_email']  as String? ?? '';
      final key     = parsed['private_key']   as String? ?? '';
      final project = parsed['project_id']    as String? ?? '';
      if (email.isEmpty || key.isEmpty || project.isEmpty) {
        setState(() { _pushStatusMsg = 'ملف JSON غير صحيح أو ناقص'; _pushStatusOk = false; });
        return;
      }
      await FirebaseFirestore.instance.collection('configs').doc('fcm')
          .set({'clientEmail': email, 'privateKey': key, 'projectId': project},
               SetOptions(merge: true));
      setState(() {
        _pushStatusMsg = '✅ تم حفظ بيانات Service Account';
        _pushStatusOk  = true;
        _pushSaJsonCtrl.text = '✅ بيانات محفوظة: $email';
      });
    } catch (e) {
      setState(() { _pushStatusMsg = 'ملف JSON غير صحيح: $e'; _pushStatusOk = false; });
    }
  }

  Future<String> _getFcmAccessToken(String clientEmail, String privateKey) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final jwt = JWT({
      'iss':   clientEmail,
      'scope': 'https://www.googleapis.com/auth/firebase.messaging',
      'aud':   'https://oauth2.googleapis.com/token',
      'iat':   now,
      'exp':   now + 3600,
    });
    final signed = jwt.sign(RSAPrivateKey(privateKey), algorithm: JWTAlgorithm.RS256);
    final res = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=$signed',
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final token = data['access_token'] as String?;
    if (token == null) throw Exception('فشل الحصول على access token: ${res.body}');
    return token;
  }

  Future<void> _sendPushNotification() async {
    final title = _pushTitleCtrl.text.trim();
    final body  = _pushBodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(() { _pushStatusMsg = 'أدخل العنوان والنص أولاً'; _pushStatusOk = false; });
      return;
    }
    setState(() { _pushSending = true; _pushStatusMsg = ''; });
    try {
      final doc = await FirebaseFirestore.instance.collection('configs').doc('fcm').get();
      final clientEmail = doc.data()?['clientEmail'] as String? ?? '';
      final privateKey  = doc.data()?['privateKey']  as String? ?? '';
      final projectId   = doc.data()?['projectId']   as String? ?? '';
      if (clientEmail.isEmpty || privateKey.isEmpty || projectId.isEmpty) {
        setState(() { _pushStatusMsg = 'الصق Service Account JSON واحفظه أولاً'; _pushStatusOk = false; _pushSending = false; });
        return;
      }

      final accessToken = await _getFcmAccessToken(clientEmail, privateKey);

      final users = await FirebaseFirestore.instance.collection('users').get();
      final tokens = users.docs
          .map((d) => d.data()['fcmToken'] as String?)
          .where((t) => t != null && t.isNotEmpty)
          .cast<String>()
          .toList();

      if (tokens.isEmpty) {
        setState(() { _pushStatusMsg = 'لا يوجد مستخدمون لديهم توكن مسجّل'; _pushStatusOk = false; _pushSending = false; });
        return;
      }

      int sent = 0;
      for (final token in tokens) {
        try {
          final res = await http.post(
            Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send'),
            headers: {
              'Content-Type':  'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode({
              'message': {
                'token': token,
                'notification': {'title': title, 'body': body},
                'android': {'priority': 'high'},
                'apns': {'payload': {'aps': {'sound': 'default'}}},
                'data': {'type': 'admin_broadcast'},
              },
            }),
          );
          if (res.statusCode == 200) sent++;
        } catch (_) {}
      }

      setState(() {
        _pushStatusMsg = '✅ تم الإرسال لـ $sent مستخدم من أصل ${tokens.length}';
        _pushStatusOk  = true;
        _pushSending   = false;
      });
      _pushTitleCtrl.clear();
      _pushBodyCtrl.clear();
    } catch (e) {
      setState(() { _pushStatusMsg = 'خطأ: $e'; _pushStatusOk = false; _pushSending = false; });
    }
  }

  @override
  void dispose() {
    _newUserSubscription?.cancel();
    _newUserOverlay?.remove();
    _pushTitleCtrl.dispose();
    _pushBodyCtrl.dispose();
    _pushSaJsonCtrl.dispose();
    _globalVipValueController.dispose();
    _brNameCtrl.dispose();     _brLogoCtrl.dispose();     _brLinkCtrl.dispose();
    _brChartUrlCtrl.dispose(); _brPromoCtrl.dispose();    _brBonusCtrl.dispose();
    _brMinDepCtrl.dispose();   _brOrderCtrl.dispose();    _brClickKeyCtrl.dispose();
    _brColorCtrl.dispose();
    _updVersionCtrl.dispose(); _updFeaturesCtrl.dispose(); _updLinkCtrl.dispose();
    _maintMsgCtrl.dispose(); _maintHoursCtrl.dispose();
    _stdStrategyCtrl.dispose(); _vipStrategyCtrl.dispose();
    super.dispose();
  }

  // Atomically reset device ID
  Future<void> _resetDeviceId(String accountId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(accountId)
          .update({'deviceId': ''});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم مسح معرف الجهاز بنجاح. يمكن للمستخدم التسجيل بجهاز جديد.',
            ),
            backgroundColor: callGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء مسح معرف الجهاز: $e'),
            backgroundColor: putRed,
          ),
        );
      }
    }
  }

  void _showBanDialog(String accountId, bool isBanned, String currentReason) {
    if (isBanned) {
      // Unban immediately
      _toggleBanUser(accountId, false, '');
      return;
    }
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBgColor,
        title: Text('حظر المستخدم $accountId',
            style: GoogleFonts.outfit(color: putRed, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('سيظهر للمستخدم رسالة حظر ولن يتمكن من استخدام التطبيق.',
                style: GoogleFonts.outfit(color: textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'سبب الحظر (اختياري)',
                hintStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 12),
                filled: true, fillColor: spaceBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: putRed)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.outfit(color: textSecondary))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _toggleBanUser(accountId, true, reasonCtrl.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: putRed, foregroundColor: Colors.white),
            child: Text('تأكيد الحظر', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleGuaranteedWin(String accountId, bool enable) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(accountId)
          .update({'guaranteedWin': enable});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(enable
              ? '🛡️ تم تفعيل ضمان الفوز للمستخدم $accountId'
              : '❌ تم إلغاء ضمان الفوز للمستخدم $accountId'),
          backgroundColor: enable ? callGreen : textSecondary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: putRed),
        );
      }
    }
  }

  Future<void> _toggleBanUser(String accountId, bool ban, String reason) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(accountId).update({
        'isBanned': ban,
        'banReason': reason,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ban ? '🚫 تم حظر المستخدم $accountId' : '✅ تم رفع الحظر عن $accountId'),
        backgroundColor: ban ? putRed : callGreen,
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: putRed));
    }
  }

  // Delete user from Firestore
  Future<void> _deleteUser(String accountId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(accountId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف المستخدم بنجاح من قاعدة البيانات.'),
            backgroundColor: callGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء حذف المستخدم: $e'),
            backgroundColor: putRed,
          ),
        );
      }
    }
  }

  // Upgrade/Modify user VIP status with flexible duration
  Future<void> _updateUserVipStatus(
    String accountId,
    bool makeVip, {
    Duration duration = Duration.zero,
    String durationText = '',
  }) async {
    try {
      final expiryDate = makeVip ? DateTime.now().add(duration) : null;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(accountId)
          .update({
            'role': makeVip ? 'vip' : 'standard',
            'vipExpiry': expiryDate != null
                ? Timestamp.fromDate(expiryDate)
                : 0,
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              makeVip
                  ? 'تم تفعيل عضوية VIP بنجاح للمستخدم لمدة $durationText ✅'
                  : 'تم إلغاء عضوية VIP وإرجاع المستخدم للباقة القياسية.',
            ),
            backgroundColor: callGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء تحديث حالة VIP: $e'),
            backgroundColor: putRed,
          ),
        );
      }
    }
  }

  // Activate Global VIP for all existing users + write config for new users
  Future<void> _activateGlobalVipForAll(
    Duration duration,
    String durationText,
  ) async {
    final firestore = FirebaseFirestore.instance;
    final expiryDate = DateTime.now().add(duration);
    final expiryTimestamp = Timestamp.fromDate(expiryDate);

    try {
      // Write global config first so new registrations pick it up immediately
      await firestore.collection('configs').doc('globalVip').set({
        'enabled': true,
        'expiry': expiryTimestamp,
        'durationText': durationText,
        'activatedAt': FieldValue.serverTimestamp(),
      });

      // Batch update all existing users
      final users = await firestore.collection('users').get();
      final batches = <WriteBatch>[];
      WriteBatch batch = firestore.batch();
      int count = 0;

      for (final doc in users.docs) {
        batch.update(doc.reference, {
          'role': 'vip',
          'vipExpiry': expiryTimestamp,
        });
        count++;
        if (count == 499) {
          batches.add(batch);
          batch = firestore.batch();
          count = 0;
        }
      }
      if (count > 0) batches.add(batch);

      for (final b in batches) {
        await b.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تفعيل VIP لجميع المستخدمين (${users.docs.length} مستخدم) لمدة $durationText ✅',
            ),
            backgroundColor: callGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء تفعيل VIP العام: $e'),
            backgroundColor: putRed,
          ),
        );
      }
    }
  }

  // Deactivate global VIP — disables config AND downgrades all users to standard
  Future<void> _deactivateGlobalVip() async {
    final firestore = FirebaseFirestore.instance;
    try {
      // 1. Disable the global config
      await firestore.collection('configs').doc('globalVip').set({
        'enabled': false,
        'disabledAt': FieldValue.serverTimestamp(),
      });

      // 2. Downgrade ALL vip users back to standard in batches of 500
      int downgradedCount = 0;
      QuerySnapshot snapshot;
      do {
        snapshot = await firestore
            .collection('users')
            .where('role', isEqualTo: 'vip')
            .limit(500)
            .get();

        if (snapshot.docs.isEmpty) break;

        final batch = firestore.batch();
        for (final doc in snapshot.docs) {
          batch.update(doc.reference, {
            'role':      'standard',
            'vipExpiry': 0,
          });
        }
        await batch.commit();
        downgradedCount += snapshot.docs.length;
      } while (snapshot.docs.length == 500);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إيقاف VIP العام. تم تحويل $downgradedCount مستخدم إلى standard ✅',
            ),
            backgroundColor: callGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: putRed),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    return Scaffold(
      backgroundColor: spaceBackground,
      appBar: AppBar(
        backgroundColor: cardBgColor,
        elevation: 0,
        title: Row(
          children: [
            const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.amber,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              'EURO TRADE - لوحة تحكم الإدارة 👑',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          // Platform Stats Stream for real-time display in App Bar if screen space is tight
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('clicks')
                .doc('brokers')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const SizedBox();
              }
              final data = snapshot.data!.data() as Map<String, dynamic>?;
              if (data == null) return const SizedBox();

              final quotexClicks = data['quotex'] ?? 0;
              final pocketClicks = data['pocketOption'] ?? 0;
              final expertClicks = data['expertOption'] ?? 0;
              final totalClicks = quotexClicks + pocketClicks + expertClicks;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: accentCyan.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accentCyan.withAlpha(50)),
                    ),
                    child: Text(
                      'إجمالي نقرات المنصات: $totalClicks',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: accentCyan,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            // Left/Sidebar Navigation for Desktop
            if (isDesktop) _buildSidebar(),

            // Main Dashboard Body
            Expanded(
              child: Column(
                children: [
                  // Tab selector for Mobile layout
                  if (!isDesktop) _buildMobileTabSelector(),

                  // Top Summary Cards
                  _buildSummarySection(),

                  // Content view based on active tab
                  Expanded(
                    child: IndexedStack(
                      index: _activeTabIndex,
                      children: [
                        _buildUserDatabaseView(),
                        _buildAnalyticsView(),
                        _buildGlobalVipView(),
                        _buildBrokerManagementView(),
                        _buildAppUpdatesView(),
                        _buildAppControlView(),
                        _buildSiteThemeView(),
                        _buildPushNotificationView(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Color helpers ────────────────────────────────────────────────
  Color _hexToColor(String hex) {
    try {
      final cleaned = hex.replaceAll('#', '').trim();
      if (cleaned.length == 6) return Color(int.parse('FF$cleaned', radix: 16));
    } catch (_) {}
    return accentCyan;
  }

  String _colorToHex(Color color) {
    // ignore: deprecated_member_use
    final hex = color.value.toRadixString(16).padLeft(8, '0');
    return '#${hex.substring(2).toUpperCase()}';
  }

  Widget _buildLogoImage(String url, {BoxFit fit = BoxFit.contain, Widget? placeholder}) {
    final fallback = placeholder ?? const Icon(Icons.storefront_rounded, color: Colors.grey, size: 20);
    if (url.isEmpty) return fallback;
    if (url.startsWith('data:')) {
      try {
        final bytes = base64Decode(url.substring(url.indexOf(',') + 1));
        return Image.memory(bytes, fit: fit,
            errorBuilder: (_, e, s) => fallback);
      } catch (_) {
        return fallback;
      }
    }
    if (url.startsWith('http')) {
      return Image.network(url, fit: fit,
          errorBuilder: (_, e, s) => fallback);
    }
    return Image.asset(url, fit: fit);
  }

  void _showQuickColorPicker(String docId, Color currentColor) {
    Color tempColor = currentColor;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPickerState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: cardBgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: borderGlow),
            ),
            title: Text('لون ثيم المنصة',
                style: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ColorPicker(
                    pickerColor: tempColor,
                    onColorChanged: (c) => setPickerState(() => tempColor = c),
                    enableAlpha: false,
                    hexInputBar: true,
                    labelTypes: const [],
                    pickerAreaHeightPercent: 0.65,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء', style: GoogleFonts.outfit(color: textSecondary)),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await FirebaseFirestore.instance
                      .collection('brokers')
                      .doc(docId)
                      .update({'themeColor': _colorToHex(tempColor)});
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('تم تحديث لون الثيم ✅'),
                      backgroundColor: tempColor,
                    ));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: tempColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('حفظ اللون', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showColorPickerDialog(StateSetter setDlg) {
    Color tempColor = _brThemeColor;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPickerState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: cardBgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: borderGlow),
            ),
            title: Text('اختيار لون الثيم',
                style: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
            content: SingleChildScrollView(
              child: ColorPicker(
                pickerColor: tempColor,
                onColorChanged: (c) => setPickerState(() => tempColor = c),
                enableAlpha: false,
                hexInputBar: true,
                labelTypes: const [],
                pickerAreaHeightPercent: 0.7,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء', style: GoogleFonts.outfit(color: textSecondary)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setDlg(() {
                    _brThemeColor = tempColor;
                    _brColorCtrl.text = _colorToHex(tempColor);
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: tempColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('تأكيد اللون', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Sidebar navigation layout
  Widget _buildSidebar() {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: cardBgColor,
        border: Border(left: BorderSide(color: borderGlow, width: 1.5)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildSidebarNavItem(
            0,
            'المستندات والمستخدمين',
            Icons.people_alt_rounded,
          ),
          _buildSidebarNavItem(
            1,
            'إحصائيات النقرات والروابط',
            Icons.analytics_rounded,
          ),
          _buildSidebarNavItem(
            2,
            'تفعيل VIP العام للكل',
            Icons.auto_awesome_rounded,
          ),
          _buildSidebarNavItem(
            3,
            'إدارة المنصات والروابط',
            Icons.storefront_rounded,
          ),
          _buildSidebarNavItem(
            4,
            'إرسال تحديث التطبيق',
            Icons.system_update_alt_rounded,
          ),
          _buildSidebarNavItem(
            5,
            'تحكم في التطبيق والحظر',
            Icons.admin_panel_settings_rounded,
          ),
          _buildSidebarNavItem(
            6,
            'ثيم الموقع الكامل 🎨',
            Icons.palette_rounded,
          ),
          _buildSidebarNavItem(
            7,
            'إشعارات فورية 🔔',
            Icons.notifications_active_rounded,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'نسخة الآدمن v1.0.0',
              style: GoogleFonts.outfit(fontSize: 10, color: textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem(int index, String label, IconData icon) {
    final isSelected = _activeTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _activeTabIndex = index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isSelected ? accentCyan.withAlpha(20) : Colors.transparent,
          border: Border.all(
            color: isSelected ? accentCyan.withAlpha(100) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? accentCyan : textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? textPrimary : textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mobile Tab selector bar
  Widget _buildMobileTabSelector() {
    return Container(
      color: cardBgColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildMobileTabItem(0, 'المستخدمين'),
            _buildMobileTabItem(1, 'النقرات'),
            _buildMobileTabItem(2, 'VIP عام'),
            _buildMobileTabItem(3, 'المنصات'),
            _buildMobileTabItem(4, 'تحديث'),
            _buildMobileTabItem(5, 'تحكم'),
            _buildMobileTabItem(6, 'الثيم 🎨'),
            _buildMobileTabItem(7, 'إشعارات 🔔'),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileTabItem(int index, String label) {
    final isSelected = _activeTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _activeTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? accentCyan : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? accentCyan : textSecondary,
          ),
        ),
      ),
    );
  }

  // Top summary metrics
  Widget _buildSummarySection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, userSnapshot) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('clicks')
              .doc('brokers')
              .snapshots(),
          builder: (context, clickSnapshot) {
            int totalUsers = 0;
            int vipUsers = 0;
            int standardUsers = 0;

            if (userSnapshot.hasData) {
              totalUsers = userSnapshot.data!.docs.length;
              for (var doc in userSnapshot.data!.docs) {
                final role =
                    (doc.data() as Map<String, dynamic>?)?['role'] ??
                    'standard';
                if (role == 'vip') {
                  vipUsers++;
                } else {
                  standardUsers++;
                }
              }
            }

            int quotexClicks = 0;
            int pocketClicks = 0;
            int expertClicks = 0;
            int quotexLogins = 0;
            int pocketLogins = 0;
            int expertLogins = 0;

            if (clickSnapshot.hasData && clickSnapshot.data!.exists) {
              final data = clickSnapshot.data!.data() as Map<String, dynamic>?;
              if (data != null) {
                quotexClicks = data['quotex'] ?? 0;
                pocketClicks = data['pocketOption'] ?? 0;
                expertClicks = data['expertOption'] ?? 0;
                quotexLogins = data['quotexLogins'] ?? 0;
                pocketLogins = data['pocketOptionLogins'] ?? 0;
                expertLogins = data['expertOptionLogins'] ?? 0;
              }
            }

            final totalClicks = quotexClicks + pocketClicks + expertClicks;
            final totalLogins = quotexLogins + pocketLogins + expertLogins;

            return Container(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildSummaryCard(
                      'إجمالي الأعضاء',
                      '$totalUsers مستخدم',
                      Icons.group_rounded,
                      accentBlue,
                    ),
                    _buildSummaryCard(
                      'أعضاء VIP نشطين',
                      '$vipUsers VIP 👑',
                      Icons.workspace_premium_rounded,
                      Colors.amber,
                    ),
                    _buildSummaryCard(
                      'أعضاء قياسيين (Standard)',
                      '$standardUsers عضو',
                      Icons.person_rounded,
                      textSecondary,
                    ),
                    _buildSummaryCard(
                      'إجمالي نقرات المنصات',
                      '$totalClicks نقرة',
                      Icons.touch_app_rounded,
                      accentCyan,
                    ),
                    _buildSummaryCard(
                      'إجمالي المسجلين الفعليين',
                      '$totalLogins حساب',
                      Icons.how_to_reg_rounded,
                      callGreen,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      width: 180,
      margin: const EdgeInsets.only(left: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderGlow),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 10, color: textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // VIEW 1: User Database management list
  Widget _buildUserDatabaseView() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGlow),
      ),
      child: Column(
        children: [
          // Filter & Search Controls
          _buildFilterControls(),
          const SizedBox(height: 16),

          // User Grid/Table
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: accentCyan),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'لا يوجد مستخدمين مسجلين في قاعدة البيانات حالياً.',
                      style: TextStyle(color: textSecondary),
                    ),
                  );
                }

                // Filtering locally to allow fast real-time search & filter
                final filteredDocs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>?;
                  if (data == null) return false;

                  final accountId = (data['accountId'] ?? '')
                      .toString()
                      .toLowerCase();
                  final broker = (data['broker'] ?? '').toString();
                  final role = (data['role'] ?? 'standard').toString();

                  // Search query filter
                  final matchesSearch = accountId.contains(
                    _searchQuery.toLowerCase(),
                  );

                  // Platform filter
                  final matchesPlatform =
                      _selectedPlatformFilter == 'all' ||
                      broker.toLowerCase().contains(
                        _selectedPlatformFilter.toLowerCase(),
                      );

                  // Role filter
                  final matchesRole =
                      _selectedRoleFilter == 'all' ||
                      role.toLowerCase() == _selectedRoleFilter.toLowerCase();

                  return matchesSearch && matchesPlatform && matchesRole;
                }).toList();

                if (filteredDocs.isEmpty) {
                  return const Center(
                    child: Text(
                      'لا توجد نتائج مطابقة للتصفية الحالية.',
                      style: TextStyle(color: textSecondary),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final data =
                        filteredDocs[index].data() as Map<String, dynamic>;
                    return _buildUserListItem(data);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterControls() {
    return Column(
      children: [
        Row(
          children: [
            // Search Input
            Expanded(
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: spaceBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderGlow),
                ),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: textSecondary,
                      size: 18,
                    ),
                    hintText: 'البحث عن طريق معرف حساب العميل (ID)...',
                    hintStyle: GoogleFonts.outfit(
                      color: textSecondary,
                      fontSize: 12,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Platform Filter Dropdown
            Expanded(
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: spaceBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderGlow),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: cardBgColor,
                    value: _selectedPlatformFilter,
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(
                          'جميع المنصات',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Quotex',
                        child: Text(
                          'منصة Quotex',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Pocket',
                        child: Text(
                          'منصة Pocket Option',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Expert',
                        child: Text(
                          'منصة Expert Option',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                    onChanged: (val) =>
                        setState(() => _selectedPlatformFilter = val ?? 'all'),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Role Filter Dropdown
            Expanded(
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: spaceBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderGlow),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: cardBgColor,
                    value: _selectedRoleFilter,
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(
                          'جميع العضويات',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'vip',
                        child: Text(
                          'أعضاء VIP فقط',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'standard',
                        child: Text(
                          'أعضاء قياسيين (Standard) فقط',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                    onChanged: (val) =>
                        setState(() => _selectedRoleFilter = val ?? 'all'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Row card item for each user document
  Widget _buildUserListItem(Map<String, dynamic> user) {
    final accountId = user['accountId'] ?? '----';
    final broker = user['broker'] ?? '----';
    final role = user['role'] ?? 'standard';
    final deviceId = user['deviceId'] ?? '';
    final clickedBroker = user['clickedBroker'] ?? '';
    final isBanned = user['isBanned'] as bool? ?? false;
    final banReason = user['banReason'] as String? ?? '';
    final isGuaranteedWin = user['guaranteedWin'] as bool? ?? false;
    final createdAtData = user['createdAt'];

    String dateStr = '----';
    if (createdAtData is Timestamp) {
      dateStr = DateFormat('yyyy/MM/dd HH:mm').format(createdAtData.toDate());
    }

    final isVip = role == 'vip';

    // Check if referral code matches registered platform
    bool isReferralValid =
        clickedBroker != '' &&
        broker.toString().toLowerCase().contains(
          clickedBroker.toString().toLowerCase().replaceAll(' Option', ''),
        );

    // VIP Expiry display
    String expiryStatusText = '';
    final vipExpiryData = user['vipExpiry'];
    if (isVip && vipExpiryData is Timestamp) {
      final expiryDate = vipExpiryData.toDate();
      final isExpired = expiryDate.isBefore(DateTime.now());
      if (isExpired) {
        expiryStatusText =
            'منتهي الصلاحية ${DateFormat('yyyy/MM/dd').format(expiryDate)} ⚠️';
      } else {
        expiryStatusText =
            'ينتهي: ${DateFormat('yyyy/MM/dd HH:mm').format(expiryDate)}';
      }
    } else if (isVip) {
      expiryStatusText = 'تفعيل دائم';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: spaceBackground.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isBanned ? putRed.withAlpha(120) : borderGlow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // User ID Icon
              CircleAvatar(
                radius: 18,
                backgroundColor: isVip
                    ? Colors.amber.withAlpha(20)
                    : accentBlue.withAlpha(20),
                child: Icon(
                  isVip
                      ? Icons.workspace_premium_rounded
                      : Icons.person_rounded,
                  color: isVip ? Colors.amber : accentBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),

              // ID & Platform Name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'معرف المستخدم: $accountId',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'منصة التداول: $broker',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        color: accentCyan,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Badges
              _buildRoleBadge(isVip, expiryStatusText),
            ],
          ),
          const Divider(color: borderGlow, height: 16),

          // Additional Info Row
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _buildInfoSnippet(
                Icons.devices_rounded,
                'حالة القفل:',
                deviceId != '' ? 'مقفل بجهاز 🔒' : 'مفتوح (جاهز للتسجيل) 🔓',
                deviceId != '' ? Colors.amber : callGreen,
              ),
              _buildInfoSnippet(
                Icons.link_rounded,
                'رابط التنويه:',
                clickedBroker != ''
                    ? 'ضغط على رابط $clickedBroker ${isReferralValid ? '✅ (مطابق)' : '⚠️ (منصة أخرى)'}'
                    : 'سجل مباشرة 🚫 (لم يضغط على الرابط)',
                clickedBroker != ''
                    ? (isReferralValid ? callGreen : putRed)
                    : textSecondary,
              ),
              _buildInfoSnippet(
                Icons.calendar_month_rounded,
                'تاريخ التسجيل:',
                dateStr,
                textSecondary,
              ),
              if (isBanned)
                _buildInfoSnippet(
                  Icons.block_rounded,
                  'محظور:',
                  banReason.isNotEmpty ? banReason : 'بدون سبب',
                  putRed,
                ),
              if (isGuaranteedWin)
                _buildInfoSnippet(
                  Icons.shield_rounded,
                  'ضمان الفوز:',
                  'مفعّل - الإشارات مضمونة 100% ✅',
                  callGreen,
                ),
            ],
          ),

          const SizedBox(height: 12),

          // User Action buttons — 2 per row
          Column(
            children: [
              // Row 1: Guaranteed Win + Ban/Unban
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleGuaranteedWin(accountId, !isGuaranteedWin),
                    icon: Icon(isGuaranteedWin ? Icons.shield_rounded : Icons.shield_outlined, size: 14),
                    label: Text(isGuaranteedWin ? 'ضمان فعال' : 'ضمان الفوز'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isGuaranteedWin ? callGreen : textSecondary,
                      side: BorderSide(color: isGuaranteedWin ? callGreen.withAlpha(180) : borderGlow),
                      backgroundColor: isGuaranteedWin ? callGreen.withAlpha(20) : null,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showBanDialog(accountId, isBanned, banReason),
                    icon: Icon(isBanned ? Icons.lock_open_rounded : Icons.block_rounded, size: 14),
                    label: Text(isBanned ? 'رفع الحظر' : 'حظر المستخدم'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isBanned ? callGreen : putRed,
                      side: BorderSide(color: isBanned ? callGreen.withAlpha(120) : putRed.withAlpha(120)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              // Row 2: VIP + Reset Device
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showVipManagementDialog(accountId, isVip, expiryStatusText),
                    icon: const Icon(Icons.workspace_premium_rounded, size: 14),
                    label: Text(isVip ? 'تعديل الـ VIP' : 'تفعيل VIP 👑'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isVip ? Colors.amber.withAlpha(40) : Colors.amber,
                      foregroundColor: isVip ? Colors.amber : Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                      side: isVip ? const BorderSide(color: Colors.amber) : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: deviceId != '' ? () => _resetDeviceId(accountId) : null,
                    icon: const Icon(Icons.restart_alt_rounded, size: 14),
                    label: const Text('فك قفل الجهاز'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.amberAccent,
                      side: BorderSide(color: deviceId != '' ? Colors.amberAccent.withAlpha(120) : borderGlow),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              // Row 3: Delete (full width)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showDeleteConfirmDialog(accountId),
                  icon: const Icon(Icons.delete_forever_rounded, size: 14),
                  label: const Text('حذف الحساب نهائياً'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: putRed,
                    side: BorderSide(color: putRed.withAlpha(100)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(bool isVip, String expiryText) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isVip ? Colors.amber.withAlpha(20) : textSecondary.withAlpha(10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isVip ? Colors.amber : textSecondary.withAlpha(50),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            isVip ? 'عضو VIP 👑' : 'عضو قياسي STANDARD',
            style: GoogleFonts.outfit(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: isVip ? Colors.amber : textSecondary,
            ),
          ),
          if (isVip && expiryText.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              expiryText,
              style: GoogleFonts.outfit(fontSize: 8, color: textPrimary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoSnippet(
    IconData icon,
    String title,
    String val,
    Color valColor,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: textSecondary, size: 13),
        const SizedBox(width: 4),
        Text(
          title,
          style: GoogleFonts.outfit(fontSize: 10, color: textSecondary),
        ),
        const SizedBox(width: 4),
        Text(
          val,
          style: GoogleFonts.outfit(
            fontSize: 10,
            color: valColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // Dialog to modify VIP settings - flexible duration (months/days/hours/minutes)
  void _showVipManagementDialog(
    String accountId,
    bool isAlreadyVip,
    String currentExpiryText,
  ) {
    String dialogUnit = 'days';
    final dialogValueController = TextEditingController(text: '30');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: cardBgColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: borderGlow),
                ),
                title: Text(
                  'إدارة عضوية الـ VIP للحساب: $accountId',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isAlreadyVip) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: callGreen.withAlpha(15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: callGreen.withAlpha(40)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '✅ الحالة الحالية: الـ VIP نشط حالياً.',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: callGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentExpiryText,
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      Text(
                        'اختر وحدة المدة:',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Unit selector chips
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildUnitChip(
                            setDialogState,
                            dialogUnit,
                            'months',
                            '📅 شهور',
                            (u) => dialogUnit = u,
                          ),
                          _buildUnitChip(
                            setDialogState,
                            dialogUnit,
                            'days',
                            '📆 أيام',
                            (u) => dialogUnit = u,
                          ),
                          _buildUnitChip(
                            setDialogState,
                            dialogUnit,
                            'hours',
                            '🕐 ساعات',
                            (u) => dialogUnit = u,
                          ),
                          _buildUnitChip(
                            setDialogState,
                            dialogUnit,
                            'minutes',
                            '⏱ دقائق',
                            (u) => dialogUnit = u,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Text(
                        'أدخل عدد ${_unitLabel(dialogUnit)}:',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Value input
                      TextFormField(
                        controller: dialogValueController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: spaceBackground,
                          hintText: 'مثال: 30',
                          hintStyle: GoogleFonts.outfit(
                            fontSize: 14,
                            color: textSecondary.withAlpha(80),
                          ),
                          suffixText: _unitLabel(dialogUnit),
                          suffixStyle: GoogleFonts.outfit(
                            fontSize: 12,
                            color: textSecondary,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: borderGlow),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: borderGlow),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Colors.amber,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),

                      // Quick shortcuts
                      const SizedBox(height: 12),
                      Text(
                        'اختصارات سريعة:',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildQuickButton(
                            setDialogState,
                            dialogValueController,
                            () => dialogUnit = 'days',
                            'days',
                            '1 يوم',
                            1,
                          ),
                          _buildQuickButton(
                            setDialogState,
                            dialogValueController,
                            () => dialogUnit = 'days',
                            'days',
                            '7 أيام',
                            7,
                          ),
                          _buildQuickButton(
                            setDialogState,
                            dialogValueController,
                            () => dialogUnit = 'months',
                            'months',
                            '1 شهر',
                            1,
                          ),
                          _buildQuickButton(
                            setDialogState,
                            dialogValueController,
                            () => dialogUnit = 'months',
                            'months',
                            '3 شهور',
                            3,
                          ),
                          _buildQuickButton(
                            setDialogState,
                            dialogValueController,
                            () => dialogUnit = 'hours',
                            'hours',
                            '12 ساعة',
                            12,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  // Cancel
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(color: textSecondary),
                    ),
                  ),

                  // Downgrade standard (only if VIP)
                  if (isAlreadyVip)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _updateUserVipStatus(accountId, false);
                      },
                      child: const Text(
                        'إلغاء الـ VIP وإرجاعه قياسي',
                        style: TextStyle(color: putRed),
                      ),
                    ),

                  // Activate
                  ElevatedButton(
                    onPressed: () {
                      final val =
                          int.tryParse(dialogValueController.text.trim()) ?? 0;
                      if (val <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('يرجى إدخال قيمة صحيحة أكبر من 0'),
                            backgroundColor: putRed,
                          ),
                        );
                        return;
                      }
                      Navigator.pop(context);
                      final dur = _calculateVipDuration(dialogUnit, val);
                      final label = '$val ${_unitLabel(dialogUnit)}';
                      _updateUserVipStatus(
                        accountId,
                        true,
                        duration: dur,
                        durationText: label,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      isAlreadyVip
                          ? 'تحديث وتمديد الاشتراك'
                          : 'تفعيل العضوية VIP 👑',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUnitChip(
    StateSetter setDialogState,
    String currentUnit,
    String unitValue,
    String label,
    Function(String) onSelect,
  ) {
    final isSelected = currentUnit == unitValue;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      backgroundColor: spaceBackground,
      selectedColor: Colors.amber.withAlpha(40),
      labelStyle: GoogleFonts.outfit(
        fontSize: 11,
        color: isSelected ? Colors.amber : textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(color: isSelected ? Colors.amber : borderGlow),
      onSelected: (bool selected) {
        if (selected) {
          setDialogState(() {
            onSelect(unitValue);
          });
        }
      },
    );
  }

  Widget _buildQuickButton(
    StateSetter setDialogState,
    TextEditingController ctrl,
    VoidCallback setUnit,
    String unit,
    String label,
    int value,
  ) {
    return ActionChip(
      label: Text(label),
      backgroundColor: spaceBackground,
      side: const BorderSide(color: borderGlow),
      labelStyle: GoogleFonts.outfit(fontSize: 10, color: accentCyan),
      onPressed: () {
        setDialogState(() {
          setUnit();
          ctrl.text = value.toString();
        });
      },
    );
  }

  void _showDeleteConfirmDialog(String accountId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: cardBgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: borderGlow),
            ),
            title: const Text(
              'تأكيد حذف الحساب ⚠️',
              style: TextStyle(color: putRed),
            ),
            content: Text(
              'هل أنت متأكد من رغبتك في حذف الحساب $accountId نهائياً من النظام؟ لا يمكن التراجع عن هذا الإجراء.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'إلغاء',
                  style: TextStyle(color: textSecondary),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteUser(accountId);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: putRed,
                  foregroundColor: Colors.white,
                ),
                child: const Text('حذف الحساب نهائياً'),
              ),
            ],
          ),
        );
      },
    );
  }

  // VIEW 2: Analytics & conversion performance — fully dynamic
  Widget _buildAnalyticsView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('brokers')
          .orderBy('order')
          .snapshots(),
      builder: (context, brokersSnap) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('clicks')
              .doc('brokers')
              .snapshots(),
          builder: (context, clicksSnap) {
            if (brokersSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: accentCyan));
            }

            final clickData = (clicksSnap.hasData && clicksSnap.data!.exists)
                ? (clicksSnap.data!.data() as Map<String, dynamic>? ?? {})
                : <String, dynamic>{};

            final brokerDocs = brokersSnap.data?.docs ?? [];

            final brokers = brokerDocs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final hex = d['themeColor'] as String? ?? '';
              return {
                'name':     d['name']     as String? ?? '',
                'logoUrl':  d['logoUrl']  as String? ?? '',
                'clickKey': d['clickKey'] as String? ?? '',
                'color':    hex.isNotEmpty ? _hexToColor(hex) : accentCyan,
              };
            }).toList();

            // Totals across all brokers
            int totalClicks  = 0;
            int totalLogins  = 0;
            for (final b in brokers) {
              final key = b['clickKey'] as String;
              totalClicks += (clickData[key]             as int? ?? 0);
              totalLogins += (clickData['${key}Logins']  as int? ?? 0);
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('تحليلات روابط الشراكة ومعدلات التحويل',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: accentCyan.withAlpha(10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accentCyan.withAlpha(50)),
                    ),
                    child: Text(
                      'إجمالي النقرات: $totalClicks  |  إجمالي التسجيلات: $totalLogins',
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: accentCyan),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  ...brokers.asMap().entries.expand((entry) {
                    final i = entry.key;
                    final b = entry.value;
                    final key    = b['clickKey'] as String;
                    final clicks = clickData[key]            as int? ?? 0;
                    final logins = clickData['${key}Logins'] as int? ?? 0;
                    return [
                      if (i > 0) const SizedBox(height: 16),
                      _buildBrokerAnalyticRow(
                        b['name']    as String,
                        clicks,
                        logins,
                        b['logoUrl'] as String,
                        b['color']   as Color,
                      ),
                    ];
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBrokerAnalyticRow(
    String name,
    int clicks,
    int logins,
    String logoPath,
    Color accentColor,
  ) {
    final double conversionRate = clicks > 0 ? (logins / clicks * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGlow),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _buildLogoImage(logoPath),
              ),
              const SizedBox(width: 12),
              Text(
                name,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accentColor.withAlpha(60)),
                ),
                child: Text(
                  'معدل التحويل: ${conversionRate.toStringAsFixed(1)}%',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: borderGlow, height: 24),
          Row(
            children: [
              // Clicks metric
              Expanded(
                child: _buildMetricSnippet(
                  'إجمالي النقرات على اللينك 🔗',
                  '$clicks نقرة',
                  accentColor,
                ),
              ),
              Container(width: 1.5, height: 40, color: borderGlow),
              // Registrations metric
              Expanded(
                child: _buildMetricSnippet(
                  'المسجلين الفعليين بالتطبيق 👤',
                  '$logins مستخدم',
                  callGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricSnippet(String title, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(fontSize: 10, color: textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // VIEW 3: Global VIP control panel
  Widget _buildGlobalVipView() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('configs')
          .doc('globalVip')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.hasData && snapshot.data!.exists
            ? snapshot.data!.data() as Map<String, dynamic>?
            : null;
        final isGlobalVipEnabled = data?['enabled'] == true;
        final globalExpiry = data?['expiry'];
        final durationText = data?['durationText'] ?? '';

        String statusText = '';
        bool isExpired = false;
        if (isGlobalVipEnabled && globalExpiry is Timestamp) {
          final expiryDate = globalExpiry.toDate();
          if (expiryDate.isBefore(DateTime.now())) {
            statusText =
                'انتهت صلاحية VIP العام في ${DateFormat('yyyy/MM/dd HH:mm').format(expiryDate)} ⚠️';
            isExpired = true;
          } else {
            statusText =
                'ينتهي في: ${DateFormat('yyyy/MM/dd HH:mm').format(expiryDate)}';
          }
        }

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: 560,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isGlobalVipEnabled && !isExpired
                      ? Colors.amber.withAlpha(120)
                      : borderGlow,
                  width: isGlobalVipEnabled && !isExpired ? 1.5 : 1,
                ),
              ),
              child: StatefulBuilder(
                builder: (context, setLocalState) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.withAlpha(20),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.amber,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تفعيل VIP العام للجميع 👑',
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: textPrimary,
                                  ),
                                ),
                                Text(
                                  'يشمل المستخدمين الحاليين والجدد عند التسجيل',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Current status card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isGlobalVipEnabled && !isExpired
                              ? callGreen.withAlpha(15)
                              : isExpired
                              ? putRed.withAlpha(15)
                              : spaceBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isGlobalVipEnabled && !isExpired
                                ? callGreen.withAlpha(60)
                                : isExpired
                                ? putRed.withAlpha(60)
                                : borderGlow,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isGlobalVipEnabled && !isExpired
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              color: isGlobalVipEnabled && !isExpired
                                  ? callGreen
                                  : isExpired
                                  ? putRed
                                  : textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isGlobalVipEnabled && !isExpired
                                        ? 'VIP العام مفعّل حالياً'
                                        : isExpired
                                        ? 'VIP العام منتهي الصلاحية'
                                        : 'VIP العام غير مفعّل',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isGlobalVipEnabled && !isExpired
                                          ? callGreen
                                          : isExpired
                                          ? putRed
                                          : textSecondary,
                                    ),
                                  ),
                                  if (statusText.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      statusText,
                                      style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
                                  if (durationText.isNotEmpty &&
                                      (isGlobalVipEnabled || isExpired)) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'المدة المضبوطة: $durationText',
                                      style: GoogleFonts.outfit(
                                        fontSize: 10,
                                        color: accentCyan,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Duration picker
                      Text(
                        'اختر وحدة المدة:',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildUnitChip(
                            setLocalState,
                            _globalVipUnit,
                            'months',
                            '📅 شهور',
                            (u) => _globalVipUnit = u,
                          ),
                          _buildUnitChip(
                            setLocalState,
                            _globalVipUnit,
                            'days',
                            '📆 أيام',
                            (u) => _globalVipUnit = u,
                          ),
                          _buildUnitChip(
                            setLocalState,
                            _globalVipUnit,
                            'hours',
                            '🕐 ساعات',
                            (u) => _globalVipUnit = u,
                          ),
                          _buildUnitChip(
                            setLocalState,
                            _globalVipUnit,
                            'minutes',
                            '⏱ دقائق',
                            (u) => _globalVipUnit = u,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Text(
                        'أدخل عدد ${_unitLabel(_globalVipUnit)}:',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),

                      TextFormField(
                        controller: _globalVipValueController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: spaceBackground,
                          hintText: 'مثال: 30',
                          hintStyle: GoogleFonts.outfit(
                            fontSize: 14,
                            color: textSecondary.withAlpha(80),
                          ),
                          suffixText: _unitLabel(_globalVipUnit),
                          suffixStyle: GoogleFonts.outfit(
                            fontSize: 13,
                            color: textSecondary,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: borderGlow),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: borderGlow),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Colors.amber,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      ),

                      // Quick shortcuts
                      const SizedBox(height: 12),
                      Text(
                        'اختصارات سريعة:',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildQuickButton(
                            setLocalState,
                            _globalVipValueController,
                            () => _globalVipUnit = 'days',
                            'days',
                            '1 يوم',
                            1,
                          ),
                          _buildQuickButton(
                            setLocalState,
                            _globalVipValueController,
                            () => _globalVipUnit = 'days',
                            'days',
                            '7 أيام',
                            7,
                          ),
                          _buildQuickButton(
                            setLocalState,
                            _globalVipValueController,
                            () => _globalVipUnit = 'months',
                            'months',
                            '1 شهر',
                            1,
                          ),
                          _buildQuickButton(
                            setLocalState,
                            _globalVipValueController,
                            () => _globalVipUnit = 'months',
                            'months',
                            '3 شهور',
                            3,
                          ),
                          _buildQuickButton(
                            setLocalState,
                            _globalVipValueController,
                            () => _globalVipUnit = 'months',
                            'months',
                            '6 شهور',
                            6,
                          ),
                          _buildQuickButton(
                            setLocalState,
                            _globalVipValueController,
                            () => _globalVipUnit = 'months',
                            'months',
                            '12 شهر',
                            12,
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Action buttons
                      ElevatedButton.icon(
                        onPressed: () {
                          final val =
                              int.tryParse(
                                _globalVipValueController.text.trim(),
                              ) ??
                              0;
                          if (val <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'يرجى إدخال قيمة صحيحة أكبر من 0',
                                ),
                                backgroundColor: putRed,
                              ),
                            );
                            return;
                          }
                          _showGlobalVipConfirmDialog(val);
                        },
                        icon: const Icon(
                          Icons.workspace_premium_rounded,
                          size: 18,
                        ),
                        label: Text(
                          'تفعيل VIP للجميع الآن 👑',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),

                      if (isGlobalVipEnabled && !isExpired) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _showGlobalVipDeactivateDialog(),
                          icon: const Icon(Icons.block_rounded, size: 16),
                          label: Text(
                            'إيقاف VIP العام للمستخدمين الجدد',
                            style: GoogleFonts.outfit(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: putRed,
                            side: BorderSide(color: putRed.withAlpha(120)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _showGlobalVipConfirmDialog(int val) {
    final dur = _calculateVipDuration(_globalVipUnit, val);
    final label = '$val ${_unitLabel(_globalVipUnit)}';

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: cardBgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: borderGlow),
          ),
          title: Text(
            'تأكيد تفعيل VIP العام 👑',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.amber,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هل تريد تفعيل عضوية VIP لمدة $label لـ:',
                style: GoogleFonts.outfit(fontSize: 13, color: textPrimary),
              ),
              const SizedBox(height: 12),
              _buildConfirmPoint(
                'جميع المستخدمين المسجلين حالياً في قاعدة البيانات',
              ),
              _buildConfirmPoint('أي مستخدم جديد سيسجل لاحقاً خلال هذه الفترة'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withAlpha(60)),
                ),
                child: Text(
                  'تاريخ انتهاء VIP: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now().add(dur))}',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'إلغاء',
                style: TextStyle(color: textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _activateGlobalVipForAll(dur, label);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('تفعيل VIP للجميع'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded, color: callGreen, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.outfit(fontSize: 12, color: textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _showGlobalVipDeactivateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: cardBgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: borderGlow),
          ),
          title: const Text('إيقاف VIP العام', style: TextStyle(color: putRed)),
          content: Text(
            'هل تريد إيقاف VIP العام؟\n\nالمستخدمون الجدد بعد الإيقاف سيسجلون كـ standard.\nالمستخدمون الحاليين الـ VIP لن يتأثروا.',
            style: GoogleFonts.outfit(fontSize: 13, color: textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'إلغاء',
                style: TextStyle(color: textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deactivateGlobalVip();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: putRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('إيقاف VIP العام'),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // VIEW 5 — BROKER MANAGEMENT
  // ══════════════════════════════════════════════════════════════════
  Widget _buildBrokerManagementView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('brokers')
          .orderBy('order')
          .snapshots(),
      builder: (context, snap) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('إدارة المنصات والروابط',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
                  ElevatedButton.icon(
                    onPressed: () => _showBrokerDialog(null, null),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text('إضافة منصة جديدة', style: GoogleFonts.outfit(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentCyan,
                      foregroundColor: spaceBackground,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentBlue.withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accentBlue.withAlpha(60)),
                ),
                child: Text(
                  'ℹ️  اللوجو: الصق رابط صورة مباشر (مثال: https://site.com/logo.png)',
                  style: GoogleFonts.outfit(fontSize: 11, color: accentBlue),
                ),
              ),
              const SizedBox(height: 16),
              if (!snap.hasData || snap.data!.docs.isEmpty)
                Center(child: Text('لا توجد منصات مضافة بعد', style: GoogleFonts.outfit(color: textSecondary)))
              else
                ...snap.data!.docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final isActive   = d['isActive'] as bool? ?? true;
                  final isRec     = d['isRecommended'] as bool? ?? false;
                  final logoUrl   = d['logoUrl'] as String? ?? '';
                  final colorHex  = d['themeColor'] as String? ?? '';
                  final cardColor = colorHex.isNotEmpty ? _hexToColor(colorHex) : accentCyan;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isRec ? callGreen.withAlpha(150) : cardColor.withAlpha(100),
                        width: isRec ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _buildLogoImage(logoUrl),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(
                                  width: 8, height: 8,
                                  margin: const EdgeInsets.only(left: 6),
                                  decoration: BoxDecoration(color: cardColor, shape: BoxShape.circle),
                                ),
                                Text(d['name'] ?? '', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: textPrimary)),
                                if (isRec) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: callGreen.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                                    child: Text('مُرشحة', style: GoogleFonts.outfit(fontSize: 10, color: callGreen)),
                                  ),
                                ],
                                if (!isActive) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: putRed.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                                    child: Text('مخفية', style: GoogleFonts.outfit(fontSize: 10, color: putRed)),
                                  ),
                                ],
                              ]),
                              const SizedBox(height: 2),
                              Text(d['registrationLink'] ?? '', style: GoogleFonts.outfit(fontSize: 10, color: textSecondary),
                                  overflow: TextOverflow.ellipsis, maxLines: 1),
                              if ((d['promoCode'] as String? ?? '').isNotEmpty)
                                Text('كود: ${d['promoCode']} | بونص: ${d['bonusPercent']}% على إيداع \$${d['minDeposit']}+',
                                    style: GoogleFonts.outfit(fontSize: 10, color: callGreen)),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: 'تغيير لون الثيم',
                          child: GestureDetector(
                            onTap: () => _showQuickColorPicker(doc.id, cardColor),
                            child: Container(
                              width: 32, height: 32,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: cardColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24, width: 1.5),
                              ),
                              child: const Icon(Icons.palette_rounded, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showBrokerDialog(doc.id, d),
                          icon: const Icon(Icons.edit_rounded, color: accentCyan, size: 20),
                          tooltip: 'تعديل',
                        ),
                        IconButton(
                          onPressed: () => _confirmDeleteBroker(doc.id, d['name'] ?? ''),
                          icon: const Icon(Icons.delete_rounded, color: putRed, size: 20),
                          tooltip: 'حذف',
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  void _showBrokerDialog(String? id, Map<String, dynamic>? data) {
    _editingBrokerId = id;
    if (data != null) {
      _brNameCtrl.text     = data['name']             ?? '';
      _brLogoCtrl.text     = data['logoUrl']           ?? '';
      _brLinkCtrl.text     = data['registrationLink']  ?? '';
      _brChartUrlCtrl.text = data['chartUrl']          ?? '';
      _brPromoCtrl.text    = data['promoCode']         ?? '';
      _brBonusCtrl.text    = (data['bonusPercent']      ?? 0).toString();
      _brMinDepCtrl.text   = (data['minDeposit']        ?? 0).toString();
      _brOrderCtrl.text    = (data['order']             ?? 1).toString();
      _brClickKeyCtrl.text = data['clickKey']           ?? '';
      _brIsRecommended     = data['isRecommended']      ?? false;
      _brIsActive          = data['isActive']           ?? true;
      _brLogoPreview       = data['logoUrl']            ?? '';
      final colorHex       = data['themeColor']         as String? ?? '';
      _brThemeColor        = colorHex.isNotEmpty ? _hexToColor(colorHex) : accentCyan;
      _brColorCtrl.text    = colorHex.isNotEmpty ? colorHex : _colorToHex(accentCyan);
    } else {
      _brNameCtrl.clear();     _brLogoCtrl.clear();     _brLinkCtrl.clear();
      _brChartUrlCtrl.clear(); _brPromoCtrl.clear();
      _brBonusCtrl.text = '0'; _brMinDepCtrl.text = '0';
      _brOrderCtrl.text = '1'; _brClickKeyCtrl.clear();
      _brIsRecommended = false; _brIsActive = true; _brLogoPreview = '';
      _brThemeColor = accentCyan;
      _brColorCtrl.text = _colorToHex(accentCyan);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: cardBgColor,
          title: Text(id == null ? 'إضافة منصة جديدة' : 'تعديل المنصة',
              style: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dlgField(_brNameCtrl, 'اسم المنصة *', Icons.storefront_rounded),

                  // ── Logo section ───────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          // Preview box
                          Container(
                            width: 60, height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderGlow),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: _buildLogoImage(
                                _brLogoPreview,
                                placeholder: const Icon(Icons.image_rounded, color: Colors.grey),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await _pickLogoImage();
                                    setDlg(() {});
                                  },
                                  icon: const Icon(Icons.upload_rounded, size: 16),
                                  label: Text('رفع صورة من الجهاز', style: GoogleFonts.outfit(fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accentBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text('أو الصق رابط URL للصورة أدناه',
                                    style: GoogleFonts.outfit(fontSize: 10, color: textSecondary),
                                    textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _brLogoCtrl,
                          onChanged: (v) => setDlg(() => _brLogoPreview = v.trim()),
                          style: GoogleFonts.outfit(color: textPrimary, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'https://example.com/logo.png',
                            hintStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 11),
                            prefixIcon: const Icon(Icons.link_rounded, color: textSecondary, size: 16),
                            filled: true, fillColor: spaceBackground,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: accentCyan)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Color theme section ────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('لون ثيم المنصة',
                            style: GoogleFonts.outfit(color: textSecondary, fontSize: 12)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => _showColorPickerDialog(setDlg),
                              child: Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: _brThemeColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: borderGlow, width: 1.5),
                                ),
                                child: const Icon(Icons.colorize_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _brColorCtrl,
                                onChanged: (v) {
                                  final c = _hexToColor(v);
                                  setDlg(() => _brThemeColor = c);
                                },
                                style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: '#06B6D4',
                                  hintStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 11),
                                  prefixIcon: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Container(
                                      width: 18, height: 18,
                                      decoration: BoxDecoration(
                                        color: _brThemeColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  filled: true, fillColor: spaceBackground,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _brThemeColor)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _showColorPickerDialog(setDlg),
                              icon: const Icon(Icons.palette_rounded, size: 16),
                              label: Text('اختيار', style: GoogleFonts.outfit(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _brThemeColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  _dlgField(_brLinkCtrl, 'رابط التسجيل *', Icons.link_rounded),

                  // ── OTC Scraper URL ────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Icon(Icons.blur_on_rounded, color: warningOrange, size: 14),
                      const SizedBox(width: 6),
                      Text('إعدادات OTC',
                          style: GoogleFonts.outfit(
                              fontSize: 11, fontWeight: FontWeight.bold, color: warningOrange)),
                    ]),
                  ),
                  _dlgField(_brChartUrlCtrl, 'لينك شارت المنصة (لجلب OTC)', Icons.open_in_browser_rounded),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10, top: 2),
                    child: Text(
                      'مثال: https://pocketoption.com/en/cabinet/demo-quick-high-low/\n'
                      'السيرفر يفتح هذا الرابط ويجلب كل الأزواج التي بجانبها OTC تلقائياً.',
                      style: GoogleFonts.outfit(fontSize: 9.5, color: textSecondary, height: 1.5),
                    ),
                  ),

                  _dlgField(_brClickKeyCtrl,'مفتاح النقرات (بالإنجليزي، مثال: quotex)', Icons.key_rounded),
                  _dlgField(_brPromoCtrl,   'البروموكود (اختياري)', Icons.card_giftcard_rounded),
                  Row(children: [
                    Expanded(child: _dlgField(_brBonusCtrl,  'نسبة البونص %',    Icons.percent_rounded,     isNum: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _dlgField(_brMinDepCtrl, 'حد أدنى إيداع \$', Icons.attach_money_rounded, isNum: true)),
                  ]),
                  _dlgField(_brOrderCtrl, 'ترتيب العرض (1, 2, 3...)', Icons.sort_rounded, isNum: true),
                  const SizedBox(height: 8),
                  Row(children: [
                    Checkbox(
                      value: _brIsRecommended,
                      onChanged: (v) => setDlg(() => _brIsRecommended = v ?? false),
                      activeColor: callGreen,
                    ),
                    Text('منصة مُرشحة', style: GoogleFonts.outfit(color: textPrimary, fontSize: 13)),
                    const SizedBox(width: 20),
                    Checkbox(
                      value: _brIsActive,
                      onChanged: (v) => setDlg(() => _brIsActive = v ?? true),
                      activeColor: accentCyan,
                    ),
                    Text('نشطة / مرئية', style: GoogleFonts.outfit(color: textPrimary, fontSize: 13)),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.outfit(color: textSecondary))),
            ElevatedButton(
              onPressed: () { Navigator.pop(ctx); _saveBroker(); },
              style: ElevatedButton.styleFrom(backgroundColor: accentCyan, foregroundColor: spaceBackground),
              child: Text(id == null ? 'إضافة' : 'حفظ', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dlgField(TextEditingController ctrl, String hint, IconData icon, {bool isNum = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: isNum ? TextInputType.number : TextInputType.url,
        style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 12),
          prefixIcon: Icon(icon, color: textSecondary, size: 18),
          filled: true, fillColor: spaceBackground,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: accentCyan)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  Future<void> _pickLogoImage() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 160,
      maxHeight: 160,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final mimeType = picked.mimeType ?? 'image/jpeg';
    final dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';

    if (mounted) {
      setState(() {
        _brLogoCtrl.text = dataUrl;
        _brLogoPreview   = dataUrl;
      });
    }
  }

  Future<void> _saveBroker() async {
    final name     = _brNameCtrl.text.trim();
    final link     = _brLinkCtrl.text.trim();
    final chartUrl = _brChartUrlCtrl.text.trim();
    if (name.isEmpty || link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الاسم ورابط التسجيل مطلوبان'), backgroundColor: putRed),
      );
      return;
    }
    try {
      final Map<String, dynamic> data = {
        'name':             name,
        'logoUrl':          _brLogoCtrl.text.trim(),
        'registrationLink': link,
        'chartUrl':         chartUrl,
        'promoCode':        _brPromoCtrl.text.trim(),
        'bonusPercent':     int.tryParse(_brBonusCtrl.text) ?? 0,
        'minDeposit':       int.tryParse(_brMinDepCtrl.text) ?? 0,
        'order':            int.tryParse(_brOrderCtrl.text) ?? 1,
        'clickKey':         _brClickKeyCtrl.text.trim().isNotEmpty
            ? _brClickKeyCtrl.text.trim()
            : name.toLowerCase().replaceAll(' ', '_'),
        'isRecommended':    _brIsRecommended,
        'isActive':         _brIsActive,
        'themeColor':       _colorToHex(_brThemeColor),
        'updatedAt':        FieldValue.serverTimestamp(),
      };
      if (_editingBrokerId != null) {
        await FirebaseFirestore.instance.collection('brokers').doc(_editingBrokerId).update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('brokers').add(data);
      }
      // Sync chartUrl to proxy server so scraper starts automatically
      if (chartUrl.isNotEmpty) {
        _syncBrokerToProxy(name, chartUrl).catchError((_) {});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_editingBrokerId != null ? 'تم تحديث المنصة بنجاح ✅' : 'تمت إضافة المنصة بنجاح ✅'),
          backgroundColor: callGreen,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: putRed));
    }
  }

  Future<void> _syncBrokerToProxy(String name, String chartUrl) async {
    try {
      await http.post(
        Uri.parse('https://euro-trade-proxy.onrender.com/api/admin/sync-broker'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'chartUrl': chartUrl}),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  void _confirmDeleteBroker(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBgColor,
        title: Text('حذف منصة $name', style: GoogleFonts.outfit(color: putRed, fontWeight: FontWeight.bold)),
        content: Text('هل أنت متأكد؟ سيتم حذف المنصة نهائياً.', style: GoogleFonts.outfit(color: textPrimary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.outfit(color: textSecondary))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseFirestore.instance.collection('brokers').doc(id).delete();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حذف المنصة'), backgroundColor: putRed));
            },
            style: ElevatedButton.styleFrom(backgroundColor: putRed, foregroundColor: Colors.white),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // VIEW 6 — APP UPDATE NOTIFICATIONS
  // ══════════════════════════════════════════════════════════════════
  Widget _buildAppUpdatesView() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('configs').doc('appUpdate').snapshots(),
      builder: (context, snap) {
        final existing = snap.hasData && snap.data!.exists
            ? snap.data!.data() as Map<String, dynamic>?
            : null;
        final isActive = existing?['hasUpdate'] as bool? ?? false;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('إرسال تحديث للمستخدمين',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
              const SizedBox(height: 8),
              if (isActive)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: callGreen.withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: callGreen.withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: callGreen, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text('✅ يوجد تحديث نشط حالياً — النسخة: ${existing?['version'] ?? ''}',
                          style: GoogleFonts.outfit(color: callGreen, fontSize: 13, fontWeight: FontWeight.bold))),
                      ElevatedButton(
                        onPressed: _clearUpdate,
                        style: ElevatedButton.styleFrom(backgroundColor: putRed, foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                        child: Text('إلغاء التحديث', style: GoogleFonts.outfit(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderGlow),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('إعداد التحديث الجديد', style: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 12),
                    _dlgField(_updVersionCtrl, 'رقم النسخة الجديدة (مثال: 2.1.0)', Icons.new_releases_rounded),
                    _dlgField(_updLinkCtrl, 'رابط التحميل/التحديث', Icons.download_rounded),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: _updFeaturesCtrl,
                        maxLines: 4,
                        style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'المميزات الجديدة (كل ميزة في سطر)',
                          hintStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 12),
                          filled: true, fillColor: spaceBackground,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: accentCyan)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                    ),
                    StatefulBuilder(
                      builder: (ctx, setLocal) => Row(
                        children: [
                          Checkbox(
                            value: _updIsForced,
                            onChanged: (v) { setState(() => _updIsForced = v ?? false); setLocal(() {}); },
                            activeColor: putRed,
                          ),
                          Text('إجباري — لا يمكن تخطيه', style: GoogleFonts.outfit(color: textPrimary, fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _publishUpdate,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: Text('نشر التحديث الآن', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentCyan,
                        foregroundColor: spaceBackground,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _publishUpdate() async {
    final version = _updVersionCtrl.text.trim();
    final link    = _updLinkCtrl.text.trim();
    if (version.isEmpty || link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم النسخة والرابط مطلوبان'), backgroundColor: putRed));
      return;
    }
    final features = _updFeaturesCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    try {
      await FirebaseFirestore.instance.collection('configs').doc('appUpdate').set({
        'hasUpdate':   true,
        'version':     version,
        'features':    features,
        'downloadLink': link,
        'isForced':    _updIsForced,
        'publishedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نشر التحديث بنجاح ✅'), backgroundColor: callGreen));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: putRed));
    }
  }

  Future<void> _clearUpdate() async {
    await FirebaseFirestore.instance.collection('configs').doc('appUpdate').set({'hasUpdate': false});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إلغاء التحديث'), backgroundColor: callGreen));
  }

  // ══════════════════════════════════════════════════════════════════
  // VIEW 7 — APP CONTROL (Maintenance + User Bans overview)
  // ══════════════════════════════════════════════════════════════════
  Widget _buildAppControlView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('تحكم في حالة التطبيق',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
          const SizedBox(height: 16),

          // ── Pairs Management ──────────────────────────────────────
          _buildPairsSection(),
          const SizedBox(height: 16),

          // ── Strategy Upload ───────────────────────────────────────
          _buildStrategyUploadSection(),
          const SizedBox(height: 16),

          // ── App Theme Colors ──────────────────────────────────────
          _buildThemeColorSection(),
          const SizedBox(height: 16),

          // ── Maintenance Mode ──────────────────────────────────────
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('configs').doc('maintenance').snapshots(),
            builder: (context, snap) {
              final d = snap.hasData && snap.data!.exists
                  ? snap.data!.data() as Map<String, dynamic>?
                  : null;
              final isActive = d?['isActive'] as bool? ?? false;
              String endsAtStr = '';
              if (isActive && d?['endsAt'] is Timestamp) {
                final endsAt = (d!['endsAt'] as Timestamp).toDate();
                final remaining = endsAt.difference(DateTime.now());
                if (remaining.isNegative) {
                  endsAtStr = 'انتهت الصيانة (يجب الإيقاف يدوياً)';
                } else {
                  final h = remaining.inHours;
                  final m = remaining.inMinutes % 60;
                  endsAtStr = 'ينتهي خلال: ${h}س ${m}د'; // h and m are single letters — braces needed
                }
              }

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isActive ? putRed.withAlpha(120) : borderGlow),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isActive ? putRed.withAlpha(20) : accentBlue.withAlpha(20),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(isActive ? Icons.construction_rounded : Icons.check_circle_rounded,
                              color: isActive ? putRed : callGreen, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(isActive ? '🔴 التطبيق في وضع الصيانة' : '🟢 التطبيق يعمل بشكل طبيعي',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: textPrimary, fontSize: 14)),
                              if (isActive && endsAtStr.isNotEmpty)
                                Text(endsAtStr, style: GoogleFonts.outfit(fontSize: 11, color: putRed)),
                              if (isActive && d?['message'] != null)
                                Text(d!['message'], style: GoogleFonts.outfit(fontSize: 11, color: textSecondary)),
                            ],
                          ),
                        ),
                        if (isActive)
                          ElevatedButton(
                            onPressed: _deactivateMaintenance,
                            style: ElevatedButton.styleFrom(backgroundColor: callGreen, foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                            child: Text('تشغيل التطبيق', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    if (!isActive) ...[
                      const Divider(color: borderGlow, height: 24),
                      Text('تفعيل وضع الصيانة', style: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _maintHoursCtrl,
                              keyboardType: TextInputType.number,
                              style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'مدة الصيانة بالساعات',
                                hintStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 12),
                                prefixIcon: const Icon(Icons.timer_rounded, color: textSecondary, size: 18),
                                filled: true, fillColor: spaceBackground,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: putRed)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _maintMsgCtrl,
                        style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'رسالة تظهر للمستخدمين',
                          hintStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 12),
                          prefixIcon: const Icon(Icons.message_rounded, color: textSecondary, size: 18),
                          filled: true, fillColor: spaceBackground,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: putRed)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _activateMaintenance,
                        icon: const Icon(Icons.construction_rounded, size: 18),
                        label: Text('إيقاف التطبيق للصيانة', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: putRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // ── Chart Data Source ─────────────────────────────────────
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('configs')
                .doc('chart_settings')
                .snapshots(),
            builder: (context, snap) {
              final d = snap.hasData && snap.data!.exists
                  ? snap.data!.data() as Map<String, dynamic>?
                  : null;
              final currentMode = d?['mode'] as String? ?? 'sim';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accentCyan.withAlpha(80)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accentCyan.withAlpha(20),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.candlestick_chart_rounded,
                              color: accentCyan, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('مصدر بيانات الشارت',
                                  style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      color: textPrimary,
                                      fontSize: 14)),
                              Text(
                                currentMode == 'tv'
                                    ? '🔴 نشط: اسكرابنج TradingView (بيانات حقيقية)'
                                    : '🟢 نشط: محاكي واقعي (بيانات افتراضية)',
                                style: GoogleFonts.outfit(
                                    fontSize: 11, color: textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: borderGlow, height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _chartModeBtn(
                            label: '🤖 محاكي',
                            subtitle: 'بيانات افتراضية واقعية',
                            mode: 'sim',
                            currentMode: currentMode,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _chartModeBtn(
                            label: '📡 اسكرابنج',
                            subtitle: 'بيانات TradingView الحقيقية',
                            mode: 'tv',
                            currentMode: currentMode,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // ── Banned Users overview ─────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderGlow),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المستخدمون المحظورون',
                    style: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text('لإدارة الحظر، اذهب إلى تبويب "المستخدمين" واضغط على زر "حظر" بجانب أي مستخدم.',
                    style: GoogleFonts.outfit(color: textSecondary, fontSize: 11)),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users')
                      .where('isBanned', isEqualTo: true).snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData || snap.data!.docs.isEmpty) {
                      return Text('لا يوجد مستخدمون محظورون حالياً ✅',
                          style: GoogleFonts.outfit(color: callGreen, fontSize: 12));
                    }
                    return Column(
                      children: snap.data!.docs.map((doc) {
                        final d = doc.data() as Map<String, dynamic>;
                        final id = d['accountId'] ?? doc.id;
                        final reason = d['banReason'] as String? ?? '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: putRed.withAlpha(10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: putRed.withAlpha(60)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.block_rounded, color: putRed, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(id.toString(), style: GoogleFonts.outfit(color: textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                                    if (reason.isNotEmpty)
                                      Text(reason, style: GoogleFonts.outfit(color: textSecondary, fontSize: 10)),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () => _toggleBanUser(id.toString(), false, ''),
                                child: Text('رفع الحظر', style: GoogleFonts.outfit(color: callGreen, fontSize: 11)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartModeBtn({
    required String label,
    required String subtitle,
    required String mode,
    required String currentMode,
  }) {
    final isSelected = currentMode == mode;
    final color = mode == 'tv' ? accentCyan : callGreen;
    return GestureDetector(
      onTap: isSelected
          ? null
          : () async {
              await FirebaseFirestore.instance
                  .collection('configs')
                  .doc('chart_settings')
                  .set({'mode': mode}, SetOptions(merge: true));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('تم تفعيل $label للمستخدمين ✅'),
                  backgroundColor: color,
                ));
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(25) : spaceBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : borderGlow,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? color : textSecondary)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style:
                    GoogleFonts.outfit(fontSize: 10, color: textSecondary)),
            if (isSelected) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('مفعّل الآن',
                    style: GoogleFonts.outfit(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  final _stdStrategyCtrl = TextEditingController();
  final _vipStrategyCtrl = TextEditingController();

  Future<void> _uploadStrategy(String role) async {
    final ctrl = role == 'standard' ? _stdStrategyCtrl : _vipStrategyCtrl;
    final raw = ctrl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('الحقل فارغ — الصق محتوى الـ JSON أولاً'),
        backgroundColor: putRed,
      ));
      return;
    }
    try {
      final Map<String, dynamic> json = jsonDecode(raw);
      final docId = role == 'standard' ? 'strategy_standard' : 'strategy_vip';
      await FirebaseFirestore.instance.collection('configs').doc(docId).set(json);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ تم رفع استراتيجية ${role == "standard" ? "Standard" : "VIP"} بنجاح'),
          backgroundColor: callGreen,
        ));
        ctrl.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ خطأ في الـ JSON: $e'),
          backgroundColor: putRed,
        ));
      }
    }
  }

  Widget _buildStrategyUploadSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentCyan.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.auto_graph_rounded, color: accentCyan, size: 18),
            const SizedBox(width: 8),
            Text('استراتيجيات التحليل',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: accentCyan)),
          ]),
          const SizedBox(height: 16),

          // Standard
          Text('استراتيجية Standard',
              style: GoogleFonts.outfit(fontSize: 13, color: textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _stdStrategyCtrl,
            maxLines: 6,
            style: GoogleFonts.outfit(fontSize: 11, color: textPrimary),
            decoration: InputDecoration(
              hintText: 'الصق محتوى ملف JSON للاستراتيجية هنا...',
              hintStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 11),
              filled: true, fillColor: spaceBackground,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: accentCyan)),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _uploadStrategy('standard'),
            icon: const Icon(Icons.upload_rounded, size: 16),
            label: const Text('رفع استراتيجية Standard'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentBlue, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),

          const Divider(color: borderGlow, height: 28),

          // VIP
          Text('استراتيجية VIP',
              style: GoogleFonts.outfit(fontSize: 13, color: Colors.amber, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _vipStrategyCtrl,
            maxLines: 6,
            style: GoogleFonts.outfit(fontSize: 11, color: textPrimary),
            decoration: InputDecoration(
              hintText: 'الصق محتوى ملف JSON للاستراتيجية VIP هنا...',
              hintStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 11),
              filled: true, fillColor: spaceBackground,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderGlow)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.amber.withAlpha(180))),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _uploadStrategy('vip'),
            icon: const Icon(Icons.workspace_premium_rounded, size: 16),
            label: const Text('رفع استراتيجية VIP'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber, foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _activateMaintenance() async {
    final hours = int.tryParse(_maintHoursCtrl.text) ?? 2;
    final msg   = _maintMsgCtrl.text.trim();
    final endsAt = DateTime.now().add(Duration(hours: hours));
    try {
      await FirebaseFirestore.instance.collection('configs').doc('maintenance').set({
        'isActive': true,
        'endsAt':   Timestamp.fromDate(endsAt),
        'message':  msg.isNotEmpty ? msg : 'التطبيق متوقف مؤقتاً للصيانة',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🔴 تم إيقاف التطبيق لمدة $hours ساعة للصيانة'), backgroundColor: putRed));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: putRed));
    }
  }

  Future<void> _deactivateMaintenance() async {
    await FirebaseFirestore.instance.collection('configs').doc('maintenance').set({
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ تم تشغيل التطبيق مجدداً'), backgroundColor: callGreen));
  }

  Widget _buildThemeColorSection() {
    const presets = <Map<String, String>>[
      {'name': 'سماوي + أزرق (افتراضي)', 'primary': '#00FFF0', 'secondary': '#1A8CFF'},
      {'name': 'أخضر + ذهبي',             'primary': '#00FF7F', 'secondary': '#FFAD00'},
      {'name': 'بنفسجي + وردي',           'primary': '#BF5FFF', 'secondary': '#FF5FAA'},
      {'name': 'أحمر + برتقالي',          'primary': '#FF2A6D', 'secondary': '#FF8C00'},
      {'name': 'أبيض + فضي',              'primary': '#FFFFFF', 'secondary': '#B0B8C8'},
      {'name': 'أصفر + ليموني',           'primary': '#FFE600', 'secondary': '#7FFF00'},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderGlow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: accentCyan.withAlpha(20), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.palette_rounded, color: accentCyan, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ثيم ألوان التطبيق',
                    style: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                Text('يُطبَّق على كل المستخدمين عند فتح التطبيق',
                    style: GoogleFonts.outfit(color: textSecondary, fontSize: 10)),
              ],
            )),
          ]),
          const Divider(color: borderGlow, height: 20),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('configs').doc('theme').snapshots(),
            builder: (context, snap) {
              final raw = snap.hasData && snap.data!.exists
                  ? (snap.data!.data() as Map<String, dynamic>? ?? {})
                  : <String, dynamic>{};

              String resolveHex(String key, String fallback) {
                final v = raw[key];
                if (v is String && v.startsWith('#')) return v;
                if (v is int) return '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
                return fallback;
              }

              final primaryHex   = resolveHex('primaryColor',   '#00FFF0');
              final secondaryHex = resolveHex('secondaryColor', '#1A8CFF');
              final primaryColor   = _hexToColor(primaryHex);
              final secondaryColor = _hexToColor(secondaryHex);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current colors row — clickable
                  Row(children: [
                    Text('الثيم الحالي:', style: GoogleFonts.outfit(color: textSecondary, fontSize: 12)),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _showSiteThemeColorPicker('primaryColor', primaryColor),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: primaryColor, shape: BoxShape.circle,
                          border: Border.all(color: Colors.white38, width: 1.5),
                          boxShadow: [BoxShadow(color: primaryColor.withAlpha(120), blurRadius: 6)],
                        ),
                        child: const Icon(Icons.colorize_rounded, color: Colors.white70, size: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _showSiteThemeColorPicker('secondaryColor', secondaryColor),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: secondaryColor, shape: BoxShape.circle,
                          border: Border.all(color: Colors.white38, width: 1.5),
                          boxShadow: [BoxShadow(color: secondaryColor.withAlpha(120), blurRadius: 6)],
                        ),
                        child: const Icon(Icons.colorize_rounded, color: Colors.white70, size: 14),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('$primaryHex  /  $secondaryHex',
                        style: GoogleFonts.outfit(color: textSecondary, fontSize: 11)),
                  ]),
                  const SizedBox(height: 14),
                  Text('ثيمات جاهزة:', style: GoogleFonts.outfit(color: textSecondary, fontSize: 12)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: presets.map((p) {
                      final pp = p['primary']!;
                      final ps = p['secondary']!;
                      final isSelected = primaryHex.toUpperCase() == pp.toUpperCase() &&
                                         secondaryHex.toUpperCase() == ps.toUpperCase();
                      return InkWell(
                        onTap: () => _saveThemeColors(pp, ps),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: isSelected ? accentCyan.withAlpha(18) : spaceBackground,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? accentCyan : borderGlow,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 16, height: 16,
                              decoration: BoxDecoration(color: _hexToColor(pp), shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withAlpha(30), width: 0.5))),
                            const SizedBox(width: 4),
                            Container(width: 16, height: 16,
                              decoration: BoxDecoration(color: _hexToColor(ps), shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withAlpha(30), width: 0.5))),
                            const SizedBox(width: 8),
                            Text(p['name']!,
                                style: GoogleFonts.outfit(
                                  color: isSelected ? accentCyan : textSecondary,
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                )),
                            if (isSelected) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.check_circle_rounded, color: accentCyan, size: 13),
                            ],
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveThemeColors(String primary, String secondary) async {
    try {
      await FirebaseFirestore.instance.collection('configs').doc('theme').set({
        'primaryColor':   primary,
        'secondaryColor': secondary,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ تم حفظ الثيم — يُطبَّق على المستخدمين عند فتح التطبيق',
            style: GoogleFonts.outfit()),
        backgroundColor: callGreen,
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: putRed));
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // VIEW 8 — SITE THEME CONTROL
  // ══════════════════════════════════════════════════════════════════
  Widget _buildSiteThemeView() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('configs').doc('theme').snapshots(),
      builder: (context, snap) {
        final data = snap.hasData && snap.data!.exists
            ? (snap.data!.data() as Map<String, dynamic>? ?? {})
            : <String, dynamic>{};

        String resolveHex(String key, String fallback) {
          final raw = data[key];
          if (raw is String && raw.startsWith('#')) return raw;
          if (raw is int) return '#${(raw & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
          return fallback;
        }

        final entries = [
          ('primaryColor',    'اللون الرئيسي',         resolveHex('primaryColor',    '#06B6D4')),
          ('secondaryColor',  'اللون الثانوي',          resolveHex('secondaryColor',  '#3B82F6')),
          ('backgroundColor', 'لون الخلفية',            resolveHex('backgroundColor', '#030712')),
          ('cardColor',       'لون الكاردات',           resolveHex('cardColor',       '#111827')),
          ('successColor',    'لون الصعود / كول 📈',    resolveHex('successColor',    '#10B981')),
          ('dangerColor',     'لون الهبوط / بوت 📉',    resolveHex('dangerColor',     '#EF4444')),
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: accentCyan.withAlpha(20), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.palette_rounded, color: accentCyan, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ثيم الموقع الكامل',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
                  Text('اضغط على أي دايرة أو زرار "تغيير" — colour wheel + حقل hex',
                      style: GoogleFonts.outfit(fontSize: 11, color: textSecondary)),
                ])),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderGlow),
                ),
                child: Column(
                  children: entries.asMap().entries.map((e) {
                    final i = e.key;
                    final (key, label, hex) = e.value;
                    final color = _hexToColor(hex);
                    return Column(children: [
                      if (i > 0) const Divider(color: borderGlow, height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(children: [
                          GestureDetector(
                            onTap: () => _showSiteThemeColorPicker(key, color),
                            child: Container(
                              width: 48, height: 48,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24, width: 2),
                                boxShadow: [BoxShadow(color: color.withAlpha(100), blurRadius: 10, spreadRadius: 2)],
                              ),
                              child: const Icon(Icons.colorize_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(label, style: GoogleFonts.outfit(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Text(hex, style: GoogleFonts.outfit(color: textSecondary, fontSize: 12)),
                          ])),
                          OutlinedButton.icon(
                            onPressed: () => _showSiteThemeColorPicker(key, color),
                            icon: const Icon(Icons.palette_rounded, size: 14),
                            label: Text('تغيير', style: GoogleFonts.outfit(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: color,
                              side: BorderSide(color: color.withAlpha(180)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ]),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _resetSiteTheme,
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: Text('استعادة الألوان الافتراضية', style: GoogleFonts.outfit(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: textSecondary,
                  side: const BorderSide(color: borderGlow),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSiteThemeColorPicker(String colorKey, Color currentColor) {
    Color tempColor = currentColor;
    final hexCtrl = TextEditingController(text: _colorToHex(currentColor));
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPickerState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: cardBgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: borderGlow),
            ),
            title: Text('اختيار اللون',
                style: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ColorPicker(
                  pickerColor: tempColor,
                  onColorChanged: (c) => setPickerState(() {
                    tempColor = c;
                    hexCtrl.text = _colorToHex(c);
                  }),
                  enableAlpha: false,
                  hexInputBar: false,
                  labelTypes: const [],
                  pickerAreaHeightPercent: 0.6,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hexCtrl,
                  style: GoogleFonts.outfit(color: textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  onChanged: (v) => setPickerState(() => tempColor = _hexToColor(v)),
                  decoration: InputDecoration(
                    hintText: '#06B6D4',
                    hintStyle: GoogleFonts.outfit(color: textSecondary),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: tempColor,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white24),
                        ),
                      ),
                    ),
                    filled: true, fillColor: spaceBackground,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: borderGlow)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: borderGlow)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: tempColor, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () { Navigator.pop(ctx); hexCtrl.dispose(); },
                child: Text('إلغاء', style: GoogleFonts.outfit(color: textSecondary)),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  hexCtrl.dispose();
                  await FirebaseFirestore.instance.collection('configs')
                      .doc('theme')
                      .set({colorKey: _colorToHex(tempColor)}, SetOptions(merge: true));
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('✅ تم حفظ اللون ${_colorToHex(tempColor)}'),
                    backgroundColor: tempColor,
                  ));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: tempColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('حفظ اللون', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resetSiteTheme() async {
    await FirebaseFirestore.instance.collection('configs').doc('theme').set({
      'primaryColor':    '#06B6D4',
      'secondaryColor':  '#3B82F6',
      'backgroundColor': '#030712',
      'cardColor':       '#111827',
      'successColor':    '#10B981',
      'dangerColor':     '#EF4444',
      'updatedAt':       FieldValue.serverTimestamp(),
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ تم استعادة الألوان الافتراضية'), backgroundColor: callGreen));
  }

  // VIEW 8: Push Notifications
  Widget _buildPushNotificationView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.notifications_active_rounded, color: Colors.orange, size: 22),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('إشعارات فورية للمستخدمين',
                  style: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('إرسال push notification لكل المستخدمين المُسجَّلين',
                  style: GoogleFonts.outfit(color: textSecondary, fontSize: 11)),
            ]),
          ]),
          const SizedBox(height: 24),

          // ── Service Account JSON ────────────────────────────────────
          _pushCard(
            title: '🔑 Service Account JSON',
            subtitle: 'الصق محتوى ملف JSON من Firebase Console → Project Settings → Service Accounts',
            child: _inputField(
              controller: _pushSaJsonCtrl,
              hint: '{ "type": "service_account", "project_id": "...", ... }',
              maxLines: 4,
              suffix: TextButton(
                onPressed: _saveFcmCredentials,
                child: Text('حفظ', style: GoogleFonts.outfit(color: accentCyan, fontSize: 12)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Compose Notification ───────────────────────────────────
          _pushCard(
            title: '✍️ إنشاء الإشعار',
            child: Column(children: [
              _inputField(controller: _pushTitleCtrl, hint: 'عنوان الإشعار — مثال: إشارة قوية على EUR/USD 🔥'),
              const SizedBox(height: 10),
              _inputField(
                controller: _pushBodyCtrl,
                hint: 'نص الإشعار — مثال: إشارة CALL لمدة دقيقة واحدة، ادخل الآن!',
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _pushSending ? null : _sendPushNotification,
                  icon: _pushSending
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(_pushSending ? 'جاري الإرسال...' : 'إرسال للجميع',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (_pushStatusMsg.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: (_pushStatusOk ? callGreen : putRed).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: (_pushStatusOk ? callGreen : putRed).withAlpha(80)),
                  ),
                  child: Text(_pushStatusMsg,
                      style: GoogleFonts.outfit(
                          color: _pushStatusOk ? callGreen : putRed, fontSize: 12)),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),

          // ── Live New Users feed ────────────────────────────────────
          _pushCard(
            title: '🟢 تسجيلات مباشرة (منذ فتح الأدمن)',
            child: _liveNewUsers.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('لا يوجد تسجيلات جديدة بعد',
                          style: GoogleFonts.outfit(color: textSecondary, fontSize: 12)),
                    ),
                  )
                : Column(
                    children: _liveNewUsers.take(20).map((u) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        radius: 16, backgroundColor: Color(0xFF1F2937),
                        child: Icon(Icons.person_rounded, size: 16, color: callGreen),
                      ),
                      title: Text('ID: ${u['accountId']}',
                          style: GoogleFonts.outfit(color: textPrimary, fontSize: 12)),
                      subtitle: Text('${u['broker']} — ${DateFormat('HH:mm:ss').format(u['time'] as DateTime)}',
                          style: GoogleFonts.outfit(color: textSecondary, fontSize: 10)),
                      trailing: const Icon(Icons.fiber_new_rounded, color: callGreen, size: 18),
                    )).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _pushCard({required String title, String? subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderGlow),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.outfit(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: GoogleFonts.outfit(color: textSecondary, fontSize: 10)),
        ],
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    int maxLines = 1,
    Widget? suffix,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: spaceBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderGlow),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            obscureText: obscure,
            maxLines: maxLines,
            style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 12),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (suffix != null) suffix,
      ]),
    );
  }

}
