import 'package:flutter/material.dart';
import '../core/api.dart';
import '../ui/prado_design.dart';
import '../ui/prado_form.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key, required this.api, required this.onLogout});
  final FamilyApi api;
  final VoidCallback onLogout;
  @override State<MembersScreen> createState()=>_MembersScreenState();
}
class _MembersScreenState extends State<MembersScreen> {
  late Future<List<dynamic>> data;
  @override void initState(){super.initState();refresh();}
  void refresh(){
    data=() async {
      final results=await Future.wait<dynamic>([
        widget.api.get('/api/members'),widget.api.get('/api/auth/me'),
      ]);
      final me=results[1] as Map<String,dynamic>;
      results.add(me['role']=='ADMIN'
        ? await widget.api.get('/api/admin/accounts') : <dynamic>[]);
      return results;
    }();
  }
  void reload(){setState(refresh);}
  void notice(Object m){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$m')));}
  Future<void> createAccount(Map<String,dynamic> member)async{
    final email=TextEditingController(),password=TextEditingController();
    try{
      final accepted=await showPradoForm<bool>(context:context,builder:(ctx)=>AlertDialog(insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24), constraints: const BoxConstraints(maxWidth: 560, minWidth: 320), scrollable: true, 
        title:Text('Crear acceso para ${member['name']}'),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:email,keyboardType:TextInputType.emailAddress,
            decoration:const InputDecoration(labelText:'Correo electrónico')),
          const SizedBox(height:12),TextField(controller:password,obscureText:true,
            decoration:const InputDecoration(labelText:'Contraseña inicial (mínimo 8 caracteres)')),
          const SizedBox(height:10),const Text('Comunica la contraseña por un medio privado y solicita que la cambien. No compartas claves en el grupo familiar.'),
        ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Crear cuenta'))]));
      if(accepted==true){await widget.api.post('/api/admin/accounts',{
        'email':email.text.trim(),'initialPassword':password.text,'memberId':member['id'],
      });reload();notice('Cuenta creada. Entrega el acceso a la persona correspondiente.');}
    }catch(e){notice(e);}finally{email.dispose();password.dispose();}
  }
  Future<void> resetMemberAccess(Map<String,dynamic> member, Map<String,dynamic> account) async {
    final password=TextEditingController();
    try {
      final accepted=await showPradoForm<bool>(context:context,builder:(ctx)=>AlertDialog(insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24), constraints: const BoxConstraints(maxWidth: 560, minWidth: 320), scrollable: true, 
        title:Text('Restablecer acceso de ${member['name']}'),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          Text('Cuenta: ${account['email']}'),
          const SizedBox(height:12),
          TextField(controller:password,obscureText:true,
            decoration:const InputDecoration(labelText:'Nueva contraseña (mínimo 8 caracteres)')),
          const SizedBox(height:10),
          const Text('Se cerrarán todas sus sesiones anteriores. Entrega la nueva clave únicamente a esa persona.'),
        ]),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Restablecer'))],
      ));
      if(accepted==true){
        await widget.api.post('/api/admin/accounts/${account['id']}/reset-password',{
          'newPassword':password.text,
        });
        notice('Acceso restablecido; las sesiones anteriores quedaron revocadas.');
      }
    }catch(e){notice(e);}finally{password.dispose();}
  }
  Future<void> changePassword()async{
    final old=TextEditingController(),newPass=TextEditingController();
    try{
      final confirm=await showPradoForm<bool>(context:context,builder:(ctx)=>AlertDialog(insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24), constraints: const BoxConstraints(maxWidth: 560, minWidth: 320), scrollable: true, 
        title:const Text('Cambiar mi contraseña'),content:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:old,obscureText:true,decoration:const InputDecoration(labelText:'Contraseña actual')),
          const SizedBox(height:10),TextField(controller:newPass,obscureText:true,
            decoration:const InputDecoration(labelText:'Nueva contraseña (mínimo 8 caracteres)')),
        ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Cambiar contraseña'))]));
      if(confirm==true){await widget.api.post('/api/auth/change-password',{
        'currentPassword':old.text,'newPassword':newPass.text});
        await widget.api.logout(localOnly:true);if(mounted)widget.onLogout();}
    }catch(e){notice(e);}finally{old.dispose();newPass.dispose();}
  }
  @override Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: data, builder: (context, snap) {
      if (!snap.hasData) return Center(child: snap.hasError
        ? Text('No se pudieron cargar los familiares: ${snap.error}')
        : const CircularProgressIndicator());
      final members = snap.data![0] as List;
      final me = snap.data![1] as Map<String, dynamic>;
      final accounts = (snap.data![2] as List).cast<Map<String,dynamic>>();
      final ordered = [...members]..sort((a, b) =>
        ((a['position'] as num?)?.toInt() ?? 0).compareTo(
          (b['position'] as num?)?.toInt() ?? 0));
      return RefreshIndicator(onRefresh: () async { reload(); await data; },
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const PradoIntro(eyebrow: 'Siempre juntos', title: 'Nuestra familia',
            subtitle: 'Ocho hermanos organizados para acompañar a Papá Isidro.',
            icon: Icons.family_restroom_outlined, tint: PradoColors.peach),
          PradoPanel(tint: PradoColors.paleBlue,
            child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(
                color: PradoColors.navy, borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.person_outline, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(me['role'] == 'ADMIN' ? 'Cuenta Administrador' : 'Mi cuenta',
                    style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 3),
                  Text('${me['email']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PradoColors.muted, fontSize: 14)),
                  const SizedBox(height: 6),
                  const Text('El acceso es personal y privado.',
                    style: TextStyle(color: PradoColors.muted, fontSize: 13)),
                ])),
            ])),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: changePassword,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Cambiar mi contraseña')),
          const SizedBox(height: 18),
          PradoSectionHeading('Los ocho hijos',
            subtitle: 'Nombres y orden en el calendario familiar.'),
          for (var i = 0; i < ordered.length; i++)
            Padding(padding: const EdgeInsets.only(bottom: 10),
              child: PradoPanel(child: Row(children: [
                Container(height: 54, width: 54,
                  decoration: BoxDecoration(color: i.isEven
                    ? PradoColors.mint : PradoColors.paleSand,
                    borderRadius: BorderRadius.circular(17)),
                  child: Center(child: Text(
                    '${ordered[i]['name']}'.isNotEmpty
                      ? '${ordered[i]['name']}'.substring(0, 1).toUpperCase() : '?',
                    style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800,
                      color: PradoColors.navy)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${ordered[i]['name']}',
                      style: Theme.of(context).textTheme.titleSmall),
                    Text('Turno ${(ordered[i]['position'] ?? i+1)} en la rotación',
                      style: const TextStyle(color: PradoColors.muted, fontSize: 14)),
                  ])),
                if (me['role'] == 'ADMIN') Builder(builder: (context) {
                  final member = Map<String,dynamic>.from(ordered[i] as Map);
                  Map<String,dynamic>? account;
                  for (final candidate in accounts) {
                    if (candidate['memberId']==member['id']) { account=candidate; break; }
                  }
                  if (account == null) return IconButton(
                    tooltip: 'Crear una cuenta para ${member['name']}',
                    icon: const Icon(Icons.person_add_alt_1_outlined,
                      color: PradoColors.ocean),
                    onPressed: () => createAccount(member));
                  final current=account;
                  return IconButton(
                    tooltip: 'Restablecer acceso de ${member['name']}',
                    icon: const Icon(Icons.lock_reset_outlined,
                      color: PradoColors.ocean),
                    onPressed: () => resetMemberAccess(member,current));
                })
                else const Icon(Icons.favorite_outline, color: PradoColors.coral),
              ]))),
          const SizedBox(height: 16),
          PradoPanel(tint: PradoColors.paleSand,
            child: const PradoInfoRow(icon: Icons.shield_outlined,
              text: 'Las contraseñas y los documentos médicos son privados. '
                'No compartas tu acceso por WhatsApp.')),
          const SizedBox(height: 24),
        ]));
    });
}
