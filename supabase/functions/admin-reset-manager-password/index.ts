import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,'Content-Type':'application/json'}})

Deno.serve(async(req)=>{
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors})
  try{
    const url=Deno.env.get('SUPABASE_URL')!
    const pub=Deno.env.get('SUPABASE_ANON_KEY')!
    const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const auth=req.headers.get('Authorization')??''
    const caller=createClient(url,pub,{global:{headers:{Authorization:auth}}})
    const server=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}})

    const {data:{user}}=await caller.auth.getUser()
    if(!user) return json({error:'unauthorized'},401)

    const {data:me}=await server.from('organization_members')
      .select('organization_id,role,active')
      .eq('user_id',user.id).eq('active',true).single()
    if(!me||me.role!=='admin') return json({error:'admin_required'},403)

    const body=await req.json()
    const id=String(body.membership_id??'')
    const password=String(body.temporary_password??'')
    if(password.length<8) return json({error:'password_too_short'},400)

    const {data:target}=await server.from('organization_members')
      .select('id,user_id,organization_id,role')
      .eq('id',id).single()
    if(!target||target.organization_id!==me.organization_id||target.role!=='manager'){
      return json({error:'manager_not_found'},404)
    }

    const {error:ae}=await server.auth.admin.updateUserById(target.user_id,{password})
    if(ae) return json({error:ae.message},400)

    const {error}=await server.from('organization_members')
      .update({must_change_password:true,updated_at:new Date().toISOString()})
      .eq('id',id)
    if(error) return json({error:error.message},400)

    await server.from('devices')
      .delete()
      .eq('organization_id',me.organization_id)
      .eq('user_id',target.user_id)

    return json({ok:true})
  }catch(e){
    return json({error:String(e)},500)
  }
})
