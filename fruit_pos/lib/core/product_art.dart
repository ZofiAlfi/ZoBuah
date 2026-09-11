import 'package:flutter/material.dart';

/// Gambar produk berupa emoji berwarna (rendered warna oleh system font).
class ProductArt {
  static const Map<String, String> _emojiByKeyword = {
    'apel': '🍎',
    'pisang': '🍌',
    'jeruk': '🍊',
    'lemon': '🍋',
    'anggur': '🍇',
    'semangka': '🍉',
    'melon': '🍈',
    'pepaya': '🍈',
    'mangga': '🥭',
    'stroberi': '🍓',
    'strawberry': '🍓',
    'kiwi': '🥝',
    'pir': '🍐',
    'nanas': '🍍',
    'kelapa': '🥥',
    'alpukat': '🥑',
    'jeruk bali': '🍊',
    'duku': '🍇',
    'rambutan': '🍓',
    'salak': '🥝',
    'durian': '🍈',
    'nangka': '🥭',
    'markisa': '🍋',
  };

  static const List<Color> _palette = [
    Color(0xFFE8F5E9),
    Color(0xFFFFF3E0),
    Color(0xFFE3F2FD),
    Color(0xFFFCE4EC),
    Color(0xFFF3E5F5),
    Color(0xFFFFF8E1),
    Color(0xFFE0F7FA),
    Color(0xFFEFEBE9),
  ];

  static String emoji(String name) {
    final n = name.toLowerCase();
    for (final entry in _emojiByKeyword.entries) {
      if (n.contains(entry.key)) return entry.value;
    }
    return '🍏';
  }

  static Color background(String name) {
    final n = name.toLowerCase();
    var h = n.hashCode.abs();
    if (h == 0) h = 3;
    return _palette[h % _palette.length];
  }
}
