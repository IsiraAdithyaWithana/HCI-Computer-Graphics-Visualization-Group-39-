import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/furniture_model.dart';
import '../services/custom_furniture_registry.dart';
import '../services/pricing_service.dart';
import '../theme/app_theme.dart';

/// Admin-only screen to define/update prices for every furniture type.
/// Prices are saved globally and visible to all users when viewing their bill.
class PricingManagerScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const PricingManagerScreen({super.key, this.onBack});

  @override
  State<PricingManagerScreen> createState() => _PricingManagerScreenState();
}

class _PricingManagerScreenState extends State<PricingManagerScreen> {
  // Working copy of prices — committed to PricingService on Save
  final Map<String, TextEditingController> _controllers = {};
  String _currency = '£';
  String _search = '';
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;

  // Built-in furniture types we show (exclude lights — they have no purchase price)
  static final _builtins = kFurnitureCategories
      .expand((cat) => cat.items)
      .toList();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await PricingService.instance.load();
    final existing = PricingService.instance.allPrices;

    // Built-in types
    for (final item in _builtins) {
      final key = item.type.name;
      _controllers[key] = TextEditingController(
        text: existing.containsKey(key)
            ? existing[key]!.toStringAsFixed(2)
            : '',
      );
    }

    // Custom GLB entries
    for (final entry in CustomFurnitureRegistry.instance.entries) {
      final key = entry.glbFileName;
      _controllers[key] = TextEditingController(
        text: existing.containsKey(key)
            ? existing[key]!.toStringAsFixed(2)
            : '',
      );
    }

    if (mounted)
      setState(() {
        _currency = PricingService.instance.currency;
        _loading = false;
      });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final prices = <String, double>{};
    for (final e in _controllers.entries) {
      final v = double.tryParse(e.value.text.trim());
      if (v != null && v >= 0) prices[e.key] = v;
    }
    await PricingService.instance.saveAll(prices, _currency);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _saved = false);
  }

  // ── Rows that match the current search ──────────────────────────────────

  List<_PriceRow> get _filteredRows {
    final q = _search.toLowerCase();
    final rows = <_PriceRow>[];

    for (final item in _builtins) {
      if (q.isNotEmpty && !item.label.toLowerCase().contains(q)) continue;
      rows.add(
        _PriceRow(
          key: item.type.name,
          label: item.label,
          subtitle: _categoryName(item.type),
          isCustom: false,
        ),
      );
    }

    for (final entry in CustomFurnitureRegistry.instance.entries) {
      if (q.isNotEmpty &&
          !entry.name.toLowerCase().contains(q) &&
          !entry.glbFileName.toLowerCase().contains(q))
        continue;
      rows.add(
        _PriceRow(
          key: entry.glbFileName,
          label: entry.name,
          subtitle: 'Custom · ${entry.glbFileName}',
          isCustom: true,
        ),
      );
    }

    return rows;
  }

  String _categoryName(FurnitureType type) {
    if ([
      FurnitureType.chair,
      FurnitureType.sofa,
      FurnitureType.armchair,
      FurnitureType.bench,
      FurnitureType.stool,
    ].contains(type))
      return 'Seating';
    if ([
      FurnitureType.table,
      FurnitureType.coffeeTable,
      FurnitureType.desk,
      FurnitureType.sideTable,
    ].contains(type))
      return 'Tables';
    if ([
      FurnitureType.wardrobe,
      FurnitureType.bookshelf,
      FurnitureType.cabinet,
      FurnitureType.dresser,
    ].contains(type))
      return 'Storage';
    if ([
      FurnitureType.bed,
      FurnitureType.singleBed,
      FurnitureType.nightstand,
    ].contains(type))
      return 'Bedroom';
    if ([
      FurnitureType.floorLampLight,
      FurnitureType.tableLampLight,
      FurnitureType.wallLight,
      FurnitureType.ceilingSpot,
      FurnitureType.windowLight,
    ].contains(type))
      return 'Lighting';
    return 'Décor';
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: AppTheme.textPrimary,
          ),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.maybePop(context);
            }
          },
        ),
        title: const Row(
          children: [
            Icon(Icons.sell_outlined, color: AppTheme.accent, size: 20),
            SizedBox(width: 10),
            Text(
              'Pricing Manager',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          // Currency selector
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderDark),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: DropdownButton<String>(
                value: _currency,
                underline: const SizedBox.shrink(),
                dropdownColor: AppTheme.surfaceAlt,
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                items: ['£', '\$', '€', 'Rs']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _currency = v);
                },
              ),
            ),
          ),
          // Save button
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 16, 10),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _saved
                  ? Container(
                      key: const ValueKey('saved'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.success.withOpacity(0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: AppTheme.success,
                            size: 15,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Saved!',
                            style: TextStyle(
                              color: AppTheme.success,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ElevatedButton.icon(
                      key: const ValueKey('save'),
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: AppTheme.bgDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.bgDark,
                              ),
                            )
                          : const Icon(Icons.save_outlined, size: 15),
                      label: const Text(
                        'Save Prices',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ──────────────────────────────────────────────────
          Container(
            color: AppTheme.surfaceDark,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search furniture...',
                hintStyle: const TextStyle(color: AppTheme.textMuted),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppTheme.textMuted,
                  size: 20,
                ),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppTheme.textMuted,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _search = ''),
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.borderDark),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.borderDark),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.accent,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
              ),
            ),
          ),

          // ── Info bar ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.accentGlow,
              border: const Border(
                bottom: BorderSide(color: AppTheme.borderDark),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppTheme.accent,
                  size: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Set a price for each furniture item. '
                    'Leave blank to show "Price on request" to users. '
                    '${rows.length} item${rows.length == 1 ? '' : 's'} shown.',
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Price list ─────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.accent),
                  )
                : rows.isEmpty
                ? const Center(
                    child: Text(
                      'No furniture matches your search.',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _PriceRowTile(
                      row: rows[i],
                      controller: _controllers[rows[i].key]!,
                      currency: _currency,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Data model for a single row ───────────────────────────────────────────────
class _PriceRow {
  final String key;
  final String label;
  final String subtitle;
  final bool isCustom;
  const _PriceRow({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.isCustom,
  });
}

// ── Individual price row tile ─────────────────────────────────────────────────
class _PriceRowTile extends StatelessWidget {
  final _PriceRow row;
  final TextEditingController controller;
  final String currency;

  const _PriceRowTile({
    required this.row,
    required this.controller,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: row.isCustom
                  ? AppTheme.info.withOpacity(0.12)
                  : AppTheme.accentGlow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              row.isCustom ? Icons.view_in_ar_outlined : Icons.chair_outlined,
              color: row.isCustom ? AppTheme.info : AppTheme.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Label
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.subtitle,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Price field
          SizedBox(
            width: 140,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: 'Not set',
                hintStyle: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 13,
                ),
                prefixText: '$currency ',
                prefixStyle: const TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w700,
                ),
                filled: true,
                fillColor: AppTheme.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.borderDark),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.borderDark),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppTheme.accent,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
