import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/student_media_service.dart';

class StoredImage extends StatelessWidget {
  const StoredImage({
    super.key,
    required this.reference,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallback,
  });

  final String? reference;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final ref = reference;
    if (ref == null || ref.isEmpty) return fallback ?? const SizedBox.shrink();
    return FutureBuilder<Uint8List?>(
      future: StudentMediaService().readStoredFileBytes(ref),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return fallback ?? const SizedBox.shrink();
        }
        return Image.memory(bytes, width: width, height: height, fit: fit,
            errorBuilder: (_, __, ___) => fallback ?? const SizedBox.shrink());
      },
    );
  }
}
