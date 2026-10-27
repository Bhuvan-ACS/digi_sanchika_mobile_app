import 'package:flutter/material.dart';

/// Soft bordered panel that groups one content section (a header, a thin
/// divider, then its cards). Used by Favourites, My Files and Shared so
/// their Folders / Documents sections share the same look.
class SectionPanel extends StatelessWidget {
  const SectionPanel({
    super.key,
    required this.child,
    this.header,
    this.margin = const EdgeInsets.symmetric(horizontal: 12),
  });

  final Widget? header;
  final Widget child;

  /// Space outside the panel (default: 12px left and right).
  final EdgeInsetsGeometry margin;

  /// Horizontal padding inside the panel; cards sit this far from its edge.
  static const double innerPadding = 10;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(innerPadding, 12, innerPadding, 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(140),
        borderRadius: BorderRadius.circular(22),
        // Soft pale-blue edge: visible against the page background without
        // competing with the inner cards.
        border: Border.all(color: const Color(0xFFE8EFF8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null) ...[
            header!,
            const SectionPanelDivider(),
          ],
          child,
        ],
      ),
    );
  }
}

/// Space under a section header. It used to draw a thin line; the line was
/// removed, and the gap keeps the same height so nothing else moves.
class SectionPanelDivider extends StatelessWidget {
  const SectionPanelDivider({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(height: 21);
}

/// Centred page title (My Files, Shared, Favourites).
class RuledTitle extends StatelessWidget {
  const RuledTitle(
    this.text, {
    super.key,
    this.style = const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0F172A),
    ),
  });

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // The fading rules on either side were removed; the title stands alone.
    return Center(
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
