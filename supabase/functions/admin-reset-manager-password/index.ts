import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,'Content-Type':'application/json'}})
const strongPassword=(v:string)=>v.length>=10&&/[a-z]/.test(v)&&/[A-Z]/.test(v)&&/[0-9]/.test(v)
Deno.serve(async(req)=>{if(req.method==='OPTIONS')return new Response('ok',{headers:cors});try{
 const url=Deno.env.get('SUPABASE_URL')!, anon=Deno.env.get('SUPABASE_ANON_KEY')??Deno.env.get('SUPABASE_PUBLISHABLE_KEY')!, service=Deno.env.get('SUPABASE_SECRET_KEY')??Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, auth=req.headers.get('Authorization')??''
 const caller=createClient(url,anon,{global:{headers:{Authorization:auth}}}), admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}})
 const {data:{user}}=await caller.auth.getUser(); if(!user)return json({error:'unauthorized'},401)
 const {data:me}=await admin.from('organization_members').select('organization_id,role,active,status').eq('user_id',user.id).single(); if(!me?.active||me.role!=='admin'||me.status!=='active')return json({error:'admin_required'},403)
 const {data:billingOrg,error:billingError}=await admin.from('organizations').select('active,subscription_status,subscription_expires_at').eq('id',me.organization_id).single(); if(billingError||!billingOrg?.active||(billingOrg.subscription_status!=='legacy'&&(billingOrg.subscription_status!=='active'||!billingOrg.subscription_expires_at||Date.parse(billingOrg.subscription_expires_at)<=Date.now())))return json({error:'subscription_expired'},403)
 const body=await req.json(), id=String(body.membership_id??''), password=String(body.temporary_password??''); if(!strongPassword(password))return json({error:'password_too_weak'},400)
 const {data:target}=await admin.from('organization_members').select('id,user_id,organization_id,role,active,status').eq('id',id).single(); if(!target||target.organization_id!==me.organization_id||target.role!=='manager'||!target.active||target.status!=='active')return json({error:'manager_not_found'},404)
 const {error:flagError}=await admin.from('organization_members').update({must_change_password:true,updated_at:new Date().toISOString()}).eq('id',id).eq('organization_id',me.organization_id); if(flagError)return json({error:'reset_flag_failed'},500)
 const {error:authError}=await admin.auth.admin.updateUserById(target.user_id,{password}); if(authError)return json({error:'password_update_failed_change_required'},500)
 return json({ok:true})
}catch(e){return json({error:String(e)},500)}})
