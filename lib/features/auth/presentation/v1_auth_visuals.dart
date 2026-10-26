import 'dart:ui';

import 'package:flutter/material.dart';

/// V1's authentication visual language, ported without V1's controllers,
/// Firebase access, stored passwords or salon/booking branding.
enum AuthDecorationVariant { login, register, reset }

class V1AuthLayout extends StatefulWidget {
  const V1AuthLayout({
    required this.title,
    required this.subtitle,
    required this.content,
    required this.variant,
    this.footer,
    this.onBack,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget content;
  final Widget? footer;
  final VoidCallback? onBack;
  final AuthDecorationVariant variant;

  @override
  State<V1AuthLayout> createState() => _V1AuthLayoutState();
}

class _V1AuthLayoutState extends State<V1AuthLayout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutQuad,
    ));
    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final height = screenSize.height;
    final isLogin = widget.variant == AuthDecorationVariant.login;
    final isReset = widget.variant == AuthDecorationVariant.reset;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    const Color(0xFF1A237E),
                    const Color(0xFF303F9F),
                    const Color(0xFF1565C0),
                  ],
                  stops: const [0.1, 0.5, 0.9],
                ),
              ),
              child: const SizedBox.expand(),
            ),
            Positioned(
              top: -height * 0.1,
              right: -screenSize.width * 0.2,
              child: CircleAvatar(
                radius: (screenSize.width * 0.3).clamp(60.0, 300.0),
                backgroundColor: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            Positioned(
              bottom: -height * 0.05,
              left: -screenSize.width * 0.1,
              child: CircleAvatar(
                radius: (screenSize.width * 0.25).clamp(50.0, 250.0),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            for (var i = 0; i < 6; i++)
              Positioned(
                top: height * i / 6,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: height / 12,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.04),
                          Colors.white.withValues(alpha: 0),
                        ],
                        stops: const [0.1, 0.5, 0.9],
                      ),
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 12),
                            if (widget.onBack != null)
                              Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  tooltip: 'رجوع',
                                  onPressed: widget.onBack,
                                  icon: const Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            if (isReset) SizedBox(height: height * 0.02),
                            Center(
                              child: Hero(
                                tag: isReset ? 'reset_logo' : 'app_logo',
                                child: Container(
                                  height: isLogin ? 130 : 110,
                                  width: isLogin ? 130 : 110,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withValues(alpha: 0.5),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    isReset
                                        ? Icons.lock_reset_rounded
                                        : isLogin
                                            ? Icons.electric_bolt_rounded
                                            : Icons.person_add_alt_1_rounded,
                                    size: isLogin ? 68 : 56,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                                height: isLogin
                                    ? 40
                                    : isReset
                                        ? 30
                                        : 20),
                            Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isLogin ? 32 : 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    offset: const Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: isLogin || isReset ? 12 : 8),
                            Text(
                              widget.subtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white.withValues(alpha: 0.9),
                                letterSpacing: 0.5,
                                height: 1.3,
                              ),
                            ),
                            SizedBox(
                                height: isLogin
                                    ? 50
                                    : isReset
                                        ? 40
                                        : 25),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 10,
                                  sigmaY: 10,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: widget.content,
                                ),
                              ),
                            ),
                            if (widget.footer != null) ...[
                              SizedBox(height: isLogin ? 30 : 24),
                              widget.footer!,
                            ],
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}

/// Curves reproduce the respective V1 auth painters.
class V1AuthCurvePainter extends CustomPainter {
  const V1AuthCurvePainter({required this.variant});
  final AuthDecorationVariant variant;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final width = size.width;
    final height = size.height;
    if (variant == AuthDecorationVariant.register) {
      paint.color = Colors.white.withValues(alpha: 0.15);
      var path = Path()
        ..moveTo(width, height * 0.7)
        ..quadraticBezierTo(width * 0.65, height * 0.45, 0, height * 0.8)
        ..lineTo(0, 0)
        ..lineTo(width, 0);
      canvas.drawPath(path, paint);
      paint.color = Colors.white.withValues(alpha: 0.1);
      path = Path()
        ..moveTo(width, height * 0.6)
        ..quadraticBezierTo(width * 0.4, height * 0.8, 0, height * 0.5)
        ..lineTo(0, 0)
        ..lineTo(width, 0);
      canvas.drawPath(path, paint);
      return;
    }
    if (variant == AuthDecorationVariant.reset) {
      paint.color = Colors.white.withValues(alpha: 0.15);
      var path = Path()
        ..moveTo(0, height * 0.7)
        ..quadraticBezierTo(width * 0.35, height * 0.45, width, height * 0.8)
        ..lineTo(width, 0)
        ..lineTo(0, 0);
      canvas.drawPath(path, paint);
      paint.color = Colors.white.withValues(alpha: 0.1);
      path = Path()
        ..moveTo(0, height * 0.6)
        ..quadraticBezierTo(width * 0.6, height * 0.8, width, height * 0.5)
        ..lineTo(width, 0)
        ..lineTo(0, 0);
      canvas.drawPath(path, paint);
      return;
    }
    paint.color = Colors.white.withValues(alpha: 0.15);
    var path = Path()
      ..moveTo(0, height * 0.7)
      ..quadraticBezierTo(
          width * 0.25, height * 0.55, width * 0.5, height * 0.75)
      ..quadraticBezierTo(width * 0.75, height * 0.95, width, height * 0.7)
      ..lineTo(width, 0)
      ..lineTo(0, 0);
    canvas.drawPath(path, paint);
    paint.color = Colors.white.withValues(alpha: 0.1);
    path = Path()
      ..moveTo(0, height * 0.8)
      ..quadraticBezierTo(
          width * 0.3, height * 0.65, width * 0.6, height * 0.85)
      ..quadraticBezierTo(width * 0.8, height * 0.95, width, height * 0.8)
      ..lineTo(width, 0)
      ..lineTo(0, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant V1AuthCurvePainter oldDelegate) =>
      oldDelegate.variant != variant;
}

class V1AuthControls {
  static InputDecoration decoration({
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      floatingLabelStyle: TextStyle(
        color: Colors.blue.shade800,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      labelStyle: TextStyle(
        color: Colors.blue.shade800,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(color: Colors.grey.shade400),
      prefixIcon: Icon(icon, color: Colors.blue.shade700, size: 22),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 18,
        horizontal: 16,
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  static Widget primaryButton({
    required String label,
    required bool loading,
    required VoidCallback? onPressed,
  }) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade300.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: loading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  static Widget errorBanner(String? message) {
    if (message == null || message.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.red.shade700, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
