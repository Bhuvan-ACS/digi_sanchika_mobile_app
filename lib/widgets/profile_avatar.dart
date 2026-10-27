import 'dart:io';

import 'package:flutter/material.dart';

import 'illustrated_person.dart';

export 'illustrated_person.dart' show PersonAvatarSpec, HairStyle;

/// What the user picked for their avatar, encoded as a single string so it
/// can be stored alongside the other profile overrides:
///   `photo:<file path>`  – a picture copied from the device
///   `preset:<index>`     – one of [AvatarChoice.presets]
///   `gen:<prompt>`       – an avatar generated from a text prompt
/// A null value means "show initials".
class AvatarChoice {
  const AvatarChoice._(this.kind, this.value);

  final String kind;
  final String value;

  factory AvatarChoice.photo(String path) => AvatarChoice._('photo', path);
  factory AvatarChoice.preset(int index) =>
      AvatarChoice._('preset', index.toString());
  factory AvatarChoice.generated(String prompt) =>
      AvatarChoice._('gen', prompt.trim());

  static AvatarChoice? decode(String? encoded) {
    if (encoded == null) return null;
    final i = encoded.indexOf(':');
    if (i <= 0) return null;
    return AvatarChoice._(encoded.substring(0, i), encoded.substring(i + 1));
  }

  String encode() => '$kind:$value';

  /// Illustrated people for the quick presets. Order matters: saved choices
  /// are stored as `preset:<index>`.
  static const presets = <PersonAvatarSpec>[
    PersonAvatarSpec(
      background: [Color(0xFFBFDBFE), Color(0xFF60A5FA)],
      skin: Color(0xFFE0AC69),
      hair: Color(0xFF1F2937),
      hairStyle: HairStyle.sidePart,
      shirt: Color(0xFF1D4ED8),
    ),
    PersonAvatarSpec(
      background: [Color(0xFFE9D5FF), Color(0xFFC084FC)],
      skin: Color(0xFFF1C27D),
      hair: Color(0xFF7C2D12),
      hairStyle: HairStyle.long,
      shirt: Color(0xFF7C3AED),
    ),
    PersonAvatarSpec(
      background: [Color(0xFFA7F3D0), Color(0xFF34D399)],
      skin: Color(0xFF8D5524),
      hair: Color(0xFF111827),
      hairStyle: HairStyle.curly,
      shirt: Color(0xFF047857),
    ),
    PersonAvatarSpec(
      background: [Color(0xFFFDE68A), Color(0xFFFB923C)],
      skin: Color(0xFFC68642),
      hair: Color(0xFF0F172A),
      hairStyle: HairStyle.headscarf,
      shirt: Color(0xFFEA580C),
    ),
    PersonAvatarSpec(
      background: [Color(0xFFFBCFE8), Color(0xFFF472B6)],
      skin: Color(0xFFFFDBAC),
      hair: Color(0xFF92400E),
      hairStyle: HairStyle.bun,
      shirt: Color(0xFFDB2777),
      glasses: true,
    ),
    PersonAvatarSpec(
      background: [Color(0xFFA5F3FC), Color(0xFF22D3EE)],
      skin: Color(0xFF5C3A21),
      hair: Color(0xFF111827),
      hairStyle: HairStyle.buzz,
      shirt: Color(0xFF0F766E),
      beard: true,
    ),
    PersonAvatarSpec(
      background: [Color(0xFFE2E8F0), Color(0xFF94A3B8)],
      skin: Color(0xFFF1C27D),
      hair: Color(0xFF374151),
      hairStyle: HairStyle.short,
      shirt: Color(0xFF334155),
      glasses: true,
    ),
    PersonAvatarSpec(
      background: [Color(0xFFFECACA), Color(0xFFF87171)],
      skin: Color(0xFFE0AC69),
      hair: Color(0xFF1C1917),
      hairStyle: HairStyle.long,
      shirt: Color(0xFFB91C1C),
    ),
  ];

  static const _generatorIcons = <IconData>[
    Icons.pets_rounded,
    Icons.music_note_rounded,
    Icons.sports_esports_rounded,
    Icons.flight_rounded,
    Icons.palette_rounded,
    Icons.coffee_rounded,
    Icons.psychology_rounded,
    Icons.star_rounded,
    Icons.landscape_rounded,
    Icons.code_rounded,
    Icons.camera_alt_rounded,
    Icons.diamond_rounded,
  ];

  static const _keywordIcons = <String, IconData>{
    'cat': Icons.pets_rounded,
    'dog': Icons.pets_rounded,
    'pet': Icons.pets_rounded,
    'music': Icons.music_note_rounded,
    'game': Icons.sports_esports_rounded,
    'travel': Icons.flight_rounded,
    'plane': Icons.flight_rounded,
    'art': Icons.palette_rounded,
    'coffee': Icons.coffee_rounded,
    'brain': Icons.psychology_rounded,
    'star': Icons.star_rounded,
    'space': Icons.rocket_launch_rounded,
    'rocket': Icons.rocket_launch_rounded,
    'mountain': Icons.landscape_rounded,
    'nature': Icons.eco_rounded,
    'leaf': Icons.eco_rounded,
    'code': Icons.code_rounded,
    'tech': Icons.memory_rounded,
    'camera': Icons.camera_alt_rounded,
    'sun': Icons.wb_sunny_rounded,
    'ocean': Icons.waves_rounded,
    'sea': Icons.waves_rounded,
    'fire': Icons.local_fire_department_rounded,
    'heart': Icons.favorite_rounded,
    'book': Icons.menu_book_rounded,
  };

  /// Deterministically turns a prompt into a gradient + motif: the same
  /// prompt always produces the same avatar. Keywords pick the motif.
  static AvatarStyle styleForPrompt(String prompt) {
    final text = prompt.toLowerCase().trim();
    var hash = 0;
    for (final unit in text.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    final start = HSLColor.fromAHSL(1, hue, 0.70, 0.42).toColor();
    final end = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.80, 0.62).toColor();

    IconData? icon;
    for (final entry in _keywordIcons.entries) {
      if (text.contains(entry.key)) {
        icon = entry.value;
        break;
      }
    }
    icon ??= _generatorIcons[(hash ~/ 7) % _generatorIcons.length];
    return AvatarStyle([start, end], icon);
  }
}

class AvatarStyle {
  const AvatarStyle(this.colors, this.icon);
  final List<Color> colors;
  final IconData icon;
}

/// Circular avatar that renders an [AvatarChoice], falling back to initials.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.initials,
    this.avatar,
    this.size = 72,
    this.initialsColor = Colors.white,
    this.background,
    this.border,
  });

  final String initials;

  /// Encoded [AvatarChoice] or null.
  final String? avatar;
  final double size;
  final Color initialsColor;

  /// Fill used behind initials. Defaults to translucent white.
  final Color? background;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final choice = AvatarChoice.decode(avatar);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        color: choice == null ? (background ?? Colors.white.withAlpha(35)) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: _content(choice),
    );
  }

  Widget _content(AvatarChoice? choice) {
    switch (choice?.kind) {
      case 'photo':
        return Image.file(
          File(choice!.value),
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, _, _) => _initials(),
        );
      case 'preset':
        final index = int.tryParse(choice!.value) ?? 0;
        return IllustratedPerson(
          spec: AvatarChoice.presets[index % AvatarChoice.presets.length],
          size: size,
        );
      case 'gen':
        return _styled(AvatarChoice.styleForPrompt(choice!.value));
      default:
        return _initials();
    }
  }

  Widget _styled(AvatarStyle style) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: style.colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Center(
      child: Icon(style.icon, color: Colors.white, size: size * 0.48),
    ),
  );

  Widget _initials() => Center(
    child: Text(
      initials,
      style: TextStyle(
        fontSize: size * 0.36,
        fontWeight: FontWeight.w800,
        color: initialsColor,
      ),
    ),
  );
}
