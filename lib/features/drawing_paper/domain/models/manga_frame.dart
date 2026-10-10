import 'package:flutter/material.dart';

class MangaPanelCut {
  final String id;
  final Rect rect;
  final double borderWidth;
  final Color borderColor;
  final Color backgroundColor;
  final double rotation;

  const MangaPanelCut({
    required this.id,
    required this.rect,
    this.borderWidth = 2.5,
    this.borderColor = Colors.black,
    this.backgroundColor = Colors.transparent,
    this.rotation = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'l': rect.left,
    't': rect.top,
    'w': rect.width,
    'h': rect.height,
    'bw': borderWidth,
    'bc': borderColor.toARGB32(),
    'bg': backgroundColor.toARGB32(),
    'r': rotation,
  };

  factory MangaPanelCut.fromJson(Map<String, dynamic> json) => MangaPanelCut(
    id:
        json['id'] as String? ??
        'panel_${DateTime.now().microsecondsSinceEpoch}',
    rect: Rect.fromLTWH(
      (json['l'] as num).toDouble(),
      (json['t'] as num).toDouble(),
      (json['w'] as num).toDouble(),
      (json['h'] as num).toDouble(),
    ),
    borderWidth: (json['bw'] as num?)?.toDouble() ?? 2.5,
    borderColor: Color((json['bc'] as num?)?.toInt() ?? 0xFF000000),
    backgroundColor: Color((json['bg'] as num?)?.toInt() ?? 0x00000000),
    rotation: (json['r'] as num?)?.toDouble() ?? 0.0,
  );

  MangaPanelCut copyWith({
    String? id,
    Rect? rect,
    double? borderWidth,
    Color? borderColor,
    Color? backgroundColor,
    double? rotation,
  }) => MangaPanelCut(
    id: id ?? this.id,
    rect: rect ?? this.rect,
    borderWidth: borderWidth ?? this.borderWidth,
    borderColor: borderColor ?? this.borderColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    rotation: rotation ?? this.rotation,
  );
}

enum SpeechBalloonType {
  speechOval,
  thoughtCloud,
  shoutExplosion,
  squareWhisper,
}

class SpeechBalloon {
  final String id;
  final String text;
  final Offset position;
  final Size size;
  final Offset tailTarget;
  final SpeechBalloonType type;
  final bool isVerticalText;
  final double fontSize;
  final Color textColor;
  final Color balloonColor;
  final Color borderColor;
  final double borderWidth;
  final double rotation;

  const SpeechBalloon({
    required this.id,
    this.text = '...',
    required this.position,
    required this.size,
    required this.tailTarget,
    this.type = SpeechBalloonType.speechOval,
    this.isVerticalText = false,
    this.fontSize = 16.0,
    this.textColor = Colors.black,
    this.balloonColor = Colors.white,
    this.borderColor = Colors.black,
    this.borderWidth = 2.0,
    this.rotation = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'x': position.dx,
    'y': position.dy,
    'w': size.width,
    'h': size.height,
    'tx': tailTarget.dx,
    'ty': tailTarget.dy,
    'type': type.name,
    'isVertical': isVerticalText,
    'fontSize': fontSize,
    'tc': textColor.toARGB32(),
    'bc': balloonColor.toARGB32(),
    'borderC': borderColor.toARGB32(),
    'bw': borderWidth,
    'r': rotation,
  };

  factory SpeechBalloon.fromJson(Map<String, dynamic> json) => SpeechBalloon(
    id:
        json['id'] as String? ??
        'balloon_${DateTime.now().microsecondsSinceEpoch}',
    text: json['text'] as String? ?? '...',
    position: Offset(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    ),
    size: Size((json['w'] as num).toDouble(), (json['h'] as num).toDouble()),
    tailTarget: Offset(
      (json['tx'] as num).toDouble(),
      (json['ty'] as num).toDouble(),
    ),
    type: SpeechBalloonType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => SpeechBalloonType.speechOval,
    ),
    isVerticalText: json['isVertical'] as bool? ?? false,
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16.0,
    textColor: Color((json['tc'] as num?)?.toInt() ?? 0xFF000000),
    balloonColor: Color((json['bc'] as num?)?.toInt() ?? 0xFFFFFFFF),
    borderColor: Color((json['borderC'] as num?)?.toInt() ?? 0xFF000000),
    borderWidth: (json['bw'] as num?)?.toDouble() ?? 2.0,
    rotation: (json['r'] as num?)?.toDouble() ?? 0.0,
  );

  SpeechBalloon copyWith({
    String? id,
    String? text,
    Offset? position,
    Size? size,
    Offset? tailTarget,
    SpeechBalloonType? type,
    bool? isVerticalText,
    double? fontSize,
    Color? textColor,
    Color? balloonColor,
    Color? borderColor,
    double? borderWidth,
    double? rotation,
  }) => SpeechBalloon(
    id: id ?? this.id,
    text: text ?? this.text,
    position: position ?? this.position,
    size: size ?? this.size,
    tailTarget: tailTarget ?? this.tailTarget,
    type: type ?? this.type,
    isVerticalText: isVerticalText ?? this.isVerticalText,
    fontSize: fontSize ?? this.fontSize,
    textColor: textColor ?? this.textColor,
    balloonColor: balloonColor ?? this.balloonColor,
    borderColor: borderColor ?? this.borderColor,
    borderWidth: borderWidth ?? this.borderWidth,
    rotation: rotation ?? this.rotation,
  );
}

class MangaStructure {
  final List<MangaPanelCut> panels;
  final List<SpeechBalloon> balloons;
  final double gutterHorizontal;
  final double gutterVertical;

  const MangaStructure({
    this.panels = const [],
    this.balloons = const [],
    this.gutterHorizontal = 18.0,
    this.gutterVertical = 12.0,
  });

  Map<String, dynamic> toJson() => {
    'panels': panels.map((p) => p.toJson()).toList(),
    'balloons': balloons.map((b) => b.toJson()).toList(),
    'gh': gutterHorizontal,
    'gv': gutterVertical,
  };

  factory MangaStructure.fromJson(Map<String, dynamic> json) => MangaStructure(
    panels:
        (json['panels'] as List<dynamic>?)
            ?.map((p) => MangaPanelCut.fromJson(p as Map<String, dynamic>))
            .toList() ??
        const [],
    balloons:
        (json['balloons'] as List<dynamic>?)
            ?.map((b) => SpeechBalloon.fromJson(b as Map<String, dynamic>))
            .toList() ??
        const [],
    gutterHorizontal: (json['gh'] as num?)?.toDouble() ?? 18.0,
    gutterVertical: (json['gv'] as num?)?.toDouble() ?? 12.0,
  );

  MangaStructure clone() => MangaStructure(
    panels: List.of(panels),
    balloons: List.of(balloons),
    gutterHorizontal: gutterHorizontal,
    gutterVertical: gutterVertical,
  );

  MangaStructure copyWith({
    List<MangaPanelCut>? panels,
    List<SpeechBalloon>? balloons,
    double? gutterHorizontal,
    double? gutterVertical,
  }) => MangaStructure(
    panels: panels ?? this.panels,
    balloons: balloons ?? this.balloons,
    gutterHorizontal: gutterHorizontal ?? this.gutterHorizontal,
    gutterVertical: gutterVertical ?? this.gutterVertical,
  );
}
