import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/ui/family_report.dart';

void main() {
  testWidgets('Vista previa conserva las líneas y permite cambiar imagen', (tester) async {
    final reports = [
      FamilyReport(title:'Agenda', subtitle:'Semana', mainLabel:'Citas', mainValue:'6',
        expanded:true, lines:List.generate(6,(i)=>ReportLine('Cita ${i+1}','Responsable ${i+1}')),
        generatedLabel:'23/11/2026 12:00'),
      const FamilyReport(title:'Continuación', subtitle:'Semana', mainLabel:'Citas',mainValue:'6',
        expanded:true, lines:[ReportLine('Última cita','Carlos')],generatedLabel:'23/11/2026 12:00'),
    ];
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(context)=>
      TextButton(onPressed:()=>showFamilyReportPages(context,reports),child:const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Imagen 1 de 2'),findsOneWidget);
    expect(find.text('Cita 6'),findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('Imagen 2 de 2'),findsOneWidget);
    expect(find.text('Última cita'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
