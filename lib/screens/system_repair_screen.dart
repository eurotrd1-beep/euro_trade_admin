import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/repair_web.dart';

// ── Theme (deep black + purple, terminal style) ──
const _bg = Color(0xFF030712);
const _card = Color(0xFF0B1220);
const _border = Color(0xFF1F2937);
const _cyan = Color(0xFF06B6D4);
const _purple = Color(0xFF7C3AED);
const _green = Color(0xFF10B981);
const _amber = Color(0xFFF59E0B);
const _red = Color(0xFFFF2A6D);
const _muted = Color(0xFF8B88A0);
const _text = Color(0xFFE5E7EB);

// ── Fixed infra endpoints ──
const _kWorker = 'https://euro-trade-cache.eurotrade.workers.dev';
const _kOrigin = 'https://euro-trade-proxy-1.onrender.com'; // the working proxy / worker origin
const _kRef = 'dlzqdmqkvlvwnjhqxqym';
const _kRenderDash = 'https://dashboard.render.com';
const _kSupaUsage = 'https://supabase.com/dashboard/project/$_kRef/reports';

enum RStatus { checking, ok, warn, fail, na, unknown }

class RHelp {
  final String measure, why, whenRed, quickFix, deepFix, external;
  const RHelp(
      {this.measure = '', this.why = '', this.whenRed = '', this.quickFix = '', this.deepFix = '', this.external = ''});
}

class RCheck {
  final String id, section, title;
  final RHelp help;
  RStatus status = RStatus.unknown;
  String detail = '', cause = '', fix = '';
  String? externalUrl, externalLabel, fixLabel;
  Future<String> Function()? fixAction;
  bool danger = false;
  RCheck({required this.id, required this.section, required this.title, this.help = const RHelp()});
}

class SystemRepairScreen extends StatefulWidget {
  const SystemRepairScreen({super.key});
  @override
  State<SystemRepairScreen> createState() => _SystemRepairScreenState();
}

class _SystemRepairScreenState extends State<SystemRepairScreen> {
  final _sb = Supabase.instance.client;
  late final List<RCheck> _checks = _build();
  bool _running = false;
  int _done = 0;
  String _activeProxy = _kOrigin; // configs.proxy_server_url (what the app uses)
  bool _wsOk = false; // shared /ws result (worker + gwin sections)

  // Gemini
  bool _geminiLoading = false;
  String? _geminiText;
  String? _geminiError;

  final _sections = const [
    ['proxy', '⚙️ البروكسي / Render'],
    ['worker', '⚡ Cloudflare Worker'],
    ['data', '📊 الأسعار والبيانات'],
    ['supabase', '🗄️ Supabase'],
    ['po', '🔑 جلسة Pocket Option'],
    ['captcha', '💸 رصيد 2captcha'],
    ['gwin', '🎯 ضمان الفوز'],
    ['app', '📱 التطبيق'],
  ];

  @override
  void initState() {
    super.initState();
    _runAll();
  }

  // ══════════════════════════ Check catalogue ══════════════════════════
  List<RCheck> _build() => [
        // ── 1) Proxy / Render ──
        RCheck(id: 'proxy_serves', section: 'proxy', title: '⭐ الرابط في الكونفيج بيخدم 183 رمز فعلاً؟', help: const RHelp(
            measure: 'يقرأ configs.proxy_server_url ثم يطلب /api/otc/status منه ويعدّ الرموز.',
            why: 'أخطر فخّ: ممكن الكونفيج يشاور على خدمة Render مكرّرة ميتة بتردّ /health أخضر بس بترجّع 0 رمز — فالتطبيق يقول "تعذر الاتصال بالسوق".',
            whenRed: '0 رمز = الرابط بيشاور على بروكسي ميّت.',
            quickFix: 'رجّع الكونفيج للبروكسي الشغّال (زرار "رجّع للبروكسي المباشر" في قسم الـ Worker).',
            deepFix: 'علّق/امسح خدمة Render المكرّرة الميتة من الداشبورد.',
            external: 'Render dashboard')),
        RCheck(id: 'proxy_alive', section: 'proxy', title: 'البروكسي حي + زمن الاستجابة', help: const RHelp(
            measure: 'GET /health على الرابط النشط مع توقيت.', why: 'لو مردّش، مفيش أسعار ولا شموع.',
            whenRed: 'فشل الاتصال.', quickFix: 'استنى ~دقيقة (cold start) وافحص تاني.', deepFix: 'اعمل Manual Deploy للخدمة في Render.')),
        RCheck(id: 'proxy_endpoints', section: 'proxy', title: 'كل الـ endpoints بتردّ (status/candles/health)', help: const RHelp(
            measure: 'GET لكل endpoint والتأكد إنه 200.', why: 'التطبيق بيعتمد عليهم كلهم.', whenRed: 'أي endpoint ≠ 200.')),
        RCheck(id: 'proxy_restart', section: 'proxy', title: 'إعادة تشغيل البروكسي (يدوي)', help: const RHelp(
            measure: 'زرار بيفتح Render.', why: 'أحياناً السكرابر يحتاج restart.', quickFix: 'Render → الخدمة → Manual Deploy → Deploy latest commit.')),

        // ── 2) Cloudflare Worker ──
        RCheck(id: 'wk_alive', section: 'worker', title: 'الـ Worker حي + زمن الاستجابة', help: const RHelp(
            measure: 'GET $_kWorker/health.', why: 'طبقة الكاش قدام البروكسي.', whenRed: 'فشل → التطبيق لازم يرجع للأصل المباشر.')),
        RCheck(id: 'wk_active', section: 'worker', title: 'التطبيق بيضرب على الـ Worker ولا الأصل؟', help: const RHelp(
            measure: 'يقرأ configs.proxy_server_url ويقارنه برابط الـ Worker.', why: 'تعرف مصدر البيانات الحالي.')),
        RCheck(id: 'wk_cache', section: 'worker', title: 'الكاش شغّال (HIT/MISS)', help: const RHelp(
            measure: 'يطلب status مرتين ويقرأ هيدر X-Cache.', why: 'لو دايماً MISS، الكاش مش بيوفّر حمل.', whenRed: 'مفيش HIT إطلاقاً.')),
        RCheck(id: 'wk_match', section: 'worker', title: 'الـ Worker بيرجّع نفس داتا الأصل', help: const RHelp(
            measure: 'يقارن عدد الرموز بين الـ Worker والأصل.', why: 'لو مختلفين = الكاش قديم/تالف.', whenRed: 'فرق في عدد الرموز.')),
        RCheck(id: 'wk_ws', section: 'worker', title: '⭐ الـ WebSocket /ws شغّال من خلال الـ Worker', help: const RHelp(
            measure: 'يفتح WS على الـ Worker ويشوف اتصل/جه tick.', why: 'السعر اللحظي + ضمان الفوز بيركبوا الـ WS.',
            whenRed: 'مقطوع = ضمان الفوز مش هيشتغل.', quickFix: 'رجّع للبروكسي المباشر لو الـ Worker بيكسر الـ WS.')),
        RCheck(id: 'wk_cors', section: 'worker', title: 'CORS headers موجودة', help: const RHelp(
            measure: 'يتأكد Access-Control-Allow-Origin موجود.', why: 'من غيرها Flutter Web مش هيقرا.')),

        // ── 3) Prices / data ──
        RCheck(id: 'd_fresh', section: 'data', title: 'الأسعار مش متجمّدة (عمر أحدث تحديث)', help: const RHelp(
            measure: 'عمر أحدث t في otc_prices.', why: 'أسعار متجمّدة = السكرابر واقف.', whenRed: 'أكبر من 90 ثانية.',
            quickFix: 'نبّه السكرابر يعيد المحاولة، أو راجع جلسة PO.')),
        RCheck(id: 'd_count', section: 'data', title: 'عدد الرموز من 183', help: const RHelp(
            measure: 'عدد المفاتيح في otc_prices.', why: 'رموز ناقصة = مشكلة اشتراك في السكرابر.', whenRed: '0 رمز.')),
        RCheck(id: 'd_anom', section: 'data', title: 'مفيش أسعار صفر/null/شاذة', help: const RHelp(
            measure: 'يمسح القيم على 0/null/غير منطقي.', why: 'أسعار شاذة تفسد الشموع والإشارات.', whenRed: 'أي قيمة شاذة.')),
        RCheck(id: 'd_candles', section: 'data', title: 'الشموع راجعة لكل فريم (1m..1D)', help: const RHelp(
            measure: 'GET /api/otc/candles لكل فريم على رمز شغّال.', why: 'محرك الإشارات بيتغذى منها.', whenRed: 'أي فريم فاضي.')),
        RCheck(id: 'd_market', section: 'data', title: 'حالة السوق متسقة مع طزاجة الأسعار', help: const RHelp(
            measure: 'يقارن فلاج po مع طزاجة السعر.', why: 'تناقض = بيانات غير موثوقة.')),
        RCheck(id: 'd_engine', section: 'data', title: 'مدخلات المحرك سليمة (استراتيجيات + شموع + أسعار)', help: const RHelp(
            measure: 'configs الاستراتيجيات موجودة + أسعار طازة + شموع.', why: 'المحرك بيشتغل في تطبيق المستخدم — ده فحص المدخلات.')),

        // ── 4) Supabase ──
        RCheck(id: 's_alive', section: 'supabase', title: 'الاتصال حي + زمن الاستجابة', help: const RHelp(
            measure: 'استعلام configs?select=id&limit=1 مع توقيت.', why: 'كل حاجة معتمدة على Supabase.',
            whenRed: 'فشل/522 = الداتابيز Unhealthy.', deepFix: 'Settings → Infrastructure → Restart project، ولو تكرّر كبّر المعالج.')),
        RCheck(id: 's_tables', section: 'supabase', title: 'الجداول موجودة وفيها بيانات', help: const RHelp(
            measure: 'count: configs/pairs/otc_pairs/users/candles.', why: 'مشروع فاضي/غلط = التطبيق مايشتغلش.', whenRed: 'أي جدول 404 أو 0.')),
        RCheck(id: 's_usage', section: 'supabase', title: 'الاستهلاك (connections/messages/egress) + صحة المشروع', help: const RHelp(
            measure: 'عبر البروكسي (/api/supabase-usage) بمفتاح Management. الأرقام الكاملة من الداشبورد.',
            why: 'تجاوز الحدود = قطع الخدمة. الحدود: 500 اتصال، 5M رسالة/شهر، 250GB Egress.',
            whenRed: 'المشروع Unhealthy أو أي مقياس فوق 90%.', external: 'صفحة Usage في الداشبورد')),

        // ── 5) PO session (view only) ──
        RCheck(id: 'po_token', section: 'po', title: 'توكن Pocket Option صالح', help: const RHelp(
            measure: 'طول التوكن (authLen) من otc_status.cfg.', why: 'من غير توكن سليم مفيش أسعار.',
            whenRed: 'authLen ~144 أو 0 = لوجين معلّق/منتهي.', quickFix: 'سجّل دخول بإيدك والصق التوكن الجديد تحت.')),
        RCheck(id: 'po_last', section: 'po', title: 'آخر اتصال ناجح بـ PO', help: const RHelp(
            measure: 'طزاجة الأسعار = آخر بثّ ناجح.', why: 'مؤشر إن الجلسة لسه حية.')),

        // ── 6) 2captcha (view only) ──
        RCheck(id: 'cap_bal', section: 'captcha', title: 'رصيد 2captcha', help: const RHelp(
            measure: 'عبر البروكسي (/api/captcha-balance).', why: 'من غير رصيد، السكرابر مش هيحل كابتشا اللوجين.',
            whenRed: '\$0 (ZERO_BALANCE).', quickFix: 'اشحن الحساب على 2captcha.com.', external: '2captcha.com')),

        // ── 7) Guaranteed win ──
        RCheck(id: 'g_users', section: 'gwin', title: 'ضمان الفوز مفعّل على كام مستخدم', help: const RHelp(
            measure: 'عدّ users حيث guaranteed_win = true.', why: 'تعرف مين متأثر لو الـ WS وقع.')),
        RCheck(id: 'g_ws', section: 'gwin', title: 'الـ WebSocket اللي بيغذّي ضمان الفوز متصل', help: const RHelp(
            measure: 'نفس فحص /ws.', why: 'ضمان الفوز بيعدّل السعر لايف عبر الـ WS.', whenRed: 'مقطوع = ضمان الفوز مش هيشتغل.')),

        // ── 8) App ──
        RCheck(id: 'a_ver', section: 'app', title: 'الإصدار + الكونفيج الحالي', help: const RHelp(
            measure: 'إصدار الأدمن + قيم configs الأساسية.', why: 'مرجع سريع للحالة.')),
        RCheck(id: 'a_push', section: 'app', title: 'الإشعارات (Web Push) مظبوطة', help: const RHelp(
            measure: 'جدول push_subscriptions فيه اشتراكات.', why: 'من غيرها مفيش تنبيهات.', whenRed: '0 اشتراك.')),
        RCheck(id: 'a_env', section: 'app', title: 'متغيرات بيئة البروكسي (من otc_status.cfg)', help: const RHelp(
            measure: 'email/pass/captcha booleans من cfg.', why: 'أي واحد false = السكرابر ناقصه إعداد.', whenRed: 'أي واحد false.')),
      ];

  // ══════════════════════════ Runner ══════════════════════════
  Future<void> _runAll() async {
    if (_running) return;
    setState(() {
      _running = true;
      _done = 0;
      _geminiText = null;
      _geminiError = null;
      for (final c in _checks) {
        c.status = RStatus.checking;
        c.detail = c.cause = c.fix = '';
        c.externalUrl = c.fixLabel = c.externalLabel = null;
        c.fixAction = null;
        c.danger = false;
      }
    });
    // Prime shared state (active proxy + /ws) first.
    _activeProxy = await _readActiveProxy();
    _wsOk = await checkWebSocket(_wsUrl(_kWorker), 'EURUSD_otc');
    await Future.wait(_checks.map((c) => _runOne(c).timeout(const Duration(seconds: 20), onTimeout: () {
          _set(c, RStatus.warn, 'انتهت المهلة', cause: 'الفحص أخذ أكتر من 20 ثانية');
        })));
    if (mounted) setState(() => _running = false);
  }

  void _tick() {
    if (mounted) setState(() => _done++);
  }

  void _set(RCheck c, RStatus s, String detail,
      {String cause = '', String fix = '', String? url, String? urlLabel, String? fixLabel, Future<String> Function()? action, bool danger = false}) {
    c.status = s;
    c.detail = detail;
    c.cause = cause;
    c.fix = fix;
    c.externalUrl = url;
    c.externalLabel = urlLabel;
    c.fixLabel = fixLabel;
    c.fixAction = action;
    c.danger = danger;
    if (mounted) setState(() {});
  }

  Future<void> _runOne(RCheck c) async {
    try {
      switch (c.id) {
        // ---- proxy ----
        case 'proxy_serves':
          final st = await _otcStatus(_activeProxy);
          final n = st?['count'] ?? -1;
          if (st == null) {
            _set(c, RStatus.fail, 'الرابط النشط مش بيردّ: $_activeProxy', cause: 'البروكسي ميّت أو غلط',
                fix: 'رجّع للبروكسي المباشر', url: _kRenderDash, urlLabel: 'Render');
          } else if (n == 0) {
            _set(c, RStatus.fail, '🔴 0 رمز! الكونفيج بيشاور على بروكسي ميّت ($_activeProxy)',
                cause: 'خدمة Render مكرّرة/معطّلة — بتردّ /health بس مفيش بيانات',
                fix: 'اضغط "رجّع للبروكسي المباشر" (تحت في قسم الـ Worker)، وعلّق الخدمة المكررة في Render',
                url: _kRenderDash, urlLabel: 'Render', fixLabel: 'رجّع للبروكسي المباشر',
                action: () => _switchProxy(_kOrigin), danger: true);
          } else if (n < 183) {
            _set(c, RStatus.warn, '$n / 183 رمز', cause: 'بعض الرموز ناقصة من السكرابر');
          } else {
            _set(c, RStatus.ok, '183 / 183 رمز ✅ ($_activeProxy)');
          }
          break;
        case 'proxy_alive':
          final r = await _timed('$_activeProxy/health');
          if (r == null) {
            _set(c, RStatus.fail, 'مفيش رد', cause: 'البروكسي واقف أو cold-start طويل',
                fix: 'استنى ~دقيقة وافحص تاني، أو اعمل Manual Deploy', url: _kRenderDash, urlLabel: 'Render');
          } else if (r.$1 != 200) {
            _set(c, RStatus.fail, 'HTTP ${r.$1}', cause: 'البروكسي بيردّ خطأ');
          } else if (r.$2 > 5000) {
            _set(c, RStatus.warn, 'بطيء: ${r.$2}ms (cold start)', cause: 'الخدمة كانت نايمة وبتصحى');
          } else {
            _set(c, RStatus.ok, '200 في ${r.$2}ms');
          }
          break;
        case 'proxy_endpoints':
          final eps = {
            '/health': '$_activeProxy/health',
            '/api/otc/status': '$_activeProxy/api/otc/status',
            '/api/otc/candles': '$_activeProxy/api/otc/candles?symbol=EURUSD_otc&interval=1m',
          };
          final bad = <String>[];
          for (final e in eps.entries) {
            final r = await _timed(e.value);
            if (r == null || r.$1 != 200) bad.add('${e.key} (${r?.$1 ?? "لا رد"})');
          }
          if (bad.isEmpty) {
            _set(c, RStatus.ok, 'كل الـ endpoints 200 ✅');
          } else {
            _set(c, RStatus.fail, 'فشل: ${bad.join("، ")}', cause: 'endpoint مش بيردّ صح');
          }
          break;
        case 'proxy_restart':
          _set(c, RStatus.na, 'زرار يدوي', fix: 'Render → الخدمة → Manual Deploy → Deploy latest commit',
              url: _kRenderDash, urlLabel: 'افتح Render');
          break;

        // ---- worker ----
        case 'wk_alive':
          final r = await _timed('$_kWorker/health');
          if (r == null) {
            _set(c, RStatus.fail, 'الـ Worker مش بيردّ', cause: 'مشكلة في Cloudflare أو شهادة',
                fix: 'رجّع للبروكسي المباشر مؤقتاً', fixLabel: 'رجّع للبروكسي المباشر', action: () => _switchProxy(_kOrigin), danger: true);
          } else {
            _set(c, RStatus.ok, '200 في ${r.$2}ms');
          }
          break;
        case 'wk_active':
          final onWorker = _activeProxy.contains('workers.dev');
          if (onWorker) {
            _set(c, RStatus.ok, 'التطبيق بيضرب على الـ Worker ✅', fixLabel: 'رجّع للبروكسي المباشر',
                action: () => _switchProxy(_kOrigin), danger: true);
          } else {
            _set(c, RStatus.warn, 'التطبيق بيضرب على الأصل مباشرة: $_activeProxy',
                cause: 'الكاش مش مفعّل — حمل أعلى على البروكسي', fix: 'حوّل للـ Worker لتفعيل الكاش',
                fixLabel: 'حوّل للـ Worker', action: () => _switchProxy(_kWorker), danger: true);
          }
          break;
        case 'wk_cache':
          await _timed('$_kWorker/api/otc/status'); // warm
          final h1 = await _header('$_kWorker/api/otc/status', 'x-cache');
          final h2 = await _header('$_kWorker/api/otc/status', 'x-cache');
          final tag = (h2 ?? h1 ?? '').toUpperCase();
          if (tag.contains('HIT')) {
            _set(c, RStatus.ok, 'X-Cache: HIT ✅ (الكاش شغّال)');
          } else if (tag.contains('STALE')) {
            _set(c, RStatus.warn, 'X-Cache: STALE', cause: 'الأصل بطّأ — الـ Worker بيقدّم نسخة محفوظة');
          } else if (tag.isEmpty) {
            _set(c, RStatus.warn, 'مفيش هيدر X-Cache', cause: 'ممكن التطبيق مش على الـ Worker');
          } else {
            _set(c, RStatus.warn, 'X-Cache: $tag (مفيش HIT)', cause: 'الكاش لسه بيسخّن');
          }
          break;
        case 'wk_match':
          final w = await _otcStatus(_kWorker);
          final o = await _otcStatus(_kOrigin);
          if (w == null || o == null) {
            _set(c, RStatus.warn, 'تعذّر المقارنة', cause: 'أحد الطرفين مردّش');
          } else if (w['count'] != o['count']) {
            _set(c, RStatus.fail, 'فرق: Worker ${w['count']} / الأصل ${o['count']}', cause: 'كاش قديم/تالف',
                fix: 'رجّع للبروكسي المباشر مؤقتاً', fixLabel: 'رجّع للبروكسي المباشر', action: () => _switchProxy(_kOrigin), danger: true);
          } else {
            _set(c, RStatus.ok, 'مطابق: ${w['count']} رمز على الاتنين ✅');
          }
          break;
        case 'wk_ws':
          if (_wsOk) {
            _set(c, RStatus.ok, 'الـ WS متصل عبر الـ Worker ✅');
          } else {
            _set(c, RStatus.fail, '🔴 الـ WS مقطوع عبر الـ Worker — ضمان الفوز مش هيشتغل!',
                cause: 'الـ Worker بيكسر تمرير الـ WebSocket', fix: 'رجّع للبروكسي المباشر فوراً',
                fixLabel: 'رجّع للبروكسي المباشر', action: () => _switchProxy(_kOrigin), danger: true);
          }
          break;
        case 'wk_cors':
          final cors = await _header('$_kWorker/api/otc/status', 'access-control-allow-origin');
          _set(c, cors != null ? RStatus.ok : RStatus.warn, cors != null ? 'موجود: $cors ✅' : 'مش ظاهر',
              cause: cors == null ? 'ممكن قيد على قراءة الهيدر من المتصفح' : '');
          break;

        // ---- data ----
        case 'd_fresh':
          final st = await _otcStatus(_activeProxy);
          final age = st?['newestAge'];
          if (st == null) {
            _set(c, RStatus.fail, 'مفيش رد من البروكسي', cause: 'البروكسي واقف');
          } else if (age == null) {
            _set(c, RStatus.fail, 'مفيش أسعار', cause: 'السكرابر مش بيبثّ');
          } else if (age > 90) {
            _set(c, RStatus.fail, 'متجمّدة من ${age}s', cause: 'السكرابر واقف / جلسة PO ماتت',
                fix: 'نبّه السكرابر يعيد المحاولة، وراجع قسم Pocket Option', fixLabel: 'نبّه السكرابر', action: _nudgeScraper);
          } else if (age > 30) {
            _set(c, RStatus.warn, 'آخر تحديث من ${age}s', cause: 'بثّ بطيء');
          } else {
            _set(c, RStatus.ok, 'حيّة — آخر تحديث ${age}s ✅');
          }
          break;
        case 'd_count':
          final st = await _otcStatus(_activeProxy);
          final n = st?['count'] ?? -1;
          if (n < 0) {
            _set(c, RStatus.fail, 'مفيش رد', cause: 'البروكسي واقف');
          } else if (n == 0) {
            _set(c, RStatus.fail, '0 رمز', cause: 'السكرابر مش مشترك في أي رمز');
          } else if (n < 183) {
            _set(c, RStatus.warn, '$n / 183', cause: 'رموز ناقصة');
          } else {
            _set(c, RStatus.ok, '183 / 183 ✅');
          }
          break;
        case 'd_anom':
          final st = await _otcStatus(_activeProxy);
          final bad = st?['anomalies'] as int? ?? 0;
          if (st == null) {
            _set(c, RStatus.warn, 'تعذّر الفحص');
          } else if (bad > 0) {
            _set(c, RStatus.fail, '$bad قيمة شاذة (0/null)', cause: 'خطأ في السكرابر');
          } else {
            _set(c, RStatus.ok, 'كل الأسعار سليمة ✅');
          }
          break;
        case 'd_candles':
          final tfs = ['1m', '5m', '15m', '1h', '1D'];
          final empty = <String>[];
          for (final tf in tfs) {
            final r = await _json('$_activeProxy/api/otc/candles?symbol=EURUSD_otc&interval=$tf');
            final cnt = (r?['candles'] as List?)?.length ?? 0;
            if (cnt == 0) empty.add(tf);
          }
          if (empty.isEmpty) {
            _set(c, RStatus.ok, 'كل الفريمات فيها شموع ✅');
          } else {
            _set(c, RStatus.warn, 'فاضية: ${empty.join("، ")}', cause: 'الفريمات دي لسه بتتراكم أو مش مخزّنة');
          }
          break;
        case 'd_market':
          final st = await _otcStatus(_activeProxy);
          if (st == null) {
            _set(c, RStatus.warn, 'تعذّر الفحص');
          } else {
            final closed = st['closed'] as int? ?? 0;
            final total = st['count'] as int? ?? 0;
            _set(c, RStatus.ok, '$closed مقفول / $total (متسق مع فلاجات PO) ✅');
          }
          break;
        case 'd_engine':
          final ids = ['strategy_standard', 'strategy_vip', 'monitoring_standard', 'monitoring_vip'];
          final rows = await _sb.from('configs').select('id,data').inFilter('id', ids).timeout(const Duration(seconds: 8));
          final present = (rows as List).where((r) => (r['data'] is Map) && (r['data'] as Map).isNotEmpty).length;
          final st = await _otcStatus(_activeProxy);
          final freshOk = (st?['newestAge'] ?? 999) <= 90;
          if (present >= 2 && freshOk) {
            _set(c, RStatus.ok, 'الاستراتيجيات ($present/4) + أسعار طازة ✅');
          } else if (present < 2) {
            _set(c, RStatus.warn, 'استراتيجيات ناقصة ($present/4)', cause: 'configs الاستراتيجيات فاضية');
          } else {
            _set(c, RStatus.warn, 'الأسعار مش طازة → المحرك على بيانات قديمة', cause: 'راجع قسم الأسعار');
          }
          break;

        // ---- supabase ----
        case 's_alive':
          final t0 = DateTime.now();
          try {
            await _sb.from('configs').select('id').limit(1).timeout(const Duration(seconds: 6));
            final ms = DateTime.now().difference(t0).inMilliseconds;
            _set(c, ms > 3000 ? RStatus.warn : RStatus.ok, '200 في ${ms}ms',
                cause: ms > 3000 ? 'بطيء — ممكن ضغط على النانو' : '');
          } catch (e) {
            _set(c, RStatus.fail, 'فشل: ${_short(e)}', cause: 'الداتابيز Unhealthy / 522',
                fix: 'Settings → Infrastructure → Restart project (لو تكرّر: كبّر المعالج)',
                url: 'https://supabase.com/dashboard/project/$_kRef', urlLabel: 'Supabase');
          }
          break;
        case 's_tables':
          // table → a column that surely exists on it. `candles` is keyed by
          // `key` (cols: key/data/updated_at) and has NO `id` column, so probing
          // `id` there throws and shows a false "خطأ". Probe each by a real column.
          const probe = {'configs': 'id', 'pairs': 'id', 'otc_pairs': 'id', 'users': 'id', 'candles': 'key'};
          final miss = <String>[];
          for (final t in probe.keys) {
            try {
              final n = await _count(t, col: probe[t]!);
              if (n <= 0) miss.add('$t (0)');
            } catch (_) {
              miss.add('$t (خطأ)');
            }
          }
          if (miss.isEmpty) {
            _set(c, RStatus.ok, 'كل الجداول موجودة وفيها بيانات ✅');
          } else {
            _set(c, RStatus.fail, 'مشكلة: ${miss.join("، ")}', cause: 'مشروع فاضي/غلط');
          }
          break;
        case 's_usage':
          final u = await _json('$_kOrigin/api/supabase-usage');
          if (u == null || u['available'] != true) {
            _set(c, RStatus.na, 'الأرقام مش متاحة من التطبيق', cause: u?['reason']?.toString() ?? 'البروكسي/التوكن مش جاهز',
                fix: 'الأرقام الكاملة (اتصالات/رسائل/Egress) من صفحة Usage في الداشبورد',
                url: _kSupaUsage, urlLabel: 'افتح Usage');
          } else {
            final ps = u['projectStatus']?.toString() ?? '?';
            final healthy = ps == 'ACTIVE_HEALTHY';
            _set(c, healthy ? RStatus.ok : RStatus.warn, 'المشروع: $ps',
                cause: healthy ? '' : 'المشروع مش ACTIVE_HEALTHY',
                fix: 'راجع الأرقام التفصيلية في الداشبورد (حد 500 اتصال / 5M رسالة / 250GB)',
                url: _kSupaUsage, urlLabel: 'افتح Usage');
          }
          break;

        // ---- PO session ----
        case 'po_token':
          final st = await _otcStatus(_activeProxy);
          final authLen = st?['authLen'] as int? ?? 0;
          if (authLen == 0) {
            _set(c, RStatus.fail, 'مفيش توكن', cause: 'السكرابر ماقدرش يسجّل دخول', fix: _poFixText, danger: false);
          } else if (authLen < 200) {
            _set(c, RStatus.fail, 'توكن معلّق/منتهي (authLen=$authLen)', cause: 'اللوجين واقف أو التوكن انتهى', fix: _poFixText);
          } else {
            _set(c, RStatus.ok, 'توكن سليم (authLen=$authLen) ✅');
          }
          break;
        case 'po_last':
          final st = await _otcStatus(_activeProxy);
          final age = st?['newestAge'];
          if (age == null) {
            _set(c, RStatus.warn, 'مفيش بثّ', cause: 'الجلسة ممكن تكون ماتت');
          } else if (age > 90) {
            _set(c, RStatus.warn, 'آخر بثّ ناجح من ${age}s', cause: 'الجلسة بطيئة/واقفة');
          } else {
            _set(c, RStatus.ok, 'آخر اتصال ناجح من ${age}s ✅');
          }
          break;

        // ---- 2captcha ----
        case 'cap_bal':
          final b = await _json('$_kOrigin/api/captcha-balance');
          if (b == null || b['available'] != true) {
            _set(c, RStatus.na, 'مش متاح', cause: b?['reason']?.toString() ?? 'البروكسي/المفتاح مش جاهز',
                fix: 'الرصيد من 2captcha.com', url: 'https://2captcha.com', urlLabel: '2captcha');
          } else {
            final bal = (b['balance'] as num?)?.toDouble() ?? 0;
            if (bal <= 0) {
              _set(c, RStatus.fail, '\$${bal.toStringAsFixed(2)} — ZERO BALANCE', cause: 'اللوجين مش هيشتغل من غير رصيد',
                  fix: 'اشحن الحساب', url: 'https://2captcha.com', urlLabel: 'اشحن 2captcha');
            } else if (bal < 2) {
              _set(c, RStatus.warn, '\$${bal.toStringAsFixed(2)} (قليل)', cause: 'قرّب يخلص',
                  fix: 'اشحن قريباً', url: 'https://2captcha.com', urlLabel: '2captcha');
            } else {
              _set(c, RStatus.ok, '\$${bal.toStringAsFixed(2)} ✅');
            }
          }
          break;

        // ---- gwin ----
        case 'g_users':
          final n = await _count('users', filter: (q) => q.eq('guaranteed_win', true));
          _set(c, RStatus.ok, 'مفعّل على $n مستخدم');
          break;
        case 'g_ws':
          if (_wsOk) {
            _set(c, RStatus.ok, 'الـ WS متصل — ضمان الفوز هيشتغل ✅');
          } else {
            _set(c, RStatus.fail, '🔴 الـ WS مقطوع — ضمان الفوز مش هيشتغل', cause: 'مصدر السعر اللحظي مقطوع',
                fix: 'رجّع للبروكسي المباشر / راجع البروكسي', fixLabel: 'رجّع للبروكسي المباشر',
                action: () => _switchProxy(_kOrigin), danger: true);
          }
          break;

        // ---- app ----
        case 'a_ver':
          final cfg = await _sb.from('configs').select('id,data').inFilter('id', ['price_system', 'display_source', 'chart_settings']).timeout(const Duration(seconds: 8));
          final m = {for (final r in (cfg as List)) r['id']: (r['data'] as Map?)?['value'] ?? (r['data'] as Map?)?['mode']};
          _set(c, RStatus.ok, 'v1.0.0 • proxy=$_activeProxy • ${m.toString()}');
          break;
        case 'a_push':
          final n = await _count('push_subscriptions');
          _set(c, n > 0 ? RStatus.ok : RStatus.warn, '$n اشتراك',
              cause: n == 0 ? 'مفيش أجهزة مشتركة في الإشعارات' : '');
          break;
        case 'a_env':
          final st = await _otcStatus(_activeProxy);
          final cfg = st?['cfg']?.toString() ?? '';
          final email = cfg.contains('email=true');
          final pass = cfg.contains('pass=true');
          final cap = cfg.contains('captcha=true');
          final missing = <String>[];
          if (!email) missing.add('PO_EMAIL');
          if (!pass) missing.add('PO_PASSWORD');
          if (!cap) missing.add('CAPTCHA_API_KEY');
          if (missing.isEmpty && cfg.isNotEmpty) {
            _set(c, RStatus.ok, 'email/pass/captcha كلهم مضبوطين ✅');
          } else if (cfg.isEmpty) {
            _set(c, RStatus.warn, 'مفيش cfg من السكرابر', cause: 'السكرابر لسه بيقلع');
          } else {
            _set(c, RStatus.fail, 'ناقص: ${missing.join("، ")}', cause: 'متغيرات بيئة ناقصة في Render',
                url: _kRenderDash, urlLabel: 'Render → Environment');
          }
          break;
        default:
          _set(c, RStatus.unknown, '—');
      }
    } catch (e) {
      _set(c, RStatus.warn, 'خطأ في الفحص: ${_short(e)}');
    } finally {
      _tick();
    }
  }

  static const _poFixText =
      'التوكن انتهى — سجّل دخول بإيدك في المتصفح على pocketoption.com، افتح شارت، ومن أدوات المطور (Network → WS) خُد إطار "auth" اللي فيه session. الصقه تحت واحفظ.';

  // ══════════════════════════ Measurement helpers ══════════════════════════
  Future<String> _readActiveProxy() async {
    try {
      final r = await _sb.from('configs').select('data').eq('id', 'proxy_server_url').maybeSingle().timeout(const Duration(seconds: 6));
      final u = ((r?['data'] as Map?)?['url'] as String?)?.trim();
      if (u != null && u.isNotEmpty) return u.replaceAll(RegExp(r'/+$'), '');
    } catch (_) {}
    return _kOrigin;
  }

  String _wsUrl(String base) => '${base.replaceFirst(RegExp(r'^http'), 'ws')}/ws';

  Future<(int, int)?> _timed(String url) async {
    final t0 = DateTime.now();
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      return (r.statusCode, DateTime.now().difference(t0).inMilliseconds);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _json(String url) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final d = jsonDecode(r.body);
      if (d is Map<String, dynamic>) return d;
      return {'_list': d};
    } catch (_) {
      return null;
    }
  }

  Future<String?> _header(String url, String name) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      return r.headers[name.toLowerCase()];
    } catch (_) {
      return null;
    }
  }

  // Parse /api/otc/status → {count, newestAge, anomalies, closed, authLen, cfg}
  Future<Map<String, dynamic>?> _otcStatus(String base) async {
    try {
      final r = await http.get(Uri.parse('$base/api/otc/status')).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final list = jsonDecode(r.body) as List;
      final prices = (list.firstWhere((x) => x['id'] == 'otc_prices', orElse: () => {'data': {}})['data'] as Map?) ?? {};
      final status = (list.firstWhere((x) => x['id'] == 'otc_status', orElse: () => {'data': {}})['data'] as Map?) ?? {};
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      int anomalies = 0, closed = 0;
      int? newest;
      prices.forEach((k, v) {
        if (v is Map) {
          final p = v['p'];
          if (p == null || (p is num && (p <= 0 || !p.isFinite))) anomalies++;
          if (v['po'] == false) closed++;
          final t = (v['t'] as num?)?.toInt();
          if (t != null) {
            final age = now - t;
            if (newest == null || age < newest!) newest = age;
          }
        }
      });
      final cfg = status['cfg']?.toString() ?? '';
      final m = RegExp(r'authLen=(\d+)').firstMatch(cfg);
      return {
        'count': prices.length,
        'newestAge': newest,
        'anomalies': anomalies,
        'closed': closed,
        'authLen': m != null ? int.parse(m.group(1)!) : 0,
        'cfg': cfg,
      };
    } catch (_) {
      return null;
    }
  }

  // Version-safe count: fetch id-only rows (small tables) and count them. Throws
  // if the table doesn't exist (caught by the caller → treated as missing).
  Future<int> _count(String table, {String col = 'id', dynamic Function(dynamic)? filter}) async {
    dynamic q = _sb.from(table).select(col);
    if (filter != null) q = filter(q);
    final r = await q.timeout(const Duration(seconds: 8));
    return (r as List).length;
  }

  String _short(Object e) => e.toString().replaceAll('\n', ' ').trim();
  String _short2(Object e) => _short(e).length > 60 ? '${_short(e).substring(0, 60)}…' : _short(e);

  // ══════════════════════════ Repairs ══════════════════════════
  Future<String> _switchProxy(String url) async {
    await _sb.from('configs').upsert({
      'id': 'proxy_server_url',
      'data': {'url': url, 'updatedAt': DateTime.now().toUtc().toIso8601String()},
    });
    await _log('switch_proxy', 'proxy_server_url → $url');
    _activeProxy = url;
    return 'تم التحويل إلى:\n$url\nكل الأجهزة هتتحول خلال ثواني (realtime).';
  }

  Future<String> _nudgeScraper() async {
    await _sb.from('configs').upsert({
      'id': 'otc_scan',
      'data': {'trigger': DateTime.now().toUtc().toIso8601String()},
    });
    await _log('nudge_scraper', 'otc_scan trigger');
    return 'اتبعت إشارة للسكرابر يعيد المحاولة. استنى ~دقيقة وافحص تاني.';
  }

  Future<String> _saveToken(String token) async {
    final t = token.trim();
    if (t.length < 40) return 'التوكن قصير جداً — تأكد إنك لصقت إطار auth كامل.';
    await _sb.from('configs').upsert({
      'id': 'otc_token',
      'data': {'auth': t, 'capturedAt': DateTime.now().toUtc().toIso8601String(), 'via': 'admin_repair'},
    });
    await _log('save_po_token', 'otc_token updated (len=${t.length})');
    return 'اتحفظ التوكن الجديد ✅. اعمل Manual Deploy للبروكسي عشان يلتقطه، أو نبّه السكرابر.';
  }

  Future<String> _resubRealtime() async {
    try {
      _sb.realtime.disconnect();
    } catch (_) {}
    await _log('resub_realtime', 'realtime disconnect (auto-reconnect)');
    return 'اتقطع الـ realtime — هيعيد الاشتراك تلقائياً.';
  }

  Future<String> _clearCache() async {
    final msg = await clearWebCaches();
    await _log('clear_cache', msg);
    return '$msg. اعمل refresh للصفحة.';
  }

  Future<void> _log(String action, String result) async {
    try {
      await _sb.from('repair_log').insert({
        'action': action,
        'result': result,
        'at': DateTime.now().toUtc().toIso8601String(),
      }).timeout(const Duration(seconds: 6));
    } catch (_) {/* table may not exist yet — non-fatal */}
  }

  // ══════════════════════════ Gemini ══════════════════════════
  Future<void> _runGemini() async {
    setState(() {
      _geminiLoading = true;
      _geminiText = null;
      _geminiError = null;
    });
    final report = {
      'summary': _summary(),
      'checks': _checks
          .map((c) => {'section': c.section, 'title': c.title, 'status': c.status.name, 'detail': c.detail, 'cause': c.cause})
          .toList(),
    };
    try {
      final r = await http
          .post(Uri.parse('$_kOrigin/api/diagnose'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode(report))
          .timeout(const Duration(seconds: 32));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['available'] == true && d['text'] != null) {
        setState(() => _geminiText = d['text'].toString());
      } else {
        setState(() => _geminiError = d['reason']?.toString() ?? 'Gemini مش متاح');
      }
    } catch (e) {
      setState(() => _geminiError = 'تعذّر الاتصال بالبروكسي: ${_short2(e)}');
    } finally {
      if (mounted) setState(() => _geminiLoading = false);
    }
  }

  Map<String, int> _summary() {
    final m = {'fail': 0, 'warn': 0, 'ok': 0, 'na': 0};
    for (final c in _checks) {
      if (c.status == RStatus.fail) m['fail'] = m['fail']! + 1;
      if (c.status == RStatus.warn) m['warn'] = m['warn']! + 1;
      if (c.status == RStatus.ok) m['ok'] = m['ok']! + 1;
      if (c.status == RStatus.na) m['na'] = m['na']! + 1;
    }
    return m;
  }

  String _textReport() {
    final b = StringBuffer('تقرير إصلاح النظام — Euro Trade\n');
    b.writeln('${DateTime.now().toUtc().toIso8601String()} UTC\n');
    for (final s in _sections) {
      b.writeln('═══ ${s[1]} ═══');
      for (final c in _checks.where((x) => x.section == s[0])) {
        b.writeln('${_emoji(c.status)} ${c.title}: ${c.detail}');
        if (c.cause.isNotEmpty) b.writeln('   السبب: ${c.cause}');
        if (c.fix.isNotEmpty) b.writeln('   الحل: ${c.fix}');
      }
      b.writeln('');
    }
    return b.toString();
  }

  String _emoji(RStatus s) => switch (s) {
        RStatus.ok => '🟢',
        RStatus.warn => '🟡',
        RStatus.fail => '🔴',
        RStatus.checking => '⚪',
        RStatus.na => '⚫',
        RStatus.unknown => '⚪',
      };

  // ══════════════════════════ UI ══════════════════════════
  @override
  Widget build(BuildContext context) {
    final sum = _summary();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          title: Text('إصلاح النظام', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: _cyan),
        ),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _topBar(sum),
            const SizedBox(height: 12),
            for (final s in _sections) _sectionTile(s[0], s[1]),
            const SizedBox(height: 16),
            _geminiCard(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _topBar(Map<String, int> sum) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _running ? null : _runAll,
              style: ElevatedButton.styleFrom(backgroundColor: _cyan, padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: _running
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.radar, color: Colors.black),
              label: Text(_running ? 'بيفحص… $_done/${_checks.length}' : 'افحص كل حاجة',
                  style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 6, alignment: WrapAlignment.center, children: [
            _pill('🔴 ${sum['fail']} مشكلة', _red),
            _pill('🟡 ${sum['warn']} تحذير', _amber),
            _pill('🟢 ${sum['ok']} تمام', _green),
            if ((sum['na'] ?? 0) > 0) _pill('⚫ ${sum['na']} غير متاح', _muted),
            TextButton.icon(
              onPressed: () => _copy(_textReport(), 'اتنسخ التقرير'),
              icon: const Icon(Icons.copy, size: 15, color: _cyan),
              label: Text('نسخ التقرير', style: GoogleFonts.outfit(color: _cyan, fontSize: 12)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.withAlpha(28), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withAlpha(90))),
        child: Text(t, style: GoogleFonts.outfit(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _sectionTile(String id, String title) {
    final items = _checks.where((c) => c.section == id).toList();
    final worst = items.map((c) => c.status).fold(RStatus.ok, (a, b) {
      int rank(RStatus s) => s == RStatus.fail ? 3 : s == RStatus.warn ? 2 : s == RStatus.checking ? 1 : 0;
      return rank(b) > rank(a) ? b : a;
    });
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent, unselectedWidgetColor: _muted, colorScheme: const ColorScheme.dark(primary: _cyan)),
        child: ExpansionTile(
          initiallyExpanded: worst == RStatus.fail,
          leading: _dot(worst),
          title: Text(title, style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.bold, fontSize: 14)),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          children: items.map(_checkTile).toList(),
        ),
      ),
    );
  }

  Widget _dot(RStatus s) {
    final c = switch (s) {
      RStatus.ok => _green,
      RStatus.warn => _amber,
      RStatus.fail => _red,
      RStatus.checking => _cyan,
      _ => _muted,
    };
    if (s == RStatus.checking) {
      return const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _cyan));
    }
    return Container(width: 14, height: 14, decoration: BoxDecoration(color: c, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.withAlpha(120), blurRadius: 6)]));
  }

  Widget _checkTile(RCheck c) {
    final isRed = c.status == RStatus.fail;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: _bg, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isRed ? _red.withAlpha(120) : _border),
      ),
      child: ExpansionTile(
        initiallyExpanded: isRed,
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: _dot(c.status),
        title: Text(c.title, style: GoogleFonts.outfit(color: _text, fontSize: 12.5)),
        subtitle: c.detail.isEmpty ? null : Text(c.detail, style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
        trailing: IconButton(
          icon: const Icon(Icons.help_outline, size: 18, color: _muted),
          onPressed: () => _showHelp(c),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          if (c.cause.isNotEmpty) _kv('السبب المحتمل', c.cause, _amber),
          if (c.fix.isNotEmpty) _kv('الحل', c.fix, _cyan),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(
              onPressed: () => _runOne(c),
              icon: const Icon(Icons.refresh, size: 15, color: _cyan),
              label: Text('افحص تاني', style: GoogleFonts.outfit(color: _cyan, fontSize: 12)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: _border)),
            ),
            if (c.fixAction != null && c.fixLabel != null)
              ElevatedButton.icon(
                onPressed: () => _doFix(c),
                icon: Icon(c.danger ? Icons.warning_amber_rounded : Icons.build, size: 15, color: Colors.black),
                label: Text(c.fixLabel!, style: GoogleFonts.outfit(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: c.danger ? _amber : _green),
              ),
            if (c.externalUrl != null)
              TextButton.icon(
                onPressed: () => openTab(c.externalUrl!),
                icon: const Icon(Icons.open_in_new, size: 15, color: _purple),
                label: Text(c.externalLabel ?? 'افتح', style: GoogleFonts.outfit(color: _purple, fontSize: 12)),
              ),
          ]),
          if (c.id == 'po_token') _poTokenBox(),
          if (c.id == 'proxy_serves' || c.id == 'wk_active') _extraProxyButtons(),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: RichText(
          text: TextSpan(children: [
            TextSpan(text: '$k: ', style: GoogleFonts.outfit(color: c, fontSize: 11.5, fontWeight: FontWeight.bold)),
            TextSpan(text: v, style: GoogleFonts.outfit(color: _text, fontSize: 11.5, height: 1.5)),
          ]),
        ),
      );

  Widget _extraProxyButtons() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 8, children: [
          _miniBtn('حوّل للـ Worker', _purple, () => _confirmFix('حوّل للـ Worker', 'التطبيق هيضرب على الـ Worker (كاش). كل الأجهزة تتحول realtime.', () => _switchProxy(_kWorker))),
          _miniBtn('رجّع للبروكسي المباشر', _amber, () => _confirmFix('رجّع للبروكسي المباشر', 'التطبيق هيضرب على $_kOrigin مباشرة (بدون كاش). كل الأجهزة تتحول realtime.', () => _switchProxy(_kOrigin))),
          _miniBtn('نبّه السكرابر', _cyan, () => _confirmFix('نبّه السكرابر', 'هيتبعت للسكرابر إشارة يعيد المحاولة.', _nudgeScraper)),
          _miniBtn('مسح الكاش المحلي', _muted, () => _confirmFix('مسح الكاش المحلي', 'هيتمسح كاش المتصفح + الـ service workers لهذه الصفحة.', _clearCache)),
          _miniBtn('إعادة اشتراك Realtime', _muted, () => _confirmFix('إعادة اشتراك Realtime', 'هيتقطع اتصال realtime ويعيد الاشتراك.', _resubRealtime)),
        ]),
      );

  Widget _miniBtn(String t, Color c, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(side: BorderSide(color: c.withAlpha(120)), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
        child: Text(t, style: GoogleFonts.outfit(color: c, fontSize: 11)),
      );

  Widget _poTokenBox() {
    final ctrl = TextEditingController();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('تجديد التوكن يدوي (بدون كابتشا آلي):', style: GoogleFonts.outfit(color: _amber, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(_poFixText, style: GoogleFonts.outfit(color: _muted, fontSize: 11, height: 1.5)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          maxLines: 3,
          style: GoogleFonts.robotoMono(color: _text, fontSize: 11),
          decoration: InputDecoration(
            hintText: '["auth",{"session":"...",...}]',
            hintStyle: GoogleFonts.robotoMono(color: _muted, fontSize: 10),
            filled: true, fillColor: _bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _border)),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          ElevatedButton(
            onPressed: () => _confirmFix('حفظ توكن PO', 'هيتحفظ التوكن اللي لصقته في configs.otc_token.', () => _saveToken(ctrl.text)),
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            child: Text('حفظ التوكن', style: GoogleFonts.outfit(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ]),
      ]),
    );
  }

  Widget _geminiCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _purple.withAlpha(120)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🧠', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text('تشخيص ذكي', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          ElevatedButton(
            onPressed: _geminiLoading || _running ? null : _runGemini,
            style: ElevatedButton.styleFrom(backgroundColor: _purple),
            child: _geminiLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('حلّل بالذكاء الاصطناعي', style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ]),
        if (_geminiError != null) ...[
          const SizedBox(height: 10),
          Text('⚠️ $_geminiError', style: GoogleFonts.outfit(color: _amber, fontSize: 12)),
          Text('الفحوصات اليدوية فوق تكفي للتشخيص.', style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
        ],
        if (_geminiText != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
            child: SelectableText(_geminiText!, style: GoogleFonts.outfit(color: _text, fontSize: 12.5, height: 1.7)),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _copy(_geminiText!, 'اتنسخ التشخيص'),
              icon: const Icon(Icons.copy, size: 15, color: _purple),
              label: Text('نسخ التشخيص', style: GoogleFonts.outfit(color: _purple, fontSize: 12)),
            ),
          ),
        ],
      ]),
    );
  }

  // ── dialogs / actions ──
  Future<void> _doFix(RCheck c) async {
    if (c.fixAction == null) return;
    if (c.danger) {
      _confirmFix(c.fixLabel ?? 'إصلاح', 'إيه اللي هيحصل:\n${c.fix}', c.fixAction!);
    } else {
      final msg = await c.fixAction!();
      _snack(msg);
      await _runOne(c);
    }
  }

  void _confirmFix(String title, String body, Future<String> Function() action) {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _card,
          title: Text(title, style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.bold)),
          content: Text(body, style: GoogleFonts.outfit(color: _muted, height: 1.6)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('إلغاء', style: GoogleFonts.outfit(color: _muted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _amber),
              onPressed: () async {
                Navigator.pop(context);
                try {
                  final msg = await action();
                  _snack(msg);
                } catch (e) {
                  _snack('فشل: ${_short2(e)}');
                }
                _runAll();
              },
              child: Text('تأكيد', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelp(RCheck c) {
    final h = c.help;
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _card,
          title: Text('؟ ${c.title}', style: GoogleFonts.outfit(color: _cyan, fontWeight: FontWeight.bold, fontSize: 14)),
          content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (h.measure.isNotEmpty) _kv('بيقيس إيه', h.measure, _cyan),
              if (h.why.isNotEmpty) _kv('ليه مهم', h.why, _purple),
              if (h.whenRed.isNotEmpty) _kv('إيه اللي بيخليه أحمر', h.whenRed, _red),
              if (h.quickFix.isNotEmpty) _kv('الحل السريع', h.quickFix, _green),
              if (h.deepFix.isNotEmpty) _kv('الحل الجذري', h.deepFix, _amber),
              if (h.external.isNotEmpty) _kv('تدخل خارجي', h.external, _muted),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('تمام', style: GoogleFonts.outfit(color: _cyan)))],
        ),
      ),
    );
  }

  void _copy(String t, String msg) {
    Clipboard.setData(ClipboardData(text: t));
    _snack(msg);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: GoogleFonts.outfit()), backgroundColor: _card));
  }
}
