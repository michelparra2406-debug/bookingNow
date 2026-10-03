import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/format.dart';

/// Widgets reutilizables en toda la app.

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView(this.message, {super.key, this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 40, color: AppTheme.danger),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar')),
            ]
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyView(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.action});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: t.colorScheme.outline),
          const SizedBox(height: 16),
          Text(title,
              style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: t.colorScheme.outline),
                textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = bookingStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(Fmt.bookingStatus(status),
          style: TextStyle(
              color: c, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700))),
          if (trailing != null) trailing!,
        ]),
      );
}

class AvatarCircle extends StatelessWidget {
  final String? url;
  final String initials;
  final double radius;
  final Color? color;
  const AvatarCircle(
      {super.key,
      this.url,
      required this.initials,
      this.radius = 20,
      this.color});
  @override
  Widget build(BuildContext context) {
    final bg = color ?? Theme.of(context).colorScheme.primary;
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(url!));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg.withValues(alpha: 0.18),
      child: Text(initials,
          style: TextStyle(
              color: bg, fontWeight: FontWeight.w700, fontSize: radius * 0.8)),
    );
  }
}

/// Convierte '#RRGGBB' a Color.
Color hexColor(String? hex, [Color fallback = AppTheme.primary]) {
  if (hex == null || hex.isEmpty) return fallback;
  final h = hex.replaceAll('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// Tarjeta KPI para dashboards.
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? hint;
  const KpiCard(
      {super.key,
      required this.label,
      required this.value,
      required this.icon,
      this.color,
      this.hint});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: c, size: 20),
            ),
            const Spacer(),
            if (hint != null)
              Text(hint!,
                  style: t.textTheme.labelSmall
                      ?.copyWith(color: t.colorScheme.outline)),
          ]),
          const SizedBox(height: 14),
          Text(value,
              style:
                  t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: t.textTheme.bodySmall
                  ?.copyWith(color: t.colorScheme.outline)),
        ]),
      ),
    );
  }
}

void showSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? AppTheme.danger : null,
  ));
}

Future<bool> confirmDialog(BuildContext context,
    {required String title,
    required String message,
    String confirmLabel = 'Confirmar',
    bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppTheme.danger)
              : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Limita el ancho del contenido en pantallas grandes (panel web).
class MaxWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const MaxWidth({super.key, required this.child, this.maxWidth = 1100});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}
