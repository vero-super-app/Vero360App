import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/features/DigitalServices/chatgpt_plans.dart';
import 'package:vero360_app/features/DigitalServices/netflix_plans.dart';

/// Fallback USD → MWK rate when Firestore config is unavailable.
const double kUsdToMwkRate = 4700;

/// Live rate (updated by [DigitalServicesCatalog] from admin panel).
double digitalServicesUsdToMwkRate = kUsdToMwkRate;

final NumberFormat _usdFmt =
    NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
final NumberFormat _mwkFmt =
    NumberFormat.currency(locale: 'en_US', symbol: 'MWK ', decimalDigits: 0);

String formatUsd(num usd) => _usdFmt.format(usd);
String formatMwk(num mwk) => _mwkFmt.format(mwk.round());
double usdToMwk(num usd) => usd * digitalServicesUsdToMwkRate;

class DigitalProduct {
  final String key;
  final String name;
  final String subtitle;
  final String category;
  final Color accent;
  final String brandTag;
  final IconData? icon;
  final String? logoAsset;

  /// Remote picture URL (custom crypto / gift cards from admin).
  final String? imageUrl;

  /// Selectable face values in USD (Giftsy-style). Ignored when [fixedMwkPrice] is set.
  final List<double> usdAmounts;

  /// Fixed MWK price for subscription codes (Spotify / Apple Music / Netflix / ChatGPT).
  /// When set: skip amount picker and charge this MWK amount via PayChangu.
  final double? fixedMwkPrice;

  /// Custom MWK per unit (USDT / CNY / BNB). Overrides global USD rate when set.
  final double? mwkPerUnit;

  /// Unit label for amount picker (e.g. USDT, RMB, CNY). Empty → treat as USD.
  final String? unitLabel;

  /// Max custom ("other") amount in [unitLabel] units (or USD). Set by admin.
  final double? maxOtherAmount;

  /// When false, product is hidden (admin disabled).
  final bool active;

  const DigitalProduct({
    required this.key,
    required this.name,
    required this.subtitle,
    required this.category,
    required this.accent,
    required this.brandTag,
    this.usdAmounts = const [],
    this.fixedMwkPrice,
    this.mwkPerUnit,
    this.unitLabel,
    this.maxOtherAmount,
    this.icon,
    this.logoAsset,
    this.imageUrl,
    this.active = true,
  });

  bool get usesAmountPicker =>
      fixedMwkPrice == null && !isNetflixHub && !isChatGptHub;

  /// Homepage Netflix tile — opens plan picker instead of checkout.
  bool get isNetflixHub => key == 'netflix';

  bool get isNetflixPlan => key.startsWith('netflix_');

  /// Homepage ChatGPT tile — opens plan picker instead of checkout.
  bool get isChatGptHub => key == 'chatgpt';

  bool get isChatGptPlan => key == 'chatgpt_basic' || key == 'chatgpt_plus';

  double get startingUsd =>
      usdAmounts.isEmpty ? 0 : usdAmounts.reduce((a, b) => a < b ? a : b);

  /// Currency code shown on the custom-amount field (USDT / RMB / USD…).
  String get amountUnitLabel {
    final unit = (unitLabel ?? '').trim();
    if (unit.isNotEmpty) return unit.toUpperCase();
    return 'USD';
  }

  /// CNY / USD-TT / USDT payouts need destination + identity photos.
  DigitalPayoutKycKind? get payoutKycKind => detectDigitalPayoutKycKind(
        category: category,
        key: key,
        name: name,
        unitLabel: unitLabel ?? '',
        brandTag: brandTag,
        subtitle: subtitle,
      );

  bool get needsPayoutKyc => payoutKycKind != null;

  /// Admin max for typed amounts. If unset, allow a high default (not a hard $500).
  double get effectiveMaxOtherAmount {
    final admin = maxOtherAmount;
    if (admin != null && admin > 0) return admin;
    if (usdAmounts.isNotEmpty) {
      final largest = usdAmounts.reduce((a, b) => a > b ? a : b);
      return largest > 1000 ? largest : 10000;
    }
    return 10000;
  }

  double get effectiveMinOtherAmount => 1;

  double get effectiveMwkPerUnit =>
      (mwkPerUnit != null && mwkPerUnit! > 0)
          ? mwkPerUnit!
          : digitalServicesUsdToMwkRate;

  double amountToMwk(num amount) => amount * effectiveMwkPerUnit;

  String formatAmount(num amount) {
    final unit = amountUnitLabel;
    if (unit != 'USD') {
      final n = amount == amount.roundToDouble()
          ? amount.toStringAsFixed(0)
          : amount.toStringAsFixed(2);
      return '$n $unit';
    }
    return formatUsd(amount);
  }

  String get priceLabel {
    if (isNetflixHub || isChatGptHub) return 'Choose a plan';
    if (fixedMwkPrice != null && fixedMwkPrice! > 0) {
      return formatMwk(fixedMwkPrice!);
    }
    if (usdAmounts.isEmpty) return '—';
    return 'From ${formatAmount(startingUsd)}';
  }

  DigitalProduct copyWith({
    String? name,
    String? subtitle,
    String? brandTag,
    String? category,
    Color? accent,
    List<double>? usdAmounts,
    double? fixedMwkPrice,
    bool clearFixedMwkPrice = false,
    double? mwkPerUnit,
    bool clearMwkPerUnit = false,
    String? unitLabel,
    double? maxOtherAmount,
    bool clearMaxOtherAmount = false,
    String? imageUrl,
    bool? active,
  }) {
    return DigitalProduct(
      key: key,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      category: category ?? this.category,
      accent: accent ?? this.accent,
      brandTag: brandTag ?? this.brandTag,
      usdAmounts: usdAmounts ?? this.usdAmounts,
      fixedMwkPrice:
          clearFixedMwkPrice ? null : (fixedMwkPrice ?? this.fixedMwkPrice),
      mwkPerUnit: clearMwkPerUnit ? null : (mwkPerUnit ?? this.mwkPerUnit),
      unitLabel: unitLabel ?? this.unitLabel,
      maxOtherAmount: clearMaxOtherAmount
          ? null
          : (maxOtherAmount ?? this.maxOtherAmount),
      icon: icon,
      logoAsset: logoAsset,
      imageUrl: imageUrl ?? this.imageUrl,
      active: active ?? this.active,
    );
  }
}

/// Homepage Digital Services grid — metadata only; MWK prices come from admin.
const List<DigitalProduct> kDigitalProducts = [
  DigitalProduct(
    key: 'spotify',
    name: 'Spotify Premium',
    subtitle: '1-month subscription',
    category: 'streaming',
    accent: Color(0xFF1DB954),
    brandTag: 'Spotify',
    logoAsset: 'assets/brands/spotify.jpg',
    icon: Icons.music_note_rounded,
  ),
  DigitalProduct(
    key: 'apple_music',
    name: 'Apple Music',
    subtitle: '1-month subscription',
    category: 'streaming',
    accent: Color(0xFFFA243C),
    brandTag: 'Music',
    logoAsset: 'assets/brands/apple_music.png',
    icon: Icons.music_note_rounded,
  ),
  DigitalProduct(
    key: 'netflix',
    name: 'Netflix',
    subtitle: 'Choose a plan',
    category: 'streaming',
    accent: Color(0xFFE50914),
    brandTag: 'Netflix',
    logoAsset: 'assets/brands/netflix.png',
    icon: Icons.movie_creation_outlined,
    // Hub only — prices live on netflix_* plan products (admin).
  ),
  DigitalProduct(
    key: 'chatgpt',
    name: 'ChatGPT',
    subtitle: 'Choose a plan',
    category: 'streaming',
    accent: Color(0xFF10A37F),
    brandTag: 'GPT',
    logoAsset: 'assets/brands/chatgpt.png',
    icon: Icons.chat_bubble_outline_rounded,
  ),
];

/// Full catalog for the Digital Services page (Giftsy-style brands + streaming).
const List<DigitalProduct> kAllDigitalProducts = [
  DigitalProduct(
    key: 'visa_gc',
    name: 'Visa Gift Card',
    subtitle: 'Prepaid Visa digital card',
    category: 'gift_cards',
    accent: Color(0xFF1A1F71),
    brandTag: 'VISA',
    icon: Icons.credit_card_rounded,
    usdAmounts: [10, 25, 50, 100, 200],
  ),
  DigitalProduct(
    key: 'paypal_gc',
    name: 'PayPal',
    subtitle: 'PayPal balance top-up',
    category: 'gift_cards',
    accent: Color(0xFF003087),
    brandTag: 'PayPal',
    icon: Icons.account_balance_wallet_rounded,
    usdAmounts: [10, 25, 50, 100],
  ),
  DigitalProduct(
    key: 'mastercard_gc',
    name: 'Mastercard Gift',
    subtitle: 'Prepaid Mastercard digital card',
    category: 'gift_cards',
    accent: Color(0xFFEB001B),
    brandTag: 'MC',
    icon: Icons.credit_card_rounded,
    usdAmounts: [10, 25, 50, 100, 200],
  ),
  DigitalProduct(
    key: 'amazon_gc',
    name: 'Amazon',
    subtitle: 'Amazon gift card',
    category: 'gift_cards',
    accent: Color(0xFF232F3E),
    brandTag: 'Amazon',
    icon: Icons.card_giftcard_rounded,
    usdAmounts: [10, 25, 50, 100],
  ),
  DigitalProduct(
    key: 'itunes',
    name: 'Apple Gift Card',
    subtitle: 'App Store & iTunes',
    category: 'gift_cards',
    accent: Color(0xFF555555),
    brandTag: 'Apple',
    icon: Icons.apple,
    usdAmounts: [10, 15, 25, 50, 100],
  ),
  DigitalProduct(
    key: 'steam_gc',
    name: 'Steam Wallet',
    subtitle: 'Steam wallet top-up',
    category: 'gaming',
    accent: Color(0xFF1B2838),
    brandTag: 'STEAM',
    icon: Icons.sports_esports_rounded,
    usdAmounts: [5, 10, 20, 50, 100],
  ),
  DigitalProduct(
    key: 'google_play',
    name: 'Google Play',
    subtitle: 'Google Play gift card',
    category: 'gaming',
    accent: Color(0xFF34A853),
    brandTag: 'Play',
    icon: Icons.play_arrow_rounded,
    usdAmounts: [10, 25, 50, 100],
  ),
  DigitalProduct(
    key: 'playstation',
    name: 'PlayStation',
    subtitle: 'PSN wallet gift card',
    category: 'gaming',
    accent: Color(0xFF003791),
    brandTag: 'PSN',
    icon: Icons.sports_esports_outlined,
    usdAmounts: [10, 25, 50, 100],
  ),
  DigitalProduct(
    key: 'xbox',
    name: 'Xbox',
    subtitle: 'Xbox / Microsoft Store gift card',
    category: 'gaming',
    accent: Color(0xFF107C10),
    brandTag: 'Xbox',
    icon: Icons.gamepad_rounded,
    usdAmounts: [10, 25, 50, 100],
  ),
  DigitalProduct(
    key: 'eneba',
    name: 'Eneba',
    subtitle: 'Eneba wallet gift card',
    category: 'gaming',
    accent: Color(0xFF6C5CE7),
    brandTag: 'Eneba',
    icon: Icons.videogame_asset_rounded,
    usdAmounts: [10, 25, 50, 100],
  ),
  ...kDigitalProducts,
  ...kNetflixPlanProducts,
  ...kChatGptPlanProducts,
];

class DigitalCategory {
  final String id;
  final String label;
  final IconData icon;

  const DigitalCategory(this.id, this.label, this.icon);
}

const List<DigitalCategory> kDigitalCategories = [
  DigitalCategory('all', 'All', Icons.apps_rounded),
  DigitalCategory('gift_cards', 'Gift Cards', Icons.card_giftcard_rounded),
  DigitalCategory('crypto', 'Crypto / FX', Icons.currency_exchange_rounded),
  DigitalCategory('gaming', 'Gaming', Icons.sports_esports_rounded),
  DigitalCategory('streaming', 'Streaming', Icons.live_tv_rounded),
];

enum DigitalPayMethod {
  paychangu, // mobile money + bank (MWK)
  visa, // coming soon
}

/// Destination / identity pack collected at checkout for crypto & FX cards.
enum DigitalPayoutKycKind { cny, usdt }

DigitalPayoutKycKind? detectDigitalPayoutKycKind({
  required String category,
  required String key,
  String name = '',
  String unitLabel = '',
  String brandTag = '',
  String subtitle = '',
}) {
  final blob =
      '$key $name $subtitle $brandTag $unitLabel $category'.toLowerCase();
  final unit = unitLabel.trim().toLowerCase();
  final isCrypto = category.trim().toLowerCase() == 'crypto';

  final isUsdt = blob.contains('usdt') ||
      blob.contains('tether') ||
      blob.contains('binance') ||
      unit == 'usdt';
  if (isUsdt) return DigitalPayoutKycKind.usdt;

  final mentionsChinaRail =
      blob.contains('cny') ||
      blob.contains('rmb') ||
      blob.contains('yuan') ||
      blob.contains('alipay') ||
      blob.contains('wechat') ||
      blob.contains('weixin') ||
      unit == 'cny' ||
      unit == 'rmb';
  final isTt = RegExp(r'\btt\b').hasMatch(blob) || blob.contains('telegraphic');
  if (mentionsChinaRail ||
      (isTt &&
          (mentionsChinaRail ||
              blob.contains('china') ||
              isCrypto))) {
    return DigitalPayoutKycKind.cny;
  }

  // Crypto USD (not a gift card) uses the same Alipay/WeChat + ID + face pack.
  if (isCrypto && (unit == 'usd' || blob.contains('usd'))) {
    return DigitalPayoutKycKind.cny;
  }
  if (isCrypto) return DigitalPayoutKycKind.usdt;
  return null;
}
 