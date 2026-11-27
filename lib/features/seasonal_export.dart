import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import '../core/api.dart';

Uint8List seasonalExcel(String source) {
  source = source
      .replaceFirst('\uFEFF', '')
      .replaceFirst(RegExp(r'\r?\n$'), '');
  final rows = CsvToListConverter(
    shouldParseNumbers: false,
    allowInvalid: false,
    eol: source.contains('\r\n') ? '\r\n' : '\n',
  ).convert(source);
  if (rows.isEmpty ||
      rows.first.join(',') !=
          'invoice_id,product_id,product_name,paid_date,quantity,season,holiday' ||
      rows.any((row) => row.length != 7)) {
    throw const ApiError(400, 'Dữ liệu xuất chưa đúng định dạng. Hãy tải lại.');
  }
  rows[0] = [
    'Mã đơn',
    'Mã mẫu hoa',
    'Mẫu hoa',
    'Ngày thanh toán',
    'Số bó',
    'Mùa',
    'Dịp lễ',
  ];
  String xml(String value) => value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  final sheet = StringBuffer();
  for (var i = 0; i < rows.length; i++) {
    sheet.write('<row r="${i + 1}">');
    for (var j = 0; j < 7; j++) {
      final value = '${rows[i][j]}',
          ref = '${String.fromCharCode(65 + j)}${i + 1}';
      if (i > 0 && j == 4 && RegExp(r'^\d+$').hasMatch(value)) {
        sheet.write('<c r="$ref"><v>$value</v></c>');
      } else {
        sheet.write(
          '<c r="$ref" t="inlineStr"${i == 0 ? ' s="1"' : ''}><is><t xml:space="preserve">${xml(value)}</t></is></c>',
        );
      }
    }
    sheet.write('</row>');
  }
  final files = <String, String>{
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
    '_rels/.rels':
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml':
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Doanh số" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'xl/styles.xml':
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF174C3C"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFill="1" applyFont="1"/></cellXfs></styleSheet>',
    'xl/worksheets/sheet1.xml':
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="2" width="38" customWidth="1"/><col min="3" max="3" width="38" customWidth="1"/><col min="4" max="7" width="18" customWidth="1"/></cols><sheetData>$sheet</sheetData><autoFilter ref="A1:G${rows.length}"/></worksheet>',
  };
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
