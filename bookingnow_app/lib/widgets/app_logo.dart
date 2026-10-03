import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Logotipo de BookingNow — concepto "hueco en la agenda": tres franjas de
/// agenda y la central resaltada con un punto ámbar ("tu hueco, ahora").
/// Dibujado en vector para que escale sin pérdida en cualquier tamaño.
///
/// La geometría se define sobre una caja de 56 × 56 (la misma que los PNG
/// generados por tools/make_icons.js), así el icono de la app y el logo en
/// pantalla son idénticos.
class BnLogoMark extends StatelessWidget {
  final double size;

  /// Si es true dibuja el fondo redondeado teal; si es false, solo las
  /// franjas (para ponerlo sobre degradados o fondos oscuros).
  final bool withBackground;
  final Color barColor;
  final Color dotColor;
  final Color backgroundColor;

  const BnLogoMark({
    super.key,
    this.size = 56,
    this.withBackground = true,
    this.barColor = Colors.white,
    this.dotColor = AppTheme.accent,
    this.backgroundColor = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _LogoPainter(
          withBackground: withBackground,
          barColor: barColor,
          dotColor: dotColor,
          backgroundColor: backgroundColor,
        ),
      );
}

class _LogoPainter extends CustomPainter {
  final bool withBackground;
  final Color barColor;
  final Color dotColor;
  final Color backgroundColor;
  _LogoPainter({
    required this.withBackground,
    required this.barColor,
    required this.dotColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 56;
    if (withBackground) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(16 * s)),
        Paint()..color = backgroundColor,
      );
    }
    final bar = Paint()..color = barColor;
    final faint = Paint()..color = barColor.withValues(alpha: 0.45);
    RRect r(double y) => RRect.fromRectAndRadius(
        Rect.fromLTWH(13 * s, y * s, 30 * s, 6 * s), Radius.circular(3 * s));
    canvas.drawRRect(r(15), faint);
    canvas.drawRRect(r(25), bar);
    canvas.drawRRect(r(35), faint);
    canvas.drawCircle(Offset(40 * s, 28 * s), 5.5 * s, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.withBackground != withBackground ||
      old.barColor != barColor ||
      old.dotColor != dotColor ||
      old.backgroundColor != backgroundColor;
}

/// Marca completa: símbolo + "BookingNow" (con "Now" en color).
class BnLogo extends StatelessWidget {
  final double markSize;
  final bool onDark;
  final bool vertical;
  const BnLogo({super.key, this.markSize = 44, this.onDark = false, this.vertical = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final base = onDark ? Colors.white : t.colorScheme.onSurface;
    final nowColor = onDark ? AppTheme.primaryLight : AppTheme.primary;
    final word = Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Booking', style: TextStyle(color: base)),
        TextSpan(text: 'Now', style: TextStyle(color: nowColor)),
      ]),
      style: t.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        fontSize: markSize * 0.62,
      ),
    );
    final mark = BnLogoMark(
      size: markSize,
      withBackground: !onDark,
      barColor: Colors.white,
    );
    if (vertical) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        mark,
        SizedBox(height: markSize * 0.3),
        word,
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      mark,
      SizedBox(width: markSize * 0.28),
      word,
    ]);
  }
}

/// Cabecera con degradado de marca (para dashboard, fichas y pantallas de
/// acceso). Admite contenido y, opcionalmente, un logo en marca de agua.
class BrandHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final bool watermark;
  const BrandHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius,
    this.watermark = true,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: Container(
          decoration: const BoxDecoration(gradient: AppTheme.brandGradient),
          child: Stack(children: [
            if (watermark)
              const Positioned(
                right: -30,
                top: -30,
                child: Opacity(
                  opacity: 0.12,
                  child: BnLogoMark(size: 180, withBackground: false, dotColor: Colors.white),
                ),
              ),
            Padding(padding: padding, child: child),
          ]),
        ),
      );
}
