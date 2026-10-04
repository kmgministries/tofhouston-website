-- Results Matter database setup, version 1.
-- Run once in the Supabase SQL Editor for the Results Matter project.
-- No passwords, service keys, real residents, or automatically promoted users.
begin;
create schema if not exists rm_private;
revoke all on schema rm_private from public, anon, authenticated;
create table public.rm_roles (name text primary key);
insert into public.rm_roles values ('Super Administrator'),('Executive Director'),('Program Director'),('Case Manager'),('House Manager'),('Finance'),('Staff'),('Volunteer'),('Resident');
create table public.rm_modules (name text primary key, label text not null, resident_visible boolean not null default false, statuses text[] not null);
insert into public.rm_modules values
('residents','Residents',true,array['Applicant','Waitlisted','Approved','Intake Scheduled','Active','Temporarily Away','Graduated','Discharged','Inactive']),
('applications','Applications',false,array['Submitted','Under Review','Documents Requested','Interview Scheduled','Approved','Denied','Waitlisted','Intake Scheduled','Converted']),
('properties','Properties',false,array['Active','Inactive']),('rooms','Rooms',false,array['Available','Unavailable']),
('beds','Beds',false,array['Available','Occupied','Reserved','Maintenance','Unavailable']),
('bed_assignments','Bed assignments',false,array['Active','Moved Out']),
('case_notes','Case notes',false,array['Open','Completed']),('assessments','Assessments',false,array['Draft','Completed']),
('service_plans','Service plans',false,array['Draft','Active','Completed']),('reentry','Reentry',false,array['Active','Completed']),
('goals','Goals',true,array['Not Started','In Progress','At Risk','Completed','Cancelled']),
('tasks','Tasks',true,array['Not Started','In Progress','Completed','Overdue']),
('programs','Programs',true,array['Active','Inactive']),('enrollments','Program enrollments',true,array['Active','Completed','Withdrawn']),
('attendance','Attendance',true,array['Present','Absent','Excused','Late']),
('house_logs','House management',false,array['Open','Approved','Denied','Completed']),
('appointments','Calendar',true,array['Scheduled','Completed','Cancelled']),
('incidents','Incidents',false,array['Open','Under Review','Resolved','Closed']),
('documents','Documents',true,array['Draft','Awaiting Signature','Signed','Expired']),
('charges','Charges',true,array['Charge','Credit','Waiver','Assistance']),('payments','Payments',true,array['Recorded','Voided']),
('requests','Requests',true,array['Submitted','Under Review','Approved','Denied','Completed']),
('messages','Messages',true,array['Sent','Read']),('announcements','Announcements',true,array['Draft','Published','Archived']),
('resources','Resources',true,array['Active','Inactive']),('referrals','Referrals',false,array['Open','Completed']),
('discharges','Discharges',false,array['Planned','Completed']),('followups','Follow-ups',false,array['Scheduled','Completed','Unable to Contact']),
('outcomes','Outcomes',false,array['Recorded']),('notifications','Notifications',true,array['Unread','Read']);
create table public.rm_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default '', email text not null default '',
 role text not null default 'Resident' references public.rm_roles(name),
 active boolean not null default false, require_mfa boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.rm_permissions (
 role text not null references public.rm_roles(name), module text not null references public.rm_modules(name),
 can_view boolean not null default false, can_create boolean not null default false,
 can_edit boolean not null default false, can_export boolean not null default false, can_delete boolean not null default false,
 primary key (role,module)
);
insert into public.rm_permissions select r.name,m.name,false,false,false,false,false from public.rm_roles r cross join public.rm_modules m;
update public.rm_permissions set can_view=true,can_create=true,can_edit=true,can_export=true,can_delete=true where role in ('Super Administrator','Executive Director');
update public.rm_permissions set can_view=true,can_create=true,can_edit=true,can_export=true where role='Program Director' and module not in ('charges','payments');
update public.rm_permissions set can_view=true,can_create=true,can_edit=true where role='Case Manager' and module in ('residents','applications','case_notes','assessments','service_plans','reentry','goals','tasks','programs','enrollments','attendance','appointments','documents','requests','messages','announcements','resources','referrals','discharges','followups','outcomes','notifications');
update public.rm_permissions set can_view=true,can_create=true,can_edit=true where role='House Manager' and module in ('residents','properties','rooms','beds','bed_assignments','house_logs','tasks','incidents','appointments','programs','attendance','requests','messages','announcements','resources','notifications');
update public.rm_permissions set can_view=true,can_create=true,can_edit=true,can_export=true where role='Finance' and module in ('charges','payments');
update public.rm_permissions set can_view=true where role='Finance' and module='residents';
update public.rm_permissions set can_view=true,can_create=true,can_edit=true where role='Staff' and module in ('tasks','attendance','house_logs','appointments','requests','messages','notifications');
update public.rm_permissions set can_view=true where role in ('Staff','Volunteer') and module in ('programs','announcements','resources');
update public.rm_permissions set can_view=true where role='Resident' and module in (select name from public.rm_modules where resident_visible);
update public.rm_permissions set can_create=true where role='Resident' and module in ('goals','requests','messages');
update public.rm_permissions set can_edit=true where role='Resident' and module in ('goals','tasks','messages','notifications');
create table public.rm_residents (
 id uuid primary key default gen_random_uuid(), title text not null check(length(title) between 1 and 250),
 user_id uuid unique references public.rm_profiles(id), resident_id uuid,
 status text not null default 'Applicant', email text not null default '',
 category text not null default '', details jsonb not null default '{}',
 event_date date, due_date date, amount numeric(12,2) not null default 0,
 progress integer not null default 0 check(progress between 0 and 100),
 assigned_user uuid references public.rm_profiles(id), created_by uuid references public.rm_profiles(id),
 is_demo boolean not null default false, deleted_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(jsonb_typeof(details)='object' and octet_length(details::text)<=32768)
);
-- Module-specific tables have shared filtering columns and resident foreign keys.
-- Supplemental typed form fields live in details; confidential notes have separate tables.
do $$ declare m record; begin
 for m in select name,statuses from public.rm_modules where name<>'residents' loop
  execute format('create table public.rm_%I (id uuid primary key default gen_random_uuid(), title text not null check(length(title) between 1 and 250), resident_id uuid references public.rm_residents(id), assigned_user uuid references public.rm_profiles(id), status text not null default %L, email text not null default '''', category text not null default '''', details jsonb not null default ''{}'', event_date date, due_date date, amount numeric(12,2) not null default 0, progress integer not null default 0 check(progress between 0 and 100), is_demo boolean not null default false, created_by uuid references public.rm_profiles(id), deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), check(jsonb_typeof(details)=''object'' and octet_length(details::text)<=32768))', m.name, m.statuses[1]);
  execute format('create index on public.rm_%I(resident_id)',m.name);
  execute format('create index on public.rm_%I(status,created_at)',m.name);
 end loop;
end $$;
alter table public.rm_rooms add column property_id uuid references public.rm_properties(id);
alter table public.rm_beds add column room_id uuid references public.rm_rooms(id);
alter table public.rm_bed_assignments add column bed_id uuid not null references public.rm_beds(id);
create unique index rm_one_active_bed on public.rm_bed_assignments(bed_id) where status='Active' and deleted_at is null;
create unique index rm_one_active_resident_bed on public.rm_bed_assignments(resident_id) where status='Active' and deleted_at is null;
alter table public.rm_enrollments add column program_id uuid references public.rm_programs(id);
alter table public.rm_attendance add column program_id uuid references public.rm_programs(id);
alter table public.rm_goals add column staff_owner uuid references public.rm_profiles(id);
alter table public.rm_documents add column storage_path text unique;
alter table public.rm_documents add column resident_visible boolean not null default false;
alter table public.rm_documents add column signed_at timestamptz;
alter table public.rm_documents add column signed_by uuid references public.rm_profiles(id);
alter table public.rm_payments add column receipt_number bigint generated always as identity;
create table public.rm_audit_logs (
 id bigint generated always as identity primary key, actor_id uuid references auth.users(id) on delete set null,
 action text not null,module text not null,record_id uuid,session_id text,
 created_at timestamptz not null default now()
);
create table rm_private.sessions (session_id text primary key, user_id uuid not null references auth.users(id) on delete cascade, last_seen timestamptz not null default now(), ended_at timestamptz);
create function rm_private.role_name() returns text language sql stable security definer set search_path='' as $$ select role from public.rm_profiles where id=auth.uid() and active $$;
create function rm_private.session_ok() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.rm_profiles p join rm_private.sessions s on s.user_id=p.id where p.id=auth.uid() and p.active and s.session_id=auth.jwt()->>'session_id' and s.ended_at is null and s.last_seen>now()-interval '20 minutes' and (not p.require_mfa or auth.jwt()->>'aal'='aal2'))
$$;
create function rm_private.can(m text,a text) returns boolean language sql stable security definer set search_path='' as $$
 select rm_private.session_ok() and coalesce((select case a when 'view' then can_view when 'create' then can_create when 'edit' then can_edit when 'export' then can_export when 'delete' then can_delete else false end from public.rm_permissions where role=rm_private.role_name() and module=m),false)
$$;
create function rm_private.owns(r uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.rm_residents where id=r and user_id=auth.uid() and deleted_at is null)$$;
create function rm_private.visible(m text,r uuid,owner_id uuid,author_id uuid,s text,d jsonb,doc_visible boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select rm_private.can(m,'view') and (
 rm_private.role_name()<>'Resident' or (m in (select name from public.rm_modules where resident_visible) and
 case when m='residents' then rm_private.owns(r)
 when m='messages' then owner_id=auth.uid() or author_id=auth.uid()
 when m='notifications' then owner_id=auth.uid()
 when m='announcements' then s='Published' and d->>'audience' in ('Residents','Everyone')
 when m in ('programs','resources') then s='Active'
 when m='documents' then rm_private.owns(r) and doc_visible
 else rm_private.owns(r) end))
$$;
-- Defense in depth: direct writes are revoked; table reads also obey RLS.
do $$ declare m record; clause text; begin
 for m in select name from public.rm_modules loop
  execute format('alter table public.rm_%I enable row level security',m.name);
  clause:=case when m.name='residents' then 'id' else 'resident_id' end;
  execute format('create policy rm_read on public.rm_%I for select to authenticated using(deleted_at is null and rm_private.visible(%L,%s,assigned_user,created_by,status,details,%s))',m.name,m.name,clause,case when m.name='documents' then 'resident_visible' else 'false' end);
  execute format('revoke all on public.rm_%I from anon,authenticated',m.name);
  execute format('grant select on public.rm_%I to authenticated',m.name);
 end loop;
end $$;
alter table public.rm_profiles enable row level security;
create policy rm_profiles_read on public.rm_profiles for select to authenticated using(id=auth.uid() or (rm_private.session_ok() and rm_private.role_name()<>'Resident' and (role<>'Resident' or rm_private.can('residents','edit'))));
alter table public.rm_permissions enable row level security;
create policy rm_permissions_read on public.rm_permissions for select to authenticated using(role=rm_private.role_name() or (rm_private.session_ok() and rm_private.role_name()='Super Administrator'));
alter table public.rm_modules enable row level security;
create policy rm_modules_read on public.rm_modules for select to authenticated using(true);
alter table public.rm_roles enable row level security;
create policy rm_roles_read on public.rm_roles for select to authenticated using(true);
alter table public.rm_audit_logs enable row level security;
create policy rm_audit_read on public.rm_audit_logs for select to authenticated using(rm_private.session_ok() and rm_private.role_name() in ('Super Administrator','Executive Director'));
revoke all on public.rm_profiles,public.rm_permissions,public.rm_modules,public.rm_roles,public.rm_audit_logs from anon,authenticated;
grant select on public.rm_profiles,public.rm_permissions,public.rm_modules,public.rm_roles,public.rm_audit_logs to authenticated;
grant usage on schema rm_private to authenticated;
-- Functions below are the only authenticated mutation API.
create function public.rm_start_session() returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.rm_profiles; sid text:=auth.jwt()->>'session_id'; begin
 if auth.uid() is null or sid is null then raise exception 'Sign in required'; end if;
 select * into p from public.rm_profiles where id=auth.uid();
 if not found or not p.active then raise exception 'Your account has not been activated. Contact the program administrator.'; end if;
 if p.require_mfa and auth.jwt()->>'aal'<>'aal2' then raise exception 'Two-factor verification required'; end if;
 if not exists(select 1 from jsonb_array_elements(coalesce(auth.jwt()->'amr','[]')) a where a->>'method' in ('password','totp','otp') and (a->>'timestamp')::bigint>extract(epoch from now()-interval '2 minutes')) then raise exception 'Please sign in again'; end if;
 insert into rm_private.sessions(session_id,user_id) values(sid,auth.uid()) on conflict(session_id) do update set last_seen=now(),ended_at=null;
 insert into public.rm_audit_logs(actor_id,action,module,session_id) values(auth.uid(),'login','authentication',sid);
 return jsonb_build_object('role',p.role,'display_name',p.display_name);
end $$;
create function public.rm_touch_session() returns void language plpgsql security definer set search_path='' as $$ begin
 if not rm_private.session_ok() then raise exception 'Your session has ended. Please sign in again.'; end if;
 update rm_private.sessions set last_seen=now() where session_id=auth.jwt()->>'session_id' and user_id=auth.uid();
end $$;
create function public.rm_end_session() returns void language plpgsql security definer set search_path='' as $$begin update rm_private.sessions set ended_at=now() where session_id=auth.jwt()->>'session_id' and user_id=auth.uid(); end$$;
create function rm_private.audit_write() returns trigger language plpgsql security definer set search_path='' as $$ begin
 insert into public.rm_audit_logs(actor_id,action,module,record_id,session_id) values(auth.uid(),case when tg_op='INSERT' then 'created' when new.deleted_at is not null and old.deleted_at is null then 'archived' else 'updated' end,substr(tg_table_name,4),new.id,auth.jwt()->>'session_id');
 return new;
end $$;
do $$ declare m record; begin for m in select name from public.rm_modules loop execute format('create trigger rm_audit after insert or update on public.rm_%I for each row execute function rm_private.audit_write()',m.name); end loop; end $$;
create function public.rm_save(m text,payload jsonb,record_id uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare item jsonb; result uuid:=coalesce(record_id,gen_random_uuid()); r uuid; perm text:=case when record_id is null then 'create' else 'edit' end; role_name text:=rm_private.role_name(); allowed text[]; new_status text; key text; begin
 if not exists(select 1 from public.rm_modules where name=m) or not rm_private.can(m,perm) then raise exception 'Permission denied'; end if;
 if jsonb_typeof(payload)<>'object' or octet_length(payload::text)>40000 then raise exception 'Invalid record'; end if;
 if record_id is not null then execute format('select to_jsonb(t) from public.rm_%I t where id=$1 and deleted_at is null for update',m) into item using record_id; if item is null then raise exception 'Record not found'; end if; end if;
 r:=coalesce(nullif(payload->>'resident_id','')::uuid,nullif(item->>'resident_id','')::uuid);
 if role_name='Resident' then
  if m not in ('goals','tasks','requests','messages','notifications') then raise exception 'Permission denied'; end if;
  if record_id is not null and m='requests' then raise exception 'Request decisions are staff-only'; end if;
  if m in ('goals','requests','messages') and record_id is null then select id into r from public.rm_residents where user_id=auth.uid() and deleted_at is null; end if;
  if m<>'notifications' and (r is null or not rm_private.owns(r) or (record_id is not null and (item->>'resident_id')::uuid is distinct from r)) then raise exception 'Permission denied'; end if;
  if record_id is not null and m='messages' and (item->>'assigned_user')::uuid is distinct from auth.uid() then raise exception 'Permission denied'; end if;
  if m='notifications' and (item->>'assigned_user')::uuid is distinct from auth.uid() then raise exception 'Permission denied'; end if;
  if record_id is not null then
   if m in ('messages','notifications') then payload:=jsonb_build_object('status','Read');
   elsif m='tasks' then payload:=jsonb_build_object('status',payload->>'status');
   else payload:=jsonb_build_object('title',payload->>'title','status',payload->>'status','progress',payload->'progress','due_date',payload->'due_date','details',jsonb_build_object('description',payload->'details'->>'description','notes',payload->'details'->>'notes')); end if;
  else
   if m='requests' then payload:=jsonb_build_object('title',payload->>'title','category',payload->>'category','details',jsonb_build_object('description',payload->'details'->>'description','requested_date',payload->'details'->>'requested_date'),'status','Submitted');
   elsif m='messages' then
    if not exists(select 1 from public.rm_profiles where id=nullif(payload->>'assigned_user','')::uuid and active and role<>'Resident') then raise exception 'Select a staff recipient'; end if;
    payload:=jsonb_build_object('title',payload->>'title','assigned_user',payload->'assigned_user','details',jsonb_build_object('description',payload->'details'->>'description'),'status','Sent');
   else payload:=jsonb_build_object('title',payload->>'title','due_date',payload->'due_date','details',jsonb_build_object('description',payload->'details'->>'description'),'status','Not Started','progress',0); end if;
  end if;
  payload:=payload||jsonb_build_object('resident_id',r);
 end if;
 item:=coalesce(item,'{}')||payload;
 new_status:=coalesce(item->>'status',(select statuses[1] from public.rm_modules where name=m));
 select statuses into allowed from public.rm_modules where name=m;
 if not new_status=any(allowed) then raise exception 'Invalid status'; end if;
 if length(coalesce(item->>'title','')) not between 1 and 250 then raise exception 'A title or name is required (maximum 250 characters)'; end if;
 if m='bed_assignments' then raise exception 'Use the bed assignment action'; end if;
 if m='beds' and new_status='Occupied' and not exists(select 1 from public.rm_bed_assignments where bed_id=result and status='Active' and deleted_at is null) then raise exception 'Assign a resident to occupy a bed'; end if;
 if m='beds' and new_status<>'Occupied' and exists(select 1 from public.rm_bed_assignments where bed_id=result and status='Active' and deleted_at is null) then raise exception 'Move out the resident before changing this bed status'; end if;
 if m='documents' and (payload->>'status'='Signed' or payload ? 'signed_at' or payload ? 'signed_by') then raise exception 'Use the document signing action'; end if;
 allowed:=array['title','resident_id','assigned_user','status','email','category','details','event_date','due_date','amount','progress','is_demo'];
 if m='residents' then allowed:=allowed||array['user_id']; elsif m='rooms' then allowed:=allowed||array['property_id']; elsif m='beds' then allowed:=allowed||array['room_id']; elsif m in ('enrollments','attendance') then allowed:=allowed||array['program_id']; elsif m='documents' then allowed:=allowed||array['storage_path','resident_visible']; end if;
 if record_id is null then
  execute format('insert into public.rm_%I(id,title,status,created_by) values($1,$2,$3,$4)',m) using result,item->>'title',new_status,auth.uid();
 end if;
 item:=item||jsonb_build_object('status',new_status);
 for key in select jsonb_object_keys(item) loop
  if key=any(allowed) then execute format('update public.rm_%I set %I=(select %I from jsonb_populate_record(null::public.rm_%I,$1)),updated_at=now() where id=$2',m,key,key,m) using item,result; end if;
 end loop;
 return result;
end $$;
create function public.rm_archive(m text,record_id uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if rm_private.role_name()='Resident' or not rm_private.can(m,'delete') or not exists(select 1 from public.rm_modules where name=m) then raise exception 'Permission denied'; end if;
 if m='bed_assignments' then raise exception 'Use move out to end a bed assignment'; end if;
 if m='beds' and exists(select 1 from public.rm_bed_assignments where bed_id=record_id and status='Active' and deleted_at is null) then raise exception 'Move out the resident before archiving this bed'; end if;
 if m='residents' and exists(select 1 from public.rm_bed_assignments where resident_id=record_id and status='Active' and deleted_at is null) then raise exception 'Move out the resident before archiving this profile'; end if;
 execute format('update public.rm_%I set deleted_at=now(),updated_at=now() where id=$1',m) using record_id;
end $$;
create function public.rm_export(m text) returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 if not rm_private.can(m,'export') or rm_private.role_name()='Resident' then raise exception 'Permission denied'; end if;
 execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from public.rm_%I t where deleted_at is null',m) into result;
 insert into public.rm_audit_logs(actor_id,action,module,session_id) values(auth.uid(),'export',m,auth.jwt()->>'session_id');return result;
end$$;
create function public.rm_assign_bed(bed uuid,resident uuid,move_in date) returns uuid language plpgsql security definer set search_path='' as $$declare b public.rm_beds; rid uuid; oldbed uuid;begin
 if rm_private.role_name()='Resident' or not rm_private.can('bed_assignments','create') or not rm_private.can('beds','edit') then raise exception 'Permission denied'; end if;
 if move_in is null then raise exception 'A move-in date is required'; end if;
 perform 1 from public.rm_residents where id=resident and deleted_at is null for update; if not found then raise exception 'Resident not found'; end if;
 select * into b from public.rm_beds where id=bed and deleted_at is null for update;
 if not found or b.status not in ('Available','Reserved') then raise exception 'This bed is not available'; end if;
 select bed_id into oldbed from public.rm_bed_assignments where resident_id=resident and status='Active' and deleted_at is null;
 update public.rm_bed_assignments set status='Moved Out',due_date=move_in,updated_at=now() where resident_id=resident and status='Active' and deleted_at is null;
 update public.rm_beds set status='Available',updated_at=now() where id=oldbed;
 insert into public.rm_bed_assignments(title,resident_id,bed_id,event_date,status,created_by) values(b.title,resident,bed,move_in,'Active',auth.uid()) returning id into rid;
 update public.rm_beds set status='Occupied',updated_at=now() where id=bed;
 return rid;
end$$;
create function public.rm_move_out(resident uuid,exit_date date) returns void language plpgsql security definer set search_path='' as $$declare bed uuid;begin
 if rm_private.role_name()='Resident' or not rm_private.can('bed_assignments','edit') or not rm_private.can('beds','edit') then raise exception 'Permission denied'; end if;
 if exit_date is null then raise exception 'An exit date is required'; end if;
 perform 1 from public.rm_residents where id=resident for update;
 select bed_id into bed from public.rm_bed_assignments where resident_id=resident and status='Active' and deleted_at is null;
 update public.rm_bed_assignments set status='Moved Out',due_date=exit_date,updated_at=now() where resident_id=resident and status='Active' and deleted_at is null;
 update public.rm_beds set status='Available',updated_at=now() where id=bed;
end$$;
create function public.rm_convert_application(application uuid) returns uuid language plpgsql security definer set search_path='' as $$declare a public.rm_applications;r uuid;begin
 if rm_private.role_name()='Resident' or not rm_private.can('applications','edit') or not rm_private.can('residents','create') then raise exception 'Permission denied'; end if;
 select * into a from public.rm_applications where id=application and deleted_at is null for update;
 if not found or a.status not in ('Approved','Intake Scheduled') then raise exception 'Approve this application first'; end if;
 insert into public.rm_residents(title,email,status,details,event_date,created_by,is_demo) values(a.title,a.email,'Approved',a.details-'review_notes',a.due_date,auth.uid(),a.is_demo) returning id into r;
 update public.rm_applications set resident_id=r,status='Converted',updated_at=now() where id=application;
 return r;
end$$;
create function public.rm_submit_application(payload jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 if coalesce(payload->>'website','')<>'' then return; end if;
 if length(coalesce(payload->>'title','')) not between 2 and 250 or length(coalesce(payload->>'email','')) not between 5 and 254 or payload->>'email' !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' or octet_length(payload::text)>32768 or coalesce(payload->'details'->>'consent','false')<>'true' or length(coalesce(payload->'details'->>'signature',''))<2 then raise exception 'Complete your name, email, consent, and signature'; end if;
 perform pg_advisory_xact_lock(793024);
 if (select count(*) from public.rm_applications where created_at>now()-interval '1 hour')>=50 or exists(select 1 from public.rm_applications where lower(email)=lower(payload->>'email') and created_at>now()-interval '1 day') then raise exception 'Please contact the church for help with your application'; end if;
 insert into public.rm_applications(title,email,details,status) values(payload->>'title',payload->>'email',payload->'details','Submitted');
end$$;
create function public.rm_staff_directory() returns table(id uuid,display_name text,role text) language sql security definer set search_path='' as $$select id,display_name,role from public.rm_profiles where active and role<>'Resident' and rm_private.session_ok()$$;
create function public.rm_admin_user(target uuid,new_role text,is_active boolean,mfa_required boolean) returns void language plpgsql security definer set search_path='' as $$begin
 if not rm_private.session_ok() or rm_private.role_name()<>'Super Administrator' then raise exception 'Permission denied'; end if;
 if target=auth.uid() and (new_role<>'Super Administrator' or not is_active) then raise exception 'Another administrator must change your access'; end if;
 update public.rm_profiles set role=new_role,active=is_active,require_mfa=mfa_required,updated_at=now() where id=target;
 insert into public.rm_audit_logs(actor_id,action,module,record_id,session_id) values(auth.uid(),'permissions changed','profiles',target,auth.jwt()->>'session_id');
end$$;
create function public.rm_admin_permission(target_role text,target_module text,rights jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 if not rm_private.session_ok() or rm_private.role_name()<>'Super Administrator' or target_role='Super Administrator' then raise exception 'Permission denied'; end if;
 update public.rm_permissions set can_view=coalesce((rights->>'view')::boolean,false),can_create=coalesce((rights->>'create')::boolean,false),can_edit=coalesce((rights->>'edit')::boolean,false),can_export=coalesce((rights->>'export')::boolean,false),can_delete=coalesce((rights->>'delete')::boolean,false) where role=target_role and module=target_module;
 insert into public.rm_audit_logs(actor_id,action,module,session_id) values(auth.uid(),'role permissions changed',target_module,auth.jwt()->>'session_id');
end$$;
create function rm_private.new_user() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into public.rm_profiles(id,email,display_name) values(new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'display_name',''));
 return new;
end$$;
create trigger rm_new_user after insert on auth.users for each row execute function rm_private.new_user();
insert into public.rm_profiles(id,email,display_name) select id,coalesce(email,''),coalesce(raw_user_meta_data->>'display_name','') from auth.users on conflict(id) do nothing;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('rm-documents','rm-documents',false,5242880,array['application/pdf','image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy rm_storage_upload on storage.objects for insert to authenticated with check(bucket_id='rm-documents' and rm_private.can('documents','create') and rm_private.role_name()<>'Resident' and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|jpg|png|webp)$');
create policy rm_storage_read on storage.objects for select to authenticated using(bucket_id='rm-documents' and exists(select 1 from public.rm_documents d where d.storage_path=name and d.deleted_at is null and rm_private.visible('documents',d.resident_id,d.assigned_user,d.created_by,d.status,d.details,d.resident_visible)));
create function public.rm_document_access(document uuid) returns text language plpgsql security definer set search_path='' as $$declare d public.rm_documents;begin
 select * into d from public.rm_documents where id=document and deleted_at is null;
 if not found or not rm_private.visible('documents',d.resident_id,d.assigned_user,d.created_by,d.status,d.details,d.resident_visible) then raise exception 'Permission denied'; end if;
 insert into public.rm_audit_logs(actor_id,action,module,record_id,session_id) values(auth.uid(),'document accessed','documents',document,auth.jwt()->>'session_id'); return d.storage_path;
end$$;
create function public.rm_sign_document(document uuid,signature text) returns void language plpgsql security definer set search_path='' as $$declare d public.rm_documents;begin
 select * into d from public.rm_documents where id=document and deleted_at is null for update;
 if not rm_private.session_ok() or not rm_private.owns(d.resident_id) or not d.resident_visible or d.status<>'Awaiting Signature' or length(signature) not between 2 and 250 then raise exception 'Unable to sign this document'; end if;
 update public.rm_documents set status='Signed',signed_by=auth.uid(),signed_at=now(),details=details||jsonb_build_object('signature',signature),updated_at=now() where id=document;
end$$;
-- Revoke the default PUBLIC execute grant on every application function.
create function public.rm_seed_demo() returns void language plpgsql security definer set search_path='' as $$
declare r uuid; p uuid; room uuid; bed uuid; program uuid; assignment uuid; m record; begin
 if not rm_private.session_ok() or rm_private.role_name()<>'Super Administrator' then raise exception 'Permission denied'; end if;
 if exists(select 1 from public.rm_residents where is_demo and deleted_at is null) then raise exception 'Demo records already exist'; end if;
 r:=public.rm_save('residents',jsonb_build_object('title','DEMO — Jordan Sample','status','Active','event_date',current_date-14,'is_demo',true,'details',jsonb_build_object('phase','Orientation','employment','Seeking Employment')),null);
 perform public.rm_save('residents',jsonb_build_object('title','DEMO — Taylor Sample','status','Graduated','event_date',current_date-90,'is_demo',true,'details',jsonb_build_object('phase','Completed','employment','Employed')),null);
 p:=public.rm_save('properties',jsonb_build_object('title','DEMO — Sample House','is_demo',true),null);
 room:=public.rm_save('rooms',jsonb_build_object('title','DEMO — Room 1','property_id',p,'is_demo',true),null);
 bed:=public.rm_save('beds',jsonb_build_object('title','DEMO — Bed 1','room_id',room,'is_demo',true),null);
 assignment:=public.rm_assign_bed(bed,r,current_date-14);
 update public.rm_bed_assignments set is_demo=true where id=assignment;
 perform public.rm_save('beds',jsonb_build_object('title','DEMO — Bed 2','room_id',room,'is_demo',true),null);
 program:=public.rm_save('programs',jsonb_build_object('title','DEMO — Life Skills Workshop','is_demo',true,'details',jsonb_build_object('description','Fictional program for testing only')),null);
 perform public.rm_save('enrollments',jsonb_build_object('title','DEMO — Enrollment','resident_id',r,'program_id',program,'is_demo',true),null);
 perform public.rm_save('attendance',jsonb_build_object('title','DEMO — Workshop attendance','resident_id',r,'program_id',program,'event_date',current_date,'is_demo',true),null);
 for m in select name,label from public.rm_modules where name not in ('residents','properties','rooms','beds','bed_assignments','programs','enrollments','attendance','documents') loop
  perform public.rm_save(m.name,jsonb_build_object('title','DEMO — '||m.label,'resident_id',r,'event_date',current_date,'due_date',current_date+7,'is_demo',true,'assigned_user',auth.uid(),'amount',case when m.name='charges' then 120 when m.name='payments' then 60 else 0 end,'details',jsonb_build_object('description','Fictional sample for testing only. No actual person or transaction.','audience','Everyone')),null);
 end loop;
end$$;
do $$ declare f record;begin
 for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname like 'rm_%') or n.nspname='rm_private' loop
  execute format('revoke all on function %s from public,anon,authenticated',f.sig);
  if f.sig::text like 'rm_private.%' then execute format('grant execute on function %s to authenticated',f.sig);
  else execute format('grant execute on function %s to authenticated',f.sig); end if;
 end loop;
end$$;
grant execute on function public.rm_submit_application(jsonb) to anon;
commit;
