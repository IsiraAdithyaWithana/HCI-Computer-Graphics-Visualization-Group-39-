import 'package:flutter/material.dart';
import '../models/furniture_model.dart';
import '../services/pricing_service.dart';
import '../theme/app_theme.dart';
import 'payment_screen.dart';

// ── BillPreviewScreen ─────────────────────────────────────────────────────────
// Shown when a user (or admin) clicks "View Bill" from 2D or 3D view.
// Loads prices from PricingService and builds an itemised bill.

class BillPreviewScreen extends StatefulWidget {
  final List<FurnitureModel> furniture;
  final String projectName;

  const BillPreviewScreen({
    super.key,
    required this.furniture,
    required this.projectName,
  });

  @override
  State<BillPreviewScreen> createState() => _BillPreviewScreenState();
}

class _BillPreviewScreenState extends State<BillPreviewScreen> {
  bool _loading = true;
  late List<_BillLine> _lines;
  late String _currency;

  @override
  void initState() {
    super.initState();
    _buildBill();
  }

  Future<void> _buildBill() async {
    await PricingService.instance.load();
    _currency = PricingService.instance.currency;

    // Group furniture by type key → { label, typeKey, quantity, unitPrice }
    final Map<String, _BillLine> grouped = {};
    for (final item in widget.furniture) {
      final typeKey = item.glbOverride != null
          ? item.glbOverride!.split('/').last
          : item.type.name;

      final label =
          item.labelOverride ??
          item.glbOverride?.split('/').last.replaceAll('_', ' ') ??
          _typeLabel(item.type);

      final price = PricingService.instance.getPrice(typeKey);

      if (grouped.containsKey(typeKey)) {
        grouped[typeKey]!.quantity++;
      } else {
        grouped[typeKey] = _BillLine(
          label: label,
          typeKey: typeKey,
          unitPrice: price,
          quantity: 1,
          isCustom: item.glbOverride != null,
        );
      }
    }

    _lines = grouped.values.toList();
    if (mounted) setState(() => _loading = false);
  }

  String _typeLabel(FurnitureType t) {
    const map = {
      FurnitureType.chair: 'Chair',
      FurnitureType.sofa: 'Sofa',
      FurnitureType.armchair: 'Armchair',
      FurnitureType.bench: 'Bench',
      FurnitureType.stool: 'Stool',
      FurnitureType.table: 'Dining Table',
      FurnitureType.coffeeTable: 'Coffee Table',
      FurnitureType.desk: 'Desk',
      FurnitureType.sideTable: 'Side Table',
      FurnitureType.wardrobe: 'Wardrobe',
      FurnitureType.bookshelf: 'Bookshelf',
      FurnitureType.cabinet: 'Cabinet',
      FurnitureType.dresser: 'Dresser',
      FurnitureType.bed: 'Bed',
      FurnitureType.singleBed: 'Single Bed',
      FurnitureType.nightstand: 'Nightstand',
      FurnitureType.plant: 'Plant',
      FurnitureType.lamp: 'Lamp',
      FurnitureType.tvStand: 'TV Stand',
      FurnitureType.rug: 'Rug',
      FurnitureType.floorLampLight: 'Floor Lamp',
      FurnitureType.tableLampLight: 'Table Lamp',
      FurnitureType.wallLight: 'Wall Light',
      FurnitureType.ceilingSpot: 'Ceiling Spot',
      FurnitureType.windowLight: 'Window Light',
    };
    return map[t] ?? t.name;
  }

  double get _subtotal => _lines.fold(
    0,
    (s, l) => s + (l.unitPrice != null ? l.unitPrice! * l.quantity : 0),
  );
  double get _vat => _subtotal * 0.10;
  double get _grandTotal => _subtotal + _vat;

  bool get _hasPrices => _lines.any((l) => l.unitPrice != null);

  List<CartItem> _toCartItems() => _lines
      .where((l) => l.unitPrice != null)
      .map(
        (l) => CartItem(
          name: l.label,
          category: l.isCustom ? 'Custom' : 'Furniture',
          pricePerUnit: l.unitPrice!,
          quantity: l.quantity,
        ),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
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
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(Icons.receipt_long_outlined, color: AppTheme.accent, size: 20),
            SizedBox(width: 10),
            Text(
              'My Bill',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            )
          : Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  color: AppTheme.surfaceDark,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.projectName,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_lines.fold(0, (s, l) => s + l.quantity)} item(s) in this design',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppTheme.borderDark, height: 1),

                // Bill lines
                Expanded(
                  child: _lines.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chair_outlined,
                                size: 56,
                                color: AppTheme.textMuted,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'No furniture in this design.',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          children: [
                            // Column headers
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 54,
                                bottom: 8,
                              ),
                              child: Row(
                                children: const [
                                  Expanded(
                                    child: Text(
                                      'Item',
                                      style: TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 60,
                                    child: Text(
                                      'Qty',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 90,
                                    child: Text(
                                      'Unit Price',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 90,
                                    child: Text(
                                      'Total',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Item rows
                            ..._lines.map(
                              (line) =>
                                  _BillLineRow(line: line, currency: _currency),
                            ),

                            const SizedBox(height: 16),
                            const Divider(color: AppTheme.borderDark),
                            const SizedBox(height: 10),

                            // Totals
                            if (_hasPrices) ...[
                              _TotalRow(
                                label: 'Subtotal',
                                value:
                                    '$_currency${_subtotal.toStringAsFixed(2)}',
                              ),
                              const SizedBox(height: 6),
                              _TotalRow(
                                label: 'VAT (10%)',
                                value: '$_currency${_vat.toStringAsFixed(2)}',
                              ),
                              const SizedBox(height: 10),
                              const Divider(color: AppTheme.borderDark),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Grand Total',
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$_currency${_grandTotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: AppTheme.accent,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 22,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Delivery costs will be calculated at checkout.',
                                style: TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppTheme.warning.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppTheme.warning.withOpacity(0.3),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: AppTheme.warning,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Prices have not been set by the designer yet. '
                                        'Please contact us for a quote.',
                                        style: TextStyle(
                                          color: AppTheme.warning,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                ),

                // ── Bottom bar ────────────────────────────────────────────
                if (_hasPrices)
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: const BoxDecoration(
                      color: AppTheme.surfaceDark,
                      border: Border(
                        top: BorderSide(color: AppTheme.borderDark),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PaymentScreen(
                                projectName: widget.projectName,
                                cartItems: _toCartItems(),
                                currency: _currency,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: AppTheme.bgDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                        label: Text(
                          'Proceed to Purchase  ·  '
                          '$_currency${_grandTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ── Bill line data ────────────────────────────────────────────────────────────
class _BillLine {
  final String label;
  final String typeKey;
  final double? unitPrice;
  int quantity;
  final bool isCustom;

  _BillLine({
    required this.label,
    required this.typeKey,
    required this.unitPrice,
    required this.quantity,
    required this.isCustom,
  });

  double? get lineTotal => unitPrice != null ? unitPrice! * quantity : null;
}

// ── Row widget ────────────────────────────────────────────────────────────────
class _BillLineRow extends StatelessWidget {
  final _BillLine line;
  final String currency;

  const _BillLineRow({super.key, required this.line, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              color: line.isCustom
                  ? AppTheme.info.withOpacity(0.12)
                  : AppTheme.accentGlow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              line.isCustom ? Icons.view_in_ar_outlined : Icons.chair_outlined,
              color: line.isCustom ? AppTheme.info : AppTheme.accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),

          // Label
          Expanded(
            child: Text(
              line.label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),

          // Qty
          SizedBox(
            width: 60,
            child: Text(
              '× ${line.quantity}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),

          // Unit price
          SizedBox(
            width: 90,
            child: Text(
              line.unitPrice != null
                  ? '$currency${line.unitPrice!.toStringAsFixed(2)}'
                  : 'On request',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: line.unitPrice != null
                    ? AppTheme.textSecondary
                    : AppTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ),

          // Line total
          SizedBox(
            width: 90,
            child: Text(
              line.lineTotal != null
                  ? '$currency${line.lineTotal!.toStringAsFixed(2)}'
                  : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: line.lineTotal != null
                    ? AppTheme.textPrimary
                    : AppTheme.textMuted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label, value;
  const _TotalRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      ),
      Text(
        value,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ],
  );
}
