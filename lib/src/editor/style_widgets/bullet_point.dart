import 'package:flutter/widgets.dart';

class QuillBulletPoint extends StatelessWidget {
  const QuillBulletPoint({
    required this.style,
    required this.width,
    this.padding = 0,
    this.backgroundColor,
    this.textAlign,
    super.key,
  });

  final TextStyle style;
  final double width;
  final double padding;
  final Color? backgroundColor;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    double? height;
    if (style.height != null && style.fontSize != null) {
      height = style.height! * style.fontSize!;
    }

    return Container(
      alignment: AlignmentDirectional.topEnd,
      width: width,
      height: height,
      padding: EdgeInsetsDirectional.only(end: padding),
      color: backgroundColor,
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: style.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
