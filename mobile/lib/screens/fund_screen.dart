import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/live_updates.dart';
import '../ui/prado_design.dart';
import '../ui/prado_form.dart';
import '../ui/family_report.dart';
import '../ui/period_reports.dart';

class FundScreen extends StatefulWidget {
  const FundScreen({super.key,required this.api, required this.updates});
  final FamilyApi api;
  final LiveUpdates updates;
  @override State<FundScreen> createState()=>_FundScreenState();
}
class _FundScreenState extends State<FundScreen> {
  late Future<List<dynamic>> data;
  @override void initState(){
    super.initState();
    refresh();
    widget.updates.addListener(_onUpdate);
  }
  void _onUpdate() {
    if (widget.updates.lastTopic == 'fund' || widget.updates.lastTopic == 'all') {
      if (mounted) reload();
    }
  }
  @override void dispose() {
    widget.updates.removeListener(_onUpdate);
    super.dispose();
  }
  void refresh(){data=Future.wait([
    widget.api.get('/api/fund/summary'),widget.api.get('/api/fund/collections'),
    widget.api.get('/api/fund/expenses'),widget.api.get('/api/auth/me'),widget.api.get('/api/members'),
  ]);}
  void reload(){setState(refresh);}
  void notice(Object error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$error')));}
  Future<void> collect() async {
    final concept=TextEditingController(),amount=TextEditingController();
    try{
      final accept=await showPradoForm<bool>(context:context,builder:(ctx)=>AlertDialog(insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24), constraints: const BoxConstraints(maxWidth: 560, minWidth: 320), scrollable: true, 
        title:const Text('Nueva colecta familiar'),content:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:concept,decoration:const InputDecoration(labelText:'¿Para qué se necesita el dinero?')),
          const SizedBox(height:10),TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),
            decoration:const InputDecoration(labelText:'Monto por cada hijo (soles)')),
        ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Crear colecta'))]));
      if(accept==true){await widget.api.post('/api/fund/collections',{
        'concept':concept.text.trim(),'amountPerMember':double.tryParse(amount.text.replaceAll(',','.')),
      });reload();notice('Colecta creada');}
    }catch(e){notice(e);}finally{concept.dispose();amount.dispose();}
  }
  Future<void> contribute(String collectionId,Map<String,dynamic> me,List<dynamic> members) async {
    final amount=TextEditingController(),reference=TextEditingController();
    String? memberId=(me['memberId'] as String?);
    if(memberId==null&&members.isNotEmpty)memberId=members.first['id'];
    String method='YAPE';
    try{
      final accept=await showPradoForm<bool>(context:context,builder:(ctx)=>StatefulBuilder(
        builder:(ctx,redraw)=>AlertDialog(insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24), constraints: const BoxConstraints(maxWidth: 560, minWidth: 320), scrollable: true, title:const Text('Registrar un aporte'),content:
          SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
            if(me['role']=='ADMIN') DropdownButtonFormField<String>(initialValue:memberId,
              decoration:const InputDecoration(labelText:'¿Quién aportó?'),
              items:members.map((m)=>DropdownMenuItem<String>(value:m['id'],child:Text(m['name']))).toList(),
              onChanged:(v)=>redraw(()=>memberId=v)),
            const SizedBox(height:12),TextField(controller:amount,
              decoration:const InputDecoration(labelText:'Importe aportado en soles'),
              keyboardType:const TextInputType.numberWithOptions(decimal:true)),
            const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:method,
              decoration:const InputDecoration(labelText:'Forma de pago'),
              items:const [DropdownMenuItem(value:'YAPE',child:Text('Yape')),
                DropdownMenuItem(value:'PLIN',child:Text('Plin')),
                DropdownMenuItem(value:'TRANSFER',child:Text('Transferencia')),
                DropdownMenuItem(value:'CASH',child:Text('Efectivo'))],
              onChanged:(v){if(v!=null)redraw(()=>method=v);}),
            const SizedBox(height:12),TextField(controller:reference,
              decoration:const InputDecoration(labelText:'Referencia de pago (opcional)')),
            const SizedBox(height:8),const Text('El dinero se sumará a la caja cuando administración confirme el aporte.'),
          ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
            FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Guardar aporte'))])));
      if(accept==true&&memberId!=null){await widget.api.post('/api/fund/collections/$collectionId/contributions',{
        'memberId':memberId,'amount':double.tryParse(amount.text.replaceAll(',','.')),
        'paymentMethod':method,'paymentReference':reference.text.trim(),
      });reload();notice('Aporte enviado para verificación');}
    }catch(e){notice(e);}finally{amount.dispose();reference.dispose();}
  }
  Future<void> expense() async {
    final concept=TextEditingController(),amount=TextEditingController(),receipt=TextEditingController();
    try{
      final accept=await showPradoForm<bool>(context:context,builder:(ctx)=>AlertDialog(insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24), constraints: const BoxConstraints(maxWidth: 560, minWidth: 320), scrollable: true, title:const Text('Solicitar un gasto'),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:concept,decoration:const InputDecoration(labelText:'Descripción de la compra')),
          const SizedBox(height:12),TextField(controller:amount,
            decoration:const InputDecoration(labelText:'Importe en soles'),
            keyboardType:const TextInputType.numberWithOptions(decimal:true)),
          const SizedBox(height:12),TextField(controller:receipt,
            decoration:const InputDecoration(labelText:'Número o referencia de boleta (opcional)')),
          const SizedBox(height:10),const Text('Por ahora no hay carga de imágenes: guarda la referencia de la boleta y conserva el comprobante.'),
        ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Enviar solicitud'))]));
      if(accept==true){await widget.api.post('/api/fund/expenses',{
        'concept':concept.text,'amount':double.tryParse(amount.text.replaceAll(',','.')),
        'receiptReference':receipt.text,
      });reload();notice('Gasto enviado para revisión');}
    }catch(e){notice(e);}finally{concept.dispose();amount.dispose();receipt.dispose();}
  }
  Future<void> review(String path,bool accept)async{
    try{await widget.api.post(path,{'accept':accept});reload();notice('Operación registrada');}
    catch(e){notice(e);}
  }
  Future<void> _shareFundReport() async {
    try {
      final now = peruToday();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 0);
      final report = await widget.api.get(
        '/api/fund/report?from=${isoDate(start)}&to=${isoDate(end)}',
      ) as Map<String, dynamic>;
      if (!mounted) return;
      final rows = <ReportLine>[
        ReportLine('Saldo al inicio del mes', pradoMoney(report['opening'])),
        ReportLine('Aportes verificados', '+ ${pradoMoney(report['verified'])}'),
        ReportLine('Gastos aprobados', '- ${pradoMoney(report['approved'])}'),
      ];
      final movements = report['recentMovements'] as List? ?? [];
      for (final movement in movements.take(2)) {
        final m = movement as Map;
        rows.add(ReportLine(
          '${m['kind'] == 'IN' ? 'Aporte: ' : 'Gasto: '}${m['concept']}',
          '${m['kind'] == 'IN' ? '+' : '-'} ${pradoMoney(m['amount'])}',
        ));
      }
      await showFamilyReport(context, FamilyReport(
        title: 'Resumen de caja familiar',
        subtitle: 'Del ${dateSpanish(start)} al ${dateSpanish(end)}',
        mainLabel: 'SALDO AL CIERRE DEL PERIODO',
        mainValue: pradoMoney(report['closing']),
        lines: rows,
        generatedLabel: peruReportStamp(),
        privacy: 'Solo se contabilizan aportes verificados y gastos aprobados. '
            'Al compartir una imagen, sus datos salen de la aplicación.',
      ));
    } catch (e) {
      notice('No se pudo preparar el reporte de caja: $e');
    }
  }

  @override Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: data, builder: (context, snap) {
      if (!snap.hasData) return Center(child: snap.hasError
        ? Text('No se pudo abrir la caja: ${snap.error}')
        : const CircularProgressIndicator());
      final summary = snap.data![0] as Map<String, dynamic>;
      final collections = snap.data![1] as List;
      final expenses = snap.data![2] as List;
      final me = snap.data![3] as Map<String, dynamic>;
      final members = snap.data![4] as List;
      final names = {for (final m in members) m['id']: m['name']};
      return RefreshIndicator(onRefresh: () async { reload(); await data; },
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const PradoIntro(eyebrow: 'Organización familiar', title: 'Caja compartida',
            subtitle: 'Cada aporte y gasto, siempre claro.',
            icon: Icons.savings_outlined, tint: PradoColors.mint),
          Container(padding: const EdgeInsets.all(21),
            decoration: BoxDecoration(color: PradoColors.navy,
              borderRadius: BorderRadius.circular(24)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DISPONIBLE EN CAJA', style: TextStyle(
                color: Color(0xFFE7EDF3), fontWeight: FontWeight.w700,
                letterSpacing: 1.3, fontSize: 12)),
              const SizedBox(height: 7),
              Text(pradoMoney(summary['available']), style: const TextStyle(
                color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
              const SizedBox(height: 17),
              Wrap(spacing: 12, runSpacing: 10, children: [
                _totalLabel(Icons.add_circle_outline, 'Aportes verificados',
                  pradoMoney(summary['collected'])),
                _totalLabel(Icons.remove_circle_outline, 'Gastos aprobados',
                  pradoMoney(summary['spent'])),
              ]),
            ])),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _shareFundReport,
            icon: const Icon(Icons.ios_share_outlined),
            label: const Text('Generar resumen en imagen')),
          const SizedBox(height: 15),
          if (me['role'] == 'ADMIN') ...[
            FilledButton.icon(onPressed: collect, icon: const Icon(Icons.add),
              label: const Text('Crear colecta')),
            const SizedBox(height: 12),
          ],
          PradoSectionHeading('Colectas',
            subtitle: 'Los aportes pendientes aún no suman al saldo.'),
          if (collections.isEmpty) const PradoEmpty(title: 'Sin colectas',
            detail: 'Cuando se cree una colecta familiar aparecerá aquí.',
            icon: Icons.handshake_outlined),
          for (final collection in collections) Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Card(clipBehavior: Clip.antiAlias, child: ExpansionTile(
              leading: Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: PradoColors.paleSand,
                  borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.volunteer_activism_outlined,
                  color: PradoColors.navy)),
              title: Text('${collection['concept']}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              subtitle: Text('${pradoMoney(collection['amountPerMember'])} por familiar',
                style: const TextStyle(color: PradoColors.muted, fontSize: 15)),
              children: [Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 15),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  OutlinedButton.icon(onPressed: () => shareCollectionReport(context, widget.api, '${collection['id']}'),
                    icon: const Icon(Icons.ios_share_outlined), label: const Text('Compartir reporte de colecta')),
                  OutlinedButton.icon(
                    onPressed: () => contribute(collection['id'], me, members),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Registrar aporte')),
                  FutureBuilder<dynamic>(
                    future: widget.api.get('/api/fund/collections/${collection['id']}/contributions'),
                    builder: (context, paymentsSnap) {
                      if (!paymentsSnap.hasData) return const Padding(
                        padding: EdgeInsets.all(12), child: Text('Cargando aportes…'));
                      final payments = paymentsSnap.data as List;
                      if (payments.isEmpty) return const Padding(
                        padding: EdgeInsets.all(12), child: Text('Todavía no hay aportes.'));
                      return Column(children: [for (final p in payments) Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: PradoPanel(tint: PradoColors.cream,
                          padding: const EdgeInsets.all(13), child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text('${names[p['memberId']] ?? 'Familiar'} · '
                                '${pradoMoney(p['amount'])}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                              _paymentPill('${p['status']}'),
                            ]),
                            if (me['role'] == 'ADMIN' && p['status'] == 'SUBMITTED')
                              Wrap(spacing: 8, children: [
                                TextButton.icon(onPressed: () => review(
                                  '/api/fund/contributions/${p['id']}/review', true),
                                  icon: const Icon(Icons.check), label: const Text('Confirmar')),
                                TextButton.icon(onPressed: () => review(
                                  '/api/fund/contributions/${p['id']}/review', false),
                                  icon: const Icon(Icons.close), label: const Text('Rechazar')),
                              ]),
                          ]))),
                      ]);
                    },
                  ),
                ])),
              ],
            )),
          ),
          const SizedBox(height: 12),
          PradoSectionHeading('Gastos',
            subtitle: 'Quién lo registró, importe y estado de revisión.',
            action: IconButton(tooltip: 'Actualizar gastos', onPressed: reload,
              icon: const Icon(Icons.refresh))),
          OutlinedButton.icon(onPressed: expense, icon: const Icon(Icons.add),
            label: const Text('Registrar compra o gasto')),
          const SizedBox(height: 12),
          if (expenses.isEmpty) const PradoEmpty(title: 'Sin gastos',
            detail: 'Las compras aparecerán aquí para que todos puedan consultarlas.',
            icon: Icons.receipt_long_outlined),
          for (final e in expenses) Padding(padding: const EdgeInsets.only(bottom: 11),
            child: PradoPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${e['concept']}', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(pradoMoney(e['amount']), style: const TextStyle(
                        fontSize: 22, color: PradoColors.navy, fontWeight: FontWeight.w800)),
                    ])),
                  _expensePill('${e['status']}'),
                ]),
                const SizedBox(height: 11),
                PradoInfoRow(icon: Icons.person_outline,
                  text: 'Registrado por ${e['registeredBy'] ?? 'No disponible'}'),
                if (e['createdAt'] != null)
                  PradoInfoRow(icon: Icons.schedule_outlined,
                    text: 'Fecha: ${dateSpanish(peruClock(e['createdAt'] as String))}'),
                if (e['reviewedBy'] != null)
                  PradoInfoRow(icon: Icons.verified_user_outlined,
                    text: 'Revisado por ${e['reviewedBy']}'),
                if (me['role'] == 'ADMIN' && e['status'] == 'REQUESTED') ...[
                  const Divider(height: 18, color: PradoColors.line),
                  Wrap(spacing: 7, children: [
                    FilledButton.icon(onPressed: () => review(
                      '/api/fund/expenses/${e['id']}/review', true),
                      icon: const Icon(Icons.check, size: 18), label: const Text('Aprobar')),
                    OutlinedButton.icon(onPressed: () => review(
                      '/api/fund/expenses/${e['id']}/review', false),
                      icon: const Icon(Icons.close, size: 18), label: const Text('Rechazar')),
                  ]),
                ],
              ]))),
          const SizedBox(height: 24),
        ]));
    });

  Widget _totalLabel(IconData icon, String label, String value) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: const Color(0xFFF0D49F), size: 16),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ]),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white,
        fontWeight: FontWeight.w800, fontSize: 16)),
    ]),
  );

  Widget _paymentPill(String status) => switch (status) {
    'VERIFIED' => const PradoPill('Confirmado', icon: Icons.check),
    'REJECTED' => const PradoPill('Rechazado', color: PradoColors.coral,
      tint: PradoColors.peach, icon: Icons.close),
    _ => const PradoPill('Por verificar', color: PradoColors.ocean,
      tint: PradoColors.paleBlue, icon: Icons.pending_outlined),
  };

  Widget _expensePill(String status) => switch (status) {
    'APPROVED' => const PradoPill('Aprobado', icon: Icons.check),
    'REJECTED' => const PradoPill('Rechazado', color: PradoColors.coral,
      tint: PradoColors.peach, icon: Icons.close),
    _ => const PradoPill('En revisión', color: PradoColors.ocean,
      tint: PradoColors.paleBlue, icon: Icons.pending_outlined),
  };
}
