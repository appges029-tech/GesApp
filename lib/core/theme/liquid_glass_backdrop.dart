import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Rich backdrop used by every GesApp route so Liquid Glass surfaces have
/// real colour and depth to refract. It stays static to preserve battery/GPU.
class LiquidGlassBackdrop extends StatelessWidget {
  const LiquidGlassBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [
                      Color(0xFF07111F),
                      Color(0xFF0B1830),
                      Color(0xFF122440),
                    ]
                  : const [
                      Color(0xFFF5F9FF),
                      Color(0xFFEAF3FF),
                      Color(0xFFF8F4E8),
                    ],
            ),
          ),
        ),
        Positioned(
          top: -90,
          left: -70,
          child: _Orb(
            size: 260,
            color: AppColors.primary.withValues(alpha: dark ? .25 : .18),
          ),
        ),
        Positioned(
          top: 140,
          right: -90,
          child: _Orb(
            size: 290,
            color: AppColors.accent.withValues(alpha: dark ? .18 : .13),
          ),
        ),
        Positioned(
          bottom: -110,
          left: 70,
          child: _Orb(
            size: 320,
            color: const Color(0xFF7C5CFC).withValues(
              alpha: dark ? .17 : .10,
            ),
          ),
        ),
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: color.a * .45),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}
