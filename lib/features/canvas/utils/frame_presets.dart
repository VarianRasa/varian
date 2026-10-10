import 'package:flutter/material.dart';

enum FramePresetCategory {
  mobile,
  tablet,
  desktop,
  presentation,
  social,
  paper,
}

class FramePreset {
  final String id;
  final String name;
  final FramePresetCategory category;
  final double width;
  final double height;
  final IconData icon;
  final String description;

  const FramePreset({
    required this.id,
    required this.name,
    required this.category,
    required this.width,
    required this.height,
    required this.icon,
    required this.description,
  });

  double getWidth(bool isLandscape) => isLandscape
      ? (height > width ? height : width)
      : (height > width ? width : height);
  double getHeight(bool isLandscape) => isLandscape
      ? (height > width ? width : height)
      : (height > width ? height : width);
}

class FramePresetsCatalog {
  static const List<FramePreset> presets = [
    // Mobile
    FramePreset(
      id: 'iphone_16_pro',
      name: 'iPhone 16 / 15 Pro',
      category: FramePresetCategory.mobile,
      width: 393,
      height: 852,
      icon: Icons.smartphone,
      description: '393 x 852 px (Standard iOS)',
    ),
    FramePreset(
      id: 'iphone_se',
      name: 'iPhone SE',
      category: FramePresetCategory.mobile,
      width: 375,
      height: 667,
      icon: Icons.smartphone,
      description: '375 x 667 px (Compact iOS)',
    ),
    FramePreset(
      id: 'samsung_s24',
      name: 'Samsung Galaxy S24',
      category: FramePresetCategory.mobile,
      width: 360,
      height: 780,
      icon: Icons.phone_android,
      description: '360 x 780 px (Android UI)',
    ),
    FramePreset(
      id: 'pixel_8',
      name: 'Google Pixel 8',
      category: FramePresetCategory.mobile,
      width: 412,
      height: 915,
      icon: Icons.phone_android,
      description: '412 x 915 px (Material 3)',
    ),

    // Tablet
    FramePreset(
      id: 'ipad_pro_11',
      name: 'iPad Pro 11"',
      category: FramePresetCategory.tablet,
      width: 834,
      height: 1194,
      icon: Icons.tablet_mac,
      description: '834 x 1194 px',
    ),
    FramePreset(
      id: 'ipad_pro_12',
      name: 'iPad Pro 12.9"',
      category: FramePresetCategory.tablet,
      width: 1024,
      height: 1366,
      icon: Icons.tablet_mac,
      description: '1024 x 1366 px',
    ),

    // Desktop
    FramePreset(
      id: 'macbook_pro_14',
      name: 'MacBook Pro 14"',
      category: FramePresetCategory.desktop,
      width: 1512,
      height: 982,
      icon: Icons.laptop_mac,
      description: '1512 x 982 px (Retina Web)',
    ),
    FramePreset(
      id: 'desktop_hd',
      name: 'Desktop (1440p)',
      category: FramePresetCategory.desktop,
      width: 1440,
      height: 900,
      icon: Icons.desktop_windows,
      description: '1440 x 900 px',
    ),
    FramePreset(
      id: 'full_hd',
      name: 'Full HD (1080p)',
      category: FramePresetCategory.desktop,
      width: 1920,
      height: 1080,
      icon: Icons.tv,
      description: '1920 x 1080 px',
    ),

    // Presentation
    FramePreset(
      id: 'slide_16_9',
      name: 'Slide 16:9',
      category: FramePresetCategory.presentation,
      width: 1920,
      height: 1080,
      icon: Icons.slideshow,
      description: 'Widescreen Presentation Slide',
    ),
    FramePreset(
      id: 'slide_4_3',
      name: 'Slide 4:3',
      category: FramePresetCategory.presentation,
      width: 1024,
      height: 768,
      icon: Icons.aspect_ratio,
      description: 'Standard Presentation Slide',
    ),

    // Social Media
    FramePreset(
      id: 'ig_post',
      name: 'Instagram Post',
      category: FramePresetCategory.social,
      width: 1080,
      height: 1080,
      icon: Icons.square_outlined,
      description: '1:1 Square (1080 x 1080 px)',
    ),
    FramePreset(
      id: 'ig_story',
      name: 'Instagram / TikTok Story',
      category: FramePresetCategory.social,
      width: 1080,
      height: 1920,
      icon: Icons.stay_current_portrait,
      description: '9:16 Vertical Video / Story',
    ),
    FramePreset(
      id: 'dribbble_shot',
      name: 'Dribbble Shot',
      category: FramePresetCategory.social,
      width: 1600,
      height: 1200,
      icon: Icons.photo_camera_back,
      description: '4:3 HD Dribbble Portfolio',
    ),
    FramePreset(
      id: 'twitter_header',
      name: 'Twitter / X Header',
      category: FramePresetCategory.social,
      width: 1500,
      height: 500,
      icon: Icons.crop_16_9,
      description: '3:1 Banner Header',
    ),

    // Paper
    FramePreset(
      id: 'paper_a4',
      name: 'A4 Document',
      category: FramePresetCategory.paper,
      width: 595,
      height: 842,
      icon: Icons.description_outlined,
      description: 'ISO A4 (595 x 842 pt)',
    ),
    FramePreset(
      id: 'paper_us_letter',
      name: 'US Letter',
      category: FramePresetCategory.paper,
      width: 612,
      height: 792,
      icon: Icons.article_outlined,
      description: 'US Letter (612 x 792 pt)',
    ),
  ];

  static FramePreset? findById(String? id) {
    if (id == null) return null;
    try {
      return presets.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}
