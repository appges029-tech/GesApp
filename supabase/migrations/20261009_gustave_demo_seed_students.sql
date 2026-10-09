
-- Établissement Gustave Flaubert : jeu fictif mis en attente d'import explicite.
-- Les écoles réelles conservent leur snapshot .gesync intact.
create table if not exists public.tenant_demo_seed_students (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  seed_code text not null,
  first_name text not null,
  last_name text not null,
  classroom text not null,
  cycle text not null,
  gender text check (gender in ('M', 'F')),
  birth_date date,
  birth_place text,
  guardian_name text,
  guardian_phone text,
  family_name text,
  nationality text,
  address text,
  origin_school text,
  created_at timestamptz not null default now(),
  primary key (organization_id, seed_code)
);
alter table public.tenant_demo_seed_students enable row level security;
revoke all on public.tenant_demo_seed_students from anon, authenticated;
grant select on public.tenant_demo_seed_students to authenticated;
drop policy if exists "tenant_managers_read_demo_students" on public.tenant_demo_seed_students;
create policy "tenant_managers_read_demo_students"
on public.tenant_demo_seed_students
for select to authenticated
using ((select private.is_active_manager(organization_id)));

comment on table public.tenant_demo_seed_students is
 'Only clearly marked synthetic school test data, with explicit in-app import. No overwrite of encrypted snapshots.';

with grades(ord,cycle,classroom,birth_year) as (
  values
  (1,'Primaire','CP1',2019),(2,'Primaire','CP2',2018),
  (3,'Primaire','CE1',2017),(4,'Primaire','CE2',2016),
  (5,'Primaire','CM1',2015),(6,'Primaire','CM2',2014),
  (7,'Collège','6e',2013),(8,'Collège','5e',2012),
  (9,'Collège','4e',2011),(10,'Collège','3e',2010),
  (11,'Lycée','Seconde',2009),(12,'Lycée','Première',2008),
  (13,'Lycée','Terminale',2007)
),
numbered as (
 select grades.*, gs.idx, ((grades.ord-1)*20+gs.idx)::int as rn
 from grades cross join lateral generate_series(1,20) gs(idx)
),
synthetics as (
 select
  'b38efacc-4fa1-4ffe-8989-e936a90fc197'::uuid as organization_id,
  'GUSTAVE-DEMO-2026-'||lpad(rn::text,3,'0') as seed_code,
  'DEMO '||(array[
   'Aline','Samuel','Audrey','Emmanuel','Grâce','Jonathan','Ruth','David',
   'Nadia','Isaac','Esther','Daniel','Sarah','Paul','Chloé','Junior',
   'Élodie','Pierre','Marie','Benjamin'
  ])[((rn-1)%20)+1]||'-'||lpad(rn::text,3,'0') as first_name,
  'TEST-'||(array[
   'Mabiala','Makosso','Mboungou','Banzouzi','Moukoko','Nkouka',
   'Mavoungou','Milandou','Ngalula','Ntsemou','Massamba','Matsima',
   'Moutou','Itoua','Nzaba','Ondongo','Kimbouala','Yoka',
   'Bouanga','Loubaki','Bikindou','Moukala','Tsiba','Dinga',
   'Nkoumbou','Koumba'
  ])[((rn-1)%26)+1] as last_name,
  classroom,cycle,
  case when rn%2=1 then 'F' else 'M' end as gender,
  make_date(birth_year,((rn-1)%12)+1,((rn-1)%27)+1) as birth_date,
  'Brazzaville' as birth_place,
  'Tuteur DEMO '||lpad((((rn-1)%130)+1)::text,3,'0') as guardian_name,
  null::text as guardian_phone,
  'FAMILLE-DEMO-'||lpad((((rn-1)%130)+1)::text,3,'0') as family_name,
  'Congolaise' as nationality,
  'Brazzaville - adresse fictive' as address,
  'Ecole fictive' as origin_school
 from numbered
)
insert into public.tenant_demo_seed_students (
 organization_id,seed_code,first_name,last_name,classroom,cycle,gender,
 birth_date,birth_place,guardian_name,guardian_phone,family_name,nationality,address,origin_school
)
select organization_id,seed_code,first_name,last_name,classroom,cycle,gender,
       birth_date,birth_place,guardian_name,guardian_phone,family_name,nationality,address,origin_school
from synthetics
on conflict (organization_id,seed_code) do nothing;
