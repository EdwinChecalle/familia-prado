import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'prado_design.dart';

/// Only data already authorised and retrieved from the backend enters a report.
/// A PNG is external to Familia Prado after the user shares it.
class FamilyReport {
  const FamilyReport({
    required this.title,
    required this.subtitle,
    required this.mainLabel,
    required this.mainValue,
    required this.lines,
    required this.generatedLabel,
    this.privacy = 'Comparte solo con personas de confianza.',
  });
  final String title;
  final String subtitle;
  final String mainLabel;
  final String mainValue;
  final List<ReportLine> lines;
  final String generatedLabel;
  final String privacy;
}

class ReportLine {
  const ReportLine(this.label, this.value, {this.emphasis = false});
  final String label;
  final String value;
  final bool emphasis;
}

Future<void> showFamilyReport(BuildContext context, FamilyReport report) =>
    showDialog<void>(
      context: context,
      builder: (context) => _ReportDialog(report: report),
    );

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.report});
  final FamilyReport report;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _imageKey = GlobalKey();
  bool _busy = false;

  Future<File> _createPng({required bool permanent}) async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _imageKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      throw StateError('La vista previa todavía no está preparada.');
    }
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('No fue posible generar el PNG.');
      final directory = permanent
          ? await getApplicationDocumentsDirectory()
          : await getTemporaryDirectory();
      final filename = 'familia_prado_${DateTime.now().millisecondsSinceEpoch}.png';
      return File('${directory.path}${Platform.pathSeparator}$filename')
          .writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  }

  Future<void> _export({required bool share}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _createPng(permanent: !share);
      if (!mounted) return;
      if (share) {
        await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')],
            text: 'Familia Prado · ${widget.report.title}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Copia guardada en los archivos privados de la aplicación. '
              'También puedes usar Compartir para enviarla a Archivos o WhatsApp.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar la imagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Vista previa · Imagen para compartir',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: RepaintBoundary(
                  key: _imageKey,
                  child: _ReportArtwork(report: widget.report),
                ),
              ),
              const SizedBox(height: 14),
              Text(widget.report.privacy,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: PradoColors.muted)),
              const SizedBox(height: 12),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8,
                children: [
                  OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Volver')),
                  OutlinedButton.icon(onPressed: _busy ? null : () => _export(share: false),
                      icon: const Icon(Icons.save_alt), label: const Text('Guardar copia')),
                  FilledButton.icon(onPressed: _busy ? null : () => _export(share: true),
                      icon: const Icon(Icons.share_outlined),
                      label: Text(_busy ? 'Preparando…' : 'Compartir')),
                ],
              ),
            ]),
          ),
        ),
      );
}

class _ReportArtwork extends StatelessWidget {
  const _ReportArtwork({required this.report});
  final FamilyReport report;

  @override
  Widget build(BuildContext context) => Container(
        width: 360,
        height: 450,
        color: PradoColors.cream,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(height: 38, width: 38,
                decoration: BoxDecoration(color: PradoColors.paleSand,
                  borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.favorite_outline, color: PradoColors.coral)),
              const SizedBox(width: 10),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FAMILIA PRADO',
                    style: TextStyle(color: PradoColors.navy, letterSpacing: 1.5,
                      fontSize: 13, fontWeight: FontWeight.w900)),
                  Text('Siempre juntos',
                    style: TextStyle(color: PradoColors.muted, fontSize: 11)),
                ])),
            ]),
            const SizedBox(height: 18),
            Text(report.title,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900,
                color: PradoColors.navy)),
            const SizedBox(height: 5),
            Text(report.subtitle, style: const TextStyle(
              color: PradoColors.muted, fontSize: 12)),
            const SizedBox(height: 18),
            Container(width: double.infinity, padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: PradoColors.navy,
                borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(report.mainLabel,
                  style: const TextStyle(color: Color(0xFFE3EDF1), fontSize: 12)),
                const SizedBox(height: 3),
                Text(report.mainValue, maxLines: 2,
                  style: const TextStyle(color: Colors.white,
                    fontSize: 24, fontWeight: FontWeight.w900)),
              ])),
            const SizedBox(height: 14),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.start,
              children: [
                for (final line in report.lines.take(5)) Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(line.label,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: PradoColors.ink, fontSize: 12,
                        fontWeight: line.emphasis ? FontWeight.w800 : FontWeight.w500))),
                    const SizedBox(width: 9),
                    Flexible(child: Text(line.value, textAlign: TextAlign.end,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: PradoColors.navy,
                        fontSize: 13, fontWeight: line.emphasis
                          ? FontWeight.w900 : FontWeight.w700))),
                  ])),
              ])),
            const Divider(color: PradoColors.line),
            Text('Generado: ${report.generatedLabel} · Hora de Perú',
              style: const TextStyle(color: PradoColors.muted, fontSize: 10)),
            const SizedBox(height: 4),
            const Text('Resumen informativo · Consulta los detalles en Familia Prado',
              style: TextStyle(color: PradoColors.muted, fontSize: 10)),
          ]),
        ),
      );
}

/// Fecha de generación según calendario peruano, independiente del emulador.
String peruReportStamp() {
  final now = DateTime.now().toUtc().subtract(const Duration(hours: 5));
  final day = '${now.day.toString().padLeft(2, '0')}/'
      '${now.month.toString().padLeft(2, '0')}/${now.year}';
  final hour = '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';
  return '$day $hour';
}
