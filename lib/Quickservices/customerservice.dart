import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// In-app customer service chat agent for Vero360.
/// English + Chichewa — user picks a language before chatting.
class CustomerServicePage extends StatefulWidget {
  const CustomerServicePage({super.key});

  static const supportPhone = '+265992695612';
  static const supportWhatsApp = '+265992695612';
  static const supportEmail = 'info@vero360.app';
  static const _prefKey = 'pref_support_language_code';

  @override
  State<CustomerServicePage> createState() => _CustomerServicePageState();
}

class _CustomerServicePageState extends State<CustomerServicePage> {
  static const _brand = Color(0xFFFF8A00);
  static const _bg = Color(0xFFF3F4F7);
  static const _ink = Color(0xFF101010);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatMsg>[];
  bool _typing = false;

  /// null = language not chosen yet (gate screen).
  String? _lang; // 'en' | 'ny'
  String? _suggestedLang;

  String _t(String en, String ny) => _lang == 'ny' ? ny : en;

  List<String> get _quickPrompts => _lang == 'ny'
      ? const [
          'Ndingathe bwanji kuyitanitsa chakudya?',
          'Tsata order yanga',
          'Kulipila & wallet',
          'Kukhala merchant',
          'Lankhulani ndi munthu',
        ]
      : const [
          'How do I order food?',
          'Track my order',
          'Payment & wallet',
          'Become a merchant',
          'Talk to a human',
        ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadSuggestedLang());
  }

  Future<void> _loadSuggestedLang() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(CustomerServicePage._prefKey) ??
          prefs.getString('pref_language_code');
      if (!mounted) return;
      if (saved == 'en' || saved == 'ny') {
        setState(() => _suggestedLang = saved);
      }
    } catch (_) {}
  }

  Future<void> _selectLanguage(String code) async {
    setState(() {
      _lang = code;
      _messages.clear();
      _messages.add(
        _ChatMsg(
          fromBot: true,
          text: code == 'ny'
              ? 'Moni — ndine Vero Assist 👋\nMundifunse za Maulendo, Maoda, kulipila, marketplace, malo ogona, kapena china chili chonse pa Vero360.\n\nDinaninani chidziwitso pansipa, kapena lembani funso lanu.'
              : 'Hi — I’m Vero Assist 👋\nAsk me about rides, orders, payments, marketplace, stays, or anything on Vero360.\n\nTap a suggestion below, or type your question.',
        ),
      );
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(CustomerServicePage._prefKey, code);
    } catch (_) {}
  }

  void _changeLanguage() {
    setState(() {
      _lang = null;
      _messages.clear();
      _typing = false;
      _input.clear();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _typing || _lang == null) return;
    _input.clear();

    setState(() {
      _messages.add(_ChatMsg(fromBot: false, text: text));
      _typing = true;
    });
    _scrollToEnd();

    await Future<void>.delayed(
      Duration(milliseconds: 450 + math.Random().nextInt(350)),
    );
    if (!mounted) return;

    final reply = _VeroSupportBot.reply(text, lang: _lang!);
    setState(() {
      _typing = false;
      _messages.add(_ChatMsg(fromBot: true, text: reply.text, actions: reply.actions));
    });
    _scrollToEnd();
  }

  Future<void> _launchTel() async {
    final uri = Uri(scheme: 'tel', path: CustomerServicePage.supportPhone);
    try {
      await launchUrl(uri);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t('Could not open the phone dialer.', 'Sitinathe kutsegula foni.'),
          ),
        ),
      );
    }
  }

  Future<void> _launchWhatsApp([String? preset]) async {
    final phone =
        CustomerServicePage.supportWhatsApp.replaceAll(RegExp(r'\D'), '');
    final message = preset ??
        _t(
          'Hello Vero support, I need help from the app.',
          'Moni Vero support, ndikufuna thandizo kuchokera ku app yi.',
        );
    final encoded = Uri.encodeComponent(message);

    final candidates = <Uri>[
      Uri.parse('whatsapp://send?phone=$phone&text=$encoded'),
      Uri.parse('https://wa.me/$phone?text=$encoded'),
      Uri.parse('https://api.whatsapp.com/send?phone=$phone&text=$encoded'),
    ];

    Object? lastError;
    for (final uri in candidates) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (e) {
        lastError = e;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lastError == null
              ? _t(
                  'Could not open WhatsApp. Is it installed?',
                  'Sitinathe kutsegula WhatsApp. Kodi whatsapp alipo?',
                )
              : _t('Could not open WhatsApp.', 'Sitinathe kutsegula WhatsApp.'),
        ),
      ),
    );
  }

  Future<void> _launchEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: CustomerServicePage.supportEmail,
      queryParameters: {
        'subject': _t('Vero360 support', 'Thandizo la Vero360'),
        'body': _t(
          'Hello Vero support,\n\nI need help with:\n',
          'Moni Vero support,\n\nNdikufuna thandizo pa:\n',
        ),
      },
    );
    try {
      await launchUrl(uri);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('Could not open email.', 'Sitinathe kutsegula imelo.')),
        ),
      );
    }
  }

  void _onBotAction(_BotAction action) {
    switch (action) {
      case _BotAction.whatsapp:
        unawaited(_launchWhatsApp());
        break;
      case _BotAction.call:
        unawaited(_launchTel());
        break;
      case _BotAction.email:
        unawaited(_launchEmail());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lang == null) {
      return _LanguageGate(
        suggested: _suggestedLang,
        onSelect: _selectLanguage,
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF4E5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.support_agent_rounded, color: _brand),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Vero Assist',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: _ink,
                    ),
                  ),
                  Text(
                    _t('Customer service bot', 'Bot ya thandizo la makasitomala'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _changeLanguage,
            child: Text(
              _lang == 'ny' ? 'EN / NY' : 'EN / NY',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: _brand,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            tooltip: 'WhatsApp',
            onPressed: () => _launchWhatsApp(),
            icon: const Icon(Icons.chat_rounded, color: _brand),
          ),
          IconButton(
            tooltip: _t('Call', 'Imbani'),
            onPressed: _launchTel,
            icon: const Icon(Icons.call_outlined, color: _ink),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFECEEF2)),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
              itemCount: _messages.length + (_typing ? 1 : 0),
              itemBuilder: (context, i) {
                if (_typing && i == _messages.length) {
                  return _TypingBubble(label: _t(
                    'Vero Assist is typing…',
                    'Vero Assist ikulemba…',
                  ));
                }
                final m = _messages[i];
                return _Bubble(
                  msg: m,
                  lang: _lang!,
                  onAction: _onBotAction,
                );
              },
            ),
          ),
          if (_messages.length <= 2)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                itemCount: _quickPrompts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final p = _quickPrompts[i];
                  return ActionChip(
                    label: Text(
                      p,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: Colors.white,
                    side: BorderSide(color: _brand.withValues(alpha: 0.35)),
                    onPressed: () => _send(p),
                  );
                },
              ),
            ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: _t('Ask Vero Assist…', 'Funsa Vero Assist…'),
                        filled: true,
                        fillColor: _bg,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: _brand,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _send(_input.text),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageGate extends StatelessWidget {
  const _LanguageGate({required this.onSelect, this.suggested});

  final void Function(String code) onSelect;
  final String? suggested;

  static const _brand = Color(0xFFFF8A00);
  static const _ink = Color(0xFF101010);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F7),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        title: const Text(
          'Vero Assist',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF4E5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: _brand,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Choose your language',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sankhani chilankhulo chanu',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Vero Assist will reply in the language you pick.',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.35),
              ),
              const SizedBox(height: 4),
              const Text(
                'Vero Assist idzayankha mu chilankhulo chomwe mwasankha.',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.35),
              ),
              const SizedBox(height: 28),
              _LangCard(
                title: 'English',
                subtitle: 'Continue in English',
                icon: Icons.language_rounded,
                highlighted: suggested == 'en',
                onTap: () => onSelect('en'),
              ),
              const SizedBox(height: 12),
              _LangCard(
                title: 'Chichewa',
                subtitle: 'Pitirizani mu Chichewa',
                icon: Icons.translate_rounded,
                highlighted: suggested == 'ny',
                onTap: () => onSelect('ny'),
              ),
              const Spacer(),
              Text(
                suggested == null
                    ? 'You can change language anytime with EN / NY.'
                    : 'Last used is highlighted — tap to continue.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF9CA3AF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangCard extends StatelessWidget {
  const _LangCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.highlighted = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;

  static const _brand = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: highlighted ? _brand : const Color(0xFFE5E7EB),
              width: highlighted ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _brand),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                highlighted ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                color: highlighted ? _brand : const Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BotAction { whatsapp, call, email }

class _BotReply {
  final String text;
  final List<_BotAction> actions;
  const _BotReply(this.text, {this.actions = const []});
}

class _ChatMsg {
  final bool fromBot;
  final String text;
  final List<_BotAction> actions;
  _ChatMsg({
    required this.fromBot,
    required this.text,
    this.actions = const [],
  });
}

/// Conversational FAQ agent — greets naturally, then helps with Vero360 topics.
class _VeroSupportBot {
  _VeroSupportBot._();

  static final _rng = math.Random();

  static final List<_Faq> _faqs = [
    _Faq(
      keys: [
        'food', 'restaurant', 'order food', 'hungry', 'menu', 'deliver food', 'eat',
        'chakudya', 'restaurant', 'yitanitsani chakudya', 'njala', 'menyu',
      ],
      answerEn:
          'To order food:\n1. Open Home → Food\n2. Pick a restaurant and items\n3. Checkout and pay\n\nYou’ll get order updates in My Orders and Notifications. Anything else?',
      answerNy:
          'Kuyitanitsa chakudya:\n1. Tsegulani Home → Food\n2. Sankhani restoranti ndi zinthu\n3. Malipiro (Checkout)\n\nMudzalandira zidziwitso mu My Orders ndi Notifications. paliso China?',
    ),
    _Faq(
      keys: [
        'track', 'where is my order', 'shipment', 'delivered', 'parcel status', 'my order',
        'tsata', 'order ili kuti', 'katundu', 'yapita', 'status ya order',
      ],
      answerEn:
          'Track orders under My Orders.\n• Marketplace / food: status + parcel & payment section\n• Courier: open Courier for live delivery updates\n\nIf payment was held in escrow, confirm receipt when your parcel arrives so the merchant is paid.',
      answerNy:
          'Tsataninani maoda mu My Orders.\n• Marketplace / chakudya: status + gawo la katundu & malipiro\n• Courier: tsegulani Courier kuti muone zotsatira\n\nNgati ndalama zili mu escrow, tsimikizirani kuti mwalandira katundu kuti merchant alandire malipiro.',
    ),
    _Faq(
      keys: [
        'payment', 'pay', 'wallet', 'paychangu', 'refund', 'money', 'escrow', 'paid',
        'malipiro', 'lipira', 'ndalama', 'bwezerani',
      ],
      answerEn:
          'Payments use PayChangu (card / mobile money).\nMarketplace orders hold funds in escrow until you confirm receipt.\nCheck wallet / My Orders for status. Refunds for failed payments may take a short time to reverse on mobile money.',
      answerNy:
          'Malipiro amagwiritsa ntchito PayChangu (khadi / mobile money).\nMaoda a Marketplace amasunga ndalama mu escrow mpaka mutsimikize kulandira.\nOnani wallet / My Orders. Kubweza ndalama kungatenge nthawi pang’ono pa mobile money.',
    ),
    _Faq(
      keys: [
        'ride', 'taxi', 'vero ride', 'driver', 'bike', 'verobike', 'trip',
        'ulendo', 'galimoto', 'woyendetsa', 'njinga',
      ],
      answerEn:
          'Vero Ride / Vero Bike:\nOpen Home → Vero Ride or Vero Bike, set pickup & drop-off, then request.\nDrivers nearby can accept. Need help with a live trip? Say “talk to a human”.',
      answerNy:
          'Vero Ride / Vero Bike:\nTsegulani Home → Vero Ride kapena Vero Bike, ikani malo otenga & otsikira, kenako pempherani.\nOyendetsa pafupi atha kuvomereza. Mukufuna thandizo pa ulendo? Nenani “lankhulani ndi munthu”.',
    ),
    _Faq(
      keys: [
        'courier', 'parcel', 'send package', 'delivery', 'send something',
        'tumizani', 'katundu', 'kutumiza',
      ],
      answerEn:
          'Courier: Home → Courier to book a parcel delivery and track it. Have pickup address, drop-off, and package size ready.',
      answerNy:
          'Courier: Home → Courier kuti mubooke kutumiza katundu ndi kutsata. Khalani ndi adilesi yotenga, yotsikira, ndi kukula kwa phukusi.',
    ),
    _Faq(
      keys: [
        'marketplace', 'sell', 'buy', 'product', 'listing', 'cart', 'shop',
        'gulitsa', 'gula', 'malonda', 'ngolo', 'sitolo',
      ],
      answerEn:
          'Marketplace: browse products from Home or Marketplace.\nAdd to cart → Checkout.\nTo sell, create a merchant account and post listings from the merchant tools.',
      answerNy:
          'Marketplace: yang’anani zinthu kuchokera ku Home kapena Marketplace.\nOnjezani ku cart → Checkout.\nKugulitsa, pangani akaunti ya merchant ndikuyika zinthu kuchokera ku zida za merchant.',
    ),
    _Faq(
      keys: [
        'merchant', 'become a seller', 'business', 'vendor', 'open a shop',
        'wogulitsa', 'bizinesi', 'tsegulani sitolo',
      ],
      answerEn:
          'To become a merchant: register / switch to a merchant account, complete your shop profile, then post products, promotions, or food menus.\nNeed onboarding help? Tap Talk to a human.',
      answerNy:
          'Kukhala merchant: lembani / sinthani ku akaunti ya merchant, malizani mbiri ya sitolo, kenako ikani zinthu, ma promo, kapena menyu ya chakudya.\nMukufuna thandizo? Dinaninani Lankhulani ndi munthu.',
    ),
    _Faq(
      keys: [
        'stay', 'hotel', 'accommodation', 'booking', 'room', 'lodge',
        'malo ogona', 'hotela', 'chipinda', 'kubooka',
      ],
      answerEn:
          'Stay: Home → Stay to browse places and book. Booking details and support for stays appear in your bookings / notifications.',
      answerNy:
          'Stay: Home → Stay kuti muone malo ndikubooka. Zambiri za booking zimapezeka mu bookings / notifications.',
    ),
    _Faq(
      keys: [
        'forex', 'fx', 'exchange', 'rate', 'kwacha', 'usd', 'dollar',
        'kusintha ndalama', 'mtengo',
      ],
      answerEn:
          'Forex: Home → Forex for live exchange rates. Rates are informational — confirm with your bank or bureau before large trades.',
      answerNy:
          'Forex: Home → Forex kuti muone mitengo yamasinthidwe. Mitengoyi ndi chidziwitso chabe, ife sitisitha ndalama.',
    ),
    _Faq(
      keys: [
        'job', 'jobs', 'vacancy', 'work', 'career', 'employment',
        'ntchito', 'majob', 'kupanga ntchito',
      ],
      answerEn:
          'Jobs: Home → Jobs to browse openings. Apply from the listing details when available.',
      answerNy:
          'Jobs: Home → Jobs kuti muone mawayilo. Lembani kuchokera ku tsatanetsatane wa listing.',
    ),
    _Faq(
      keys: [
        'promo', 'promotion', 'deal', 'discount', 'arrival', 'offer',
        'malsamayenda', 'kuchotsera', 'mwayi',
      ],
      answerEn:
          'Promotions and Today’s arrivals appear on Home. Tap a promo card for details. When something new is posted, Vero360 can notify you if Deals & new listings is on in Settings.',
      answerNy:
          'Ma promo ndi zofika lero zikuonekera pa Home. Dinaninani promo kuti muone zambiri. Zikakhala zatsopano, Vero360 ingakutumizireni notification ngati Deals ili yotseguka mu Settings.',
    ),
    _Faq(
      keys: [
        'inbox', 'seller chat', 'message seller', 'dm',
        'mauthenga', 'cheza ndi wogulitsa',
      ],
      answerEn:
          'Chat sellers from a product page (Message seller) or open your Inbox.\nRatings appear after a real chat or completed order.',
      answerNy:
          'Chezani ndi ogulitsa kuchokera ku tsamba la chinthu (Message seller) kapena Inbox.\nNdemanga zimapezeka mukatha kucheza kapena kutha order.',
    ),
    _Faq(
      keys: [
        'login', 'password', 'account', 'sign in', 'otp', 'register', 'sign up',
        'kulowa', 'password', 'akaunti', 'kulembetsa',
      ],
      answerEn:
          'Account help: use Login / Sign up on the welcome screen. Forgot password? Use reset password (email OTP).\nStill stuck? Contact support via WhatsApp.',
      answerNy:
          'Thandizo la akaunti: gwiritsani Login / Sign up pa welcome screen. Mwayiwala password? Gwiritsani reset (email OTP).\nMukuvutika? Lumikizanani ndi support pa WhatsApp.',
    ),
    _Faq(
      keys: [
        'human', 'agent', 'real person', 'talk to someone', 'customer care',
        'contact support', 'whatsapp support', 'call support',
        'munthu', 'lankhulani ndi munthu', 'thandizo', 'wothandizira',
      ],
      answerEn:
          'Sure — I can connect you to a person:\n• WhatsApp: ${CustomerServicePage.supportWhatsApp}\n• Call: ${CustomerServicePage.supportPhone}\n• Email: ${CustomerServicePage.supportEmail}\n\nUse the buttons below.',
      answerNy:
          'Chabwino — nditha kukulumikizani ndi munthu:\n• WhatsApp: ${CustomerServicePage.supportWhatsApp}\n• Imbani: ${CustomerServicePage.supportPhone}\n• Imelo: ${CustomerServicePage.supportEmail}\n\nGwiritsani batani pansipa.',
      actions: [_BotAction.whatsapp, _BotAction.call, _BotAction.email],
    ),
  ];

  static final _greetings = <String>{
    'hi', 'hii', 'hiii', 'hello', 'helloo', 'hey', 'heyy', 'hiya', 'yo', 'sup',
    'hola', 'moni', 'bwanji', 'muli bwanji', 'muli bwanji?',
    'good morning', 'good afternoon', 'good evening', 'morning', 'afternoon',
    'evening', 'how are you', 'how are you?', "how's it going", 'how r u',
    'howru', 'whats up', "what's up", 'wassup',
    'muli bwanji lero', 'takulandirani',
  };

  static final _thanks = <String>{
    'thanks', 'thank you', 'thank u', 'thx', 'ty', 'zikomo',
    'cool thanks', 'ok thanks', 'okay thanks', 'zikomo kwambiri',
  };

  static final _bye = <String>{
    'bye', 'goodbye', 'good bye', 'see you', 'later', 'ttyl', 'cheers',
    'tiwonane', 'ndapita',
  };

  static final _acks = <String>{
    'ok', 'okay', 'k', 'kk', 'sure', 'alright', 'all right', 'got it',
    'noted', 'fine', 'yes', 'yeah', 'yep', 'yup', 'no', 'nope', 'nah',
    'chabwino', 'inde', 'ayi', 'ndamva',
  };

  static final _whoAreYou = <String>{
    'who are you', 'what are you', 'your name', "what's your name",
    'are you a bot', 'are you real', 'are you ai',
    'ndiwe yani', 'dzina lako ndi ndani', 'ndiwe bot',
  };

  static _BotReply reply(String input, {required String lang}) {
    final ny = lang == 'ny';
    final q = input.toLowerCase().trim();
    final compact = q.replaceAll(RegExp(r'[!.?,]+$'), '').trim();
    if (q.isEmpty) {
      return _BotReply(
        ny
            ? 'Lembani funso lafupifupi ndidzakuthandizani.'
            : 'Type a short question and I’ll help.',
      );
    }

    final chitchat = _chitchat(compact, q, ny: ny);
    if (chitchat != null) return chitchat;

    _Faq? best;
    var bestScore = 0;
    for (final faq in _faqs) {
      final score = faq.score(q);
      if (score > bestScore) {
        bestScore = score;
        best = faq;
      }
    }

    if (best != null && bestScore >= 2) {
      return _BotReply(best.answer(lang), actions: best.actions);
    }

    if (compact == 'help' ||
        compact == 'support' ||
        compact == 'assist' ||
        compact == 'thandizo') {
      return _BotReply(
        ny
            ? _pick([
                'Ndili okondwa kuthandiza 🙂 Mukufuna chiyani — maulendo, chakudya, maoda, malipiro, marketplace, malo ogona, kapena ntchito?',
                'Ndili pano. Ndiuzeni vuto maufupi (mwachitsanzo “tsata order” kapena “sindingathe kulipira”).',
              ])
            : _pick([
                'Happy to help 🙂 What do you need — rides, food, orders, payments, marketplace, stays, or jobs?',
                'I’m here. Tell me the issue in a few words (e.g. “track my order” or “can’t pay”).',
              ]),
        actions: const [_BotAction.whatsapp],
      );
    }

    return _BotReply(
      ny
          ? _pick([
              'Pepani, sindikumvetsetsa bwino. Yesani monga “yitanitsa chakudya”, “tsata order”, kapena “malipiro”.\nKapena nenani moni ndikundiuza vuto 😊',
              'Mwina ndaphonya. Funsa za maulendo, chakudya, cart, wallet, malo ogona, kapena ntchito — kapena dinaninani Lankhulani ndi munthu.',
            ])
          : _pick([
              'Hmm, I’m not 100% sure what you mean. Try something like “order food”, “track order”, or “payment”.\nOr say hi again and tell me the problem 😊',
              'I might have missed that. Ask about rides, food, cart, wallet, stays, or jobs — or tap Talk to a human.',
            ]),
      actions: const [_BotAction.whatsapp, _BotAction.call],
    );
  }

  static _BotReply? _chitchat(String compact, String raw, {required bool ny}) {
    if (_greetings.contains(compact) ||
        _greetings.any((g) => compact.startsWith('$g ') || compact == g)) {
      return _BotReply(
        ny
            ? _pick([
                'Moni! 👋 Ndine Vero Assist — ndingakuthandizeni bwanji lero?',
                'Takulandirani ku Vero360. Mukufuna thandizo pa chiyani?',
                'Moni! 😊 Mundifunse za maulendo, chakudya, maoda, malipiro, kapena marketplace.',
              ])
            : _pick([
                'Hey! 👋 I’m Vero Assist — how can I help you today?',
                'Hi there! Welcome to Vero360. What do you need help with?',
                'Hello! 😊 Ask me about rides, food, orders, payments, or marketplace.',
              ]),
      );
    }

    if (_whoAreYou.any((w) => compact.contains(w) || compact == w)) {
      return _BotReply(
        ny
            ? 'Ndine Vero Assist — wothandizira wa Vero360 mu pulogalamu. Nditha kukutsogolerani, ndipo ngati mukufuna munthu ndidzakulumikizani pa WhatsApp kapena kuyimbira.'
            : 'I’m Vero Assist — Vero360’s in-app helper. I can guide you around the app, and if you need a person I’ll connect you on WhatsApp or a call.',
      );
    }

    if (_thanks.contains(compact) ||
        compact.startsWith('thank') ||
        compact.startsWith('zikomo')) {
      return _BotReply(
        ny
            ? _pick([
                'Zikomo! Chinanso chomwe ndingakuthandizeni?',
                'Nthawi iliyonse 🙂 Mundiyimbire ngati muvutika.',
                'Ndili wokondwa! Mukufunanso china?',
              ])
            : _pick([
                'You’re welcome! Anything else I can help with?',
                'Anytime 🙂 Ping me if you get stuck again.',
                'Glad that helped! Need anything else?',
              ]),
      );
    }

    if (_bye.contains(compact)) {
      return _BotReply(
        ny
            ? _pick([
                'Tiwonane! Tsegulani Support nthawi iliyonse mukandifuna.',
                'Tsalani bwino — gwiritsani Vero360!',
                'Tsalani bwino 👋',
              ])
            : _pick([
                'Bye! Open Support anytime if you need me again.',
                'See you later — enjoy Vero360!',
                'Take care 👋',
              ]),
      );
    }

    if (_acks.contains(compact)) {
      return _BotReply(
        ny
            ? _pick([
                'Chabwino. Ngati mukufunanso — maulendo, chakudya, maoda — funsani.',
                'Ndavamva. Chinanso chomwe ndingathandize?',
                'Chabwino. Ndili pano ngati muli ndi funso lina.',
              ])
            : _pick([
                'Cool. If you need anything else — rides, food, orders — just ask.',
                'Got it. What else can I help with?',
                'Alright. I’m here if you have another question.',
              ]),
      );
    }

    if (compact.contains('how are you') ||
        compact == 'how r u' ||
        compact.contains('how is it going') ||
        compact.contains('muli bwanji')) {
      return _BotReply(
        ny
            ? _pick([
                'Ndili bwino, zikomo kufunsa! Ndingakuthandizeni bwanji pa Vero360?',
                'Zili bwino kuno 😄 Mukufuna thandizo pa chiyani?',
              ])
            : _pick([
                'I’m doing great, thanks for asking! How can I help you on Vero360?',
                'All good here 😄 What do you need help with?',
              ]),
      );
    }

    if (compact.contains('love you') || compact == 'lol' || compact == 'haha') {
      return _BotReply(
        ny
            ? _pick([
                'Haha 😄 Nanga — maulendo, chakudya, maoda, kapena china?',
                '😂 Ndili pano mukakhala okonzeka. Mukufuna chiyani?',
              ])
            : _pick([
                'Haha 😄 So — rides, food, orders, or something else?',
                '😂 I’m here when you’re ready. What do you need?',
              ]),
      );
    }

    return null;
  }

  static String _pick(List<String> options) =>
      options[_rng.nextInt(options.length)];
}

class _Faq {
  final List<String> keys;
  final String answerEn;
  final String answerNy;
  final List<_BotAction> actions;
  const _Faq({
    required this.keys,
    required this.answerEn,
    required this.answerNy,
    this.actions = const [],
  });

  String answer(String lang) => lang == 'ny' ? answerNy : answerEn;

  int score(String q) {
    var s = 0;
    for (final k in keys) {
      if (q == k) {
        s += 10;
      } else if (q.contains(k)) {
        s += 4 + (k.length > 6 ? 1 : 0);
      } else {
        for (final w in q.split(RegExp(r'\s+'))) {
          if (w.length >= 3 && k.contains(w)) s += 1;
        }
      }
    }
    return s;
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.msg,
    required this.onAction,
    required this.lang,
  });
  final _ChatMsg msg;
  final void Function(_BotAction) onAction;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final align = msg.fromBot ? Alignment.centerLeft : Alignment.centerRight;
    final bg = msg.fromBot ? Colors.white : const Color(0xFFFF8A00);
    final fg = msg.fromBot ? const Color(0xFF101010) : Colors.white;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(msg.fromBot ? 4 : 16),
              bottomRight: Radius.circular(msg.fromBot ? 16 : 4),
            ),
            boxShadow: [
              if (msg.fromBot)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                msg.text,
                style: TextStyle(
                  color: fg,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  fontSize: 14.5,
                ),
              ),
              if (msg.actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in msg.actions)
                      OutlinedButton(
                        onPressed: () => onAction(a),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF8A00),
                          side: const BorderSide(color: Color(0xFFFF8A00)),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(_label(a)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _label(_BotAction a) {
    final ny = lang == 'ny';
    switch (a) {
      case _BotAction.whatsapp:
        return 'WhatsApp';
      case _BotAction.call:
        return ny ? 'Imbani' : 'Call';
      case _BotAction.email:
        return ny ? 'Imelo' : 'Email';
    }
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
