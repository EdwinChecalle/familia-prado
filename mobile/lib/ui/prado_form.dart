import 'package:flutter/material.dart';

/// Common accessible layout for the existing short family forms.
Future<T?> showPradoForm<T>({required BuildContext context, required WidgetBuilder builder}) {
  return showDialog<T>(context: context, barrierDismissible: false, builder: (ctx) {
    final theme = Theme.of(ctx);
    return Theme(data: theme.copyWith(
      textTheme: theme.textTheme.copyWith(bodyMedium: theme.textTheme.bodyMedium?.copyWith(fontSize: 16), titleLarge: theme.textTheme.titleLarge?.copyWith(fontSize: 23,fontWeight: FontWeight.w700)),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(contentPadding: const EdgeInsets.symmetric(horizontal:16,vertical:20)),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0,52))),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(0,48))),
    ), child: Builder(builder: builder));
  });
}
