import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LoginScreen — luxury split-panel design
// Left: dark branding panel with geometric floor-plan art
// Right: clean cream form panel
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    Future.delayed(const Duration(milliseconds: 100), () {
      _fadeCtrl.forward();
      _slideCtrl.forward();
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Row(
        children: [
          // ── Left dark panel ──────────────────────────────────────────────
          Expanded(flex: 55, child: _LeftBrandingPanel()),
          // ── Right form panel ─────────────────────────────────────────────
          Expanded(
            flex: 45,
            child: Container(
              color: AppTheme.lightBg,
              child: Center(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: _buildForm(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      width: 380,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mini logo mark
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.bgDark,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.grid_view_rounded,
              color: AppTheme.accent,
              size: 22,
            ),
          ),
          const SizedBox(height: 28),

          Text(
            'Welcome back.',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppTheme.lightText,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to continue designing your spaces.',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.lightMuted,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 36),

          // Email
          _FormLabel('Email address'),
          const SizedBox(height: 6),
          _LightTextField(
            controller: _emailCtrl,
            hint: 'you@studio.com',
            icon: Icons.mail_outline_rounded,
          ),

          const SizedBox(height: 18),

          // Password
          _FormLabel('Password'),
          const SizedBox(height: 6),
          _LightTextField(
            controller: _passwordCtrl,
            hint: '••••••••',
            icon: Icons.lock_outline_rounded,
            obscure: _obscure,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: AppTheme.lightMuted,
              ),
            ),
          ),

          // Forgot password
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.accentDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),

          // Error
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 15, color: AppTheme.error),
                  const SizedBox(width: 8),
                  Text(
                    _error!,
                    style: TextStyle(fontSize: 12, color: AppTheme.error),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 28),

          // Login button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _loading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.bgDark,
                foregroundColor: AppTheme.accent,
                disabledBackgroundColor: AppTheme.bgDark.withOpacity(0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accent,
                      ),
                    )
                  : const Text(
                      'Sign In',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 20),

          // Divider
          Row(
            children: [
              Expanded(child: Divider(color: AppTheme.lightBorder)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'or',
                  style: TextStyle(fontSize: 12, color: AppTheme.lightMuted),
                ),
              ),
              Expanded(child: Divider(color: AppTheme.lightBorder)),
            ],
          ),

          const SizedBox(height: 20),

          // Guest / Demo button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _login,
              icon: Icon(
                Icons.play_arrow_rounded,
                color: AppTheme.lightText,
                size: 18,
              ),
              label: Text(
                'Continue as Guest',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.lightText,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.lightBorder, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Sign-up nudge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Don't have an account?",
                style: TextStyle(fontSize: 13, color: AppTheme.lightMuted),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Create one',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.accentDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Left branding panel ────────────────────────────────────────────────────

class _LeftBrandingPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D0D11), Color(0xFF111118), Color(0xFF0A0A0E)],
          stops: [0, 0.5, 1],
        ),
      ),
      child: Stack(
        children: [
          // Geometric floor-plan background art
          Positioned.fill(child: CustomPaint(painter: _FloorPlanPainter())),

          // Content
          Padding(
            padding: const EdgeInsets.all(52),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.accent.withOpacity(0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.grid_view_rounded,
                        color: AppTheme.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'Spazio',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // Main heading
                const Text(
                  'Design spaces\nwith precision.',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    height: 1.1,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Professional 2D + 3D room planning for interior\ndesigners, architects, and homeowners.',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppTheme.textSecondary,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 48),

                // Feature pills
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: const [
                    _FeaturePill(
                      icon: Icons.view_in_ar,
                      label: '3D Realistic View',
                    ),
                    _FeaturePill(icon: Icons.grid_4x4, label: '2D Floor Plan'),
                    _FeaturePill(
                      icon: Icons.add_box_outlined,
                      label: 'Custom Furniture',
                    ),
                    _FeaturePill(
                      icon: Icons.save_outlined,
                      label: 'Save & Export',
                    ),
                  ],
                ),

                const SizedBox(height: 52),

                // Stat strip
                Row(
                  children: [
                    _StatBadge(value: '20+', label: 'Furniture Types'),
                    _Vr(),
                    _StatBadge(value: '3D', label: 'Realistic Preview'),
                    _Vr(),
                    _StatBadge(value: '∞', label: 'Saved Projects'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeaturePill({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.surfaceDark.withOpacity(0.6),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTheme.borderDark),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.accent),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _StatBadge extends StatelessWidget {
  final String value, label;
  const _StatBadge({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.accent,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _Vr extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 32,
    color: AppTheme.borderDark,
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );
}

// ── Light text field for form ──────────────────────────────────────────────

class _FormLabel extends StatelessWidget {
  final String text;
  const _FormLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppTheme.lightText,
      letterSpacing: 0.2,
    ),
  );
}

class _LightTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffixIcon;

  const _LightTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscure,
    style: const TextStyle(fontSize: 14, color: AppTheme.lightText),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppTheme.lightMuted, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: AppTheme.lightMuted),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppTheme.lightSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.accentDark, width: 1.5),
      ),
    ),
  );
}

// ── Floor-plan background art painter ─────────────────────────────────────

class _FloorPlanPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wallPaint = Paint()
      ..color = AppTheme.accent.withOpacity(0.08)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final dimPaint = Paint()
      ..color = AppTheme.accent.withOpacity(0.04)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = AppTheme.accent.withOpacity(0.03)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // ── Large floor plan outline ──────────────────────────────────────────
    final outerRoom = Rect.fromLTWH(w * 0.08, h * 0.15, w * 0.84, h * 0.7);
    canvas.drawRect(outerRoom, fillPaint);
    canvas.drawRect(outerRoom, wallPaint);

    // ── Inner rooms (walls) ───────────────────────────────────────────────
    // Vertical wall divider
    canvas.drawLine(
      Offset(w * 0.50, h * 0.15),
      Offset(w * 0.50, h * 0.56),
      wallPaint,
    );
    // Horizontal divider
    canvas.drawLine(
      Offset(w * 0.08, h * 0.56),
      Offset(w * 0.72, h * 0.56),
      wallPaint,
    );
    // Right room divider
    canvas.drawLine(
      Offset(w * 0.72, h * 0.56),
      Offset(w * 0.72, h * 0.85),
      wallPaint,
    );

    // ── Door arcs ─────────────────────────────────────────────────────────
    final doorPaint = Paint()
      ..color = AppTheme.accent.withOpacity(0.12)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Door in left wall
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.35),
        width: 60,
        height: 60,
      ),
      0,
      -math.pi / 2,
      false,
      doorPaint,
    );
    canvas.drawLine(
      Offset(w * 0.50, h * 0.35),
      Offset(w * 0.50 + 30, h * 0.35),
      doorPaint,
    );

    // Door in bottom
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.30, h * 0.56),
        width: 50,
        height: 50,
      ),
      math.pi / 2,
      math.pi / 2,
      false,
      doorPaint,
    );

    // ── Grid (thin dimension lines) ───────────────────────────────────────
    for (int i = 1; i < 6; i++) {
      final x = w * 0.08 + (w * 0.84 / 6) * i;
      canvas.drawLine(Offset(x, h * 0.15), Offset(x, h * 0.85), dimPaint);
    }
    for (int i = 1; i < 5; i++) {
      final y = h * 0.15 + (h * 0.7 / 5) * i;
      canvas.drawLine(Offset(w * 0.08, y), Offset(w * 0.92, y), dimPaint);
    }

    // ── Furniture silhouettes ─────────────────────────────────────────────
    final furniPaint = Paint()
      ..color = AppTheme.accent.withOpacity(0.09)
      ..style = PaintingStyle.fill;
    final furniStroke = Paint()
      ..color = AppTheme.accent.withOpacity(0.15)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Sofa (left room)
    _drawRoundRect(
      canvas,
      Rect.fromLTWH(w * 0.12, h * 0.22, w * 0.28, h * 0.10),
      4,
      furniPaint,
      furniStroke,
    );
    // Coffee table
    _drawRoundRect(
      canvas,
      Rect.fromLTWH(w * 0.17, h * 0.36, w * 0.14, h * 0.07),
      3,
      furniPaint,
      furniStroke,
    );
    // Armchair
    _drawRoundRect(
      canvas,
      Rect.fromLTWH(w * 0.38, h * 0.25, w * 0.08, h * 0.08),
      4,
      furniPaint,
      furniStroke,
    );

    // Bed (right room)
    _drawRoundRect(
      canvas,
      Rect.fromLTWH(w * 0.56, h * 0.20, w * 0.28, h * 0.22),
      4,
      furniPaint,
      furniStroke,
    );
    // Bedside tables
    _drawRoundRect(
      canvas,
      Rect.fromLTWH(w * 0.54, h * 0.23, w * 0.03, h * 0.05),
      2,
      furniPaint,
      furniStroke,
    );
    _drawRoundRect(
      canvas,
      Rect.fromLTWH(w * 0.83, h * 0.23, w * 0.03, h * 0.05),
      2,
      furniPaint,
      furniStroke,
    );

    // Dining table (bottom left)
    _drawRoundRect(
      canvas,
      Rect.fromLTWH(w * 0.12, h * 0.62, w * 0.20, h * 0.12),
      3,
      furniPaint,
      furniStroke,
    );
    // Chairs around table
    for (int i = 0; i < 3; i++) {
      _drawRoundRect(
        canvas,
        Rect.fromLTWH(w * 0.14 + i * w * 0.07, h * 0.76, w * 0.05, h * 0.04),
        2,
        furniPaint,
        furniStroke,
      );
    }

    // ── Dimension annotation lines ─────────────────────────────────────────
    final annotePaint = Paint()
      ..color = AppTheme.accent.withOpacity(0.2)
      ..strokeWidth = 0.75;
    // Top dimension
    canvas.drawLine(
      Offset(w * 0.08, h * 0.10),
      Offset(w * 0.92, h * 0.10),
      annotePaint,
    );
    canvas.drawLine(
      Offset(w * 0.08, h * 0.08),
      Offset(w * 0.08, h * 0.12),
      annotePaint,
    );
    canvas.drawLine(
      Offset(w * 0.92, h * 0.08),
      Offset(w * 0.92, h * 0.12),
      annotePaint,
    );
    // Left dimension
    canvas.drawLine(
      Offset(w * 0.03, h * 0.15),
      Offset(w * 0.03, h * 0.85),
      annotePaint,
    );
    canvas.drawLine(
      Offset(w * 0.01, h * 0.15),
      Offset(w * 0.05, h * 0.15),
      annotePaint,
    );
    canvas.drawLine(
      Offset(w * 0.01, h * 0.85),
      Offset(w * 0.05, h * 0.85),
      annotePaint,
    );
  }

  void _drawRoundRect(
    Canvas c,
    Rect r,
    double radius,
    Paint fill,
    Paint stroke,
  ) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
    c.drawRRect(rr, fill);
    c.drawRRect(rr, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
