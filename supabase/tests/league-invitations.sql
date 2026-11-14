-- Run ENTIRE file as postgres in the DEVELOPMENT SQL Editor after all 3 migrations.
-- Replace placeholders ONLY in a private execution copy. Provision Auth accounts
-- through the supported dashboard/Admin API, never INSERT/UPDATE auth.users.
-- A/B/C: distinct confirmed email accounts. D: distinct UNCONFIRMED email account.
-- Uses role/JWT contexts; no emails, Auth mutations, or persistent fixtures.
-- On ANY error run ROLLBACK before other SQL. Require PASS and final ROLLBACK.
begin;
do $verification$
declare
  v_inputs text[] := array['REPLACE_WITH_CONFIRMED_A_UUID','REPLACE_WITH_CONFIRMED_B_UUID',
    'REPLACE_WITH_CONFIRMED_C_UUID','REPLACE_WITH_UNCONFIRMED_D_UUID'];
  v_users uuid[] := array[]::uuid[];
  v_emails text[] := array[]::text[];
  v_leagues uuid[] := array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
  v_season integer;
  v_i integer;
  v_name text;
  v_role text;
  v_privilege text;
  v_table record;
  v_column record;
  v_fn record;
  v_case record;
  v_denied boolean;
  v_constraint text;
  v_result jsonb;
  v_first jsonb;
  v_claim jsonb;
  v_snapshot jsonb;
  v_key uuid := gen_random_uuid();
  v_claim_key uuid := gen_random_uuid();
  v_invite uuid;
  v_expired uuid;
  v_other uuid;
  v_unconfirmed uuid;
  v_expiry timestamptz;
  v_attempt uuid;
begin
  for v_i in 1..4 loop
    if v_inputs[v_i] like 'REPLACE_%' then raise exception 'Privately replace all four provisioned Auth fixture UUIDs'; end if;
    v_users := array_append(v_users,v_inputs[v_i]::uuid);
    if not exists(select 1 from auth.users where id=v_users[v_i] and email is not null
      and ((v_i<=3 and email_confirmed_at is not null) or (v_i=4 and email_confirmed_at is null))) then
      raise exception 'Auth fixture % has incorrect existence/email/confirmation state',v_i;
    end if;
    v_emails := array_append(v_emails,(select app_private.normalize_invitation_email(email) from auth.users where id=v_users[v_i]));
  end loop;
  if (select count(distinct x) from unnest(v_users) x)<>4
    or (select count(distinct x) from unnest(v_emails) x)<>4 then raise exception 'Use four distinct accounts and emails'; end if;

  -- All private objects deny table AND column access, even for service_role.
  foreach v_name in array array['league_invitations','invitation_requests','invitation_delivery_attempts','invitation_audit_events'] loop
    select c.* into strict v_table from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
      where n.nspname='app_private' and c.relname=v_name and c.relkind='r';
    if not v_table.relrowsecurity then raise exception 'Private table lacks RLS: %',v_name; end if;
    if exists(select 1 from pg_catalog.pg_policy where polrelid=v_table.oid) then raise exception 'Unexpected private policy: %',v_name; end if;
    if exists(select 1 from pg_catalog.aclexplode(coalesce(v_table.relacl,pg_catalog.acldefault('r',v_table.relowner))) a where a.grantee=0) then
      raise exception 'PUBLIC private table privilege: %',v_name;
    end if;
    foreach v_role in array array['anon','authenticated','service_role'] loop
      for v_privilege in select privilege_type from pg_catalog.aclexplode(pg_catalog.acldefault('r',v_table.relowner)) loop
        if has_table_privilege(v_role,v_table.oid,v_privilege) then raise exception 'Private table grant: %/%',v_name,v_role; end if;
      end loop;
      for v_column in select * from pg_catalog.pg_attribute where attrelid=v_table.oid and attnum>0 and not attisdropped loop
        if exists(select 1 from pg_catalog.aclexplode(v_column.attacl) a where a.grantee=0) then raise exception 'PUBLIC private column grant'; end if;
        foreach v_privilege in array array['SELECT','INSERT','UPDATE','REFERENCES'] loop
          if has_column_privilege(v_role,v_table.oid,v_column.attnum,v_privilege) then raise exception 'Private column grant'; end if;
        end loop;
      end loop;
    end loop;
  end loop;
  -- Exact public API signatures; internal helpers must not be callable directly.
  for v_case in select * from (values
    ('public.issue_invitation(uuid,uuid,text,text)',true),
    ('public.prepare_invitation_resend(uuid,uuid,uuid)',true),
    ('public.revoke_invitation(uuid,uuid,uuid)',true),
    ('public.claim_invitation(uuid,uuid,uuid)',true),
    ('public.list_commissioner_invitations(uuid)',true),
    ('public.list_my_invitations()',true),
    ('app_private.mutate_invitation(text,uuid,uuid,uuid,text,text)',false),
    ('app_private.normalize_invitation_email(text)',false)
  ) signatures(signature,is_public) loop
    select p.*,r.rolname into strict v_fn from pg_catalog.pg_proc p join pg_catalog.pg_roles r on r.oid=p.proowner
      where p.oid=to_regprocedure(v_case.signature);
    if v_fn.rolname<>'postgres' or not ('search_path=""'=any(coalesce(v_fn.proconfig,array[]::text[])))
      or v_fn.prosecdef is distinct from v_case.is_public then raise exception 'Unsafe function: %',v_case.signature; end if;
    if has_function_privilege('authenticated',v_fn.oid,'EXECUTE') is distinct from v_case.is_public
      or has_function_privilege('anon',v_fn.oid,'EXECUTE') or has_function_privilege('service_role',v_fn.oid,'EXECUTE')
      or exists(select 1 from pg_catalog.aclexplode(coalesce(v_fn.proacl,pg_catalog.acldefault('f',v_fn.proowner))) a where a.grantee=0)
      then raise exception 'Wrong function ACL: %',v_case.signature; end if;
  end loop;
  if app_private.normalize_invitation_email(E' \tA.B+Tag@EXAMPLE.INVALID\n')<>'a.b+tag@example.invalid'
    or app_private.normalize_invitation_email('ab@example.invalid')=app_private.normalize_invitation_email('a.b@example.invalid')
    or app_private.normalize_invitation_email('ab@example.invalid')=app_private.normalize_invitation_email('ab+tag@example.invalid') then
    raise exception 'Email normalization changed dots/plus or failed whitespace/case';
  end if;

  select x into v_season from generate_series(9998,1900,-1) x where not exists(select 1 from public.nfl_seasons where season_year=x) order by x desc limit 1;
  if v_season is null then raise exception 'No unused synthetic season'; end if;
  insert into public.nfl_seasons values(v_season,v_season+1,now());
  for v_i in 1..5 loop
    insert into public.leagues(id,season_year,name,manager_count,draft_rounds)
      values(v_leagues[v_i],v_season,'SYNTHETIC invitation verification '||v_i,case when v_i in (2,5) then 2 else 3 end,8);
    insert into public.league_scoring_versions(league_id,version) values(v_leagues[v_i],1);
    insert into public.league_memberships(league_id,user_id,display_name,role)
      values(v_leagues[v_i],case when v_i=3 then v_users[3] else v_users[1] end,'SYNTHETIC commissioner','commissioner');
  end loop;
  insert into public.league_memberships(league_id,user_id,display_name) values(v_leagues[1],v_users[3],'SYNTHETIC ordinary member');
  insert into public.league_memberships(league_id,display_name) values(v_leagues[5],'SYNTHETIC detached durable membership');

  perform set_config('request.jwt.claim.sub',v_users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v_first := public.issue_invitation(v_leagues[1],v_key,'SYNTHETIC recipient',E' \t'||upper(v_emails[2])||E'\n');
  if v_first->>'status' is distinct from 'prepared' then raise exception 'Issue failed'; end if;
  v_invite := (v_first->>'invitation_id')::uuid;
  v_attempt := (v_first->>'attempt_id')::uuid;
  if public.issue_invitation(v_leagues[1],v_key,'SYNTHETIC recipient',v_emails[2]) is distinct from v_first then raise exception 'Issue retry changed result'; end if;
  v_result := public.issue_invitation(v_leagues[1],gen_random_uuid(),'Ignored duplicate name',v_emails[2]);
  if v_result->>'status' is distinct from 'existing_reservation' or (v_result->>'invitation_id')::uuid<>v_invite or v_result?'attempt_id' then
    raise exception 'Duplicate reserved another slot/send'; end if;
  v_result := public.issue_invitation(v_leagues[1],gen_random_uuid(),'SYNTHETIC full','synthetic-full@example.invalid');
  if v_result->>'status' is distinct from 'capacity_full' then raise exception 'Capacity overbooked'; end if;
  v_result := public.list_commissioner_invitations(v_leagues[1]);
  if jsonb_array_length(v_result)<>1 or v_result->0->>'email' is distinct from v_emails[2]
    or (v_result->0->>'invitation_id')::uuid is distinct from v_invite then raise exception 'Commissioner listing incorrect'; end if;
  v_result := public.prepare_invitation_resend(v_leagues[1],v_invite,gen_random_uuid());
  if v_result->>'status' is distinct from 'cooldown' then raise exception 'Cooldown missing'; end if;
  v_denied:=false;
  begin perform public.issue_invitation(v_leagues[1],v_key,'Conflicting name',v_emails[2]);
  exception when invalid_parameter_value then v_denied:=true; end;
  if not v_denied then raise exception 'Conflicting request key accepted'; end if;
  for v_case in select * from (values
    (format('select public.list_commissioner_invitations(%L)',v_leagues[3])),
    (format('select public.issue_invitation(%L,gen_random_uuid(),''x'',''x@example.invalid'')',v_leagues[3])),
    (format('select public.prepare_invitation_resend(%L,%L,gen_random_uuid())',v_leagues[3],v_invite)),
    (format('select public.revoke_invitation(%L,%L,gen_random_uuid())',v_leagues[3],v_invite))
  ) cases(command) loop
    v_denied:=false;
    begin execute v_case.command; exception when insufficient_privilege then v_denied:=true; end;
    if not v_denied then raise exception 'Cross-league commissioner operation allowed'; end if;
  end loop;
  execute 'reset role';
  if (select count(*) from app_private.invitation_delivery_attempts where invitation_id=v_invite)<>1 then raise exception 'Duplicate attempt persisted'; end if;
  if not exists(select 1 from app_private.league_invitations where id=v_invite and expires_at=created_at+interval '168 hours' and email_normalized=v_emails[2]) then
    raise exception 'Initial TTL/normalization incorrect'; end if;

  -- Age ONLY synthetic application fixtures; never modify Auth or sleep 60s.
  update app_private.league_invitations set created_at=created_at-interval '2 minutes',expires_at=expires_at-interval '2 minutes',
    last_prepared_at=last_prepared_at-interval '61 seconds' where id=v_invite;
  select expires_at into v_expiry from app_private.league_invitations where id=v_invite;
  execute 'set local role authenticated';
  v_result := public.prepare_invitation_resend(v_leagues[1],v_invite,gen_random_uuid());
  if v_result->>'status' is distinct from 'prepared' or (v_result->>'expires_at')::timestamptz is distinct from v_expiry then raise exception 'Resend extended expiry or failed'; end if;
  execute 'reset role';
  if not exists(select 1 from app_private.invitation_delivery_attempts where id=v_attempt and state='superseded')
    or (select count(*) from app_private.invitation_delivery_attempts where invitation_id=v_invite and state='prepared')<>1 then raise exception 'Resend attempt generation incorrect'; end if;

  -- Revoke frees the actual LAST slot; old successful request stays unchanged.
  execute 'set local role authenticated';
  if public.revoke_invitation(v_leagues[1],v_invite,gen_random_uuid())->>'status' is distinct from 'revoked' then raise exception 'Last-slot revoke failed'; end if;
  if public.issue_invitation(v_leagues[1],v_key,'SYNTHETIC recipient',v_emails[2]) is distinct from v_first then raise exception 'Original issue outcome changed after revoke'; end if;
  v_result := public.issue_invitation(v_leagues[1],gen_random_uuid(),'SYNTHETIC recipient',v_emails[2]);
  if v_result->>'status' is distinct from 'prepared' then raise exception 'Revocation did not release last slot'; end if;
  v_invite := (v_result->>'invitation_id')::uuid;
  execute 'reset role';

  -- C is an ordinary member of league 1. JWT email deliberately lies: canonical
  -- auth.users email must win. No private table, helper or manager RPC access.
  perform set_config('request.jwt.claim.sub',v_users[3]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[3],'role','authenticated','email',v_emails[2])::text,true);
  execute 'set local role authenticated';
  for v_case in select * from (values
    (format('select public.issue_invitation(%L,gen_random_uuid(),''x'',''x@example.invalid'')',v_leagues[1])),
    (format('select public.prepare_invitation_resend(%L,%L,gen_random_uuid())',v_leagues[1],v_invite)),
    (format('select public.revoke_invitation(%L,%L,gen_random_uuid())',v_leagues[1],v_invite)),
    (format('select public.list_commissioner_invitations(%L)',v_leagues[1])),
    (format('select public.claim_invitation(%L,%L,gen_random_uuid())',v_leagues[1],v_invite)),
    ('select * from app_private.league_invitations'),
    ('select * from app_private.invitation_requests'),
    ('select * from app_private.invitation_delivery_attempts'),
    ('select * from app_private.invitation_audit_events'),
    ('update app_private.invitation_delivery_attempts set state=''accepted'''),
    ('select app_private.normalize_invitation_email(''x@example.invalid'')'),
    ('select app_private.mutate_invitation(''issue'',null,null,null,null,null)')
  ) cases(command) loop
    v_denied:=false;
    begin execute v_case.command; exception when insufficient_privilege then v_denied:=true; end;
    if not v_denied then raise exception 'Forbidden RPC/private operation succeeded'; end if;
  end loop;
  if exists(select 1 from jsonb_array_elements(public.list_my_invitations()) x where (x->>'league_id')::uuid=any(v_leagues)) then
    raise exception 'Wrong recipient saw an invitation through forged JWT email'; end if;
  execute 'reset role';

  -- Intended recipient sees only their offer, without manager-private fields.
  perform set_config('request.jwt.claim.sub',v_users[2]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[2],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select x into v_result from jsonb_array_elements(public.list_my_invitations()) x where (x->>'invitation_id')::uuid=v_invite;
  if v_result is null or (select count(*) from jsonb_object_keys(v_result))<>5
    or exists(select 1 from jsonb_object_keys(v_result) k where k not in ('invitation_id','league_id','league_name','display_name','expires_at')) then raise exception 'Recipient offer missing/leaked private fields'; end if;
  if exists(select 1 from public.leagues where id=v_leagues[1]) then raise exception 'Invitation granted membership before claim'; end if;
  execute 'reset role';

  -- Issuer demotion removes all management access, including old-key retries,
  -- but does not invalidate the previously authorized reservation.
  update public.league_memberships set role='member',updated_at=clock_timestamp() where league_id=v_leagues[1] and user_id=v_users[1];
  perform set_config('request.jwt.claim.sub',v_users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  for v_case in select * from (values
    (format('select public.issue_invitation(%L,%L,''SYNTHETIC recipient'',%L)',v_leagues[1],v_key,v_emails[2])),
    (format('select public.prepare_invitation_resend(%L,%L,gen_random_uuid())',v_leagues[1],v_invite)),
    (format('select public.revoke_invitation(%L,%L,gen_random_uuid())',v_leagues[1],v_invite)),
    (format('select public.list_commissioner_invitations(%L)',v_leagues[1]))
  ) cases(command) loop
    v_denied:=false;
    begin execute v_case.command; exception when insufficient_privilege then v_denied:=true; end;
    if not v_denied then raise exception 'Former commissioner retained management'; end if;
  end loop;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',v_users[2]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[2],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v_claim := public.claim_invitation(v_leagues[1],v_invite,v_claim_key);
  if v_claim->>'status' is distinct from 'claimed' then raise exception 'Valid recipient could not claim after issuer demotion'; end if;
  v_denied:=false;
  begin perform public.claim_invitation(v_leagues[1],gen_random_uuid(),v_claim_key);
  exception when invalid_parameter_value then v_denied:=true; end;
  if not v_denied then raise exception 'Claim request key accepted conflicting invitation'; end if;
  if public.claim_invitation(v_leagues[1],v_invite,v_claim_key) is distinct from v_claim
    or public.claim_invitation(v_leagues[1],v_invite,gen_random_uuid()) is distinct from v_claim then raise exception 'Repeated claim changed result'; end if;
  if not exists(select 1 from public.leagues where id=v_leagues[1]) then raise exception 'Claim did not grant RLS membership'; end if;
  execute 'reset role';
  if not exists(select 1 from public.league_memberships where id=(v_claim->>'membership_id')::uuid
    and league_id=v_leagues[1] and user_id=v_users[2] and role='member' and departed_at is null) then raise exception 'Claim role/identity incorrect'; end if;
  select to_jsonb(r) into v_snapshot from app_private.invitation_requests r where league_id=v_leagues[1] and actor_user_id=v_users[2] and request_key=v_claim_key;

  -- League 2: revocation, expiry/reissue, multiple-league claim, post-start gate.
  perform set_config('request.jwt.claim.sub',v_users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v_result := public.issue_invitation(v_leagues[2],gen_random_uuid(),'SYNTHETIC recipient',v_emails[2]);
  v_other := (v_result->>'invitation_id')::uuid;
  v_result := public.revoke_invitation(v_leagues[2],v_other,gen_random_uuid());
  if v_result->>'status' is distinct from 'revoked' then raise exception 'Revoke failed'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',v_users[2]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[2],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if public.claim_invitation(v_leagues[2],v_other,gen_random_uuid())->>'status' is distinct from 'unavailable' then raise exception 'Revoked invitation claimed'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',v_users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v_result := public.issue_invitation(v_leagues[2],gen_random_uuid(),'SYNTHETIC recipient',v_emails[2]);
  v_expired := (v_result->>'invitation_id')::uuid;
  execute 'reset role';
  update app_private.league_invitations set created_at=created_at-interval '8 days',expires_at=expires_at-interval '8 days' where id=v_expired;
  perform set_config('request.jwt.claim.sub',v_users[2]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[2],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if public.claim_invitation(v_leagues[2],v_expired,gen_random_uuid())->>'status' is distinct from 'unavailable' then raise exception 'Expired invitation claimed'; end if;
  execute 'reset role';
  if not exists(select 1 from app_private.league_invitations where id=v_expired and state='expired') then raise exception 'Expiry not materialized'; end if;
  perform set_config('request.jwt.claim.sub',v_users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v_result := public.issue_invitation(v_leagues[2],gen_random_uuid(),'SYNTHETIC recipient',v_emails[2]);
  v_other := (v_result->>'invitation_id')::uuid;
  if v_result->>'status' is distinct from 'prepared' or v_other=v_expired then raise exception 'Expiry/revocation did not release duplicate reservation'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',v_users[2]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[2],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if public.claim_invitation(v_leagues[2],v_other,gen_random_uuid())->>'status' is distinct from 'claimed' then raise exception 'Account could not join second league'; end if;
  execute 'reset role';
  update public.leagues set manager_count=3,updated_at=clock_timestamp() where id=v_leagues[2]; -- Owner fixture only.
  perform set_config('request.jwt.claim.sub',v_users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if public.issue_invitation(v_leagues[2],gen_random_uuid(),'Ignored',v_emails[2])->>'status' is distinct from 'already_member' then raise exception 'Missing already-member result'; end if;
  v_result := public.issue_invitation(v_leagues[2],gen_random_uuid(),'SYNTHETIC C',v_emails[3]);
  v_other := (v_result->>'invitation_id')::uuid;
  execute 'reset role';

  -- Owner fixture simulates started/frozen storage, NOT a draft-start RPC.
  for v_i in 1..2 loop
    insert into public.drafts(league_id,season_year,scoring_version,manager_count,rounds,status,
      order_finalized_at,pool_finalized_at,frozen_at,started_at,pick_cutoff_at)
    values(v_leagues[v_i],v_season,1,3,8,'paused',now(),now(),now(),now(),now()+interval '1 day');
  end loop;
  perform set_config('request.jwt.claim.sub',v_users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if public.issue_invitation(v_leagues[2],gen_random_uuid(),'Blocked','blocked@example.invalid')->>'status' is distinct from 'draft_started'
    or public.prepare_invitation_resend(v_leagues[2],v_other,gen_random_uuid())->>'status' is distinct from 'draft_started' then raise exception 'Post-start issue/resend allowed'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',v_users[3]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[3],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if public.claim_invitation(v_leagues[2],v_other,gen_random_uuid())->>'status' is distinct from 'draft_started' then raise exception 'Post-start claim allowed'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',v_users[2]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[2],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if public.claim_invitation(v_leagues[1],v_invite,v_claim_key) is distinct from v_claim
    or public.claim_invitation(v_leagues[1],v_invite,gen_random_uuid()) is distinct from v_claim then raise exception 'Successful claim retry failed after start'; end if;
  execute 'reset role';
  update public.league_memberships set departed_at=clock_timestamp(),updated_at=clock_timestamp() where id=(v_claim->>'membership_id')::uuid;
  execute 'set local role authenticated';
  if public.claim_invitation(v_leagues[1],v_invite,gen_random_uuid()) is distinct from v_claim then raise exception 'Original success lost after departure'; end if;
  execute 'reset role';
  if not exists(select 1 from public.league_memberships where id=(v_claim->>'membership_id')::uuid and departed_at is not null)
    or (select to_jsonb(r) from app_private.invitation_requests r where league_id=v_leagues[1] and actor_user_id=v_users[2] and request_key=v_claim_key) is distinct from v_snapshot then
    raise exception 'Retry restored departed member or altered original request'; end if;

  -- Pending claim must not restore a departed member; detached rows count too.
  perform set_config('request.jwt.claim.sub',v_users[1]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[1],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  v_result := public.issue_invitation(v_leagues[4],gen_random_uuid(),'SYNTHETIC B',v_emails[2]);
  v_other := (v_result->>'invitation_id')::uuid;
  v_result := public.issue_invitation(v_leagues[4],gen_random_uuid(),'SYNTHETIC D',v_emails[4]);
  v_unconfirmed := (v_result->>'invitation_id')::uuid;
  if public.issue_invitation(v_leagues[5],gen_random_uuid(),'Full',v_emails[2])->>'status' is distinct from 'capacity_full' then raise exception 'Detached durable member ignored in capacity'; end if;
  execute 'reset role';
  insert into public.league_memberships(league_id,user_id,display_name,departed_at) values(v_leagues[4],v_users[2],'SYNTHETIC departed',now());
  perform set_config('request.jwt.claim.sub',v_users[2]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[2],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if public.claim_invitation(v_leagues[4],v_other,gen_random_uuid())->>'status' is distinct from 'departed_member' then raise exception 'Departed membership restored'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',v_users[4]::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_users[4],'role','authenticated')::text,true);
  execute 'set local role authenticated';
  if exists(select 1 from jsonb_array_elements(public.list_my_invitations()) x where (x->>'league_id')::uuid=any(v_leagues)) then raise exception 'Unconfirmed email saw private offer'; end if;
  v_denied:=false;
  begin perform public.claim_invitation(v_leagues[4],v_unconfirmed,gen_random_uuid());
  exception when insufficient_privilege then v_denied:=true; end;
  if not v_denied then raise exception 'Unconfirmed email claimed'; end if;
  execute 'reset role';

  execute 'set local role anon';
  for v_case in select * from (values
    ('select public.list_my_invitations()'),
    (format('select public.list_commissioner_invitations(%L)',v_leagues[2])),
    (format('select public.issue_invitation(%L,gen_random_uuid(),''x'',''x@example.invalid'')',v_leagues[2])),
    (format('select public.prepare_invitation_resend(%L,%L,gen_random_uuid())',v_leagues[2],v_other)),
    (format('select public.revoke_invitation(%L,%L,gen_random_uuid())',v_leagues[2],v_other)),
    (format('select public.claim_invitation(%L,%L,gen_random_uuid())',v_leagues[2],v_other)),
    ('select * from app_private.league_invitations')
  ) cases(command) loop
    v_denied:=false;
    begin execute v_case.command; exception when insufficient_privilege then v_denied:=true; end;
    if not v_denied then raise exception 'Anonymous invitation access'; end if;
  end loop;
  execute 'reset role';
  -- Owner-level FK probes isolate same-league history references from RLS.
  for v_case in select * from (values
    (format('insert into app_private.invitation_audit_events(league_id,invitation_id,request_id,actor_user_id,event_type,created_at) values(%L,%L,%L,%L,''claimed'',clock_timestamp())',
      v_leagues[4],v_other,(v_snapshot->>'id')::uuid,v_users[1]),'invitation_audit_events_league_id_request_id_fkey'),
    (format('insert into app_private.invitation_delivery_attempts(league_id,invitation_id,request_id,generation,state,prepared_at,updated_at) values(%L,%L,%L,999999,''superseded'',now(),now())',
      v_leagues[4],v_other,(v_snapshot->>'id')::uuid),'invitation_delivery_attempts_league_id_request_id_fkey')
  ) cases(command,expected_constraint) loop
    v_denied:=false;
    begin
      execute v_case.command;
    exception when foreign_key_violation then
      get stacked diagnostics v_constraint=constraint_name;
      if v_constraint is distinct from v_case.expected_constraint then raise exception 'Wrong cross-league FK: %',v_constraint; end if;
      v_denied:=true;
    end;
    if not v_denied then raise exception 'Cross-league history FK allowed'; end if;
  end loop;
  if not exists(select 1 from app_private.invitation_audit_events where league_id=any(v_leagues) and event_type='claimed')
    or not exists(select 1 from app_private.invitation_audit_events where league_id=any(v_leagues) and event_type='resend_prepared')
    or not exists(select 1 from app_private.invitation_audit_events where league_id=any(v_leagues) and event_type='revoked')
    or not exists(select 1 from app_private.invitation_audit_events where league_id=any(v_leagues) and event_type='expired') then raise exception 'Lifecycle audit missing'; end if;
  raise notice 'Invitation database assertions passed; ROLLBACK follows.';
end;
$verification$;
select 'PASS' as league_invitations_verification;
rollback;
