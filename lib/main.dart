import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BreezeVpnApp());
}

class BreezeVpnApp extends StatelessWidget {
  const BreezeVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Breeze VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF071321),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF29D391),
          brightness: Brightness.dark,
        ),
            ),
      home: const HomePage(),
    );
  }
}

class ServerProfile {
  ServerProfile({
    required this.id,
    required this.name,
    required this.config,
    this.source = '',
    this.country = '🌐',
    this.pingMs,
    this.lastPingOk = false,
  });

  final String id;
  String name;
  String config;
  String source;
  String country;
  int? pingMs;
  bool lastPingOk;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'config': config,
        'source': source,
        'country': country,
        'pingMs': pingMs,
        'lastPingOk': lastPingOk,
      };

  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    return ServerProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Server',
      config: json['config'] as String? ?? '',
      source: json['source'] as String? ?? '',
      country: json['country'] as String? ?? '🌐',
      pingMs: json['pingMs'] as int?,
      lastPingOk: json['lastPingOk'] as bool? ?? false,
    );
  }
}

enum PingState { idle, checking, success, failed }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _profilesKey = 'profiles_v1';
  static const _selectedKey = 'selected_v1';

  final List<ServerProfile> _profiles = <ServerProfile>[];
  final TextEditingController _manualController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  late final V2ray _v2ray;
  final ValueNotifier<V2RayStatus> _v2rayStatus = ValueNotifier<V2RayStatus>(V2RayStatus());

  String? _selectedId;
  String? _coreVersion;
  String? _activeProfileId;
  PingState _selectedPingState = PingState.idle;
  int? _selectedPing;
  bool _initializing = true;
  bool _busy = false;

  ServerProfile? get _selectedProfile {
    if (_selectedId == null) return null;
    for (final profile in _profiles) {
      if (profile.id == _selectedId) return profile;
    }
    return null;
  }

  bool get _connected => _v2rayStatus.value.state.toUpperCase() == 'CONNECTED';
  bool get _isConnecting => _v2rayStatus.value.state.toUpperCase() == 'CONNECTING';

  @override
  void initState() {
    super.initState();
    _v2ray = V2ray(
      onStatusChanged: (status) {
        _v2rayStatus.value = status;
        if (status.state.toUpperCase() == 'DISCONNECTED') {
          _activeProfileId = null;
        }
        if (mounted) setState(() {});
      },
    );
    _init();
  }

  Future<void> _init() async {
    await _loadProfiles();
    try {
      await _v2ray.initialize(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
      _coreVersion = await _v2ray.getCoreVersion();
    } catch (_) {
      // The UI remains usable so the build can still be tested without a VPN permission.
    }

    if (_selectedId != null && _selectedProfile != null) {
      _selectedPing = _selectedProfile!.pingMs;
      _selectedPingState = _selectedProfile!.lastPingOk
          ? PingState.success
          : (_selectedProfile!.pingMs == null ? PingState.idle : PingState.failed);
    } else if (_profiles.isNotEmpty) {
      _selectedId = _profiles.first.id;
      _selectedPing = _profiles.first.pingMs;
      _selectedPingState = _profiles.first.lastPingOk
          ? PingState.success
          : (_profiles.first.pingMs == null ? PingState.idle : PingState.failed);
      await _persistSelection();
    }

    if (mounted) {
      setState(() => _initializing = false);
    }
  }

  Future<void> _loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList(_profilesKey) ?? <String>[];
    _profiles
      ..clear()
      ..addAll(
        encoded.map((value) {
          try {
            return ServerProfile.fromJson(jsonDecode(value) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        }).whereType<ServerProfile>(),
      );
    _selectedId = prefs.getString(_selectedKey);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _profilesKey,
      _profiles.map((profile) => jsonEncode(profile.toJson())).toList(),
    );
    await _persistSelection();
  }

  Future<void> _persistSelection() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedId == null) {
      await prefs.remove(_selectedKey);
    } else {
      await prefs.setString(_selectedKey, _selectedId!);
    }
  }

  Future<void> _connectOrDisconnect() async {
    if (_connected || _isConnecting) {
      setState(() => _busy = true);
      try {
        await _v2ray.stopV2Ray();
      } catch (error) {
        _snack('خطا در قطع اتصال: $error');
      } finally {
        _activeProfileId = null;
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    final profile = _selectedProfile;
    if (profile == null) {
      await _showAddDialog();
      return;
    }

    setState(() => _busy = true);
    try {
      if (!await _v2ray.requestPermission()) {
        _snack('اجازه VPN داده نشد.');
        return;
      }
      await _v2ray.startV2Ray(
        remark: profile.name,
        config: profile.config,
        blockedApps: null,
        bypassSubnets: null,
        proxyOnly: false,
        notificationDisconnectButtonName: 'قطع اتصال',
      );
      _activeProfileId = profile.id;
      if (mounted) setState(() {});
    } catch (error) {
      _activeProfileId = null;
      _snack('خطا در اتصال: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int> _measureDelay(ServerProfile profile) async {
    // Use the connected-server endpoint only when the selected profile is the
    // profile that is actually active. Otherwise we must test the selected
    // configuration directly; using the connected-server API would test the
    // wrong server after the user changes selection while connected.
    final urls = <String>[
      'https://google.com/generate_204',
      'https://www.gstatic.com/generate_204',
      'https://cp.cloudflare.com/generate_204',
    ];

    Object? lastError;
    for (final url in urls) {
      try {
        final delay = (_connected && _activeProfileId == profile.id)
            ? await _v2ray.getConnectedServerDelay(url: url)
            : await _v2ray.getServerDelay(config: profile.config, url: url);
        if (delay >= 0) return delay;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? StateError('No ping endpoint was reachable');
  }

  Future<void> _testSelectedPing() async {
    final profile = _selectedProfile;
    if (profile == null) {
      _snack('ابتدا یک سرور اضافه یا انتخاب کن.');
      return;
    }

    setState(() {
      _selectedPingState = PingState.checking;
      _selectedPing = null;
    });

    try {
      final delay = await _measureDelay(profile);
      profile.pingMs = delay;
      profile.lastPingOk = true;
      if (mounted) {
        setState(() {
          _selectedPing = delay;
          _selectedPingState = PingState.success;
        });
      }
      await _persist();
    } catch (_) {
      profile.pingMs = null;
      profile.lastPingOk = false;
      if (mounted) {
        setState(() {
          _selectedPing = null;
          _selectedPingState = PingState.failed;
        });
      }
      await _persist();
    }
  }

  Future<void> _testProfilePing(ServerProfile profile) async {
    try {
      final delay = await _measureDelay(profile);
      profile.pingMs = delay;
      profile.lastPingOk = true;
      if (_selectedId == profile.id) {
        _selectedPing = delay;
        _selectedPingState = PingState.success;
      }
      await _persist();
      if (mounted) setState(() {});
    } catch (_) {
      profile.pingMs = null;
      profile.lastPingOk = false;
      if (_selectedId == profile.id) {
        _selectedPing = null;
        _selectedPingState = PingState.failed;
      }
      await _persist();
      if (mounted) setState(() {});
    }
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _snack('کلیپ‌بورد خالی است.');
      return;
    }
    await _importText(text);
  }

  Future<void> _importText(String text) async {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    if (text.trimLeft().startsWith('{')) {
      _manualController.text = text.trim();
      _nameController.text = 'Imported JSON';
      await _saveManualJson(closeSheet: false);
      return;
    }

    final supported = lines.where((line) {
      final lower = line.toLowerCase();
      return lower.startsWith('vless://') ||
          lower.startsWith('vmess://') ||
          lower.startsWith('trojan://') ||
          lower.startsWith('ss://') ||
          lower.startsWith('socks://') ||
          lower.startsWith('hysteria://') ||
          lower.startsWith('hysteria2://') ||
          lower.startsWith('hy://') ||
          lower.startsWith('hy2://');
    }).toList();

    if (supported.isEmpty) {
      _manualController.text = text;
      _snack('لینک پشتیبانی‌شده‌ای پیدا نشد. فرمت‌ها: vless://، vmess://، trojan://، ss://، socks://، hysteria2://');
      return;
    }

    int added = 0;
    for (final link in supported) {
      try {
        final parsed = V2ray.parseFromURL(link);
        final name = parsed.remark.trim().isEmpty ? 'Server ${_profiles.length + 1}' : parsed.remark.trim();
        _profiles.add(
          ServerProfile(
            id: '${DateTime.now().microsecondsSinceEpoch}_$added',
            name: name,
            config: parsed.getFullConfiguration(),
            source: link,
            country: _emojiForName(name),
          ),
        );
        added++;
      } catch (_) {
        // Ignore malformed entries and keep valid ones.
      }
    }

    if (added == 0) {
      _snack('تبدیل لینک به کانفیگ ممکن نبود.');
      return;
    }

    _selectedId = _profiles.last.id;
    _resetSelectedPing();
    await _persist();
    if (mounted) setState(() {});
    _snack('$added سرور اضافه شد.');
  }

  Future<void> _saveManualJson({required bool closeSheet}) async {
    final config = _manualController.text.trim();
    if (config.isEmpty) {
      _snack('کانفیگ خالی است.');
      return;
    }
    try {
      final decoded = jsonDecode(config);
      if (decoded is! Map<String, dynamic>) throw const FormatException('not object');
    } catch (_) {
      _snack('JSON نامعتبر است.');
      return;
    }

    final name = _nameController.text.trim().isEmpty ? 'Imported JSON' : _nameController.text.trim();
    _profiles.add(
      ServerProfile(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        config: config,
        source: 'json',
        country: _emojiForName(name),
      ),
    );
    _selectedId = _profiles.last.id;
    _resetSelectedPing();
    await _persist();
    if (mounted) {
      if (closeSheet) Navigator.of(context).pop();
      setState(() {});
      _snack('کانفیگ JSON اضافه شد.');
    }
  }

  Future<void> _showAddDialog() async {
    _manualController.clear();
    _nameController.clear();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1D2D),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'افزودن سرور',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'لینک اشتراکی VLESS / VMess / Trojan / Shadowsocks را بچسبان یا JSON وارد کن.',
                      style: TextStyle(color: Colors.white.withOpacity(.65)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      decoration: _fieldDecoration('نام سرور (اختیاری)', Icons.label_outline),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _manualController,
                      minLines: 6,
                      maxLines: 12,
                      decoration: _fieldDecoration('لینک یا JSON', Icons.link_rounded),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final data = await Clipboard.getData('text/plain');
                              if (data?.text != null) {
                                _manualController.text = data!.text!.trim();
                                setSheetState(() {});
                              }
                            },
                            icon: const Icon(Icons.content_paste_go_rounded),
                            label: const Text('چسباندن'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              final text = _manualController.text.trim();
                              if (text.startsWith('{')) {
                                await _saveManualJson(closeSheet: true);
                              } else {
                                Navigator.of(context).pop();
                                await _importText(text);
                              }
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('افزودن'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _renameProfile(ServerProfile profile) async {
    final controller = TextEditingController(text: profile.name);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تغییر نام'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
          FilledButton(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isNotEmpty) profile.name = value;
              await _persist();
              if (!context.mounted) return;
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _deleteProfile(ServerProfile profile) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف سرور؟'),
        content: Text('«${profile.name}» از فهرست حذف می‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لغو')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (shouldDelete != true) return;

    if (_activeProfileId == profile.id && _connected) {
      _snack('برای حذف سرور فعال، ابتدا VPN را قطع کن.');
      return;
    }

    _profiles.removeWhere((item) => item.id == profile.id);
    if (_selectedId == profile.id) {
      _selectedId = _profiles.isEmpty ? null : _profiles.first.id;
      _resetSelectedPing();
    }
    await _persist();
    if (mounted) setState(() {});
  }

  Future<void> _selectProfile(ServerProfile profile) async {
    _selectedId = profile.id;
    _selectedPing = profile.pingMs;
    _selectedPingState = profile.lastPingOk
        ? PingState.success
        : (profile.pingMs == null ? PingState.idle : PingState.failed);
    await _persistSelection();
    if (mounted) setState(() {});
  }

  void _resetSelectedPing() {
    _selectedPing = null;
    _selectedPingState = PingState.idle;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  static String _emojiForName(String value) {
    final text = value.toLowerCase();
    if (text.contains('canada') || text.contains('تورنتو') || text.contains('مونترال')) return '🇨🇦';
    if (text.contains('usa') || text.contains('united states') || text.contains('america')) return '🇺🇸';
    if (text.contains('germany') || text.contains('de') || text.contains('فرانکفورت')) return '🇩🇪';
    if (text.contains('france') || text.contains('paris')) return '🇫🇷';
    if (text.contains('netherlands') || text.contains('amsterdam')) return '🇳🇱';
    if (text.contains('uk') || text.contains('london') || text.contains('britain')) return '🇬🇧';
    if (text.contains('finland') || text.contains('helsinki')) return '🇫🇮';
    return '🌐';
  }

  @override
  void dispose() {
    _manualController.dispose();
    _nameController.dispose();
    _v2rayStatus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0D2B4A), Color(0xFF071321), Color(0xFF050C13)],
            ),
          ),
          child: SafeArea(
            child: _initializing
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      slivers: [
                        SliverToBoxAdapter(child: _buildTopBar()),
                        SliverToBoxAdapter(child: _buildHero()),
                        SliverToBoxAdapter(child: _buildControls()),
                        SliverToBoxAdapter(child: _buildSectionHeader()),
                        _buildServerSliver(),
                        SliverToBoxAdapter(child: _buildFooter()),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _reload() async {
    await _loadProfiles();
    if (mounted) setState(() {});
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Row(
        children: [
          _glassIconButton(Icons.menu_rounded, _showAbout),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Breeze VPN', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Xray / V2Ray client', style: TextStyle(fontSize: 12, color: Colors.white54)),
              ],
            ),
          ),
          _statusPill(),
        ],
      ),
    );
  }

  Widget _statusPill() {
    final connected = _connected;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: connected ? const Color(0x2429D391) : const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: connected ? const Color(0x7729D391) : const Color(0x22FFFFFF)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? const Color(0xFF2DE08F) : Colors.white54,
            ),
          ),
          const SizedBox(width: 6),
          Text(connected ? 'ONLINE' : 'OFFLINE', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildHero() {
    final profile = _selectedProfile;
    final location = profile?.name ?? 'سروری انتخاب نشده';
    final ping = _selectedPing;
    final isGood = _selectedPingState == PingState.success;
    final isBad = _selectedPingState == PingState.failed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              profile == null ? 'یک کانفیگ اضافه کن' : 'موقعیت انتخاب‌شده',
              style: TextStyle(color: Colors.white.withOpacity(.62), fontSize: 14),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 238,
            height: 238,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 238,
                  height: 238,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0x1429D391),
                        const Color(0x0929D391),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 194,
                  height: 194,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF29D391), width: 2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x3629D391), blurRadius: 32, spreadRadius: 5),
                    ],
                    color: const Color(0xFF0A1724),
                  ),
                ),
                Container(
                  width: 168,
                  height: 168,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(.22), width: 1),
                    color: const Color(0xFF0C1E2E),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _busy ? null : _connectOrDisconnect,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Column(
                          key: ValueKey<String>(_connected ? 'on' : 'off'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.power_settings_new_rounded,
                              size: 62,
                              color: _connected ? const Color(0xFF2DE08F) : Colors.white,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _connected ? 'قطع اتصال' : 'اتصال',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  child: _pingBadge(ping, isGood, isBad),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statChip(Icons.speed_rounded, _isConnecting ? 'در حال اتصال…' : (_connected ? 'وصل شده' : 'آماده')), 
              const SizedBox(width: 8),
              _statChip(Icons.timer_outlined, _v2rayStatus.value.duration.isEmpty ? '—' : _v2rayStatus.value.duration),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pingBadge(int? ping, bool good, bool bad) {
    final checking = _selectedPingState == PingState.checking;
    final color = good
        ? const Color(0xFF2DE08F)
        : bad
            ? const Color(0xFFFF5E68)
            : Colors.white70;
    final label = checking
        ? 'PING …'
        : good
            ? '${ping} ms'
            : bad
                ? 'OFFLINE'
                : 'PING';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE60A1724),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(.55)),
      ),
      child: Row(
        children: [
          Icon(
            good ? Icons.check_circle_rounded : bad ? Icons.cancel_rounded : Icons.network_check_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x161D3346),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.07)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.white60),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _selectedProfile == null ? _showAddDialog : _testSelectedPing,
              icon: _selectedPingState == PingState.checking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.speed_rounded),
              label: Text(_selectedProfile == null ? 'افزودن سرور' : 'تست پینگ'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _glassIconButton(Icons.add_link_rounded, _showAddDialog),
          const SizedBox(width: 8),
          _glassIconButton(Icons.content_paste_rounded, _importFromClipboard),
        ],
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text('سرورها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          Text('${_profiles.length} کانفیگ', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(.55))),
        ],
      ),
    );
  }

  Widget _buildServerSliver() {
    if (_profiles.isEmpty) {
      return SliverToBoxAdapter(child: _emptyServers());
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      sliver: SliverList.separated(
        itemCount: _profiles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _serverCard(_profiles[index]),
      ),
    );
  }

  Widget _emptyServers() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: _glassDecoration(),
        child: Column(
          children: [
            const Icon(Icons.cloud_queue_rounded, size: 42, color: Colors.white38),
            const SizedBox(height: 10),
            const Text('هنوز سروری اضافه نشده', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'از دکمه افزودن یا Paste برای وارد کردن کانفیگ ساخته‌شده در پنلت استفاده کن.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(.55), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _serverCard(ServerProfile profile) {
    final selected = profile.id == _selectedId;
    final hasPing = profile.lastPingOk && profile.pingMs != null;
    final pingColor = hasPing ? const Color(0xFF2DE08F) : const Color(0xFFFF5E68);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? const Color(0x1529D391) : const Color(0x0F203547),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: selected ? const Color(0x7A29D391) : Colors.white.withOpacity(.07),
          width: selected ? 1.3 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: () => _selectProfile(profile),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.07),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(profile.country, style: const TextStyle(fontSize: 21)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              profile.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.radio_button_checked_rounded, size: 15, color: Color(0xFF2DE08F)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.config.contains('"type":"tun"') ? 'VPN / TUN' : 'Xray config',
                        style: TextStyle(color: Colors.white.withOpacity(.45), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (profile.pingMs != null || profile.lastPingOk) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: pingColor.withOpacity(.10),
                      border: Border.all(color: pingColor.withOpacity(.35)),
                    ),
                    child: Text(
                      hasPing ? '${profile.pingMs}ms' : 'OFF',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: pingColor),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'ping') _testProfilePing(profile);
                    if (value == 'rename') _renameProfile(profile);
                    if (value == 'delete') _deleteProfile(profile);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'ping', child: Text('تست پینگ')),
                    PopupMenuItem(value: 'rename', child: Text('تغییر نام')),
                    PopupMenuItem(value: 'delete', child: Text('حذف')),
                  ],
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
      child: Column(
        children: [
          Text(
            'اتصال توسط Xray-core • فقط کانفیگ خودت را استفاده کن',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(.38)),
          ),
          const SizedBox(height: 4),
          if (_coreVersion != null)
            Text(
              _coreVersion!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(.25)),
            ),
        ],
      ),
    );
  }

  BoxDecoration _glassDecoration() {
    return BoxDecoration(
      color: const Color(0x10203344),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withOpacity(.07)),
    );
  }

  Widget _glassIconButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x1422384B),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(.07)),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        tooltip: 'عملیات',
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0x1422384B),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(.08)),
      ),
    );
  }

  Future<void> _showAbout() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0D1D2D),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Breeze VPN', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('کلاینت سبک Xray/V2Ray با ظاهر الهام‌گرفته از اپ‌های VPN مدرن.'),
            const SizedBox(height: 8),
            Text('قابلیت‌ها: وارد کردن لینک، ذخیره چند سرور، تست پینگ و VPN سراسری.', style: TextStyle(color: Colors.white.withOpacity(.65))),
            const SizedBox(height: 12),
            if (_coreVersion != null) Text(_coreVersion!, style: TextStyle(color: Colors.white.withOpacity(.42), fontSize: 11)),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
            ),
          ],
        ),
      ),
    );
  }
}
