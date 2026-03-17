import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class CartItem {
  final String name;
  final String category;
  final double pricePerUnit;
  final int quantity;
  const CartItem({
    required this.name,
    required this.category,
    required this.pricePerUnit,
    required this.quantity,
  });
  double get lineTotal => pricePerUnit * quantity;
}

class PaymentScreen extends StatefulWidget {
  final String projectName;
  final List<CartItem> cartItems;
  final String currency;
  const PaymentScreen({
    super.key,
    required this.projectName,
    required this.cartItems,
    this.currency = '£',
  });
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  int _step = 0;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();
  String _delivery = 'standard';
  final _cardNumCtrl = TextEditingController();
  final _cardNameCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();
  String _method = 'card';
  bool _processing = false;
  final _form0 = GlobalKey<FormState>();
  final _form1 = GlobalKey<FormState>();

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _emailCtrl,
      _phoneCtrl,
      _addressCtrl,
      _cityCtrl,
      _postcodeCtrl,
      _cardNumCtrl,
      _cardNameCtrl,
      _expiryCtrl,
      _cvvCtrl,
    ])
      c.dispose();
    super.dispose();
  }

  double get _subtotal => widget.cartItems.fold(0.0, (s, i) => s + i.lineTotal);
  double get _vat => _subtotal * 0.10;
  double get _deliveryFee =>
      _delivery == 'express' ? 89.99 : (_subtotal > 1000 ? 0 : 49.99);
  double get _total => _subtotal + _vat + _deliveryFee;
  String get _c => widget.currency;

  void _next() async {
    if (_step == 0) {
      if (!(_form0.currentState?.validate() ?? false)) return;
      setState(() => _step = 1);
    } else if (_step == 1) {
      if (_method == 'card' && !(_form1.currentState?.validate() ?? false))
        return;
      setState(() => _processing = true);
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() {
        _processing = false;
        _step = 2;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceDark,
        elevation: 0,
        leading: _step == 2
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppTheme.textPrimary,
                ),
                onPressed: () => _step == 0
                    ? Navigator.pop(context)
                    : setState(() => _step--),
              ),
        title: const Row(
          children: [
            Icon(Icons.shopping_bag_outlined, color: AppTheme.accent, size: 20),
            SizedBox(width: 10),
            Text(
              'Checkout',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        bottom: _step < 2
            ? PreferredSize(
                preferredSize: const Size.fromHeight(36),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                  child: Row(
                    children: [
                      for (int i = 0; i < 2; i++) ...[
                        _StepDot(
                          label: ['Delivery', 'Payment'][i],
                          active: i == _step,
                          done: i < _step,
                        ),
                        if (i < 1)
                          Expanded(
                            child: Container(
                              height: 1,
                              color: i < _step
                                  ? AppTheme.accent
                                  : AppTheme.borderDark,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: _step == 2
          ? _confirmation()
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _step == 0 ? _deliveryForm() : _paymentForm(),
                  ),
                ),
                _orderPanel(),
              ],
            ),
    );
  }

  Widget _deliveryForm() => Form(
    key: _form0,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Delivery Details',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        _Sect(
          title: 'Contact',
          children: [
            _Fld(
              ctrl: _nameCtrl,
              label: 'Full Name',
              icon: Icons.person_outline,
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Fld(
                    ctrl: _emailCtrl,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        (v?.contains('@') ?? false) ? null : 'Invalid email',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Fld(
                    ctrl: _phoneCtrl,
                    label: 'Phone',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'Required' : null,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Sect(
          title: 'Address',
          children: [
            _Fld(
              ctrl: _addressCtrl,
              label: 'Street Address',
              icon: Icons.home_outlined,
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Fld(
                    ctrl: _cityCtrl,
                    label: 'City',
                    icon: Icons.location_city_outlined,
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Fld(
                    ctrl: _postcodeCtrl,
                    label: 'Postcode',
                    icon: Icons.pin_drop_outlined,
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'Required' : null,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Sect(
          title: 'Delivery Option',
          children: [
            _DelTile(
              value: 'standard',
              selected: _delivery,
              title: 'Standard Delivery',
              subtitle: '5–7 working days',
              price: _subtotal > 1000 ? 'FREE' : '${_c}49.99',
              onTap: () => setState(() => _delivery = 'standard'),
            ),
            const SizedBox(height: 10),
            _DelTile(
              value: 'express',
              selected: _delivery,
              title: 'Express Delivery',
              subtitle: '1–2 working days',
              price: '${_c}89.99',
              onTap: () => setState(() => _delivery = 'express'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _next,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.bgDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Continue to Payment',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _paymentForm() => Form(
    key: _form1,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        _Sect(
          title: 'Method',
          children: [
            Row(
              children: [
                for (final m in [
                  ('card', Icons.credit_card, 'Card'),
                  ('paypal', Icons.paypal, 'PayPal'),
                  ('bank', Icons.account_balance_outlined, 'Bank'),
                ])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _method = m.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _method == m.$1
                              ? AppTheme.accentGlow
                              : AppTheme.surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _method == m.$1
                                ? AppTheme.accent
                                : AppTheme.borderDark,
                            width: _method == m.$1 ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              m.$2,
                              color: _method == m.$1
                                  ? AppTheme.accent
                                  : AppTheme.textMuted,
                              size: 22,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m.$3,
                              style: TextStyle(
                                color: _method == m.$1
                                    ? AppTheme.accent
                                    : AppTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_method == 'card')
          _Sect(
            title: 'Card Details',
            children: [
              _Fld(
                ctrl: _cardNumCtrl,
                label: 'Card Number',
                icon: Icons.credit_card,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(16),
                ],
                validator: (v) =>
                    (v?.length == 16) ? null : 'Enter 16-digit number',
              ),
              const SizedBox(height: 12),
              _Fld(
                ctrl: _cardNameCtrl,
                label: 'Cardholder Name',
                icon: Icons.person_outline,
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Fld(
                      ctrl: _expiryCtrl,
                      label: 'Expiry (MM/YY)',
                      icon: Icons.date_range_outlined,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                        _ExpiryFmt(),
                      ],
                      validator: (v) => (v?.length == 5) ? null : 'Invalid',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Fld(
                      ctrl: _cvvCtrl,
                      label: 'CVV',
                      icon: Icons.lock_outline,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      validator: (v) =>
                          ((v?.length ?? 0) >= 3) ? null : 'Invalid',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.lock_outline, size: 13, color: AppTheme.success),
                  SizedBox(width: 6),
                  Text(
                    'Your details are encrypted and secure.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ],
          )
        else if (_method == 'paypal')
          _Sect(
            title: 'PayPal',
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.accent, size: 16),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You will be redirected to PayPal to complete payment.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          _Sect(
            title: 'Bank Transfer',
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.borderDark),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bank Details',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final r in [
                      ['Bank', 'HSBC UK'],
                      ['Sort Code', '40-47-84'],
                      ['Account', '12345678'],
                      ['Reference', 'FV-ORDER'],
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: Text(
                                r[0],
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              r[1],
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _processing ? null : _next,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.bgDark,
              disabledBackgroundColor: AppTheme.borderDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _processing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.bgDark,
                    ),
                  )
                : Text(
                    'Place Order  ·  $_c${_total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
          ),
        ),
      ],
    ),
  );

  Widget _orderPanel() => Container(
    width: 300,
    decoration: const BoxDecoration(
      color: AppTheme.surfaceDark,
      border: Border(left: BorderSide(color: AppTheme.borderDark)),
    ),
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order Summary',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.projectName,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            children: [
              for (final i in widget.cartItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${i.name} × ${i.quantity}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        '$_c${i.lineTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(color: AppTheme.borderDark, height: 20),
              _SR('Subtotal', '$_c${_subtotal.toStringAsFixed(2)}'),
              const SizedBox(height: 6),
              _SR(
                _delivery == 'express'
                    ? 'Express Delivery'
                    : 'Standard Delivery',
                _deliveryFee == 0
                    ? 'FREE'
                    : '$_c${_deliveryFee.toStringAsFixed(2)}',
              ),
              const SizedBox(height: 6),
              _SR('VAT (10%)', '$_c${_vat.toStringAsFixed(2)}'),
              const Divider(color: AppTheme.borderDark, height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Total',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    '$_c${_total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _confirmation() {
    final orderNo = 'FV-${math.Random().nextInt(90000) + 10000}';
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.success.withOpacity(0.12),
                border: Border.all(color: AppTheme.success, width: 2),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppTheme.success,
                size: 44,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Order Placed!',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Thank you for your purchase.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: Column(
                children: [
                  _CR('Order Number', orderNo),
                  const SizedBox(height: 10),
                  _CR(
                    'Items',
                    '${widget.cartItems.fold(0, (s, i) => s + i.quantity)} item(s)',
                  ),
                  const SizedBox(height: 10),
                  _CR('Total', '$_c${_total.toStringAsFixed(2)}'),
                  const SizedBox(height: 10),
                  _CR('Delivery', '5–7 working days'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'A confirmation will be sent to your email.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  int c = 0;
                  Navigator.popUntil(context, (r) => c++ >= 2);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.bgDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Back to My Design',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _SR(String l, String v) => Row(
    children: [
      Expanded(
        child: Text(
          l,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ),
      Text(
        v,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
    ],
  );
  Widget _CR(String l, String v) => Row(
    children: [
      Expanded(
        child: Text(
          l,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
      ),
      Text(
        v,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    ],
  );
}

class _Sect extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Sect({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.surfaceDark,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.borderDark),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

class _Fld extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  const _Fld({
    required this.ctrl,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.inputFormatters,
    this.validator,
  });
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: ctrl,
    keyboardType: keyboardType,
    obscureText: obscureText,
    inputFormatters: inputFormatters,
    validator: validator,
    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: AppTheme.textMuted),
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
        borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}

class _DelTile extends StatelessWidget {
  final String value, selected, title, subtitle, price;
  final VoidCallback onTap;
  const _DelTile({
    required this.value,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final sel = value == selected;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sel ? AppTheme.accentGlow : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? AppTheme.accent : AppTheme.borderDark,
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              sel ? Icons.radio_button_checked : Icons.radio_button_off,
              color: sel ? AppTheme.accent : AppTheme.textMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: sel ? AppTheme.accent : AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              price,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final String label;
  final bool active, done;
  const _StepDot({
    required this.label,
    required this.active,
    required this.done,
  });
  @override
  Widget build(BuildContext context) {
    final c = done || active ? AppTheme.accent : AppTheme.textMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? AppTheme.accent
                : active
                ? AppTheme.accentGlow
                : AppTheme.surfaceAlt,
            border: Border.all(color: c, width: 1.5),
          ),
          child: done
              ? const Icon(Icons.check, size: 13, color: AppTheme.bgDark)
              : null,
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: c,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ExpiryFmt extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    var d = n.text.replaceAll('/', '');
    if (d.length > 4) d = d.substring(0, 4);
    final b = StringBuffer();
    for (int i = 0; i < d.length; i++) {
      if (i == 2) b.write('/');
      b.write(d[i]);
    }
    final s = b.toString();
    return TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }
}
