import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_header.dart';

/// One figure of a stats row: big number above its label.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.color = AppColors.ink});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// The figures of a screen on one white card, split by thin dividers.
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.tiles});

  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.large, boxShadow: AppCard.shadow),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const VerticalDivider(width: 1, indent: 18, endIndent: 18, color: AppColors.border),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rounded white search box ("Buscar por código…").
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Buscar por código…'});

  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 15, color: AppColors.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 15, color: AppColors.muted),
        prefixIcon: const Icon(Icons.search, color: AppColors.muted, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      ),
    );
  }
}

/// Bold section title with an optional muted note on the right ("150 celdas · desliza →").
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
        ),
        if (trailing != null) Text(trailing!, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
      ],
    );
  }
}

/// Round icon button on a tinted disc (edit, code, delete).
class CircleAction extends StatelessWidget {
  const CircleAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color = AppColors.ink,
    this.background = AppColors.field,
    this.size = 40,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: size * 0.48),
        style: IconButton.styleFrom(
          backgroundColor: background,
          foregroundColor: color,
          disabledBackgroundColor: AppColors.disabledBg,
          disabledForegroundColor: AppColors.disabledFg,
        ),
      ),
    );
  }
}

/// Large outlined navigation button ("Componentes", "Códigos").
class NavButton extends StatelessWidget {
  const NavButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = const Color(0xFF374151),
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
          backgroundColor: Colors.white,
          side: BorderSide(color: color.withValues(alpha: 0.35)),
          foregroundColor: color,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Small outlined action ("Editar", "Asignar", "Deshabilitar").
class SmallActionButton extends StatelessWidget {
  const SmallActionButton({super.key, required this.label, required this.onPressed, this.color = AppColors.blue});

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
          shape: RoundedRectangleBorder(borderRadius: AppRadius.small),
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
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
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
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.large,
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
          for (final child in children) ...[const Divider(height: 1, color: Color(0xFFF0F1F4)), child],
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
      borderRadius: AppRadius.medium,
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
          borderRadius: AppRadius.medium,
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
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
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
