import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores furniture prices globally — shared across ALL users and projects.
///
/// Key strategy (matches FurnitureScaleService):
///   Built-in types  → FurnitureType.name  (e.g. "chair", "sofa")
///   Custom GLB items → glbFileName         (e.g. "custom_sofa_123.glb")
class PricingService {
  PricingService._();
  static final instance = PricingService._();

  static const _pricesKey = 'global:furniturePrices';
  static const _currencyKey = 'global:pricingCurrency';

  final Map<String, double> _prices = {};
  String _currency = '£';
  bool _loaded = false;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_pricesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          if (v is num) _prices[k] = v.toDouble();
        });
      } catch (_) {}
    }

    _currency = prefs.getString(_currencyKey) ?? '£';
    _loaded = true;
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns the price for [typeKey], or null if none has been set.
  double? getPrice(String typeKey) => _prices[typeKey];

  String get currency => _currency;

  Map<String, double> get allPrices => Map.unmodifiable(_prices);

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> saveAll(Map<String, double> prices, String currency) async {
    _prices
      ..clear()
      ..addAll(prices);
    _currency = currency;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pricesKey, jsonEncode(_prices));
    await prefs.setString(_currencyKey, _currency);
  }
}
