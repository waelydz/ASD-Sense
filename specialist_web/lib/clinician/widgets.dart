import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'clinic_data.dart';
import 'models.dart';

// ---- formatting --------------------------------------------------------------

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String two(int n) => n.toString().padLeft(2, '0');
String fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
String fmtShortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';
String fmtTime(DateTime d) {
  if (ClinicData.instance.use24HourTime) return '${two(d.hour)}:${two(d.minute)}';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String fmtDateTime(DateTime d) => '${fmtDate(d)}, ${fmtTime(d)}';
String fmtWeekday(DateTime d) => _weekdays[d.weekday - 1];
String pct(double? v, [int digits = 0]) => v == null ? '-' : '${(v * 100).toStringAsFixed(digits)}%';

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String fmtDayHeading(DateTime d) {
  final now = DateTime.now();
  if (sameDay(d, now)) return 'Today, ${fmtShortDate(d)}';
  if (sameDay(d, now.add(const Duration(days: 1)))) return 'Tomorrow, ${fmtShortDate(d)}';
  if (sameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday, ${fmtShortDate(d)}';
  return '${fmtWeekday(d)}, ${fmtShortDate(d)}';
}

String fmtAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 30) return '${diff.inDays} days ago';
  return fmtDate(d);
}

// ---- layout ------------------------------------------------------------------

class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? above;

  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.above});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        runSpacing: 14,
        spacing: 16,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (above != null) ...[above!, const SizedBox(height: 10)],
                Text(title, style: AppText.heading(28)),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(subtitle!, style: const TextStyle(color: AppColors.textGrey, fontSize: 14, height: 1.45)),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) Wrap(spacing: 10, runSpacing: 10, children: actions),
        ],
      ),
    );
  }
}

class Panel extends StatelessWidget {
  final String? title;
  final String? caption;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  const Panel({
    super.key,
    this.title,
    this.caption,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title!, style: AppText.heading(16.5)),
                          if (caption != null) ...[
                            const SizedBox(height: 3),
                            Text(caption!, style: const TextStyle(color: AppColors.textGrey, fontSize: 12.5)),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                const SizedBox(height: 16),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays children out in columns on wide screens and stacks them on narrow ones.
class ResponsiveColumns extends StatelessWidget {
  final List<Widget> children;
  final List<int> flex;
  final double breakpoint;
  final double gap;

  const ResponsiveColumns({
    super.key,
    required this.children,
    this.flex = const [],
    this.breakpoint = 900,
    this.gap = 18,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < breakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              children[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(flex: i < flex.length ? flex[i] : 1, child: children[i]),
          ],
        ],
      );
    });
  }
}

// ---- small pieces ------------------------------------------------------------

class Tag extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  const Tag(this.text, {super.key, required this.fg, required this.bg});

  factory Tag.neutral(String text) => Tag(text, fg: AppColors.textGrey, bg: const Color(0xFFF0F1EE));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700, height: 1.2)),
    );
  }
}

class ResultTag extends StatelessWidget {
  final String predictedClass;
  const ResultTag(this.predictedClass, {super.key});

  @override
  Widget build(BuildContext context) {
    switch (predictedClass) {
      case 'autistic':
        return const Tag('Flagged', fg: AppColors.danger, bg: AppColors.dangerBg);
      case 'non_autistic':
        return const Tag('Not flagged', fg: AppColors.success, bg: AppColors.successBg);
      default:
        return const Tag('Inconclusive', fg: AppColors.sand, bg: AppColors.sandBg);
    }
  }
}

class CaseStatusTag extends StatelessWidget {
  final String status;
  const CaseStatusTag(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'Awaiting review':
        return Tag(status, fg: AppColors.lavender, bg: AppColors.lavenderBg);
      case 'Referred':
        return Tag(status, fg: AppColors.danger, bg: AppColors.dangerBg);
      case 'Rescreen':
        return Tag(status, fg: AppColors.sand, bg: AppColors.sandBg);
      case 'Monitoring':
        return Tag(status, fg: AppColors.sage, bg: AppColors.sageBg);
      case 'Closed':
        return Tag(status, fg: AppColors.success, bg: AppColors.successBg);
      default:
        return Tag.neutral(status);
    }
  }
}

class VisitStatusTag extends StatelessWidget {
  final VisitStatus status;
  const VisitStatusTag(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case VisitStatus.confirmed:
        return Tag(status.label, fg: AppColors.sage, bg: AppColors.sageBg);
      case VisitStatus.completed:
        return Tag(status.label, fg: AppColors.success, bg: AppColors.successBg);
      case VisitStatus.cancelled:
        return Tag.neutral(status.label);
      case VisitStatus.noShow:
        return Tag(status.label, fg: AppColors.danger, bg: AppColors.dangerBg);
      case VisitStatus.scheduled:
        return Tag(status.label, fg: AppColors.lavender, bg: AppColors.lavenderBg);
    }
  }
}

class Dot extends StatelessWidget {
  final Color color;
  final double size;
  const Dot(this.color, {super.key, this.size = 8});

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class Avatar extends StatelessWidget {
  final String initials;
  final double size;
  const Avatar(this.initials, {super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.sageBg, borderRadius: BorderRadius.circular(size / 3.2)),
      child:
          Text(initials, style: TextStyle(color: AppColors.sage, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
  }
}

class KeyValue extends StatelessWidget {
  final String label;
  final String value;
  final Widget? valueWidget;
  const KeyValue(this.label, this.value, {super.key, this.valueWidget});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
          ),
          Expanded(
            child: valueWidget ??
                SelectableText(value,
                    style: const TextStyle(color: AppColors.textDark, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final Color accent;
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.accent = AppColors.primary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 4)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: AppColors.textGrey, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(value, style: AppText.heading(30, weight: FontWeight.w700)),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(hint!, style: const TextStyle(color: AppColors.textFaint, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class Notice extends StatelessWidget {
  final String text;
  final bool warning;
  const Notice(this.text, {super.key, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final fg = warning ? AppColors.sand : AppColors.primaryDark;
    final bg = warning ? AppColors.sandBg : AppColors.sageBg;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: fg, width: 3)),
      ),
      child: Text(text, style: TextStyle(color: fg, fontSize: 13, height: 1.45)),
    );
  }
}

// ---- buttons -----------------------------------------------------------------

enum BtnKind { primary, secondary, danger, quiet }

class Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final bool loading;
  final bool expand;

  const Btn(this.label,
      {super.key, required this.onPressed, this.kind = BtnKind.primary, this.loading = false, this.expand = false});

  const Btn.secondary(this.label, {super.key, required this.onPressed, this.loading = false, this.expand = false})
      : kind = BtnKind.secondary;

  const Btn.quiet(this.label, {super.key, required this.onPressed})
      : kind = BtnKind.quiet,
        loading = false,
        expand = false;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    const pad = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
    const text = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
    final child = loading
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
        : Text(label, style: text);

    Widget button;
    switch (kind) {
      case BtnKind.primary:
        button = FilledButton(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.border,
            padding: pad,
            shape: shape,
          ),
          child: loading
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : child,
        );
      case BtnKind.secondary:
        button = OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textDark,
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.inputBorder),
            padding: pad,
            shape: shape,
          ),
          child: child,
        );
      case BtnKind.danger:
        button = OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            backgroundColor: AppColors.dangerBg,
            side: const BorderSide(color: AppColors.dangerBorder),
            padding: pad,
            shape: shape,
          ),
          child: child,
        );
      case BtnKind.quiet:
        button = TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryDark,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            shape: shape,
          ),
          child: Text(label, style: text),
        );
    }
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// A small text button for navigation ("Full schedule", "Back to patients").
/// Shows a pointer cursor, a hover tint and a press ripple like other buttons.
class TextLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const TextLink(this.label, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryDark,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
    );
  }
}

// ---- inputs ------------------------------------------------------------------

InputDecoration fieldDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textFaint),
      filled: true,
      fillColor: AppColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
    );

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textDark)),
      );
}

class Field extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const Field({
    super.key,
    required this.label,
    required this.controller,
    this.hint = '',
    this.obscure = false,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty) FieldLabel(label),
        TextField(
          controller: controller,
          obscureText: obscure,
          maxLines: maxLines,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: const TextStyle(fontSize: 14, color: AppColors.textDark),
          decoration: fieldDecoration(hint),
        ),
      ],
    );
  }
}

class Select<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T> onChanged;
  final bool Function(T)? enabled;

  const Select({
    super.key,
    this.label = '',
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty) FieldLabel(label),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.inputBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              icon: const _Chevron(),
              borderRadius: BorderRadius.circular(10),
              dropdownColor: AppColors.surface,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 14, color: AppColors.textDark),
              items: [
                for (final item in items)
                  DropdownMenuItem<T>(
                    value: item,
                    enabled: enabled?.call(item) ?? true,
                    child: Text(
                      itemLabel(item),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: (enabled?.call(item) ?? true) ? AppColors.textDark : AppColors.textFaint,
                      ),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Down arrow for dropdowns, drawn rather than taken from an icon font.
class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 18, height: 18, child: CustomPaint(painter: _ChevronPainter()));
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textGrey
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.28, size.height * 0.40)
      ..lineTo(size.width * 0.5, size.height * 0.62)
      ..lineTo(size.width * 0.72, size.height * 0.40);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A selectable option row (used in place of radio buttons and tab strips).
class OptionRow extends StatelessWidget {
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  const OptionRow({super.key, required this.label, this.detail, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 160);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? AppColors.successBg : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.primary : AppColors.inputBorder, width: selected ? 1.4 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: duration,
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: selected ? AppColors.primary : AppColors.textFaint, width: selected ? 5 : 1.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: selected ? AppColors.primaryDark : AppColors.textDark)),
                        if (detail != null) ...[
                          const SizedBox(height: 2),
                          Text(detail!,
                              style: const TextStyle(color: AppColors.textGrey, fontSize: 12.5, height: 1.35)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Password input with a text "Show" / "Hide" toggle.
class PasswordField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const PasswordField({super.key, required this.label, required this.controller, this.onChanged, this.onSubmitted});

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(widget.label),
        TextField(
          controller: widget.controller,
          obscureText: _hidden,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          style: const TextStyle(fontSize: 14, color: AppColors.textDark),
          decoration: fieldDecoration('').copyWith(
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton(
                onPressed: () => setState(() => _hidden = !_hidden),
                style: TextButton.styleFrom(foregroundColor: AppColors.textGrey),
                child: Text(_hidden ? 'Show' : 'Hide',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A short list with small dots, for guidance text.
class Bullets extends StatelessWidget {
  final List<String> items;
  final Color dot;
  const Bullets(this.items, {super.key, this.dot = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 6), child: Dot(dot, size: 6)),
              const SizedBox(width: 10),
              Expanded(child: Text(t, style: const TextStyle(fontSize: 13.5, height: 1.45))),
            ]),
          ),
      ],
    );
  }
}

// ---- table -------------------------------------------------------------------

class Col {
  final String label;
  final int flex;

  /// Column is hidden when the table is narrower than this.
  final double minTableWidth;
  const Col(this.label, {this.flex = 2, this.minTableWidth = 0});
}

class DataList extends StatelessWidget {
  final List<Col> columns;
  final List<List<Widget>> rows;
  final void Function(int index)? onRowTap;
  final String emptyText;

  const DataList({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.emptyText = 'Nothing to show.',
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final visible = [
        for (var i = 0; i < columns.length; i++)
          if (c.maxWidth >= columns[i].minTableWidth) i
      ];
      Widget line(List<Widget> cells, {bool header = false}) => Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final i in visible)
                Expanded(
                  flex: columns[i].flex,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Align(alignment: Alignment.centerLeft, child: cells[i]),
                  ),
                ),
            ],
          );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: line([
              for (final col in columns)
                Text(col.label.toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.textFaint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            ], header: true),
          ),
          const Divider(height: 1, color: AppColors.border),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text(emptyText, style: const TextStyle(color: AppColors.textGrey))),
            ),
          for (var r = 0; r < rows.length; r++) ...[
            InkWell(
              onTap: onRowTap == null ? null : () => onRowTap!(r),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: line(rows[r]),
              ),
            ),
            if (r < rows.length - 1) const Divider(height: 1, color: AppColors.border),
          ],
        ],
      );
    });
  }
}

class CellText extends StatelessWidget {
  final String text;
  final String? sub;
  final bool strong;
  const CellText(this.text, {super.key, this.sub, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13.5, color: AppColors.textDark, fontWeight: strong ? FontWeight.w700 : FontWeight.w500)),
        if (sub != null)
          Text(sub!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
      ],
    );
  }
}

// ---- charts ------------------------------------------------------------------

/// Horizontal bar for an autism probability, with the 0.5 decision line.
class ProbabilityBar extends StatelessWidget {
  final double? value;
  final double width;
  const ProbabilityBar(this.value, {super.key, this.width = 120});

  @override
  Widget build(BuildContext context) {
    final v = (value ?? 0).clamp(0.0, 1.0);
    final color = v >= 0.5 ? AppColors.danger : AppColors.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: 8,
          child: Stack(
            children: [
              Container(decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4))),
              FractionallySizedBox(
                widthFactor: v,
                child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
              ),
              Positioned(
                left: width / 2 - 1,
                top: -2,
                bottom: -2,
                child: Container(width: 2, color: AppColors.textDark.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(pct(value), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// Autism probability over time for one patient.
class ProbabilityTrend extends StatelessWidget {
  final List<Screening> screenings;
  const ProbabilityTrend(this.screenings, {super.key});

  @override
  Widget build(BuildContext context) {
    final points = screenings.where((s) => s.autismProbability != null).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (points.length < 2) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        child: Text(
          points.isEmpty ? 'No screenings yet.' : 'One screening so far. A trend appears after the second.',
          style: const TextStyle(color: AppColors.textGrey, fontSize: 13),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 180, width: double.infinity, child: CustomPaint(painter: _TrendPainter(points))),
        const SizedBox(height: 10),
        const Wrap(spacing: 16, runSpacing: 6, children: [
          _Legend(color: AppColors.primary, label: 'MobileNetV2 (edge)'),
          _Legend(color: AppColors.lavender, label: 'ViT-B/16 (cloud)'),
          _Legend(color: AppColors.sand, label: 'Inconclusive band (confidence < 60%)'),
        ]),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Dot(color),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textGrey))),
      ]);
}

class _TrendPainter extends CustomPainter {
  final List<Screening> points;
  _TrendPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0, bottom = 22.0, top = 6.0, right = 10.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    double y(double v) => top + h * (1 - v);

    // inconclusive band: confidence < 0.6 means probability in (0.4, 0.6)
    canvas.drawRect(Rect.fromLTRB(left, y(0.6), left + w, y(0.4)), Paint()..color = AppColors.sandBg);

    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (final v in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      canvas.drawLine(
          Offset(left, y(v)),
          Offset(left + w, y(v)),
          v == 0.5
              ? (Paint()
                ..color = AppColors.textFaint
                ..strokeWidth = 1.2)
              : grid);
      _text(canvas, '${(v * 100).round()}%', Offset(0, y(v) - 7), 10.5);
    }

    final t0 = points.first.date.millisecondsSinceEpoch.toDouble();
    final t1 = points.last.date.millisecondsSinceEpoch.toDouble();
    final span = math.max(1.0, t1 - t0);
    double x(DateTime d) => left + w * ((d.millisecondsSinceEpoch - t0) / span);

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(x(points[i].date), y(points[i].autismProbability!));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.textGrey.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6);

    for (final s in points) {
      final o = Offset(x(s.date), y(s.autismProbability!));
      final vit = s.modelName.contains('ViT');
      canvas.drawCircle(o, 5.5, Paint()..color = Colors.white);
      canvas.drawCircle(o, 4.5, Paint()..color = vit ? AppColors.lavender : AppColors.primary);
    }

    _text(canvas, fmtShortDate(points.first.date), Offset(left, size.height - 14), 10.5);
    final lastLabel = fmtShortDate(points.last.date);
    _text(canvas, lastLabel, Offset(left + w - lastLabel.length * 5.6, size.height - 14), 10.5);
  }

  void _text(Canvas canvas, String s, Offset at, double size) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: GoogleFonts.dmSans(color: AppColors.textFaint, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.points != points;
}
