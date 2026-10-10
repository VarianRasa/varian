import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class VarianBrandMark extends StatelessWidget {
  const VarianBrandMark({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/image/varian_mark.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticsLabel: 'Varian logo',
    );
  }
}

class VarianLogoLockup extends StatelessWidget {
  const VarianLogoLockup({super.key, this.width = 240});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/image/varian_lockup.svg',
      width: width,
      fit: BoxFit.contain,
      semanticsLabel: 'Varian Creative Canvas Studio',
    );
  }
}
