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
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutQuad,
    ));
    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
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
                    isReset ? Colors.blue.shade700 : Colors.blue.shade800,
                    Colors.indigo.shade900,
                  ],
                ),
              ),
              child: const SizedBox.expand(),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: height * (isLogin ? 0.4 : 0.3),
              child: CustomPaint(
                painter: V1AuthCurvePainter(variant: widget.variant),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: height * (isLogin ? 0.1 : 0.05)),
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
                                tag: 'app_logo',
                                child: Container(
                                  height: isLogin ? 120 : isReset ? 100 : 90,
                                  width: isLogin ? 120 : isReset ? 100 : 90,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 15,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    isReset
                                        ? Icons.lock_reset
                                        : isLogin
                                            ? Icons.electrical_services_outlined
                                            : Icons.person_add,
                                    size: isLogin ? 64 : 45,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: isLogin ? 40 : isReset ? 30 : 20),
                            Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 28,
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
                                color: Colors.white.withValues(alpha: 0.8),
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(height: isLogin ? 50 : isReset ? 40 : 25),
                            Card(
                              elevation: 8,
                              shadowColor: Colors.black.withValues(alpha: 0.2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: widget.content,
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
      ..quadraticBezierTo(width * 0.25, height * 0.55, width * 0.5, height * 0.75)
      ..quadraticBezierTo(width * 0.75, height * 0.95, width, height * 0.7)
      ..lineTo(width, 0)
      ..lineTo(0, 0);
    canvas.drawPath(path, paint);
    paint.color = Colors.white.withValues(alpha: 0.1);
    path = Path()
      ..moveTo(0, height * 0.8)
      ..quadraticBezierTo(width * 0.3, height * 0.65, width * 0.6, height * 0.85)
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
    final normal = BorderSide(color: Colors.grey.shade300);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: Colors.grey.shade700, fontSize: 16),
      prefixIcon: Icon(icon, color: Colors.blue.shade700, size: 22),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: normal,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: normal,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 16, horizontal: 16,
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
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
        borderRadius: BorderRadius.circular(12),
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
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.blue.shade300,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
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
