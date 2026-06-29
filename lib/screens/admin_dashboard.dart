import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/js_bridge.dart';

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
  static const Color callGreen = Color(0xFF10B981);
  static const Color putRed = Color(0xFFEF4444);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color textPrimary = Color(0xFFF9FAFB);
  static const Color textSecondary = Color(0xFF9CA3AF);

  String _searchQuery = '';
  String _pairsSearchQuery = '';
  final _pairsSearchCtrl = TextEditingController();
  String _selectedPlatformFilter =
      'all'; // 'all', 'Quotex', 'Pocket Option', 'Expert Option'
  String _selectedRoleFilter = 'all'; // 'all', 'vip', 'standard'
  int _activeTabIndex = 0;

  // ── New user live alerts ─────────────────────────────────────────
  StreamSubscription<List<Map<String, dynamic>>>? _newUserSubscription;
  final List<Map<String, dynamic>> _liveNewUsers = [];
  OverlayEntry? _newUserOverlay;

  // ── Database size warning ────────────────────────────────────────
  double? _dbSizeMb;
  Timer? _dbSizeTimer;

  // Controllers for Global VIP
  final _globalVipValueController = TextEditingController(text: '30');
  String _globalVipUnit = 'days';

  // ── Broker Management state ─────────────────────────────────────
  final _brNameCtrl = TextEditingController();
  final _brLogoCtrl = TextEditingController();
  final _brLinkCtrl = TextEditingController();
  final _brPromoCtrl = TextEditingController();
  final _brBonusCtrl = TextEditingController(text: '0');
  final _brMinDepCtrl = TextEditingController(text: '0');
  final _brOrderCtrl = TextEditingController(text: '1');
  final _brClickKeyCtrl = TextEditingController();
  bool _brIsRecommended = false;
  bool _brIsActive = true;
  String? _editingBrokerId;
  String _brLogoPreview = '';
  Color _brThemeColor = const Color(0xFF06B6D4);
  final _brColorCtrl = TextEditingController();

  // ── App Update state ────────────────────────────────────────────
  final _updVersionCtrl = TextEditingController();
  final _updFeaturesCtrl = TextEditingController();
  final _updLinkCtrl = TextEditingController();
  bool _updIsForced = false;

  // ── App Control / Maintenance state ─────────────────────────────
  final _maintMsgCtrl = TextEditingController(
    text: 'التطبيق متوقف مؤقتاً للصيانة، سنعود قريباً',
  );
  final _maintHoursCtrl = TextEditingController(text: '2');


  static const _pairCategories = [
    ('forex', 'فوركس', Icons.currency_exchange_rounded),
    ('crypto', 'كريبتو', Icons.currency_bitcoin_rounded),
    ('metals', 'معادن', Icons.diamond_rounded),
    ('commodities', 'سلع', Icons.local_gas_station_rounded),
  ];


  Widget _pairDialogContent({
    required TextEditingController symCtrl,
    required TextEditingController chartSymCtrl,
    required String selectedCategory,
    required void Function(String) onCategoryChanged,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pairField(
          symCtrl,
          'اسم العرض (للمستخدم)',
          'EUR/USD',
          Icons.label_rounded,
        ),
        const SizedBox(height: 10),
        _pairField(
          chartSymCtrl,
          'رمز الزوج',
          'EURUSD',
          Icons.show_chart_rounded,
        ),
        const SizedBox(height: 16),
        Text(
          'التصنيف',
          style: GoogleFonts.outfit(color: textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (id, label, icon) in _pairCategories)
              ChoiceChip(
                avatar: Icon(
                  icon,
                  size: 16,
                  color: selectedCategory == id
                      ? spaceBackground
                      : textSecondary,
                ),
                label: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: selectedCategory == id
                        ? spaceBackground
                        : textPrimary,
                  ),
                ),
                selected: selectedCategory == id,
                selectedColor: accentCyan,
                backgroundColor: spaceBackground,
                side: BorderSide(
                  color: selectedCategory == id
                      ? accentCyan
                      : textSecondary.withValues(alpha: 0.3),
                ),
                onSelected: (_) => onCategoryChanged(id),
              ),
          ],
        ),
      ],
    );
  }

  void _showAddPairDialog() {
    final symCtrl = TextEditingController();
    final chartSymCtrl = TextEditingController();
    String selectedCategory = 'forex';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: cardBgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'إضافة زوج للتداول',
            style: GoogleFonts.outfit(
              color: textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: _pairDialogContent(
              symCtrl: symCtrl,
              chartSymCtrl: chartSymCtrl,
              selectedCategory: selectedCategory,
              onCategoryChanged: (cat) =>
                  setDlgState(() => selectedCategory = cat),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'إلغاء',
                style: GoogleFonts.outfit(color: textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentCyan,
                foregroundColor: spaceBackground,
              ),
              onPressed: () async {
                final sym = symCtrl.text.trim();
                final chartSym = chartSymCtrl.text.trim().toUpperCase();
                if (sym.isEmpty || chartSym.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('أدخل اسم الزوج ورمز الشارت'),
                      backgroundColor: putRed,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx);
                try {
                  await Supabase.instance.client.from('pairs').insert({
                    'symbol': sym,
                    'chart_symbol': chartSym,
                    'category': selectedCategory,
                    'type': selectedCategory,
                    'order': DateTime.now().millisecondsSinceEpoch,
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تمت إضافة $sym ✅'),
                        backgroundColor: callGreen,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('خطأ: $e'),
                        backgroundColor: putRed,
                        duration: const Duration(seconds: 6),
                      ),
                    );
                  }
                }
              },
              child: Text(
                'إضافة',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPairDialog(Map<String, dynamic> pair) {
    final symCtrl = TextEditingController(
      text: pair['symbol'] as String? ?? '',
    );
    final chartSymCtrl = TextEditingController(
      text: pair['chart_symbol'] as String? ?? '',
    );
    String selectedCategory = pair['category'] as String? ?? 'forex';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: cardBgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'تعديل الزوج',
            style: GoogleFonts.outfit(
              color: textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: _pairDialogContent(
              symCtrl: symCtrl,
              chartSymCtrl: chartSymCtrl,
              selectedCategory: selectedCategory,
              onCategoryChanged: (cat) =>
                  setDlgState(() => selectedCategory = cat),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'إلغاء',
                style: GoogleFonts.outfit(color: textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentCyan,
                foregroundColor: spaceBackground,
              ),
              onPressed: () {
                final sym = symCtrl.text.trim();
                final chartSym = chartSymCtrl.text.trim().toUpperCase();
                if (sym.isEmpty || chartSym.isEmpty) return;
                Supabase.instance.client.from('pairs').update({
                      'symbol': sym,
                      'chart_symbol': chartSym,
                      'category': selectedCategory,
                      'type': selectedCategory,
                    }).eq('id', pair['id'] as String);
                Navigator.pop(ctx);
              },
              child: Text(
                'حفظ',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importPairsFromCSV() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    final content = utf8.decode(bytes);
    final lines = content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return;

    // Skip header row if present
    final dataLines = lines.first.toLowerCase().startsWith('symbol')
        ? lines.skip(1).toList()
        : lines;

    int added = 0;
    final List<Map<String, dynamic>> rows = [];
    // CSV format: symbol, chartSymbol, category
    for (final line in dataLines) {
      final cols = line
          .split(',')
          .map((c) => c.trim().replaceAll('"', ''))
          .toList();
      if (cols.length < 3) continue;
      final sym = cols[0];
      final chartSym = cols[1].toUpperCase();
      if (sym.isEmpty || chartSym.isEmpty) continue;
      final cat = cols[2].toLowerCase().isNotEmpty
          ? cols[2].toLowerCase()
          : 'forex';
      rows.add({
        'symbol': sym,
        'chart_symbol': chartSym,
        'category': cat,
        'type': cat,
        'order': DateTime.now().millisecondsSinceEpoch + added,
      });
      added++;
    }
    if (added == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'لم يتم العثور على بيانات صحيحة في الملف',
              style: GoogleFonts.outfit(),
            ),
          ),
        );
      }
      return;
    }
    await Supabase.instance.client.from('pairs').upsert(rows);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم استيراد $added زوج بنجاح',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: callGreen,
        ),
      );
    }
  }

  Widget _pairField(
    TextEditingController ctrl,
    String label,
    String hint,
    IconData icon,
  ) {
    return TextField(
      controller: ctrl,
      style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 12),
        hintText: hint,
        hintStyle: GoogleFonts.outfit(
          color: textSecondary.withAlpha(100),
          fontSize: 11,
        ),
        prefixIcon: Icon(icon, color: textSecondary, size: 18),
        filled: true,
        fillColor: spaceBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderGlow),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderGlow),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accentCyan),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }


  Widget _buildPairsSection() {
    const catLabels = {
      'forex': 'فوركس',
      'metals': 'معادن',
      'commodities': 'سلع',
      'crypto': 'كريبتو',
    };
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('pairs')
          .stream(primaryKey: ['id']),
      builder: (context, snap) {
        final allPairs = snap.hasData
            ? ((snap.data ?? [])
                ..sort((a, b) => ((a['order'] as int? ?? 0)
                    .compareTo(b['order'] as int? ?? 0))))
            : <Map<String, dynamic>>[];

        final q = _pairsSearchQuery.toLowerCase();
        final pairs = q.isEmpty
            ? allPairs
            : allPairs.where((p) {
                final sym = (p['symbol'] as String? ?? '').toLowerCase();
                final chartSym = (p['chart_symbol'] as String? ?? '')
                    .toLowerCase();
                return sym.contains(q) || chartSym.contains(q);
              }).toList();

        return Container(
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderGlow),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentCyan.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.currency_exchange_rounded,
                        color: accentCyan,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'أزواج التداول',
                            style: GoogleFonts.outfit(
                              color: textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${allPairs.length} زوج',
                            style: GoogleFonts.outfit(
                              color: textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'استيراد من CSV',
                      icon: Icon(
                        Icons.upload_file_rounded,
                        color: textSecondary,
                        size: 20,
                      ),
                      onPressed: _importPairsFromCSV,
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentCyan,
                        foregroundColor: spaceBackground,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(
                        'إضافة زوج',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _showAddPairDialog,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF1F2937)),
              // Search box
              if (allPairs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: TextField(
                    controller: _pairsSearchCtrl,
                    style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'ابحث عن زوج...',
                      hintStyle: GoogleFonts.outfit(
                        color: textSecondary,
                        fontSize: 12,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: textSecondary,
                        size: 18,
                      ),
                      suffixIcon: _pairsSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: textSecondary,
                                size: 16,
                              ),
                              onPressed: () => setState(() {
                                _pairsSearchCtrl.clear();
                                _pairsSearchQuery = '';
                              }),
                            )
                          : null,
                      filled: true,
                      fillColor: spaceBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderGlow),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderGlow),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: accentCyan),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _pairsSearchQuery = v),
                  ),
                ),
              // Pairs list
              if (allPairs.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Text(
                    'لا توجد أزواج بعد — اضغط إضافة زوج للبدء',
                    style: GoogleFonts.outfit(
                      color: textSecondary,
                      fontSize: 12,
                    ),
                  ),
                )
              else if (pairs.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    'لا توجد نتائج لـ "$_pairsSearchQuery"',
                    style: GoogleFonts.outfit(
                      color: textSecondary,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 420,
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...[
                            'forex',
                            'metals',
                            'commodities',
                            'crypto',
                          ].expand((cat) {
                            final catPairs = pairs
                                .where((p) => p['category'] == cat)
                                .toList();
                            if (catPairs.isEmpty) return <Widget>[];
                            return [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  4,
                                ),
                                child: Text(
                                  catLabels[cat] ?? cat,
                                  style: GoogleFonts.outfit(
                                    color: textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ...catPairs.map(
                                (pair) => ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    4,
                                    0,
                                  ),
                                  title: Text(
                                    pair['symbol'] as String? ?? '',
                                    style: GoogleFonts.outfit(
                                      color: textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    pair['chart_symbol'] as String? ?? '',
                                    style: GoogleFonts.outfit(
                                      color: textSecondary,
                                      fontSize: 10,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.edit_rounded,
                                          color: accentCyan,
                                          size: 16,
                                        ),
                                        tooltip: 'تعديل',
                                        onPressed: () =>
                                            _showEditPairDialog(pair),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          color: putRed,
                                          size: 16,
                                        ),
                                        tooltip: 'حذف',
                                        onPressed: () => Supabase
                                            .instance.client
                                            .from('pairs')
                                            .delete()
                                            .eq('id', pair['id'] as String),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ];
                          }),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
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
    _startNewUserListener();
    _fetchDbSize();
    _dbSizeTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _fetchDbSize(),
    );
  }

  Future<void> _fetchDbSize() async {
    try {
      final result = await Supabase.instance.client.rpc('db_size_mb');
      final size = double.tryParse(result.toString());
      if (size == null) return;
      if (!mounted) return;
      setState(() => _dbSizeMb = size);
    } catch (e) {
      // Ignore errors: don't crash the dashboard or show a false warning.
      debugPrint('db_size_mb fetch failed: $e');
    }
  }

  Widget _buildDbSizeWarning() {
    final size = _dbSizeMb;
    if (size == null || size < 450) return const SizedBox.shrink();
    final isFull = size >= 500;
    final sizeStr = size.toStringAsFixed(1);
    final message = isFull
        ? 'قاعدة البيانات ممتلئة ($sizeStr/500MB) — لن يتم حفظ بيانات جديدة'
        : 'تحذير: قاعدة البيانات شبه ممتلئة ($sizeStr/500MB)';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isFull ? putRed : warningOrange,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startNewUserListener() {
    // Track IDs seen so far; first batch populates the set without alerting
    final Set<String> _seenIds = {};
    bool _initialized = false;
    _newUserSubscription = Supabase.instance.client
        .from('users')
        .stream(primaryKey: ['id'])
        .listen((rows) {
          if (!_initialized) {
            // First emission: just seed the known IDs, don't alert
            _seenIds.addAll(rows.map((r) => r['id'] as String? ?? '').where((id) => id.isNotEmpty));
            _initialized = true;
            return;
          }
          for (final row in rows) {
            final rowId = row['id'] as String? ?? '';
            if (rowId.isEmpty || _seenIds.contains(rowId)) continue;
            _seenIds.add(rowId);
            final id = row['account_id'] as String? ?? rowId;
            final broker = row['broker'] as String? ?? '';
            _onNewUser(id, broker);
          }
        });
  }

  void _onNewUser(String accountId, String broker) {
    _playAdminBeep();
    setState(() {
      _liveNewUsers.insert(0, {
        'accountId': accountId,
        'broker': broker,
        'time': DateTime.now(),
      });
      if (_liveNewUsers.length > 50) _liveNewUsers.removeLast();
    });
    _showNewUserBanner(accountId, broker);
  }

  void _playAdminBeep() {
    if (kIsWeb) {
      try {
        jsEval(
          r'''(function(){try{var C=new(window.AudioContext||window.webkitAudioContext)();function tone(f,s,d){var o=C.createOscillator(),g=C.createGain();o.type="sine";o.frequency.value=f;g.gain.setValueAtTime(0.35,C.currentTime+s);g.gain.exponentialRampToValueAtTime(0.001,C.currentTime+s+d);o.connect(g);g.connect(C.destination);o.start(C.currentTime+s);o.stop(C.currentTime+s+d+0.01);}tone(880,0,0.12);tone(1100,0.15,0.18);}catch(e){}})();''',
        );
      } catch (_) {}
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
                boxShadow: [
                  BoxShadow(color: callGreen.withAlpha(40), blurRadius: 20),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: callGreen.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_add_rounded,
                      color: callGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'مستخدم جديد سجّل! 🎉',
                          style: GoogleFonts.outfit(
                            color: callGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID: $accountId',
                          style: GoogleFonts.outfit(
                            color: textPrimary,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          broker,
                          style: GoogleFonts.outfit(
                            color: textSecondary,
                            fontSize: 10,
                          ),
                        ),
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

  @override
  void dispose() {
    _newUserSubscription?.cancel();
    _dbSizeTimer?.cancel();
    _newUserOverlay?.remove();
    _globalVipValueController.dispose();
    _brNameCtrl.dispose();
    _brLogoCtrl.dispose();
    _brLinkCtrl.dispose();
    _brPromoCtrl.dispose();
    _brBonusCtrl.dispose();
    _brMinDepCtrl.dispose();
    _brOrderCtrl.dispose();
    _brClickKeyCtrl.dispose();
    _brColorCtrl.dispose();
    _updVersionCtrl.dispose();
    _updFeaturesCtrl.dispose();
    _updLinkCtrl.dispose();
    _maintMsgCtrl.dispose();
    _maintHoursCtrl.dispose();
    _stdStrategyCtrl.dispose();
    _vipStrategyCtrl.dispose();
    _pairsSearchCtrl.dispose();
    super.dispose();
  }

  // Atomically reset device ID
  Future<void> _resetDeviceId(String accountId) async {
    try {
      await Supabase.instance.client
          .from('users')
          .update({'device_id': ''})
          .eq('id', accountId);
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
        title: Text(
          'حظر المستخدم $accountId',
          style: GoogleFonts.outfit(color: putRed, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'سيظهر للمستخدم رسالة حظر ولن يتمكن من استخدام التطبيق.',
              style: GoogleFonts.outfit(color: textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'سبب الحظر (اختياري)',
                hintStyle: GoogleFonts.outfit(
                  color: textSecondary,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: spaceBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: borderGlow),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: borderGlow),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: putRed),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'إلغاء',
              style: GoogleFonts.outfit(color: textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _toggleBanUser(accountId, true, reasonCtrl.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: putRed,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'تأكيد الحظر',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleGuaranteedWin(String accountId, bool enable) async {
    try {
      await Supabase.instance.client
          .from('users')
          .update({'guaranteed_win': enable})
          .eq('id', accountId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enable
                  ? '🛡️ تم تفعيل ضمان الفوز للمستخدم $accountId'
                  : '❌ تم إلغاء ضمان الفوز للمستخدم $accountId',
            ),
            backgroundColor: enable ? callGreen : textSecondary,
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

  Future<void> _toggleBanUser(String accountId, bool ban, String reason) async {
    try {
      await Supabase.instance.client
          .from('users')
          .update({'is_banned': ban, 'ban_reason': reason})
          .eq('id', accountId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ban
                  ? '🚫 تم حظر المستخدم $accountId'
                  : '✅ تم رفع الحظر عن $accountId',
            ),
            backgroundColor: ban ? putRed : callGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: putRed),
        );
    }
  }

  // Delete user from database
  Future<void> _deleteUser(String accountId) async {
    try {
      await Supabase.instance.client
          .from('users')
          .delete()
          .eq('id', accountId);
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

      await Supabase.instance.client
          .from('users')
          .update({
            'role': makeVip ? 'vip' : 'standard',
            'vip_expiry': expiryDate != null
                ? expiryDate.toIso8601String()
                : null,
          })
          .eq('id', accountId);

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
    final expiryDate = DateTime.now().add(duration);
    final expiryIso = expiryDate.toIso8601String();

    try {
      // Write global config first so new registrations pick it up immediately
      await Supabase.instance.client.from('configs').upsert({
        'id': 'globalVip',
        'data': {
          'enabled': true,
          'expiry': expiryIso,
          'durationText': durationText,
          'activatedAt': DateTime.now().toIso8601String(),
        },
      });

      // Fetch all users and update in one call (Supabase has no 500-doc limit here)
      final rows = await Supabase.instance.client.from('users').select('id');

      // Update all users in batches of 100 via repeated updates
      for (int i = 0; i < rows.length; i += 100) {
        final batch = rows.skip(i).take(100).map((r) => r['id'] as String).toList();
        for (final uid in batch) {
          await Supabase.instance.client
              .from('users')
              .update({'role': 'vip', 'vip_expiry': expiryIso})
              .eq('id', uid);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تفعيل VIP لجميع المستخدمين (${rows.length} مستخدم) لمدة $durationText ✅',
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
    try {
      // 1. Disable the global config
      await Supabase.instance.client.from('configs').upsert({
        'id': 'globalVip',
        'data': {
          'enabled': false,
          'disabledAt': DateTime.now().toIso8601String(),
        },
      });

      // 2. Downgrade ALL vip users back to standard
      final vipRows = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('role', 'vip');

      for (final row in vipRows) {
        await Supabase.instance.client
            .from('users')
            .update({'role': 'standard', 'vip_expiry': null})
            .eq('id', row['id'] as String);
      }
      final downgradedCount = vipRows.length;

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
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('clicks')
                .stream(primaryKey: ['id'])
                .eq('id', 'brokers'),
            builder: (context, snapshot) {
              if ((snapshot.data ?? []).isEmpty) {
                return const SizedBox();
              }
              final row = snapshot.data!.first;
              final data = row['data'] as Map<String, dynamic>?;
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
                  // Database almost-full warning banner (always visible)
                  _buildDbSizeWarning(),

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

  Widget _buildLogoImage(
    String url, {
    BoxFit fit = BoxFit.contain,
    Widget? placeholder,
  }) {
    final fallback =
        placeholder ??
        const Icon(Icons.storefront_rounded, color: Colors.grey, size: 20);
    if (url.isEmpty) return fallback;
    if (url.startsWith('data:')) {
      try {
        final bytes = base64Decode(url.substring(url.indexOf(',') + 1));
        return Image.memory(
          bytes,
          fit: fit,
          errorBuilder: (_, e, s) => fallback,
        );
      } catch (_) {
        return fallback;
      }
    }
    if (url.startsWith('http')) {
      return Image.network(url, fit: fit, errorBuilder: (_, e, s) => fallback);
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
            title: Text(
              'لون ثيم المنصة',
              style: GoogleFonts.outfit(
                color: textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
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
                child: Text(
                  'إلغاء',
                  style: GoogleFonts.outfit(color: textSecondary),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await Supabase.instance.client
                      .from('brokers')
                      .update({'themeColor': _colorToHex(tempColor)})
                      .eq('id', docId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم تحديث لون الثيم ✅'),
                        backgroundColor: tempColor,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: tempColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'حفظ اللون',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                ),
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
            title: Text(
              'اختيار لون الثيم',
              style: GoogleFonts.outfit(
                color: textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
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
                child: Text(
                  'إلغاء',
                  style: GoogleFonts.outfit(color: textSecondary),
                ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'تأكيد اللون',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                ),
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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from('users').stream(primaryKey: ['id']),
      builder: (context, userSnapshot) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client
              .from('clicks')
              .stream(primaryKey: ['id'])
              .eq('id', 'brokers'),
          builder: (context, clickSnapshot) {
            int totalUsers = 0;
            int vipUsers = 0;
            int standardUsers = 0;

            if (userSnapshot.hasData) {
              final userRows = userSnapshot.data ?? [];
              totalUsers = userRows.length;
              for (var doc in userRows) {
                final role = doc['role'] ?? 'standard';
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

            if ((clickSnapshot.data ?? []).isNotEmpty) {
              final data = clickSnapshot.data!.first['data'] as Map<String, dynamic>?;
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
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('users')
                  .stream(primaryKey: ['id'])
                  .order('created_at', ascending: false),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: accentCyan),
                  );
                }
                if (!snapshot.hasData || (snapshot.data ?? []).isEmpty) {
                  return const Center(
                    child: Text(
                      'لا يوجد مستخدمين مسجلين في قاعدة البيانات حالياً.',
                      style: TextStyle(color: textSecondary),
                    ),
                  );
                }

                // Filtering locally to allow fast real-time search & filter
                final allRows = snapshot.data ?? [];
                final filteredDocs = allRows.where((data) {
                  final accountId = (data['account_id'] ?? data['id'] ?? '')
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
                    return _buildUserListItem(filteredDocs[index]);
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
    final accountId = user['account_id'] ?? user['id'] ?? '----';
    final broker = user['broker'] ?? '----';
    final role = user['role'] ?? 'standard';
    final deviceId = user['device_id'] ?? '';
    final clickedBroker = user['clicked_broker'] ?? '';
    final isBanned = user['is_banned'] as bool? ?? false;
    final banReason = user['ban_reason'] as String? ?? '';
    final isGuaranteedWin = user['guaranteed_win'] as bool? ?? false;
    final createdAtData = user['created_at'];

    String dateStr = '----';
    if (createdAtData is String && createdAtData.isNotEmpty) {
      try {
        dateStr = DateFormat('yyyy/MM/dd HH:mm').format(DateTime.parse(createdAtData));
      } catch (_) {}
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
    final vipExpiryData = user['vip_expiry'];
    if (isVip && vipExpiryData is String && vipExpiryData.isNotEmpty) {
      try {
        final expiryDate = DateTime.parse(vipExpiryData);
        final isExpired = expiryDate.isBefore(DateTime.now());
        if (isExpired) {
          expiryStatusText =
              'منتهي الصلاحية ${DateFormat('yyyy/MM/dd').format(expiryDate)} ⚠️';
        } else {
          expiryStatusText =
              'ينتهي: ${DateFormat('yyyy/MM/dd HH:mm').format(expiryDate)}';
        }
      } catch (_) {}
    } else if (isVip) {
      expiryStatusText = 'تفعيل دائم';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: spaceBackground.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isBanned ? putRed.withAlpha(120) : borderGlow,
        ),
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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _toggleGuaranteedWin(accountId, !isGuaranteedWin),
                      icon: Icon(
                        isGuaranteedWin
                            ? Icons.shield_rounded
                            : Icons.shield_outlined,
                        size: 14,
                      ),
                      label: Text(isGuaranteedWin ? 'ضمان فعال' : 'ضمان الفوز'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isGuaranteedWin
                            ? callGreen
                            : textSecondary,
                        side: BorderSide(
                          color: isGuaranteedWin
                              ? callGreen.withAlpha(180)
                              : borderGlow,
                        ),
                        backgroundColor: isGuaranteedWin
                            ? callGreen.withAlpha(20)
                            : null,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showBanDialog(accountId, isBanned, banReason),
                      icon: Icon(
                        isBanned
                            ? Icons.lock_open_rounded
                            : Icons.block_rounded,
                        size: 14,
                      ),
                      label: Text(isBanned ? 'رفع الحظر' : 'حظر المستخدم'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isBanned ? callGreen : putRed,
                        side: BorderSide(
                          color: isBanned
                              ? callGreen.withAlpha(120)
                              : putRed.withAlpha(120),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Row 2: VIP + Reset Device
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showVipManagementDialog(
                        accountId,
                        isVip,
                        expiryStatusText,
                      ),
                      icon: const Icon(
                        Icons.workspace_premium_rounded,
                        size: 14,
                      ),
                      label: Text(isVip ? 'تعديل الـ VIP' : 'تفعيل VIP 👑'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isVip
                            ? Colors.amber.withAlpha(40)
                            : Colors.amber,
                        foregroundColor: isVip ? Colors.amber : Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                        side: isVip
                            ? const BorderSide(color: Colors.amber)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: deviceId != ''
                          ? () => _resetDeviceId(accountId)
                          : null,
                      icon: const Icon(Icons.restart_alt_rounded, size: 14),
                      label: const Text('فك قفل الجهاز'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amberAccent,
                        side: BorderSide(
                          color: deviceId != ''
                              ? Colors.amberAccent.withAlpha(120)
                              : borderGlow,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('brokers')
          .stream(primaryKey: ['id'])
          .order('order'),
      builder: (context, brokersSnap) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client
              .from('clicks')
              .stream(primaryKey: ['id'])
              .eq('id', 'brokers'),
          builder: (context, clicksSnap) {
            if (brokersSnap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: accentCyan),
              );
            }

            final clicksRow = (clicksSnap.data ?? []).isNotEmpty
                ? clicksSnap.data!.first['data'] as Map<String, dynamic>? ?? {}
                : <String, dynamic>{};
            final clickData = clicksRow;

            final brokerDocs = brokersSnap.data ?? [];

            final brokers = brokerDocs.map((d) {
              final hex = d['themeColor'] as String? ?? '';
              return {
                'name': d['name'] as String? ?? '',
                'logoUrl': d['logo_url'] as String? ?? '',
                'clickKey': d['click_key'] as String? ?? '',
                'color': hex.isNotEmpty ? _hexToColor(hex) : accentCyan,
              };
            }).toList();

            // Totals across all brokers
            int totalClicks = 0;
            int totalLogins = 0;
            for (final b in brokers) {
              final key = b['clickKey'] as String;
              totalClicks += (clickData[key] as int? ?? 0);
              totalLogins += (clickData['${key}Logins'] as int? ?? 0);
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'تحليلات روابط الشراكة ومعدلات التحويل',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
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
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: accentCyan,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  ...brokers.asMap().entries.expand((entry) {
                    final i = entry.key;
                    final b = entry.value;
                    final key = b['clickKey'] as String;
                    final clicks = clickData[key] as int? ?? 0;
                    final logins = clickData['${key}Logins'] as int? ?? 0;
                    return [
                      if (i > 0) const SizedBox(height: 16),
                      _buildBrokerAnalyticRow(
                        b['name'] as String,
                        clicks,
                        logins,
                        b['logoUrl'] as String,
                        b['color'] as Color,
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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('configs')
          .stream(primaryKey: ['id'])
          .eq('id', 'globalVip'),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? [];
        final data = rows.isNotEmpty
            ? rows.first['data'] as Map<String, dynamic>? ?? {}
            : null;
        final isGlobalVipEnabled = data?['enabled'] == true;
        final globalExpiry = data?['expiry'];
        final durationText = data?['durationText'] ?? '';

        String statusText = '';
        bool isExpired = false;
        if (isGlobalVipEnabled && globalExpiry is String && globalExpiry.isNotEmpty) {
          try {
            final expiryDate = DateTime.parse(globalExpiry);
            if (expiryDate.isBefore(DateTime.now())) {
              statusText =
                  'انتهت صلاحية VIP العام في ${DateFormat('yyyy/MM/dd HH:mm').format(expiryDate)} ⚠️';
              isExpired = true;
            } else {
              statusText =
                  'ينتهي في: ${DateFormat('yyyy/MM/dd HH:mm').format(expiryDate)}';
            }
          } catch (_) {}
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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('brokers')
          .stream(primaryKey: ['id'])
          .order('order'),
      builder: (context, snap) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'إدارة المنصات والروابط',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showBrokerDialog(null, null),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      'إضافة منصة جديدة',
                      style: GoogleFonts.outfit(fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentCyan,
                      foregroundColor: spaceBackground,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
              if (!snap.hasData || (snap.data ?? []).isEmpty)
                Center(
                  child: Text(
                    'لا توجد منصات مضافة بعد',
                    style: GoogleFonts.outfit(color: textSecondary),
                  ),
                )
              else
                ...(snap.data ?? []).map((d) {
                  final isActive = d['is_active'] as bool? ?? true;
                  final isRec = d['is_recommended'] as bool? ?? false;
                  final logoUrl = d['logo_url'] as String? ?? '';
                  final colorHex = d['themeColor'] as String? ?? '';
                  final cardColor = colorHex.isNotEmpty
                      ? _hexToColor(colorHex)
                      : accentCyan;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isRec
                            ? callGreen.withAlpha(150)
                            : cardColor.withAlpha(100),
                        width: isRec ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
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
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(left: 6),
                                    decoration: BoxDecoration(
                                      color: cardColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Text(
                                    d['name'] ?? '',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      color: textPrimary,
                                    ),
                                  ),
                                  if (isRec) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: callGreen.withAlpha(30),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'مُرشحة',
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          color: callGreen,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (!isActive) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: putRed.withAlpha(30),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'مخفية',
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          color: putRed,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                d['registration_link'] ?? '',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  color: textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              if ((d['promo_code'] as String? ?? '').isNotEmpty)
                                Text(
                                  'كود: ${d['promo_code']} | بونص: ${d['bonus_percent']}% على إيداع \$${d['min_deposit']}+',
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    color: callGreen,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: 'تغيير لون الثيم',
                          child: GestureDetector(
                            onTap: () =>
                                _showQuickColorPicker(d['id'] as String, cardColor),
                            child: Container(
                              width: 32,
                              height: 32,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: cardColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white24,
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.palette_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showBrokerDialog(d['id'] as String, d),
                          icon: const Icon(
                            Icons.edit_rounded,
                            color: accentCyan,
                            size: 20,
                          ),
                          tooltip: 'تعديل',
                        ),
                        IconButton(
                          onPressed: () =>
                              _confirmDeleteBroker(d['id'] as String, d['name'] ?? ''),
                          icon: const Icon(
                            Icons.delete_rounded,
                            color: putRed,
                            size: 20,
                          ),
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
      _brNameCtrl.text = data['name'] ?? '';
      _brLogoCtrl.text = data['logo_url'] ?? '';
      _brLinkCtrl.text = data['registration_link'] ?? '';
      _brPromoCtrl.text = data['promo_code'] ?? '';
      _brBonusCtrl.text = (data['bonus_percent'] ?? 0).toString();
      _brMinDepCtrl.text = (data['min_deposit'] ?? 0).toString();
      _brOrderCtrl.text = (data['order'] ?? 1).toString();
      _brClickKeyCtrl.text = data['click_key'] ?? '';
      _brIsRecommended = data['is_recommended'] ?? false;
      _brIsActive = data['is_active'] ?? true;
      _brLogoPreview = data['logo_url'] ?? '';
      final colorHex = data['themeColor'] as String? ?? '';
      _brThemeColor = colorHex.isNotEmpty ? _hexToColor(colorHex) : accentCyan;
      _brColorCtrl.text = colorHex.isNotEmpty
          ? colorHex
          : _colorToHex(accentCyan);
    } else {
      _brNameCtrl.clear();
      _brLogoCtrl.clear();
      _brLinkCtrl.clear();
      _brPromoCtrl.clear();
      _brBonusCtrl.text = '0';
      _brMinDepCtrl.text = '0';
      _brOrderCtrl.text = '1';
      _brClickKeyCtrl.clear();
      _brIsRecommended = false;
      _brIsActive = true;
      _brLogoPreview = '';
      _brThemeColor = accentCyan;
      _brColorCtrl.text = _colorToHex(accentCyan);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: cardBgColor,
          title: Text(
            id == null ? 'إضافة منصة جديدة' : 'تعديل المنصة',
            style: GoogleFonts.outfit(
              color: textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dlgField(
                    _brNameCtrl,
                    'اسم المنصة *',
                    Icons.storefront_rounded,
                  ),

                  // ── Logo section ───────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            // Preview box
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: borderGlow),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: _buildLogoImage(
                                  _brLogoPreview,
                                  placeholder: const Icon(
                                    Icons.image_rounded,
                                    color: Colors.grey,
                                  ),
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
                                    icon: const Icon(
                                      Icons.upload_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      'رفع صورة من الجهاز',
                                      style: GoogleFonts.outfit(fontSize: 12),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accentBlue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'أو الصق رابط URL للصورة أدناه',
                                    style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      color: textSecondary,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _brLogoCtrl,
                          onChanged: (v) =>
                              setDlg(() => _brLogoPreview = v.trim()),
                          style: GoogleFonts.outfit(
                            color: textPrimary,
                            fontSize: 12,
                          ),
                          decoration: InputDecoration(
                            hintText: 'https://example.com/logo.png',
                            hintStyle: GoogleFonts.outfit(
                              color: textSecondary,
                              fontSize: 11,
                            ),
                            prefixIcon: const Icon(
                              Icons.link_rounded,
                              color: textSecondary,
                              size: 16,
                            ),
                            filled: true,
                            fillColor: spaceBackground,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: borderGlow),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: borderGlow),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: accentCyan),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
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
                        Text(
                          'لون ثيم المنصة',
                          style: GoogleFonts.outfit(
                            color: textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => _showColorPickerDialog(setDlg),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _brThemeColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: borderGlow,
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.colorize_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
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
                                style: GoogleFonts.outfit(
                                  color: textPrimary,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  hintText: '#06B6D4',
                                  hintStyle: GoogleFonts.outfit(
                                    color: textSecondary,
                                    fontSize: 11,
                                  ),
                                  prefixIcon: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: _brThemeColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: spaceBackground,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: borderGlow,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: borderGlow,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: _brThemeColor,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _showColorPickerDialog(setDlg),
                              icon: const Icon(Icons.palette_rounded, size: 16),
                              label: Text(
                                'اختيار',
                                style: GoogleFonts.outfit(fontSize: 12),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _brThemeColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  _dlgField(_brLinkCtrl, 'رابط التسجيل *', Icons.link_rounded),

                  _dlgField(
                    _brClickKeyCtrl,
                    'مفتاح النقرات (بالإنجليزي، مثال: quotex)',
                    Icons.key_rounded,
                  ),
                  _dlgField(
                    _brPromoCtrl,
                    'البروموكود (اختياري)',
                    Icons.card_giftcard_rounded,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _dlgField(
                          _brBonusCtrl,
                          'نسبة البونص %',
                          Icons.percent_rounded,
                          isNum: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _dlgField(
                          _brMinDepCtrl,
                          'حد أدنى إيداع \$',
                          Icons.attach_money_rounded,
                          isNum: true,
                        ),
                      ),
                    ],
                  ),
                  _dlgField(
                    _brOrderCtrl,
                    'ترتيب العرض (1, 2, 3...)',
                    Icons.sort_rounded,
                    isNum: true,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: _brIsRecommended,
                        onChanged: (v) =>
                            setDlg(() => _brIsRecommended = v ?? false),
                        activeColor: callGreen,
                      ),
                      Text(
                        'منصة مُرشحة',
                        style: GoogleFonts.outfit(
                          color: textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Checkbox(
                        value: _brIsActive,
                        onChanged: (v) => setDlg(() => _brIsActive = v ?? true),
                        activeColor: accentCyan,
                      ),
                      Text(
                        'نشطة / مرئية',
                        style: GoogleFonts.outfit(
                          color: textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'إلغاء',
                style: GoogleFonts.outfit(color: textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _saveBroker();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accentCyan,
                foregroundColor: spaceBackground,
              ),
              child: Text(
                id == null ? 'إضافة' : 'حفظ',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dlgField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool isNum = false,
  }) {
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
          filled: true,
          fillColor: spaceBackground,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: borderGlow),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: borderGlow),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: accentCyan),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
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
        _brLogoPreview = dataUrl;
      });
    }
  }

  Future<void> _saveBroker() async {
    final name = _brNameCtrl.text.trim();
    final link = _brLinkCtrl.text.trim();
    if (name.isEmpty || link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الاسم ورابط التسجيل مطلوبان'),
          backgroundColor: putRed,
        ),
      );
      return;
    }
    try {
      final Map<String, dynamic> data = {
        'name': name,
        'logo_url': _brLogoCtrl.text.trim(),
        'registration_link': link,
        'promo_code': _brPromoCtrl.text.trim(),
        'bonus_percent': int.tryParse(_brBonusCtrl.text) ?? 0,
        'min_deposit': int.tryParse(_brMinDepCtrl.text) ?? 0,
        'order': int.tryParse(_brOrderCtrl.text) ?? 1,
        'click_key': _brClickKeyCtrl.text.trim().isNotEmpty
            ? _brClickKeyCtrl.text.trim()
            : name.toLowerCase().replaceAll(' ', '_'),
        'is_recommended': _brIsRecommended,
        'is_active': _brIsActive,
        'themeColor': _colorToHex(_brThemeColor),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (_editingBrokerId != null) {
        await Supabase.instance.client
            .from('brokers')
            .update(data)
            .eq('id', _editingBrokerId!);
      } else {
        data['created_at'] = DateTime.now().toIso8601String();
        await Supabase.instance.client.from('brokers').insert(data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _editingBrokerId != null
                  ? 'تم تحديث المنصة بنجاح ✅'
                  : 'تمت إضافة المنصة بنجاح ✅',
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

  void _confirmDeleteBroker(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBgColor,
        title: Text(
          'حذف منصة $name',
          style: GoogleFonts.outfit(color: putRed, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل أنت متأكد؟ سيتم حذف المنصة نهائياً.',
          style: GoogleFonts.outfit(color: textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'إلغاء',
              style: GoogleFonts.outfit(color: textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await Supabase.instance.client
                  .from('brokers')
                  .delete()
                  .eq('id', id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم حذف المنصة'),
                    backgroundColor: putRed,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: putRed,
              foregroundColor: Colors.white,
            ),
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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('configs')
          .stream(primaryKey: ['id'])
          .eq('id', 'appUpdate'),
      builder: (context, snap) {
        final rows = snap.data ?? [];
        final existing = rows.isNotEmpty
            ? rows.first['data'] as Map<String, dynamic>?
            : null;
        final isActive = existing?['hasUpdate'] as bool? ?? false;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إرسال تحديث للمستخدمين',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
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
                      const Icon(
                        Icons.check_circle_rounded,
                        color: callGreen,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '✅ يوجد تحديث نشط حالياً — النسخة: ${existing?['version'] ?? ''}',
                          style: GoogleFonts.outfit(
                            color: callGreen,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _clearUpdate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: putRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        child: Text(
                          'إلغاء التحديث',
                          style: GoogleFonts.outfit(fontSize: 12),
                        ),
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
                    Text(
                      'إعداد التحديث الجديد',
                      style: GoogleFonts.outfit(
                        color: textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _dlgField(
                      _updVersionCtrl,
                      'رقم النسخة الجديدة (مثال: 2.1.0)',
                      Icons.new_releases_rounded,
                    ),
                    _dlgField(
                      _updLinkCtrl,
                      'رابط التحميل/التحديث',
                      Icons.download_rounded,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: _updFeaturesCtrl,
                        maxLines: 4,
                        style: GoogleFonts.outfit(
                          color: textPrimary,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: 'المميزات الجديدة (كل ميزة في سطر)',
                          hintStyle: GoogleFonts.outfit(
                            color: textSecondary,
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: spaceBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: borderGlow),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: borderGlow),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: accentCyan),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                    ),
                    StatefulBuilder(
                      builder: (ctx, setLocal) => Row(
                        children: [
                          Checkbox(
                            value: _updIsForced,
                            onChanged: (v) {
                              setState(() => _updIsForced = v ?? false);
                              setLocal(() {});
                            },
                            activeColor: putRed,
                          ),
                          Text(
                            'إجباري — لا يمكن تخطيه',
                            style: GoogleFonts.outfit(
                              color: textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _publishUpdate,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        'نشر التحديث الآن',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentCyan,
                        foregroundColor: spaceBackground,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
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
    final link = _updLinkCtrl.text.trim();
    if (version.isEmpty || link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رقم النسخة والرابط مطلوبان'),
          backgroundColor: putRed,
        ),
      );
      return;
    }
    final features = _updFeaturesCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    try {
      await Supabase.instance.client.from('configs').upsert({
        'id': 'appUpdate',
        'data': {
          'hasUpdate': true,
          'version': version,
          'features': features,
          'downloadLink': link,
          'isForced': _updIsForced,
          'publishedAt': DateTime.now().toIso8601String(),
        },
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم نشر التحديث بنجاح ✅'),
            backgroundColor: callGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: putRed),
        );
    }
  }

  Future<void> _clearUpdate() async {
    await Supabase.instance.client.from('configs').upsert({
      'id': 'appUpdate',
      'data': {'hasUpdate': false},
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إلغاء التحديث'),
          backgroundColor: callGreen,
        ),
      );
    }
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
          Text(
            'تحكم في حالة التطبيق',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
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
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('configs')
                .stream(primaryKey: ['id'])
                .eq('id', 'maintenance'),
            builder: (context, snap) {
              final rows = snap.data ?? [];
              final d = rows.isNotEmpty
                  ? rows.first['data'] as Map<String, dynamic>?
                  : null;
              final isActive = d?['isActive'] as bool? ?? false;
              String endsAtStr = '';
              if (isActive && d?['endsAt'] is String && (d!['endsAt'] as String).isNotEmpty) {
                DateTime? endsAt;
                try { endsAt = DateTime.parse(d['endsAt'] as String); } catch (_) {}
                if (endsAt != null) {
                final remaining = endsAt.difference(DateTime.now());
                if (remaining.isNegative) {
                  endsAtStr = 'انتهت الصيانة (يجب الإيقاف يدوياً)';
                } else {
                  final h = remaining.inHours;
                  final m = remaining.inMinutes % 60;
                  endsAtStr =
                      'ينتهي خلال: $hس $mد'; // h and m are single letters — braces needed
                }
                } // end if (endsAt != null)
              }

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive ? putRed.withAlpha(120) : borderGlow,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isActive
                                ? putRed.withAlpha(20)
                                : accentBlue.withAlpha(20),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isActive
                                ? Icons.construction_rounded
                                : Icons.check_circle_rounded,
                            color: isActive ? putRed : callGreen,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isActive
                                    ? '🔴 التطبيق في وضع الصيانة'
                                    : '🟢 التطبيق يعمل بشكل طبيعي',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                              if (isActive && endsAtStr.isNotEmpty)
                                Text(
                                  endsAtStr,
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    color: putRed,
                                  ),
                                ),
                              if (isActive && d?['message'] != null)
                                Text(
                                  d!['message'],
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    color: textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isActive)
                          ElevatedButton(
                            onPressed: _deactivateMaintenance,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: callGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            child: Text(
                              'تشغيل التطبيق',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (!isActive) ...[
                      const Divider(color: borderGlow, height: 24),
                      Text(
                        'تفعيل وضع الصيانة',
                        style: GoogleFonts.outfit(
                          color: textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _maintHoursCtrl,
                              keyboardType: TextInputType.number,
                              style: GoogleFonts.outfit(
                                color: textPrimary,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                hintText: 'مدة الصيانة بالساعات',
                                hintStyle: GoogleFonts.outfit(
                                  color: textSecondary,
                                  fontSize: 12,
                                ),
                                prefixIcon: const Icon(
                                  Icons.timer_rounded,
                                  color: textSecondary,
                                  size: 18,
                                ),
                                filled: true,
                                fillColor: spaceBackground,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: borderGlow,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: borderGlow,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: putRed),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _maintMsgCtrl,
                        style: GoogleFonts.outfit(
                          color: textPrimary,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: 'رسالة تظهر للمستخدمين',
                          hintStyle: GoogleFonts.outfit(
                            color: textSecondary,
                            fontSize: 12,
                          ),
                          prefixIcon: const Icon(
                            Icons.message_rounded,
                            color: textSecondary,
                            size: 18,
                          ),
                          filled: true,
                          fillColor: spaceBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: borderGlow),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: borderGlow),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: putRed),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _activateMaintenance,
                        icon: const Icon(Icons.construction_rounded, size: 18),
                        label: Text(
                          'إيقاف التطبيق للصيانة',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: putRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('configs')
                .stream(primaryKey: ['id'])
                .eq('id', 'chart_settings'),
            builder: (context, snap) {
              final rows = snap.data ?? [];
              final d = rows.isNotEmpty
                  ? rows.first['data'] as Map<String, dynamic>?
                  : null;
              final currentMode = d?['mode'] as String? ?? 'sim';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (currentMode == 'tv') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withAlpha(180),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.red.shade600,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_rounded,
                            color: Colors.red.shade300,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '⚠️ الاسكراب مفعل الآن — يؤثر على كل المستخدمين فوراً!',
                              style: GoogleFonts.outfit(
                                color: Colors.red.shade200,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: currentMode == 'tv'
                            ? Colors.red.shade700
                            : accentCyan.withAlpha(80),
                        width: currentMode == 'tv' ? 1.5 : 1,
                      ),
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
                              child: const Icon(
                                Icons.candlestick_chart_rounded,
                                color: accentCyan,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'مصدر بيانات الشارت',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      color: textPrimary,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    currentMode == 'tv'
                                        ? '🔴 نشط: اسكرابنج TradingView (بيانات حقيقية)'
                                        : '🟢 نشط: محاكي واقعي (بيانات افتراضية)',
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
                  ), // Container
                ], // Column children
              ); // Column
            },
          ),

          const SizedBox(height: 16),

          // ── Social Links ──────────────────────────────────────────
          _buildSocialLinksSection(),
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
                Text(
                  'المستخدمون المحظورون',
                  style: GoogleFonts.outfit(
                    color: textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'لإدارة الحظر، اذهب إلى تبويب "المستخدمين" واضغط على زر "حظر" بجانب أي مستخدم.',
                  style: GoogleFonts.outfit(color: textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client
                      .from('users')
                      .stream(primaryKey: ['id'])
                      .eq('is_banned', true),
                  builder: (context, snap) {
                    if (!snap.hasData || (snap.data ?? []).isEmpty) {
                      return Text(
                        'لا يوجد مستخدمون محظورون حالياً ✅',
                        style: GoogleFonts.outfit(
                          color: callGreen,
                          fontSize: 12,
                        ),
                      );
                    }
                    return Column(
                      children: (snap.data ?? []).map((d) {
                        final id = d['account_id'] ?? d['id'];
                        final reason = d['ban_reason'] as String? ?? '';
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
                              const Icon(
                                Icons.block_rounded,
                                color: putRed,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      id.toString(),
                                      style: GoogleFonts.outfit(
                                        color: textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (reason.isNotEmpty)
                                      Text(
                                        reason,
                                        style: GoogleFonts.outfit(
                                          color: textSecondary,
                                          fontSize: 10,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _toggleBanUser(id.toString(), false, ''),
                                child: Text(
                                  'رفع الحظر',
                                  style: GoogleFonts.outfit(
                                    color: callGreen,
                                    fontSize: 11,
                                  ),
                                ),
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

  // ── Social Links Management ──────────────────────────────────────────────────
  Widget _buildSocialLinksSection() {
    final ytCtrl = TextEditingController();
    final tgCtrl = TextEditingController();
    final chatCtrl = TextEditingController();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('configs')
          .stream(primaryKey: ['id'])
          .eq('id', 'social'),
      builder: (context, snap) {
        final rows = snap.data ?? [];
        final data = rows.isNotEmpty
            ? rows.first['data'] as Map<String, dynamic>? ?? {}
            : <String, dynamic>{};

        final ytUrl = data['youtubeUrl'] as String? ?? '';
        final tgUrl = data['telegramUrl'] as String? ?? '';
        final chatUrl = data['chatUrl'] as String? ?? '';

        ytCtrl.text = ytUrl;
        tgCtrl.text = tgUrl;
        chatCtrl.text = chatUrl;

        Future<void> save() async {
          await Supabase.instance.client.from('configs').upsert({
            'id': 'social',
            'data': {
              'youtubeUrl': ytCtrl.text.trim(),
              'telegramUrl': tgCtrl.text.trim(),
              'chatUrl': chatCtrl.text.trim(),
            },
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('تم حفظ روابط السوشيال ✅'),
                backgroundColor: callGreen,
              ),
            );
          }
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderGlow),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.link_rounded,
                    color: Color(0xFF00FFF0),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'روابط السوشيال ميديا',
                    style: GoogleFonts.outfit(
                      color: textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'تظهر هذه الروابط للمستخدمين في التطبيق وصفحة الدخول.',
                style: GoogleFonts.outfit(color: textSecondary, fontSize: 10),
              ),
              const SizedBox(height: 14),
              // YouTube
              Row(
                children: [
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'رابط قناة يوتيوب',
                    style: GoogleFonts.outfit(
                      color: textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _inputField(
                controller: ytCtrl,
                hint: 'https://www.youtube.com/@euro_trader',
              ),
              const SizedBox(height: 10),
              // Telegram
              Row(
                children: [
                  const Icon(
                    Icons.send_rounded,
                    color: Color(0xFF29B6F6),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'رابط قناة تليجرام',
                    style: GoogleFonts.outfit(
                      color: textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _inputField(controller: tgCtrl, hint: 'https://t.me/euro_trd1'),
              const SizedBox(height: 10),
              // Chat / Contact
              Row(
                children: [
                  const Icon(
                    Icons.chat_bubble_rounded,
                    color: Colors.amber,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'رابط التواصل مع المطور',
                    style: GoogleFonts.outfit(
                      color: textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _inputField(controller: chatCtrl, hint: 'https://t.me/euro_trd'),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: save,
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: Text(
                    'حفظ الروابط',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A8CFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
              if (mode == 'tv') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => Directionality(
                    textDirection: TextDirection.rtl,
                    child: AlertDialog(
                      backgroundColor: const Color(0xFF12102A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.red.shade700, width: 2),
                      ),
                      title: Row(
                        children: [
                          Icon(
                            Icons.warning_rounded,
                            color: Colors.red.shade400,
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'تحذير!',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      content: const Text(
                        'تفعيل الاسكراب سيؤثر على جميع المستخدمين فوراً.\n\nهل أنت متأكد؟',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text(
                            'إلغاء',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                          ),
                          child: const Text('تفعيل الاسكراب'),
                        ),
                      ],
                    ),
                  ),
                );
                if (confirm != true) return;
              }
              // Read existing data first to merge, then upsert
              final existing = await Supabase.instance.client
                  .from('configs')
                  .select('data')
                  .eq('id', 'chart_settings')
                  .maybeSingle();
              final existingData = existing?['data'] as Map<String, dynamic>? ?? {};
              await Supabase.instance.client.from('configs').upsert({
                'id': 'chart_settings',
                'data': {...existingData, 'mode': mode},
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم تفعيل $label للمستخدمين ✅'),
                    backgroundColor: color,
                  ),
                );
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
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isSelected ? color : textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 10, color: textSecondary),
            ),
            if (isSelected) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'مفعّل الآن',
                  style: GoogleFonts.outfit(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الحقل فارغ — الصق محتوى الـ JSON أولاً'),
          backgroundColor: putRed,
        ),
      );
      return;
    }
    try {
      final Map<String, dynamic> json = jsonDecode(raw);
      final docId = role == 'standard' ? 'strategy_standard' : 'strategy_vip';
      await Supabase.instance.client.from('configs').upsert({
        'id': docId,
        'data': json,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ تم رفع استراتيجية ${role == "standard" ? "Standard" : "VIP"} بنجاح',
            ),
            backgroundColor: callGreen,
          ),
        );
        ctrl.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في الـ JSON: $e'),
            backgroundColor: putRed,
          ),
        );
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
          Row(
            children: [
              const Icon(Icons.auto_graph_rounded, color: accentCyan, size: 18),
              const SizedBox(width: 8),
              Text(
                'استراتيجيات التحليل',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: accentCyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Standard
          Text(
            'استراتيجية Standard',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _stdStrategyCtrl,
            maxLines: 6,
            style: GoogleFonts.outfit(fontSize: 11, color: textPrimary),
            decoration: InputDecoration(
              hintText: 'الصق محتوى ملف JSON للاستراتيجية هنا...',
              hintStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 11),
              filled: true,
              fillColor: spaceBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: borderGlow),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: borderGlow),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: accentCyan),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _uploadStrategy('standard'),
            icon: const Icon(Icons.upload_rounded, size: 16),
            label: const Text('رفع استراتيجية Standard'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),

          const Divider(color: borderGlow, height: 28),

          // VIP
          Text(
            'استراتيجية VIP',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: Colors.amber,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _vipStrategyCtrl,
            maxLines: 6,
            style: GoogleFonts.outfit(fontSize: 11, color: textPrimary),
            decoration: InputDecoration(
              hintText: 'الصق محتوى ملف JSON للاستراتيجية VIP هنا...',
              hintStyle: GoogleFonts.outfit(color: textSecondary, fontSize: 11),
              filled: true,
              fillColor: spaceBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: borderGlow),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: borderGlow),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.amber.withAlpha(180)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _uploadStrategy('vip'),
            icon: const Icon(Icons.workspace_premium_rounded, size: 16),
            label: const Text('رفع استراتيجية VIP'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _activateMaintenance() async {
    final hours = int.tryParse(_maintHoursCtrl.text) ?? 2;
    final msg = _maintMsgCtrl.text.trim();
    final endsAt = DateTime.now().add(Duration(hours: hours));
    try {
      await Supabase.instance.client.from('configs').upsert({
        'id': 'maintenance',
        'data': {
          'isActive': true,
          'endsAt': endsAt.toIso8601String(),
          'message': msg.isNotEmpty ? msg : 'التطبيق متوقف مؤقتاً للصيانة',
          'updatedAt': DateTime.now().toIso8601String(),
        },
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔴 تم إيقاف التطبيق لمدة $hours ساعة للصيانة'),
            backgroundColor: putRed,
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: putRed),
        );
    }
  }

  Future<void> _deactivateMaintenance() async {
    await Supabase.instance.client.from('configs').upsert({
      'id': 'maintenance',
      'data': {
        'isActive': false,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم تشغيل التطبيق مجدداً'),
          backgroundColor: callGreen,
        ),
      );
    }
  }

  Widget _buildThemeColorSection() {
    const presets = <Map<String, String>>[
      {
        'name': 'سماوي + أزرق (افتراضي)',
        'primary': '#00FFF0',
        'secondary': '#1A8CFF',
      },
      {'name': 'أخضر + ذهبي', 'primary': '#00FF7F', 'secondary': '#FFAD00'},
      {'name': 'بنفسجي + وردي', 'primary': '#BF5FFF', 'secondary': '#FF5FAA'},
      {'name': 'أحمر + برتقالي', 'primary': '#FF2A6D', 'secondary': '#FF8C00'},
      {'name': 'أبيض + فضي', 'primary': '#FFFFFF', 'secondary': '#B0B8C8'},
      {'name': 'أصفر + ليموني', 'primary': '#FFE600', 'secondary': '#7FFF00'},
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentCyan.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.palette_rounded,
                  color: accentCyan,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ثيم ألوان التطبيق',
                      style: GoogleFonts.outfit(
                        color: textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'يُطبَّق على كل المستخدمين عند فتح التطبيق',
                      style: GoogleFonts.outfit(
                        color: textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: borderGlow, height: 20),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client
                .from('configs')
                .stream(primaryKey: ['id'])
                .eq('id', 'theme'),
            builder: (context, snap) {
              final themeRows = snap.data ?? [];
              final raw = themeRows.isNotEmpty
                  ? themeRows.first['data'] as Map<String, dynamic>? ?? {}
                  : <String, dynamic>{};

              String resolveHex(String key, String fallback) {
                final v = raw[key];
                if (v is String && v.startsWith('#')) return v;
                if (v is int)
                  return '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
                return fallback;
              }

              final primaryHex = resolveHex('primaryColor', '#00FFF0');
              final secondaryHex = resolveHex('secondaryColor', '#1A8CFF');
              final primaryColor = _hexToColor(primaryHex);
              final secondaryColor = _hexToColor(secondaryHex);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current colors row — clickable
                  Row(
                    children: [
                      Text(
                        'الثيم الحالي:',
                        style: GoogleFonts.outfit(
                          color: textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _showSiteThemeColorPicker(
                          'primaryColor',
                          primaryColor,
                        ),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white38,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withAlpha(120),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.colorize_rounded,
                            color: Colors.white70,
                            size: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _showSiteThemeColorPicker(
                          'secondaryColor',
                          secondaryColor,
                        ),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: secondaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white38,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: secondaryColor.withAlpha(120),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.colorize_rounded,
                            color: Colors.white70,
                            size: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$primaryHex  /  $secondaryHex',
                        style: GoogleFonts.outfit(
                          color: textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'ثيمات جاهزة:',
                    style: GoogleFonts.outfit(
                      color: textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets.map((p) {
                      final pp = p['primary']!;
                      final ps = p['secondary']!;
                      final isSelected =
                          primaryHex.toUpperCase() == pp.toUpperCase() &&
                          secondaryHex.toUpperCase() == ps.toUpperCase();
                      return InkWell(
                        onTap: () => _saveThemeColors(pp, ps),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? accentCyan.withAlpha(18)
                                : spaceBackground,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? accentCyan : borderGlow,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: _hexToColor(pp),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withAlpha(30),
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: _hexToColor(ps),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withAlpha(30),
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                p['name']!,
                                style: GoogleFonts.outfit(
                                  color: isSelected
                                      ? accentCyan
                                      : textSecondary,
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: accentCyan,
                                  size: 13,
                                ),
                              ],
                            ],
                          ),
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
      final existing = await Supabase.instance.client
          .from('configs')
          .select('data')
          .eq('id', 'theme')
          .maybeSingle();
      final existingData = existing?['data'] as Map<String, dynamic>? ?? {};
      await Supabase.instance.client.from('configs').upsert({
        'id': 'theme',
        'data': {
          ...existingData,
          'primaryColor': primary,
          'secondaryColor': secondary,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ تم حفظ الثيم — يُطبَّق على المستخدمين عند فتح التطبيق',
              style: GoogleFonts.outfit(),
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

  // ══════════════════════════════════════════════════════════════════
  // VIEW 8 — SITE THEME CONTROL
  // ══════════════════════════════════════════════════════════════════
  Widget _buildSiteThemeView() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('configs')
          .stream(primaryKey: ['id'])
          .eq('id', 'theme'),
      builder: (context, snap) {
        final siteThemeRows = snap.data ?? [];
        final data = siteThemeRows.isNotEmpty
            ? siteThemeRows.first['data'] as Map<String, dynamic>? ?? {}
            : <String, dynamic>{};

        String resolveHex(String key, String fallback) {
          final raw = data[key];
          if (raw is String && raw.startsWith('#')) return raw;
          if (raw is int)
            return '#${(raw & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
          return fallback;
        }

        final entries = [
          (
            'primaryColor',
            'اللون الرئيسي',
            resolveHex('primaryColor', '#06B6D4'),
          ),
          (
            'secondaryColor',
            'اللون الثانوي',
            resolveHex('secondaryColor', '#3B82F6'),
          ),
          (
            'backgroundColor',
            'لون الخلفية',
            resolveHex('backgroundColor', '#030712'),
          ),
          ('cardColor', 'لون الكاردات', resolveHex('cardColor', '#111827')),
          (
            'successColor',
            'لون الصعود / كول 📈',
            resolveHex('successColor', '#10B981'),
          ),
          (
            'dangerColor',
            'لون الهبوط / بوت 📉',
            resolveHex('dangerColor', '#EF4444'),
          ),
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
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
                    child: const Icon(
                      Icons.palette_rounded,
                      color: accentCyan,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ثيم الموقع الكامل',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          'اضغط على أي دايرة أو زرار "تغيير" — colour wheel + حقل hex',
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
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
                    return Column(
                      children: [
                        if (i > 0) const Divider(color: borderGlow, height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () =>
                                    _showSiteThemeColorPicker(key, color),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white24,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withAlpha(100),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.colorize_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: GoogleFonts.outfit(
                                        color: textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      hex,
                                      style: GoogleFonts.outfit(
                                        color: textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _showSiteThemeColorPicker(key, color),
                                icon: const Icon(
                                  Icons.palette_rounded,
                                  size: 14,
                                ),
                                label: Text(
                                  'تغيير',
                                  style: GoogleFonts.outfit(fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: color,
                                  side: BorderSide(color: color.withAlpha(180)),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _resetSiteTheme,
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: Text(
                  'استعادة الألوان الافتراضية',
                  style: GoogleFonts.outfit(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: textSecondary,
                  side: const BorderSide(color: borderGlow),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
            title: Text(
              'اختيار اللون',
              style: GoogleFonts.outfit(
                color: textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                    style: GoogleFonts.outfit(
                      color: textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    onChanged: (v) =>
                        setPickerState(() => tempColor = _hexToColor(v)),
                    decoration: InputDecoration(
                      hintText: '#06B6D4',
                      hintStyle: GoogleFonts.outfit(color: textSecondary),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: tempColor,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                        ),
                      ),
                      filled: true,
                      fillColor: spaceBackground,
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
                        borderSide: BorderSide(color: tempColor, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  hexCtrl.dispose();
                },
                child: Text(
                  'إلغاء',
                  style: GoogleFonts.outfit(color: textSecondary),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  hexCtrl.dispose();
                  final existingTheme = await Supabase.instance.client
                      .from('configs')
                      .select('data')
                      .eq('id', 'theme')
                      .maybeSingle();
                  final existingThemeData = existingTheme?['data'] as Map<String, dynamic>? ?? {};
                  await Supabase.instance.client.from('configs').upsert({
                    'id': 'theme',
                    'data': {
                      ...existingThemeData,
                      colorKey: _colorToHex(tempColor),
                    },
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '✅ تم حفظ اللون ${_colorToHex(tempColor)}',
                        ),
                        backgroundColor: tempColor,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: tempColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'حفظ اللون',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resetSiteTheme() async {
    await Supabase.instance.client.from('configs').upsert({
      'id': 'theme',
      'data': {
        'primaryColor': '#06B6D4',
        'secondaryColor': '#3B82F6',
        'backgroundColor': '#030712',
        'cardColor': '#111827',
        'successColor': '#10B981',
        'dangerColor': '#EF4444',
        'updatedAt': DateTime.now().toIso8601String(),
      },
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم استعادة الألوان الافتراضية'),
          backgroundColor: callGreen,
        ),
      );
    }
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
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              maxLines: maxLines,
              style: GoogleFonts.outfit(color: textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: GoogleFonts.outfit(
                  color: textSecondary,
                  fontSize: 12,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          ?suffix,
        ],
      ),
    );
  }
}
