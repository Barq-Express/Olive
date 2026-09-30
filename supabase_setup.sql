-- ============================================================
-- Mr. Delivery — Supabase setup
-- شغّل هذا الملف كاملاً مرة واحدة في: Supabase → SQL Editor → New query → Run
-- ============================================================

-- 1) جدول الحالة (صف واحد يحمل كل بيانات النظام)
create table if not exists public.app_state (
  id int primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- 2) البيانات الأولية (مناديب تجريبية) — تُدرج مرة واحدة فقط
insert into public.app_state (id, data)
values (1, '{"version": 3, "riders": [{"id": "r1", "name": "أحمد البلوشي", "phone": "92001001", "civil": "11111111", "company": "Talabat", "type": "Freelancer", "joinDate": "2025-01-12", "status": "Active", "bank": "OM12 0001 1234", "notes": "", "username": "92001001", "password": "1234", "lastWorked": null}, {"id": "r2", "name": "سعيد الراشدي", "phone": "92001002", "civil": "22222222", "company": "Talabat", "type": "Freelancer", "joinDate": "2025-02-03", "status": "Active", "bank": "OM12 0001 5678", "notes": "", "username": "92001002", "password": "1234", "lastWorked": null}, {"id": "r3", "name": "خالد المعمري", "phone": "93002001", "civil": "33333333", "company": "Snoonu", "type": "Freelancer", "joinDate": "2025-03-20", "status": "Active", "bank": "", "notes": "", "username": "93002001", "password": "1234", "lastWorked": null}, {"id": "r4", "name": "ياسر الهنائي", "phone": "93002002", "civil": "44444444", "company": "Snoonu", "type": "Full Time", "joinDate": "2024-11-01", "status": "Active", "bank": "OM55 0009 2211", "notes": "موظف ثابت", "username": "93002002", "password": "1234", "lastWorked": null}, {"id": "r5", "name": "ماجد الحارثي", "phone": "94003001", "civil": "55555555", "company": "Aramex", "type": "Freelancer", "joinDate": "2025-04-10", "status": "Active", "bank": "", "notes": "", "username": "94003001", "password": "1234", "lastWorked": null}, {"id": "r6", "name": "عبدالله الكندي", "phone": "94003002", "civil": "66666666", "company": "Aramex", "type": "Full Time", "joinDate": "2025-01-05", "status": "Active", "bank": "OM77 0002 8899", "notes": "", "username": "94003002", "password": "1234", "lastWorked": null}], "imports": [], "transfers": [], "bankRows": {"Talabat": [], "Snoonu": [], "Aramex": []}, "attendance": {}}'::jsonb)
on conflict (id) do nothing;

-- 3) تفعيل حماية الصفوف: الموظفون المسجّلون فقط يقرأون/يكتبون مباشرة
alter table public.app_state enable row level security;

drop policy if exists "staff_read" on public.app_state;
create policy "staff_read" on public.app_state
  for select to authenticated using (true);

drop policy if exists "staff_update" on public.app_state;
create policy "staff_update" on public.app_state
  for update to authenticated using (true) with check (true);

-- 4) التحديث الفوري (Realtime) لجدول الحالة
do $$ begin
  execute 'alter publication supabase_realtime add table public.app_state';
exception when duplicate_object then null; when others then null;
end $$;

-- 5) دالة تطبيع رقم الهاتف
create or replace function public.norm_phone(p text)
returns text language sql immutable as $fn$
  select regexp_replace(regexp_replace(regexp_replace(coalesce(p,''),'[^0-9]','','g'),'^968',''),'^0+','')
$fn$;

-- 6) تسجيل دخول المندوب: يرجّع بيانات هذا المندوب فقط (بدون كلمة المرور)
create or replace function public.rider_login(p_phone text, p_password text)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare d jsonb; rider jsonb; rid text; mini_imports jsonb; mini_transfers jsonb;
begin
  select data into d from public.app_state where id = 1;
  select r into rider from jsonb_array_elements(d->'riders') r
   where norm_phone(r->>'phone') = norm_phone(p_phone)
     and (r->>'password') = p_password
   limit 1;
  if rider is null then return null; end if;
  rid := rider->>'id';

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', im->>'id', 'company', im->>'company', 'date', im->>'date', 'fileName', im->>'fileName',
      'results', (select coalesce(jsonb_agg(res),'[]'::jsonb)
                    from jsonb_array_elements(im->'results') res where res->>'riderId' = rid),
      'notWorkedIds', '[]'::jsonb)), '[]'::jsonb)
    into mini_imports
    from jsonb_array_elements(d->'imports') im
   where exists (select 1 from jsonb_array_elements(im->'results') res where res->>'riderId' = rid);

  select coalesce(jsonb_agg(t), '[]'::jsonb) into mini_transfers
    from jsonb_array_elements(d->'transfers') t where t->>'riderId' = rid;

  return jsonb_build_object(
    'version', 3,
    'riders', jsonb_build_array(rider - 'password'),
    'imports', mini_imports,
    'transfers', mini_transfers,
    'bankRows', jsonb_build_object('Talabat','[]'::jsonb,'Snoonu','[]'::jsonb,'Aramex','[]'::jsonb),
    'attendance', '{}'::jsonb
  );
end; $fn$;

-- 7) إرسال تحويل COD من المندوب
create or replace function public.rider_submit_transfer(
  p_phone text, p_password text, p_amount numeric, p_reference text, p_date text, p_receipt text)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare d jsonb; rider jsonb; rid text; newt jsonb;
begin
  select data into d from public.app_state where id = 1;
  select r into rider from jsonb_array_elements(d->'riders') r
   where norm_phone(r->>'phone') = norm_phone(p_phone) and (r->>'password') = p_password limit 1;
  if rider is null then return null; end if;
  rid := rider->>'id';
  newt := jsonb_build_object(
    'id', substr(md5(random()::text),1,7), 'riderId', rid, 'amount', p_amount,
    'reference', p_reference, 'date', p_date, 'receipt', coalesce(p_receipt,''),
    'status', 'Pending', 'recon', '', 'reconLabel', '');
  update public.app_state
     set data = jsonb_set(d, '{transfers}', coalesce(d->'transfers','[]'::jsonb) || newt),
         updated_at = now()
   where id = 1;
  return public.rider_login(p_phone, p_password);
end; $fn$;

-- 8) تغيير كلمة مرور المندوب
create or replace function public.rider_change_password(p_phone text, p_old text, p_new text)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare d jsonb; elem jsonb; newarr jsonb := '[]'::jsonb; found boolean := false;
begin
  select data into d from public.app_state where id = 1;
  for elem in select * from jsonb_array_elements(d->'riders') loop
    if norm_phone(elem->>'phone') = norm_phone(p_phone) and (elem->>'password') = p_old then
      elem := jsonb_set(elem, '{password}', to_jsonb(p_new)); found := true;
    end if;
    newarr := newarr || elem;
  end loop;
  if not found then return null; end if;
  update public.app_state set data = jsonb_set(d,'{riders}',newarr), updated_at = now() where id = 1;
  return jsonb_build_object('ok', true);
end; $fn$;

-- 9) السماح للمناديب (غير المسجّلين بحساب) باستدعاء دوالهم فقط
grant execute on function public.rider_login(text,text) to anon, authenticated;
grant execute on function public.rider_submit_transfer(text,text,numeric,text,text,text) to anon, authenticated;
grant execute on function public.rider_change_password(text,text,text) to anon, authenticated;

-- تم. الخطوة التالية: أنشئ حسابات الموظفين في Authentication → Users (انظر الدليل).
