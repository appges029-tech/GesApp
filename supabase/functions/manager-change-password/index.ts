import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
const json = (data: unknown, status=200) => new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json'}})
const strong = (p:string) => p.length>=10 && /[a-z]/.test(p) && /[A-Z]/.test(p) && /[0-9]/.test(p)
Deno.serve(async (req) => {
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors})
  if(req.method!=='POST')return json({error:'method_not_allowed'},405)
  try {
    const url=Deno.env.get('SUPABASE_URL')!, anon=Deno.env.get('SUPABASE_ANON_KEY')??Deno.env.get('SUPABASE_PUBLISHABLE_KEY')!, service=Deno.env.get('SUPABASE_SECRET_KEY')??Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const caller=createClient(url,anon,{global:{headers:{Authorization:req.headers.get('Authorization')??''}}})
    const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}})
    const {data:{user},error:authError}=await caller.auth.getUser()
    if(authError||!user?.email)return json({error:'unauthorized'},401)
    const {data:member,error:membershipError}=await admin.from('organization_members').select('id,organization_id,role,active,status').eq('user_id',user.id).single()
    if(membershipError||!member||member.role!=='manager'||!member.active||member.status!=='active')return json({error:'manager_required'},403)
    const {data:org,error:orgError}=await admin.from('organizations').select('active,subscription_status,subscription_expires_at').eq('id',member.organization_id).single()
    if(orgError||!org?.active||(org.subscription_status!=='legacy'&&(org.subscription_status!=='active'||!org.subscription_expires_at||Date.parse(org.subscription_expires_at)<=Date.now())))return json({error:'subscription_expired'},403)
    const body=await req.json(), current=String(body.current_password??''), next=String(body.new_password??'')
    if(!strong(next)||next===current)return json({error:'invalid_new_password'},400)
    const verifier=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}})
    const {data:verified,error:verifyError}=await verifier.auth.signInWithPassword({email:user.email,password:current})
    if(verifyError||verified.user?.id!==user.id)return json({error:'current_password_invalid'},403)
    const {error:changeError}=await admin.auth.admin.updateUserById(user.id,{password:next})
    if(changeError)return json({error:'password_update_failed'},500)
    const {error:flagError}=await admin.from('organization_members').update({must_change_password:false,updated_at:new Date().toISOString()}).eq('id',member.id).eq('user_id',user.id)
    if(flagError)return json({error:'password_changed_but_confirmation_pending'},500)
    return json({ok:true})
  } catch (_) {return json({error:'password_change_failed'},500)}
})
