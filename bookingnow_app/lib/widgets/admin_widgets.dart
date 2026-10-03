import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../config.dart';
import 'common.dart';

/// Widgets y utilidades compartidas por las pantallas de administración.

/// Colores predefinidos para servicios y profesionales.
const adminColorPresets = <String>[
  '#4F46E5',
  '#7C4DFF',
  '#0EA5E9',
  '#10B981',
  '#F59E0B',
  '#EF4444',
  '#EC4899',
  '#8B5CF6',
  '#14B8A6',
  '#64748B',
];

/// Fila de círculos de color seleccionables.
class ColorPresetPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String> onChanged;
  const ColorPresetPicker({super.key, this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final hex in adminColorPresets)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onChanged(hex),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: hexColor(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: (value ?? '').toUpperCase() == hex.toUpperCase()
                      ? Theme.of(context).colorScheme.onSurface
                      : Colors.transparent,
                  width: 3,
                ),
              ),
              child: (value ?? '').toUpperCase() == hex.toUpperCase()
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Tarjeta de formulario con título.
class FormCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final Widget? trailing;
  const FormCard({super.key, this.title, required this.children, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) ...[
            Row(children: [
              Expanded(
                child: Text(title!,
                    style: t.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 14),
          ],
          ...children,
        ]),
      ),
    );
  }
}

/// Coloca los hijos en dos columnas en pantallas anchas y en una columna
/// en móvil.
class ResponsiveFields extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  const ResponsiveFields({super.key, required this.children, this.spacing = 12});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 560;
      if (!wide) {
        return Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ]);
      }
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += 2) {
        if (i > 0) rows.add(SizedBox(height: spacing));
        rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: children[i]),
          SizedBox(width: spacing),
          Expanded(
              child: i + 1 < children.length
                  ? children[i + 1]
                  : const SizedBox.shrink()),
        ]));
      }
      return Column(children: rows);
    });
  }
}

/// Tarjeta informativa (color suave + icono).
class InfoCard extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? color;
  final Widget? action;
  const InfoCard(this.text,
      {super.key, this.icon = Icons.info_outline, this.color, this.action});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: c, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: Theme.of(context).textTheme.bodyMedium),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ]),
        ),
      ]),
    );
  }
}

/// Etiqueta pequeña de estado ("Online", "Inactivo"...).
class SmallBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const SmallBadge(this.text, {super.key, this.color = AppTheme.primary, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Fila "etiqueta: valor" para fichas de detalle.
class DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const DetailRow(this.label, this.value, {super.key, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
        ),
        Expanded(
          child: Text(value,
              style: t.textTheme.bodyMedium?.copyWith(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ),
      ]),
    );
  }
}

/// Barra horizontal simple para gráficos sin paquetes externos.
class HBar extends StatelessWidget {
  final String label;
  final double fraction; // 0..1
  final String value;
  final Color? color;
  const HBar(
      {super.key,
      required this.label,
      required this.fraction,
      required this.value,
      this.color});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
          width: 110,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodySmall),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(children: [
              Container(height: 18, color: c.withValues(alpha: 0.10)),
              FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(height: 18, color: c),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(value,
              textAlign: TextAlign.right,
              style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// Convierte "12,50" / "12.5" a céntimos.
int parseEuros(String s) {
  final n = double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.')) ??
      double.tryParse(s.trim().replaceAll(',', '.')) ??
      0;
  return (n * 100).round();
}

/// Céntimos a texto editable ("12,50").
String centsToInput(int cents) =>
    (cents / 100).toStringAsFixed(2).replaceAll('.', ',');

/// Formatter para importes en euros (dígitos, coma o punto).
final euroInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];

final intInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
];

/// Plural sencillo en español ("Profesional" → "Profesionales",
/// "Terapeuta" → "Terapeutas").
String pluralEs(String word) {
  if (word.isEmpty) return word;
  final last = word[word.length - 1].toLowerCase();
  if ('aeiou'.contains(last)) return '${word}s';
  if (last == 'z') return '${word.substring(0, word.length - 1)}ces';
  return '${word}es';
}

/// URL pública de reservas de un negocio.
String publicBookingUrl(String slug) => '${AppConfig.publicBookingHost}/b/$slug';

/// Copia al portapapeles y avisa.
Future<void> copyToClipboard(BuildContext context, String text,
    {String message = 'Copiado al portapapeles'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showSnack(context, message);
}

/// Encabezado con icono para listas vacías dentro de tarjetas.
class InlineEmpty extends StatelessWidget {
  final String text;
  const InlineEmpty(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline)),
      );
}
