// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'dart:typed_data';

import 'package:hairline_core/hairline_core.dart';
import 'package:pdf/pdf.dart';

import '../l10n/strings.dart';

/// Points per millimetre.
const double ptPerMm = 72 / 25.4;

/// Labels printed on the sheet, from the Indonesian catalog.
SheetLabels sheetLabels(int sheetId) => SheetLabels(
      title: Strings.sheetPrintedTitle(sheetId),
      cutHint: Strings.sheetPrintedCutHint,
      scaleBar: Strings.sheetPrintedScaleBar,
      printNotes: Strings.sheetPrintedNotes,
    );

/// Builds the PDF of sheet [sheetId] on [paper]: the layout of the core, vector only, one
/// page of exactly the paper size, at nominal size (the user prints it at 100 percent).
/// [compress] false keeps the content stream readable (tests).
Future<Uint8List> buildSheetPdf(int sheetId, PaperSize paper, {bool compress = true}) async {
  final doc = PdfDocument(compress: compress);
  final format = PdfPageFormat(paper.widthMm * ptPerMm, paper.heightMm * ptPerMm);
  final page = PdfPage(doc, pageFormat: format);
  final g = page.getGraphics();
  final regular = PdfFont.helvetica(doc), bold = PdfFont.helveticaBold(doc);

  // PDF y points up; the layout's y points down from the top of the page.
  double y(double mm) => format.height - mm * ptPerMm;
  for (final p in buildSheetLayout(sheetId, paper, sheetLabels(sheetId))) {
    switch (p) {
      case SheetRect():
        g
          ..setFillColor(p.black ? PdfColors.black : PdfColors.white)
          ..drawRect(p.x * ptPerMm, y(p.y + p.h), p.w * ptPerMm, p.h * ptPerMm)
          ..fillPath();
      case SheetLine():
        g
          ..setStrokeColor(PdfColors.black)
          ..setLineWidth(p.strokeMm * ptPerMm)
          ..setLineDashPattern(p.dashed ? [cutDashMm * ptPerMm, cutGapMm * ptPerMm] : const [])
          ..moveTo(p.x1 * ptPerMm, y(p.y1))
          ..lineTo(p.x2 * ptPerMm, y(p.y2))
          ..strokePath();
      case SheetText():
        final font = p.bold ? bold : regular;
        final width = font.stringMetrics(p.text).width * p.sizePt;
        g
          ..setFillColor(PdfColors.black)
          ..drawString(font, p.sizePt, p.text, p.x * ptPerMm - (p.align == SheetTextAlign.center ? width / 2 : 0), y(p.y));
    }
  }
  return doc.save();
}

