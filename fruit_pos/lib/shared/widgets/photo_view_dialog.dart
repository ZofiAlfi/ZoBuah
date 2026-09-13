import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// Menampilkan foto (base64 atau URL/path server) dalam dialog layar penuh
/// yang bisa di-zoom: pinch, seret, dan ketuk dua kali untuk perbesar.
/// Ditutup lewat tombol close, tap area luar, atau back.
Future<void> showPhotoViewDialog(BuildContext context, String image) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Tutup',
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) => _PhotoViewScreen(image: image),
  );
}

class _PhotoViewScreen extends StatefulWidget {
  final String image;
  const _PhotoViewScreen({required this.image});

  @override
  State<_PhotoViewScreen> createState() => _PhotoViewScreenState();
}

class _PhotoViewScreenState extends State<_PhotoViewScreen> {
  final TransformationController _controller = TransformationController();
  double _scale = 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    setState(() {
      if (_scale > 1) {
        _controller.value = Matrix4.identity();
        _scale = 1;
      } else {
        _scale = 2.5;
        _controller.value = Matrix4.identity()..scale(_scale);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onDoubleTap: _toggleZoom,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1,
                maxScale: 5,
                panEnabled: true,
                child: Center(child: _buildImage()),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Ketuk dua kali untuk perbesar',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    final img = widget.image;
    if (img.isEmpty) return _error();

    if (_isUrl(img)) {
      return Image.network(
        _absolute(img),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _error(),
      );
    }

    Uint8List? bytes;
    try {
      String b64 = img;
      if (b64.startsWith('data:image')) {
        b64 = b64.split(',').last;
      }
      bytes = base64Decode(b64);
    } catch (_) {}

    if (bytes == null || bytes.isEmpty) return _error();
    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _error(),
    );
  }

  Widget _error() => const Center(
        child: Icon(Icons.broken_image_outlined,
            color: Colors.white70, size: 64),
      );

  bool _isUrl(String s) =>
      s.startsWith('http://') || s.startsWith('https://') || s.startsWith('/');

  String _absolute(String s) =>
      s.startsWith('/') ? '${AppConstants.baseUrl}$s' : s;
}