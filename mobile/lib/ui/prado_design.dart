import 'package:flutter/material.dart';

/// Reusable, intentionally calm family visual language (Bloque 03.5).
abstract final class PradoColors {
  static const navy = Color(0xFF243B5A);
  static const ocean = Color(0xFF3E6689);
  static const teal = Color(0xFF367F78);
  static const coral = Color(0xFFBD674F);
  static const sand = Color(0xFFD6A55C);
  static const cream = Color(0xFFFFF9F2);
  static const paper = Color(0xFFFFFFFF);
  static const ink = Color(0xFF243144);
  static const muted = Color(0xFF5D6979);
  static const line = Color(0xFFE9E1D8);
  static const mint = Color(0xFFEAF4F0);
  static const paleBlue = Color(0xFFEAF1FA);
  static const peach = Color(0xFFFFEFE7);
  static const paleSand = Color(0xFFFFF4DB);
}

ThemeData pradoTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: PradoColors.navy,
    brightness: Brightness.light,
    surface: PradoColors.cream,
    primary: PradoColors.navy,
    secondary: PradoColors.teal,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: PradoColors.cream,
    appBarTheme: const AppBarTheme(
      backgroundColor: PradoColors.cream,
      foregroundColor: PradoColors.navy,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: PradoColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: PradoColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PradoColors.navy,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PradoColors.navy,
        side: const BorderSide(color: Color(0xFFB9C9D6)),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: PradoColors.navy,
        minimumSize: const Size(0, 48),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PradoColors.paper,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: PradoColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: PradoColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: PradoColors.ocean, width: 2)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: PradoColors.paleBlue,
      elevation: 0,
      height: 76,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: PradoColors.navy)),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 16, height: 1.35, color: PradoColors.ink),
      bodyLarge: TextStyle(fontSize: 17, height: 1.35, color: PradoColors.ink),
      titleSmall: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: PradoColors.ink),
      titleMedium: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: PradoColors.ink),
      titleLarge: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: PradoColors.navy),
      headlineMedium: TextStyle(fontSize: 31, fontWeight: FontWeight.w800, color: PradoColors.navy),
    ),
  );
}

class PradoPanel extends StatelessWidget {
  const PradoPanel({super.key, required this.child, this.tint = PradoColors.paper,
    this.padding = const EdgeInsets.all(18), this.onTap});
  final Widget child;
  final Color tint;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override Widget build(BuildContext context) => Material(
    color: tint,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: PradoColors.line)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap,
      child: Padding(padding: padding, child: child)),
  );
}

class PradoIntro extends StatelessWidget {
  const PradoIntro({super.key, required this.eyebrow, required this.title,
    required this.subtitle, this.icon = Icons.favorite_outline, this.tint = PradoColors.paleBlue});
  final String eyebrow, title, subtitle;
  final IconData icon;
  final Color tint;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(eyebrow.toUpperCase(), style: const TextStyle(color: PradoColors.teal,
          fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 11)),
        const SizedBox(height: 5),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 5),
        Text(subtitle, style: const TextStyle(color: PradoColors.muted, fontSize: 15)),
      ])),
      const SizedBox(width: 12),
      Container(width: 52, height: 52, decoration: BoxDecoration(color: tint,
        borderRadius: BorderRadius.circular(17)), child: Icon(icon, color: PradoColors.navy, size: 27)),
    ]),
  );
}

class PradoSectionHeading extends StatelessWidget {
  const PradoSectionHeading(this.title, {super.key, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12, top: 8),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if(subtitle != null) Text(subtitle!, style: const TextStyle(color: PradoColors.muted, fontSize: 14)),
      ])),
      if(action != null) action!,
    ]),
  );
}

class PradoPill extends StatelessWidget {
  const PradoPill(this.label, {super.key, this.color = PradoColors.teal, this.tint = PradoColors.mint,
    this.icon});
  final String label;
  final Color color, tint;
  final IconData? icon;
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(30)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if(icon != null) ...[Icon(icon, size: 15, color: color), const SizedBox(width: 5)],
      Flexible(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color))),
    ]),
  );
}

class PradoInfoRow extends StatelessWidget {
  const PradoInfoRow({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 19, color: PradoColors.ocean),
      const SizedBox(width: 9),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 15, color: PradoColors.ink))),
    ]),
  );
}

class PradoEmpty extends StatelessWidget {
  const PradoEmpty({super.key, required this.title, required this.detail,
    this.icon = Icons.inbox_outlined, this.action});
  final String title, detail;
  final IconData icon;
  final Widget? action;
  @override Widget build(BuildContext context) => PradoPanel(
    tint: PradoColors.paper,
    child: Column(children: [
      Container(padding: const EdgeInsets.all(13), decoration: const BoxDecoration(
        color: PradoColors.paleBlue, shape: BoxShape.circle),
        child: Icon(icon, color: PradoColors.ocean, size: 26)),
      const SizedBox(height: 10),
      Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
      const SizedBox(height: 5),
      Text(detail, style: const TextStyle(color: PradoColors.muted, fontSize: 15), textAlign: TextAlign.center),
      if(action != null) ...[const SizedBox(height: 10), action!],
    ]),
  );
}

String pradoMoney(Object? amount) {
  final n = amount is num ? amount.toDouble() : double.tryParse('$amount') ?? 0;
  return 'S/ ${n.toStringAsFixed(2)}';
}
