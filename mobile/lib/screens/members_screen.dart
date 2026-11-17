import 'package:flutter/material.dart';
import '../core/api.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key, required this.api, required this.onLogout});
  final FamilyApi api;
  final VoidCallback onLogout;
  @override State<MembersScreen> createState()=>_MembersScreenState();
}
class _MembersScreenState extends State<MembersScreen> {
  late Future<List<dynamic>> data;
  @override void initState(){super.initState();refresh();}
  void refresh(){data=Future.wait([widget.api.get('/api/members'),widget.api.get('/api/auth/me')]);}
  void reload(){setState(refresh);}
  void notice(Object m){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$m')));}
  Future<void> createAccount(Map<String,dynamic> member)async{
    final email=TextEditingController(),password=TextEditingController();
    try{
      final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:Text('Crear acceso para ${member['name']}'),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:email,keyboardType:TextInputType.emailAddress,
            decoration:const InputDecoration(labelText:'Correo electrónico')),
          const SizedBox(height:12),TextField(controller:password,obscureText:true,
            decoration:const InputDecoration(labelText:'Contraseña inicial (mínimo 12 caracteres)')),
          const SizedBox(height:10),const Text('Comunica la contraseña por un medio privado y solicita que la cambien. No compartas claves en el grupo familiar.'),
        ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Crear cuenta'))]));
      if(accepted==true){await widget.api.post('/api/admin/accounts',{
        'email':email.text.trim(),'initialPassword':password.text,'memberId':member['id'],
      });reload();notice('Cuenta creada. Entrega el acceso a la persona correspondiente.');}
    }catch(e){notice(e);}finally{email.dispose();password.dispose();}
  }
  Future<void> changePassword()async{
    final old=TextEditingController(),newPass=TextEditingController();
    try{
      final confirm=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Cambiar mi contraseña'),content:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:old,obscureText:true,decoration:const InputDecoration(labelText:'Contraseña actual')),
          const SizedBox(height:10),TextField(controller:newPass,obscureText:true,
            decoration:const InputDecoration(labelText:'Nueva contraseña (12 caracteres o más)')),
        ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Cambiar contraseña'))]));
      if(confirm==true){await widget.api.post('/api/auth/change-password',{
        'currentPassword':old.text,'newPassword':newPass.text});
        await widget.api.logout(localOnly:true);if(mounted)widget.onLogout();}
    }catch(e){notice(e);}finally{old.dispose();newPass.dispose();}
  }
  @override Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future:data,builder:(ctx,snap){
    if(!snap.hasData)return Center(child:snap.hasError?Text('${snap.error}'):const CircularProgressIndicator());
    final members=snap.data![0] as List,me=snap.data![1] as Map<String,dynamic>;
    return RefreshIndicator(onRefresh:()async{reload();await data;},child:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Tu cuenta: ${me['email']}',style:const TextStyle(fontWeight:FontWeight.bold)),
          const SizedBox(height:8),Text(me['role']=='ADMIN'?'Administrador familiar':'Miembro de la familia'),
          TextButton.icon(onPressed:changePassword,icon:const Icon(Icons.key),
            label:const Text('Cambiar mi contraseña')),
        ]))),
      const SizedBox(height:12),Text('Los ocho hijos',style:Theme.of(context).textTheme.titleLarge),
      const Text('Orden inicial provisional: debe confirmarse antes de registrar turnos reales.'),
      const SizedBox(height:10),
      ...members.map((m)=>Card(child:ListTile(
        leading:CircleAvatar(child:Text('${m['position']}')),
        title:Text(m['name'],style:const TextStyle(fontSize:18,fontWeight:FontWeight.w600)),
        subtitle:Text('Lugar ${m['position']} en la rotación'),
        trailing:me['role']=='ADMIN'?IconButton(tooltip:'Crear acceso a ${m['name']}',
          icon:const Icon(Icons.person_add_alt),onPressed:()=>createAccount(m)):null,
      ))),
      const SizedBox(height:12),
      const Text('El acceso de la familia es privado. Ninguna contraseña debe compartirse en el grupo de WhatsApp.'),
    ]));
  });
}
