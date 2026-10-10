import 'package:flutter/material.dart';

class DocumentPaperPreset {
  final String id;
  final String name;
  final double width;
  final double height;
  final String description;
  final IconData icon;

  const DocumentPaperPreset({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.description,
    this.icon = Icons.description_outlined,
  });

  double getEffectiveWidth(bool isLandscape) => isLandscape
      ? (height > width ? height : width)
      : (height > width ? width : height);

  double getEffectiveHeight(bool isLandscape) => isLandscape
      ? (height > width ? width : height)
      : (height > width ? height : width);
}

class DocumentPaperCatalog {
  static const List<DocumentPaperPreset> presets = [
    DocumentPaperPreset(
      id: 'a4',
      name: 'A4 Document',
      width: 595,
      height: 842,
      description: '595 x 842 pt (ISO standard)',
      icon: Icons.article_outlined,
    ),
    DocumentPaperPreset(
      id: 'letter',
      name: 'US Letter',
      width: 612,
      height: 792,
      description: '612 x 792 pt (North America)',
      icon: Icons.description_outlined,
    ),
    DocumentPaperPreset(
      id: 'a5',
      name: 'A5 Notebook',
      width: 420,
      height: 595,
      description: '420 x 595 pt (Compact booklet)',
      icon: Icons.menu_book_outlined,
    ),
    DocumentPaperPreset(
      id: 'a3',
      name: 'A3 Poster',
      width: 842,
      height: 1191,
      description: '842 x 1191 pt (Large spread)',
      icon: Icons.view_quilt_outlined,
    ),
    DocumentPaperPreset(
      id: 'legal',
      name: 'US Legal',
      width: 612,
      height: 1008,
      description: '612 x 1008 pt (Extended document)',
      icon: Icons.gavel_outlined,
    ),
    DocumentPaperPreset(
      id: 'executive',
      name: 'Executive',
      width: 522,
      height: 756,
      description: '522 x 756 pt (Corporate report)',
      icon: Icons.business_center_outlined,
    ),
    DocumentPaperPreset(
      id: 'b5',
      name: 'B5 Book',
      width: 499,
      height: 709,
      description: '499 x 709 pt (Standard book)',
      icon: Icons.book_outlined,
    ),
    DocumentPaperPreset(
      id: 'square',
      name: 'Square Sheet',
      width: 700,
      height: 700,
      description: '700 x 700 pt (1:1 Canvas grid)',
      icon: Icons.crop_square_outlined,
    ),
    DocumentPaperPreset(
      id: 'widescreen',
      name: 'Widescreen (16:9)',
      width: 960,
      height: 540,
      description: '960 x 540 pt (Slide / Presentation)',
      icon: Icons.slideshow_outlined,
    ),
  ];

  static DocumentPaperPreset findById(String? id) {
    if (id == null) return presets.first;
    return presets.firstWhere((p) => p.id == id, orElse: () => presets.first);
  }
}

class DocumentThemePreset {
  final String id;
  final String name;
  final Color backgroundColor;
  final Color textColor;
  final Color subTextColor;
  final Color borderColor;
  final Color headerBarColor;

  const DocumentThemePreset({
    required this.id,
    required this.name,
    required this.backgroundColor,
    required this.textColor,
    required this.subTextColor,
    required this.borderColor,
    required this.headerBarColor,
  });
}

class DocumentThemeCatalog {
  static const List<DocumentThemePreset> themes = [
    DocumentThemePreset(
      id: 'default_light',
      name: 'Clean White',
      backgroundColor: Color(0xFFFDFDFC),
      textColor: Color(0xFF111827),
      subTextColor: Color(0xFF4B5563),
      borderColor: Color(0xFFD1D5DB),
      headerBarColor: Color(0xFFF3F4F6),
    ),
    DocumentThemePreset(
      id: 'ivory',
      name: 'Warm Ivory',
      backgroundColor: Color(0xFFFAF8F3),
      textColor: Color(0xFF27231E),
      subTextColor: Color(0xFF5D5449),
      borderColor: Color(0xFFE5DDD0),
      headerBarColor: Color(0xFFF1ECE1),
    ),
    DocumentThemePreset(
      id: 'sepia',
      name: 'Vintage Sepia',
      backgroundColor: Color(0xFFF4EAD4),
      textColor: Color(0xFF43302B),
      subTextColor: Color(0xFF6B5852),
      borderColor: Color(0xFFD8C7A5),
      headerBarColor: Color(0xFFE6D6B4),
    ),
    DocumentThemePreset(
      id: 'dark',
      name: 'Obsidian Dark',
      backgroundColor: Color(0xFF1E2028),
      textColor: Color(0xFFF3F4F6),
      subTextColor: Color(0xFF9CA3AF),
      borderColor: Color(0xFF374151),
      headerBarColor: Color(0xFF282B36),
    ),
  ];

  static DocumentThemePreset findById(String? id) {
    if (id == null) return themes.first;
    return themes.firstWhere((t) => t.id == id, orElse: () => themes.first);
  }
}
