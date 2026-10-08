import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
const json = (body: unknown, status=200) => new Response(JSON.stringify(body), {status, headers:{...cors,'Content-Type':'application/json'}})
const normalize = (v:string) => v.trim().toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'')
const strongPassword=(v:string)=>v.length>=10&&/[a-z]/.test(v)&&/[A-Z]/.test(v)&&/[0-9]/.test(v)

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok',{headers:cors})
  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY')!
    const service = Deno.env.get('SUPABASE_SECRET_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const authHeader = req.headers.get('Authorization') ?? ''
    const caller = createClient(url, anon, {global:{headers:{Authorization:authHeader}}})
    const admin = createClient(url, service, {auth:{persistSession:false,autoRefreshToken:false}})
    const {data:{user},error:userError} = await caller.auth.getUser()
    if (userError || !user) return json({error:'unauthorized'},401)
    const {data:membership,error:memberError} = await admin.from('organization_members').select('organization_id,role,active').eq('user_id',user.id).single()
    if (memberError || !membership?.active || membership.role !== 'admin') return json({error:'admin_required'},403)
    const {data:org,error:orgError} = await admin.from('organizations').select('code').eq('id',membership.organization_id).single()
    if (orgError || !org) return json({error:'organization_not_found'},404)
    const body = await req.json()
    const username = normalize(String(body.username ?? ''))
    const displayName = String(body.display_name ?? '').trim()
    const password = String(body.temporary_password ?? '')
    if (username.length < 3 || !displayName || !strongPassword(password)) return json({error:'invalid_payload'},400)
    const email = `manager.${normalize(org.code)}.${username}@auth.gesapp.invalid`
    const {data:created,error:createError} = await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{gesapp_username:username,gesapp_org:org.code,display_name:displayName}})
    if (createError || !created.user) return json({error:createError?.message ?? 'auth_user_creation_failed'},409)
    const {data:row,error:insertError} = await admin.from('organization_members').insert({organization_id:membership.organization_id,user_id:created.user.id,username,display_name:displayName,role:'manager',active:true,must_change_password:true,created_by:user.id}).select('id,user_id,username,display_name,active,must_change_password').single()
    if (insertError) {
      await admin.auth.admin.deleteUser(created.user.id)
      return json({error:insertError.message},409)
    }
    return json(row,201)
  } catch (e) { return json({error:String(e)},500) }
})
