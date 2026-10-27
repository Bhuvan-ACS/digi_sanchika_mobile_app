import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

const String birdHeroTag = 'bird_delivery_hero';

/// Flying bird. Shares [birdHeroTag] so it glides between pages.
class BirdFlyAnimation extends StatelessWidget {
  final double size;
  const BirdFlyAnimation({super.key, this.size = 240});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: birdHeroTag,
      child: Lottie.asset(
        'assets/animations/bird_fly_delivery.json',
        width: size,
        height: size,
        fit: BoxFit.contain,
        repeat: true,
        errorBuilder: (_, _, _) =>
            Icon(Icons.flutter_dash, size: size * 0.6, color: Colors.blue),
      ),
    );
  }
}
