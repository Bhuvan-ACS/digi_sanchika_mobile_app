import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:digi_sanchika/widgets/profile_avatar.dart';

import '../theme/ui_theme.dart';

// UI-only building blocks for the home screens. They take plain values and
// callbacks, so the screens keep owning all data and behaviour.

// ───────────────────────── Header ─────────────────────────

/// Round white icon button with an optional red count badge (notifications).
class HomeBellButton extends StatelessWidget {
  const HomeBellButton({super.key, required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: UiColors.surface,
      elevation: 3,
      shadowColor: UiColors.ink.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(PhosphorIconsRegular.bell, color: UiColors.ink),
              if (count > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Primary-coloured initials avatar that opens the profile.
class HomeAvatar extends StatelessWidget {
  const HomeAvatar({
    super.key,
    required this.initials,
    this.avatar,
    this.onTap,
  });

  final String initials;

  /// Encoded `AvatarChoice` picked on the profile; null shows [initials].
  final String? avatar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open profile',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFDCEEFF),
            border: Border.all(color: const Color(0xFFB9DDF8)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5B9CF6).withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: avatar == null
              ? Text(
                  initials,
                  style: const TextStyle(
                    color: Color(0xFF2F80ED),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                )
              : ProfileAvatar(initials: initials, avatar: avatar, size: 44),
        ),
      ),
    );
  }
}

/// Home header: logo badge, a time-of-day greeting and the user's name as the
/// main emphasis. Plays a one-shot entrance (logo spin + pop, then greeting,
/// then name) on load and whenever the greeting period changes. Honours the
/// platform's reduce-motion setting.
class HomeGreetingHeader extends StatefulWidget {
  const HomeGreetingHeader({super.key, required this.name});

  final String name;

  @override
  State<HomeGreetingHeader> createState() => _HomeGreetingHeaderState();
}

enum _DayPart {
  morning('Good morning 👋'),
  afternoon('Good afternoon 👋'),
  evening('Good evening 👋');

  const _DayPart(this.greeting);
  final String greeting;

  static _DayPart at(DateTime t) => t.hour >= 5 && t.hour < 12
      ? morning
      : t.hour >= 12 && t.hour < 17
      ? afternoon
      : evening;

  /// The next moment the greeting changes (05:00, 12:00 or 17:00).
  static DateTime nextChange(DateTime t) {
    for (final hour in const [5, 12, 17]) {
      final at = DateTime(t.year, t.month, t.day, hour);
      if (at.isAfter(t)) return at;
    }
    return DateTime(t.year, t.month, t.day + 1, 5);
  }
}

class _HomeGreetingHeaderState extends State<HomeGreetingHeader>
    with SingleTickerProviderStateMixin {
  // Smooth "ease-out-quint"-like curve for a calm, premium settle.
  static const _ease = Cubic(0.22, 1, 0.36, 1);

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late _DayPart _part = _DayPart.at(DateTime.now());
  Timer? _timer;

  late final Animation<double> _logoTurns = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0, 0.75, curve: _ease),
  );
  late final Animation<double> _logoScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.82, end: 1.08), weight: 55),
    TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 45),
  ]).animate(CurvedAnimation(
    parent: _intro,
    curve: const Interval(0, 0.7, curve: Curves.easeOut),
  ));
  late final Animation<double> _greetingIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.18, 0.62, curve: _ease),
  );
  late final Animation<double> _nameIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.34, 0.86, curve: _ease),
  );

  @override
  void initState() {
    super.initState();
    _scheduleNextChange();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.status == AnimationStatus.dismissed) _play();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _intro.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _play() {
    if (_reduceMotion) {
      _intro.value = 1;
    } else {
      _intro.forward(from: 0);
    }
  }

  /// One timer per period boundary — no polling loop.
  void _scheduleNextChange() {
    _timer?.cancel();
    final now = DateTime.now();
    _timer = Timer(_DayPart.nextChange(now).difference(now), () {
      if (!mounted) return;
      setState(() => _part = _DayPart.at(DateTime.now()));
      _play();
      _scheduleNextChange();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _intro,
          builder: (context, child) => Transform.scale(
            scale: _logoScale.value,
            child: Transform.rotate(
              angle: _logoTurns.value * 2 * math.pi,
              child: child,
            ),
          ),
          child: const HomeLogoBadge(),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SlideFadeIn(
                animation: _greetingIn,
                offset: 10,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _part.greeting,
                    key: ValueKey(_part),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
                      color: UiColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              _SlideFadeIn(
                animation: _nameIn,
                offset: 8,
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFF2F80ED)],
                  ).createShader(bounds),
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: UiColors.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fades its child in while sliding it up by [offset] logical pixels.
class _SlideFadeIn extends StatelessWidget {
  const _SlideFadeIn({
    required this.animation,
    required this.offset,
    required this.child,
  });

  final Animation<double> animation;
  final double offset;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) => Opacity(
      opacity: animation.value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - animation.value) * offset),
        child: child,
      ),
    ),
    child: child,
  );
}

/// Small animated brand mark used beside the Home welcome message.
class HomeLogoBadge extends StatefulWidget {
  const HomeLogoBadge({super.key});

  @override
  State<HomeLogoBadge> createState() => _HomeLogoBadgeState();
}

class _HomeLogoBadgeState extends State<HomeLogoBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Digi Sanchika secure document manager',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final lift = Curves.easeInOut.transform(_controller.value);
          return Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF4FBFF), Color(0xFFDDEEFF)],
              ),
              border: Border.all(color: const Color(0xFFB9DDF8)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F9BFF).withValues(alpha: 0.20),
                  blurRadius: 14,
                  offset: Offset(0, 3 + lift * 2),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  bottom: 8,
                  child: Container(
                    width: 30,
                    height: 7,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7BC8F7).withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, -2 - lift * 3),
                  child: Transform.rotate(
                    angle: (lift - 0.5) * 0.08,
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/digi-sanchika-logo.png',
                        width: 43,
                        height: 43,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.folder_outlined,
                              color: Color(0xFF2388E8),
                            ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ───────────────────────── Search ─────────────────────────

/// Pill-shaped search field. Wraps a real [TextField], so the owning screen
/// keeps its controller, focus node and search logic. The right edge shows a
/// clear button while there is text, followed by the optional [trailing]
/// action (the AI assistant button on every screen).
class PillSearchField extends StatelessWidget {
  const PillSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint = 'Search files, folders, shared work...',
    this.onChanged,
    this.onSubmitted,
    this.onTapOutside,
    this.onClear,
    this.loading = false,
    this.trailing,
    this.flat = false,
  });

  /// Flat style: 1px light border and no shadow instead of the soft shadow.
  final bool flat;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TapRegionCallback? onTapOutside;
  final VoidCallback? onClear;
  final bool loading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasText = controller?.text.isNotEmpty ?? false;
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(flat ? 24 : 9999),
        border: flat ? Border.all(color: const Color(0xFFE2E8F0)) : null,
        boxShadow: flat ? null : softShadow(),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(
                  PhosphorIconsRegular.magnifyingGlass,
                  color: UiColors.textMuted,
                ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              onTapOutside: onTapOutside,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14, color: UiColors.ink),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: UiColors.textMuted,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          if (hasText)
            IconButton(
              onPressed: onClear,
              tooltip: 'Clear',
              icon: const Icon(
                PhosphorIconsRegular.x,
                color: UiColors.textSecondary,
                size: 18,
              ),
            ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 14),
              child: trailing,
            )
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }
}

/// Small action used at the end of a [PillSearchField]. Sparkle actions use
/// the soft glass/blue-purple treatment shown in the Home search bar.
class PillRoundAction extends StatefulWidget {
  const PillRoundAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  State<PillRoundAction> createState() => _PillRoundActionState();
}

class _PillRoundActionState extends State<PillRoundAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sparkleController;
  bool _isPressed = false;

  bool get _isSparkle => widget.icon == Icons.auto_awesome;

  @override
  void initState() {
    super.initState();
    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (_isSparkle) _sparkleController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _sparkleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSparkle = _isSparkle;
    return AnimatedBuilder(
      animation: _sparkleController,
      builder: (context, child) {
        final pulse = isSparkle
            ? Curves.easeInOut.transform(_sparkleController.value)
            : 0.0;
        return SizedBox(
          width: 48,
          height: 48,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: Ink(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSparkle ? Colors.white : UiColors.primary,
                border: isSparkle
                    ? Border.all(color: const Color(0xFFD9D8F5), width: 1.2)
                    : null,
                boxShadow: _isPressed && isSparkle
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFFFF4F9A,
                          ).withValues(alpha: 0.72),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: const Color(
                            0xFFFFC247,
                          ).withValues(alpha: 0.62),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: const Color(
                            0xFF55D9A5,
                          ).withValues(alpha: 0.58),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: const Color(
                            0xFF6D8CFF,
                          ).withValues(alpha: 0.68),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: const Color(
                            0xFF8B6BFF,
                          ).withValues(alpha: isSparkle ? 0.10 : 0.18),
                          blurRadius: isSparkle ? 5 + pulse * 3 : 6,
                          spreadRadius: 0,
                        ),
                      ],
              ),
              child: Tooltip(
                message: widget.tooltip ?? 'Action',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onTap,
                  onTapDown: (_) => setState(() => _isPressed = true),
                  onTapUp: (_) => setState(() => _isPressed = false),
                  onTapCancel: () => setState(() => _isPressed = false),
                  splashColor:
                      (isSparkle ? const Color(0xFF9D7BFF) : Colors.white)
                          .withValues(alpha: 0.22),
                  child: Center(
                    child: Transform.rotate(
                      angle: isSparkle ? (pulse - 0.5) * 0.12 : 0,
                      child: Icon(
                        widget.icon,
                        color: isSparkle
                            ? Color.lerp(
                                const Color(0xFF8C5CDB),
                                const Color(0xFF4E9BEA),
                                pulse,
                              )
                            : Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────── Section header ─────────────────────────

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  /// Optional widget shown just before the action (e.g. a filter dropdown).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: UiColors.textPrimary,
            ),
          ),
        ),
        if (trailing != null || action != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trailing != null) trailing!,
              if (trailing != null && action != null) const SizedBox(width: 6),
              if (action != null)
                InkWell(
                  onTap: onAction,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          action!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: UiColors.primary,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: UiColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

// ───────────────────────── Cards & tiles ─────────────────────────

/// White rounded card with the soft ambient shadow.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: UiColors.border),
        boxShadow: softShadow(),
      ),
      child: child,
    );
  }
}

/// Quick action (Upload / Scan / New Folder) tile.
class QuickActionTile extends StatefulWidget {
  const QuickActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<QuickActionTile> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ConstrainedBox(
        // The icon, title, and card padding need a little more vertical room
        // on narrow phone layouts than the old aspect ratio allowed.
        constraints: const BoxConstraints(minHeight: 104),
        child: AspectRatio(
          aspectRatio: 1.28,
          child: Material(
            // Keep the action tile wrapper visually transparent.
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            elevation: 0,
            shadowColor: Colors.transparent,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isHovered = true),
              onExit: (_) => setState(() => _isHovered = false),
              child: AnimatedScale(
                scale: _isPressed ? 0.96 : (_isHovered ? 1.02 : 1.0),
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(
                    0,
                    _isHovered ? -4 : 0,
                    0,
                  ),
                  transformAlignment: Alignment.center,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isHovered || _isPressed
                          ? widget.color.withValues(alpha: 0.45)
                          : UiColors.border,
                      width: _isHovered || _isPressed ? 1.4 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: _isHovered ? 0.09 : 0.06,
                        ),
                        blurRadius: _isHovered ? 18 : 14,
                        spreadRadius: 0,
                        offset: Offset.zero,
                      ),
                    ],
                  ),
                  child: InkWell(
                    focusColor: widget.color.withValues(alpha: 0.08),
                    hoverColor: widget.color.withValues(alpha: 0.04),
                    onTap: widget.onTap,
                    onTapDown: (_) => setState(() => _isPressed = true),
                    onTapUp: (_) => setState(() => _isPressed = false),
                    onTapCancel: () => setState(() => _isPressed = false),
                    borderRadius: BorderRadius.circular(20),
                    splashColor: widget.color.withValues(alpha: 0.10),
                    highlightColor: widget.color.withValues(alpha: 0.05),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: widget.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.color,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: UiColors.textPrimary,
                          ),
                        ),
                        if (widget.subtitle.isNotEmpty)
                          Text(
                            widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: UiColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filter chip with an optional count (All / PDF / Docs / Sheets).
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? UiColors.primary : UiColors.surface,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: selected ? UiColors.primary : UiColors.border,
          ),
          boxShadow: selected ? primaryGlow(0.22) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? Colors.white : UiColors.textPrimary,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : UiColors.primaryTint,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : UiColors.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
