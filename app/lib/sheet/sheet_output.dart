// Copyright (c) 2026 Vassel Goleyu. MIT License.
import 'package:hairline_core/hairline_core.dart';
import 'package:printing/printing.dart';

import 'sheet_pdf.dart';

/// Prints or shares the sheet PDF. An interface so that screens can be tested without the
/// platform printing plugin.
abstract interface class SheetOutput {
  Future<void> print(int sheetId, PaperSize paper);
  Future<void> share(int sheetId, PaperSize paper);
  Future<void> printPlate(PaperSize paper);
  Future<void> sharePlate(PaperSize paper);
}

/// The real thing (`printing`). Platform failures surface as exceptions the screen reports.
class PrintingSheetOutput implements SheetOutput {
  const PrintingSheetOutput();

  @override
  Future<void> print(int sheetId, PaperSize paper) async {
    final bytes = await buildSheetPdf(sheetId, paper);
    await Printing.layoutPdf(onLayout: (_) => bytes, name: 'hairline-lembar-$sheetId.pdf');
  }

  @override
  Future<void> share(int sheetId, PaperSize paper) async {
    final bytes = await buildSheetPdf(sheetId, paper);
    await Printing.sharePdf(bytes: bytes, filename: 'hairline-lembar-$sheetId.pdf');
  }

  @override
  Future<void> printPlate(PaperSize paper) async {
    final bytes = await buildPlatePdf(paper);
    await Printing.layoutPdf(onLayout: (_) => bytes, name: 'hairline-pelat-validasi.pdf');
  }

  @override
  Future<void> sharePlate(PaperSize paper) async {
    final bytes = await buildPlatePdf(paper);
    await Printing.sharePdf(bytes: bytes, filename: 'hairline-pelat-validasi.pdf');
  }
}
