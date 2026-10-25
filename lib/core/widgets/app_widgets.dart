import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_header.dart';

/// One figure of a stats row: small caps label above a big number.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.color = AppColors.ink});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 2,
            // Narrow tracking so "CON COMPONENTES" wraps to two lines instead
            // of being cut with "…" on ~360-414px screens.
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              height: 1.3,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 8),
          Text('$value', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.tiles});

  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }
}

/// Large outlined navigation button ("Componentes", "Códigos").
class NavButton extends StatelessWidget {
  const NavButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(),
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFF0F1F4)),
          foregroundColor: const Color(0xFF374151),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Small outlined action ("Editar", "Asignar", "Deshabilitar").
class SmallActionButton extends StatelessWidget {
  const SmallActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.blue,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(),
          side: BorderSide(color: onPressed == null ? AppColors.border : color.withValues(alpha: 0.35)),
          foregroundColor: color,
          disabledForegroundColor: AppColors.disabledFg,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Small coloured pill ("Activa", "En uso", "Normal").
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, required this.background, required this.color});

  final String text;
  final Color background;
  final Color color;

  static const green = StatusPillColors(Color(0xFFE8F8EE), AppColors.success);
  static const blue = StatusPillColors(Color(0xFFEEF3FF), AppColors.blue);
  static const grey = StatusPillColors(AppColors.disabledBg, AppColors.muted);
  static const amber = StatusPillColors(Color(0xFFFEF6E0), Color(0xFFB45309));

  factory StatusPill.of(String text, StatusPillColors colors) =>
      StatusPill(text, background: colors.background, color: colors.foreground);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      color: background,
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class StatusPillColors {
  const StatusPillColors(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

/// Section card with an uppercase title + trailing count, like
/// "INVENTARIO DE CELDAS · 6 registros". Children are separated by dividers.
class InventoryCard extends StatelessWidget {
  const InventoryCard({super.key, required this.title, required this.trailing, required this.children});

  final String title;
  final String trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFF0F1F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                Text(trailing, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              ],
            ),
          ),
          for (final child in children) ...[
            const Divider(height: 1, color: Color(0xFFF0F1F4)),
            child,
          ],
        ],
      ),
    );
  }
}

/// Labelled square-cornered dropdown matching [AppTextField].
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.onChanged,
    this.value,
    this.hint,
  });

  final String label;
  final T? value;
  final String? hint;

  /// Value -> visible text.
  final Map<T, String> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: color, width: width),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label.toUpperCase(), style: AppTheme.label),
        const SizedBox(height: 10),
        DropdownButtonFormField<T>(
          // Re-created when the selection changes from outside.
          key: ValueKey(value),
          initialValue: value,
          isExpanded: true,
          hint: hint == null ? null : Text(hint!, style: const TextStyle(fontSize: 17, color: AppColors.hint)),
          items: [
            for (final entry in items.entries)
              DropdownMenuItem<T>(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
          borderRadius: BorderRadius.zero,
          style: const TextStyle(fontSize: 17, color: AppColors.ink),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            enabledBorder: border(AppColors.border),
            disabledBorder: border(AppColors.border),
            focusedBorder: border(AppColors.blue, 1.5),
          ),
        ),
      ],
    );
  }
}

/// Highlighted notice with an optional action and close button (e.g. "2 cambios
/// pendientes de sincronizar").
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.text,
    this.icon = Icons.sync_problem_outlined,
    this.background = const Color(0xFFFEF6E0),
    this.foreground = const Color(0xFF92400E),
    this.actionLabel,
    this.onAction,
    this.onClose,
  });

  final String text;
  final IconData icon;
  final Color background;
  final Color foreground;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      color: background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(fontSize: 14, height: 1.4, color: foreground)),
                if (actionLabel != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                      foregroundColor: foreground,
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    child: Text(actionLabel!),
                  ),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'Cerrar',
              onPressed: onClose,
              icon: Icon(Icons.close, size: 18, color: foreground),
            ),
        ],
      ),
    );
  }
}

/// Frame shared by the bottom sheets: title, keyboard-safe padding, max width.
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Navigation card on the home screens, with an optional red counter badge.
class ShortcutTile extends StatelessWidget {
  const ShortcutTile({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.badge,
    this.badgeText,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  /// Red counter on the icon; hidden when null or zero.
  final int? badge;

  /// Replaces [description] (in red) when the badge is shown.
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    final count = badge ?? 0;
    return InkWell(
      onTap: onTap,
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  color: const Color(0xFFEEF3FF),
                  child: Icon(icon, color: AppColors.blue, size: 28),
                ),
                if (count > 0)
                  Positioned(
                    top: -8,
                    right: -8,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                      child: Text(
                        '$count',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    count > 0 && badgeText != null ? badgeText! : description,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: count > 0 && badgeText != null ? AppColors.error : AppColors.muted,
                      fontWeight: count > 0 && badgeText != null ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
