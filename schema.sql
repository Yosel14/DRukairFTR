-- Drukair FTR System - run once in Supabase > SQL Editor
create table profiles (id uuid primary key references auth.users on delete cascade, email text, role text not null default 'pending' check (role in ('pending','dispatcher','approver','admin')));
create table ftr_records (id text primary key, data jsonb not null, updated_at timestamptz default now());
create unique index ftr_sl_unique on ftr_records ((data->>'sl'));
create table ftr_proofs (record_id text primary key, imgs jsonb not null);
create table ftr_settings (key text primary key, value jsonb not null);
create table ftr_approvals (record_id text primary key, status text not null check (status in ('Submitted','Approved','Rejected')), note text, by_email text, at timestamptz default now());
create table ftr_audit (id bigserial primary key, at timestamptz default now(), by_email text, action text, record_id text, detail jsonb);
create table invoice_counter (id int primary key, next int not null);

insert into invoice_counter values (1, 261);
insert into ftr_settings values
 ('rates', '{"TC":{"rate":3700,"currency":"USD","name":"Tourist Charter"},"HEMS":{"rate":120000,"currency":"Nu.","name":"Medical Emergency (HEMS)"},"LC":{"rate":150000,"currency":"Nu.","name":"Local Charter"},"LC-SUB":{"rate":80000,"currency":"Nu.","name":"Subsidized Local Charter"},"LC-RGOB":{"rate":130000,"currency":"Nu.","name":"Royal Govt Charter"}}'),
 ('inv', '{"prefix":"DA/HSD/GOCS/12","gst":5,"by":"Drukair","tpn":"C10042982"}');

create function my_role() returns text language sql stable security definer set search_path = public as $$ select role from profiles where id = auth.uid() $$;
create function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$ begin insert into profiles(id, email) values (new.id, new.email); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

-- atomic invoice numbers: two people can never get the same one
create function next_invoice() returns int language plpgsql security definer set search_path = public as $$
declare n int; begin
  if my_role() not in ('dispatcher','admin') then raise exception 'not allowed'; end if;
  update invoice_counter set next = next + 1 where id = 1 returning next - 1 into n; return n; end $$;

-- once Approved, only payment / invoice fields may change; no deletion
create function lock_approved() returns trigger language plpgsql security definer set search_path = public as $$
declare pk text[] := array['payMode','payStatus','payRef','paidAmt','invNo','invDate'];
begin
  if exists (select 1 from ftr_approvals where record_id = old.id and status = 'Approved') then
    if tg_op = 'DELETE' or (old.data - pk) is distinct from (new.data - pk) then raise exception 'FTR % is approved and locked', old.id; end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end; end $$;
create trigger lock_ftr before update or delete on ftr_records for each row execute function lock_approved();

-- audit trail of every change
create function audit() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into ftr_audit(by_email, action, record_id, detail)
  values (auth.jwt()->>'email', tg_table_name || ' ' || tg_op, coalesce(to_jsonb(new)->>'id', to_jsonb(new)->>'record_id', to_jsonb(old)->>'id', to_jsonb(old)->>'record_id'), to_jsonb(coalesce(new, old)));
  return coalesce(new, old); end $$;
create trigger audit_records after insert or update or delete on ftr_records for each row execute function audit();
create trigger audit_approvals after insert or update or delete on ftr_approvals for each row execute function audit();

-- security: nothing is readable or writable without an activated role
alter table profiles enable row level security; alter table ftr_records enable row level security; alter table ftr_proofs enable row level security;
alter table ftr_settings enable row level security; alter table ftr_approvals enable row level security; alter table ftr_audit enable row level security; alter table invoice_counter enable row level security;

create policy p_read on profiles for select to authenticated using (id = auth.uid());
create policy r_read on ftr_records for select to authenticated using (my_role() in ('dispatcher','approver','admin'));
create policy r_write on ftr_records for all to authenticated using (my_role() in ('dispatcher','admin')) with check (my_role() in ('dispatcher','admin'));
create policy x_read on ftr_proofs for select to authenticated using (my_role() in ('dispatcher','approver','admin'));
create policy x_write on ftr_proofs for all to authenticated using (my_role() in ('dispatcher','admin')) with check (my_role() in ('dispatcher','admin'));
create policy s_read on ftr_settings for select to authenticated using (my_role() in ('dispatcher','approver','admin'));
create policy s_write on ftr_settings for all to authenticated using (my_role() = 'admin') with check (my_role() = 'admin');
create policy c_read on invoice_counter for select to authenticated using (my_role() in ('dispatcher','approver','admin'));
create policy c_write on invoice_counter for update to authenticated using (my_role() = 'admin') with check (my_role() = 'admin');
create policy a_read on ftr_approvals for select to authenticated using (my_role() in ('dispatcher','approver','admin'));
create policy a_write on ftr_approvals for all to authenticated
  using ((my_role() in ('dispatcher','admin') and status <> 'Approved') or my_role() = 'approver')
  with check ((my_role() in ('dispatcher','admin') and status = 'Submitted') or (my_role() = 'approver' and status in ('Approved','Rejected')));
create policy u_read on ftr_audit for select to authenticated using (my_role() in ('approver','admin'));
