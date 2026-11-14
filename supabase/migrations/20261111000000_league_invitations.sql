-- 3B2 database slice. REVIEW ONLY: leave unapplied until separately authorized.
-- No Auth writes, email dispatch/completion, UI, or changes to applied migrations.
begin;

create function app_private.normalize_invitation_email(p_email text)
returns text language sql immutable strict set search_path = ''
as $$ select lower(btrim(p_email, E' \t\n\r\f' || chr(11))); $$;

create table app_private.league_invitations (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete restrict on update restrict,
  email_normalized text not null check (
    email_normalized = app_private.normalize_invitation_email(email_normalized)
    and length(email_normalized) <= 254
    and email_normalized ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'),
  display_name text not null check (length(btrim(display_name)) between 1 and 100),
  reserved_membership_id uuid not null unique default gen_random_uuid(),
  issuer_membership_id uuid not null,
  state text not null default 'pending' check (state in ('pending','claimed','revoked','expired')),
  created_at timestamptz not null,
  expires_at timestamptz not null,
  updated_at timestamptz not null,
  last_prepared_at timestamptz not null,
  generation integer not null default 1 check (generation > 0),
  claimed_user_id uuid, -- Immutable Auth UUID snapshot, deliberately not an Auth FK.
  claimed_membership_id uuid,
  claim_result jsonb,
  unique (league_id,id),
  foreign key (league_id,issuer_membership_id) references public.league_memberships(league_id,id) on delete restrict on update restrict,
  foreign key (league_id,claimed_membership_id) references public.league_memberships(league_id,id) on delete restrict on update restrict,
  check (expires_at = created_at + interval '168 hours'),
  check (updated_at >= created_at and last_prepared_at >= created_at),
  check ((state = 'claimed') = (claimed_user_id is not null)),
  check ((state = 'claimed') = (claimed_membership_id is not null)),
  check ((state = 'claimed') = (claim_result is not null)),
  check (claim_result is null or jsonb_typeof(claim_result) = 'object'),
  check (claimed_membership_id is null or claimed_membership_id = reserved_membership_id)
);
create unique index league_invitations_pending_email_key
  on app_private.league_invitations(league_id,email_normalized) where state='pending';
create index league_invitations_recipient_idx on app_private.league_invitations(email_normalized,expires_at) where state='pending';
create index league_invitations_issuer_idx on app_private.league_invitations(league_id,issuer_membership_id);
create index league_invitations_claimed_idx on app_private.league_invitations(league_id,claimed_membership_id);

create table app_private.invitation_requests (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete restrict on update restrict,
  actor_user_id uuid not null, -- Retry identity survives account deletion.
  request_key uuid not null,
  operation text not null check (operation in ('issue','resend','revoke','claim')),
  payload jsonb not null check (jsonb_typeof(payload)='object'),
  result jsonb not null check (jsonb_typeof(result)='object'),
  created_at timestamptz not null,
  unique (league_id,actor_user_id,request_key),
  unique (league_id,id)
);

create table app_private.invitation_delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null,
  invitation_id uuid not null,
  request_id uuid not null unique,
  generation integer not null check (generation > 0),
  -- Sending/accepted/failed/unknown and provider fields require the next slice.
  state text not null default 'prepared' check (state in ('prepared','superseded','cancelled')),
  prepared_at timestamptz not null,
  updated_at timestamptz not null,
  unique (league_id,id),
  unique (invitation_id,generation),
  foreign key (league_id,invitation_id) references app_private.league_invitations(league_id,id) on delete restrict on update restrict,
  foreign key (league_id,request_id) references app_private.invitation_requests(league_id,id) on delete restrict on update restrict,
  check (updated_at >= prepared_at)
);
create unique index invitation_attempts_one_prepared_key
  on app_private.invitation_delivery_attempts(invitation_id) where state='prepared';

create table app_private.invitation_audit_events (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null,
  invitation_id uuid not null,
  request_id uuid,
  actor_user_id uuid not null,
  event_type text not null check (event_type in ('issued','resend_prepared','revoked','expired','claimed','reservation_released')),
  created_at timestamptz not null,
  foreign key (league_id,invitation_id) references app_private.league_invitations(league_id,id) on delete restrict on update restrict,
  foreign key (league_id,request_id) references app_private.invitation_requests(league_id,id) on delete restrict on update restrict
);
create index invitation_audit_timeline_idx on app_private.invitation_audit_events(league_id,invitation_id,created_at,id);
create index invitation_audit_request_idx on app_private.invitation_audit_events(league_id,request_id);

alter table app_private.league_invitations enable row level security;
alter table app_private.invitation_requests enable row level security;
alter table app_private.invitation_delivery_attempts enable row level security;
alter table app_private.invitation_audit_events enable row level security;
revoke all on app_private.league_invitations, app_private.invitation_requests,
  app_private.invitation_delivery_attempts, app_private.invitation_audit_events
  from public, anon, authenticated, service_role;

-- Called only inside the postgres-owned public wrappers; no direct client grant.
-- Small leagues: lock ALL related rows in UUID order, avoiding divergent paths.
-- Protocol: league -> draft -> invitations -> attempts -> memberships -> Auth.
-- Future draft create/start, capacity edits and membership changes MUST follow it.
create function app_private.mutate_invitation(
  p_operation text, p_league_id uuid, p_invitation_id uuid, p_request_key uuid,
  p_display_name text default null, p_email text default null
) returns jsonb language plpgsql set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_capacity integer;
  v_started boolean := false;
  v_draft public.drafts%rowtype;
  v_inv app_private.league_invitations%rowtype;
  v_request app_private.invitation_requests%rowtype;
  v_member public.league_memberships%rowtype;
  v_email text := app_private.normalize_invitation_email(p_email);
  v_name text := btrim(p_display_name);
  v_actor_email text;
  v_confirmed timestamptz;
  v_payload jsonb;
  v_result jsonb;
  v_now timestamptz;
  v_request_id uuid := gen_random_uuid();
  v_attempt_id uuid;
  v_event text;
  v_count bigint;
begin
  if v_actor is null then raise exception using errcode='42501',message='Authentication required'; end if;
  if p_request_key is null or p_league_id is null or p_operation is null or p_operation not in ('issue','resend','revoke','claim') then
    raise exception using errcode='22023',message='Invalid invitation request';
  end if;
  if p_operation='issue' then
    if v_email is null or length(v_email)>254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
      or v_name is null or length(v_name) not between 1 and 100 then
      raise exception using errcode='22023',message='Invalid invitation name or email';
    end if;
    v_payload := jsonb_build_object('display_name',v_name,'email',v_email);
  else
    if p_invitation_id is null then raise exception using errcode='22023',message='Invalid invitation request'; end if;
    v_payload := jsonb_build_object('invitation_id',p_invitation_id);
  end if;

  select manager_count into v_capacity from public.leagues where id=p_league_id for update;
  if not found then raise exception using errcode='42501',message='Invitation unavailable'; end if;
  select * into v_draft from public.drafts where league_id=p_league_id for update;
  if found then v_started := v_draft.started_at is not null or v_draft.frozen_at is not null; end if;
  perform id from app_private.league_invitations where league_id=p_league_id order by id for update;
  perform id from app_private.invitation_delivery_attempts where league_id=p_league_id order by id for update;
  perform id from public.league_memberships where league_id=p_league_id order by id for update;

  -- Recheck current role even for management request retries: demotion revokes it.
  if p_operation<>'claim' and not exists (
    select 1 from public.league_memberships where league_id=p_league_id
      and user_id=v_actor and departed_at is null and role='commissioner'
  ) then raise exception using errcode='42501',message='Active commissioner required'; end if;

  if p_operation='claim' then
    -- Current canonical Auth state, not JWT email/user_metadata. SHARE prevents
    -- email/confirmation changes until this transaction commits. Never write Auth.
    select app_private.normalize_invitation_email(email),email_confirmed_at
      into v_actor_email,v_confirmed from auth.users where id=v_actor for share;
    if v_actor_email is null or v_confirmed is null then
      raise exception using errcode='42501',message='Confirmed email required';
    end if;
  end if;

  select * into v_request from app_private.invitation_requests
    where league_id=p_league_id and actor_user_id=v_actor and request_key=p_request_key;
  if found then
    if v_request.operation<>p_operation or v_request.payload<>v_payload then
      raise exception using errcode='22023',message='Conflicting invitation request key';
    end if;
    return v_request.result; -- Exact original outcome; never reconstructed.
  end if;

  -- A row lock alone does not advance a REPEATABLE READ snapshot. Touch the
  -- locked parent for new operations so an older-snapshot contender gets 40001
  -- instead of counting stale reservations. Never change request history.
  update public.leagues set updated_at=greatest(updated_at,clock_timestamp()) where id=p_league_id;

  if p_operation='claim' then
    select * into v_inv from app_private.league_invitations where league_id=p_league_id and id=p_invitation_id;
    if not found then raise exception using errcode='42501',message='Invitation unavailable'; end if;
    if v_inv.state='claimed' and v_inv.claimed_user_id=v_actor then
      v_result := v_inv.claim_result; -- Same account, new request key, including post-start.
    elsif v_inv.email_normalized<>v_actor_email then
      raise exception using errcode='42501',message='Invitation unavailable';
    end if;
  end if;

  v_now := clock_timestamp(); -- Sample AFTER waits, including the Auth row lock.
  if v_result is null then
    -- Logical expiry releases capacity without a cron job or unstable index predicate.
    with expired as (
      update app_private.league_invitations set state='expired',updated_at=v_now
        where league_id=p_league_id and state='pending' and expires_at<=v_now returning id
    ) insert into app_private.invitation_audit_events(league_id,invitation_id,actor_user_id,event_type,created_at)
        select p_league_id,id,v_actor,'expired',v_now from expired;
    update app_private.invitation_delivery_attempts a set state='cancelled',updated_at=v_now
      where a.league_id=p_league_id and a.state='prepared' and exists (
        select 1 from app_private.league_invitations i where i.id=a.invitation_id and i.state<>'pending');

    if v_started and p_operation in ('issue','resend','claim') then
      v_result := jsonb_build_object('status','draft_started');
    elsif p_operation='issue' then
      -- Scoped to this league; never return whether an account exists elsewhere.
      select m.* into v_member from public.league_memberships m join auth.users u on u.id=m.user_id
        where m.league_id=p_league_id and app_private.normalize_invitation_email(u.email)=v_email
        order by m.id limit 1;
      if found then
        v_result := jsonb_build_object('status',case when v_member.departed_at is null then 'already_member' else 'departed_member' end);
      else
        select * into v_inv from app_private.league_invitations
          where league_id=p_league_id and email_normalized=v_email and state='pending';
        if found then
          v_result := jsonb_build_object('status','existing_reservation','invitation_id',v_inv.id,'expires_at',v_inv.expires_at);
        else
          select (select count(*) from public.league_memberships where league_id=p_league_id and departed_at is null)
            + (select count(*) from app_private.league_invitations where league_id=p_league_id and state='pending' and expires_at>v_now)
            into v_count;
          if v_count>=v_capacity then
            v_result := jsonb_build_object('status','capacity_full');
          else
            insert into app_private.league_invitations(league_id,email_normalized,display_name,issuer_membership_id,
              created_at,expires_at,updated_at,last_prepared_at)
            select p_league_id,v_email,v_name,id,v_now,v_now+interval '168 hours',v_now,v_now
              from public.league_memberships where league_id=p_league_id and user_id=v_actor
              and departed_at is null and role='commissioner' returning * into v_inv;
            v_attempt_id := gen_random_uuid();
            v_result := jsonb_build_object('status','prepared','invitation_id',v_inv.id,'attempt_id',v_attempt_id,
              'generation',v_inv.generation,'expires_at',v_inv.expires_at,'resend_available_at',v_now+interval '60 seconds');
            v_event := 'issued';
          end if;
        end if;
      end if;
    else
      select * into v_inv from app_private.league_invitations where league_id=p_league_id and id=p_invitation_id;
      if not found then raise exception using errcode='42501',message='Invitation unavailable'; end if;
      if v_inv.state<>'pending' then
        v_result := jsonb_build_object('status','unavailable');
      elsif p_operation='revoke' then
        update app_private.league_invitations set state='revoked',updated_at=v_now where id=v_inv.id;
        v_result := jsonb_build_object('status','revoked','invitation_id',v_inv.id);
        v_event := 'revoked';
      elsif p_operation='resend' then
        if v_now<v_inv.last_prepared_at+interval '60 seconds' then
          v_result := jsonb_build_object('status','cooldown','resend_available_at',v_inv.last_prepared_at+interval '60 seconds');
        else
          update app_private.invitation_delivery_attempts set state='superseded',updated_at=v_now
            where invitation_id=v_inv.id and state='prepared';
          update app_private.league_invitations set generation=generation+1,last_prepared_at=v_now,updated_at=v_now
            where id=v_inv.id returning * into v_inv;
          v_attempt_id := gen_random_uuid();
          v_result := jsonb_build_object('status','prepared','invitation_id',v_inv.id,'attempt_id',v_attempt_id,
            'generation',v_inv.generation,'expires_at',v_inv.expires_at,'resend_available_at',v_now+interval '60 seconds');
          v_event := 'resend_prepared';
        end if;
      else -- Claim: identity was checked before expiry work; only matching email reaches here.
        select * into v_member from public.league_memberships where league_id=p_league_id and user_id=v_actor;
        if found then
          if v_member.departed_at is not null then
            v_result := jsonb_build_object('status','departed_member');
          else
            update app_private.league_invitations set state='revoked',updated_at=v_now where id=v_inv.id;
            v_result := jsonb_build_object('status','already_member');
            v_event := 'reservation_released';
          end if;
        else
          -- Defend against privileged/out-of-protocol capacity changes too.
          select (select count(*) from public.league_memberships where league_id=p_league_id and departed_at is null)
            + (select count(*) from app_private.league_invitations where league_id=p_league_id and state='pending' and expires_at>v_now)
            into v_count;
          if v_count>v_capacity then
            v_result := jsonb_build_object('status','capacity_full');
          else
            insert into public.league_memberships(id,league_id,user_id,display_name,role,created_at,updated_at)
              values(v_inv.reserved_membership_id,p_league_id,v_actor,v_inv.display_name,'member',v_now,v_now);
            v_result := jsonb_build_object('status','claimed','invitation_id',v_inv.id,'membership_id',v_inv.reserved_membership_id,'league_id',p_league_id);
            update app_private.league_invitations set state='claimed',claimed_user_id=v_actor,
              claimed_membership_id=reserved_membership_id,claim_result=v_result,updated_at=v_now where id=v_inv.id;
            v_event := 'claimed';
          end if;
        end if;
      end if;
    end if;
  end if;

  -- Business rejections (capacity, cooldown, expiry, start) are recorded outcomes.
  -- Retrying that key returns it verbatim; a genuinely new attempt needs a new key.
  insert into app_private.invitation_requests(id,league_id,actor_user_id,request_key,operation,payload,result,created_at)
    values(v_request_id,p_league_id,v_actor,p_request_key,p_operation,v_payload,v_result,v_now);
  if v_attempt_id is not null then
    insert into app_private.invitation_delivery_attempts(id,league_id,invitation_id,request_id,generation,prepared_at,updated_at)
      values(v_attempt_id,p_league_id,v_inv.id,v_request_id,v_inv.generation,v_now,v_now);
  end if;
  if v_event is not null then
    insert into app_private.invitation_audit_events(league_id,invitation_id,request_id,actor_user_id,event_type,created_at)
      values(p_league_id,v_inv.id,v_request_id,v_actor,v_event,v_now);
  end if;
  update app_private.invitation_delivery_attempts a set state='cancelled',updated_at=v_now
    where a.league_id=p_league_id and a.state='prepared' and exists (
      select 1 from app_private.league_invitations i where i.id=a.invitation_id and i.state<>'pending');
  return v_result;
end;
$$;

create function public.issue_invitation(p_league_id uuid,p_request_key uuid,p_display_name text,p_email text)
returns jsonb language sql volatile security definer set search_path = ''
as $$ select app_private.mutate_invitation('issue',p_league_id,null,p_request_key,p_display_name,p_email); $$;
create function public.prepare_invitation_resend(p_league_id uuid,p_invitation_id uuid,p_request_key uuid)
returns jsonb language sql volatile security definer set search_path = ''
as $$ select app_private.mutate_invitation('resend',p_league_id,p_invitation_id,p_request_key); $$;
create function public.revoke_invitation(p_league_id uuid,p_invitation_id uuid,p_request_key uuid)
returns jsonb language sql volatile security definer set search_path = ''
as $$ select app_private.mutate_invitation('revoke',p_league_id,p_invitation_id,p_request_key); $$;
create function public.claim_invitation(p_league_id uuid,p_invitation_id uuid,p_request_key uuid)
returns jsonb language sql volatile security definer set search_path = ''
as $$ select app_private.mutate_invitation('claim',p_league_id,p_invitation_id,p_request_key); $$;

create function public.list_commissioner_invitations(p_league_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not exists(select 1 from public.league_memberships
    where league_id=p_league_id and user_id=auth.uid() and departed_at is null and role='commissioner') then
    raise exception using errcode='42501',message='Active commissioner required';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('invitation_id',i.id,'email',i.email_normalized,
    'display_name',i.display_name,'state',case when i.state='pending' and i.expires_at<=statement_timestamp() then 'expired' else i.state end,
    'expires_at',i.expires_at,'resend_available_at',i.last_prepared_at+interval '60 seconds',
    'attempt_id',a.id,'attempt_state',a.state) order by i.created_at,i.id),'[]'::jsonb)
  into v_result from app_private.league_invitations i
  left join app_private.invitation_delivery_attempts a on a.invitation_id=i.id and a.generation=i.generation
  where i.league_id=p_league_id;
  return v_result;
end;
$$;

create function public.list_my_invitations()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('invitation_id',i.id,'league_id',i.league_id,
    'league_name',l.name,'display_name',i.display_name,'expires_at',i.expires_at) order by i.created_at,i.id),'[]'::jsonb)
  from app_private.league_invitations i join public.leagues l on l.id=i.league_id
  join auth.users u on u.id=auth.uid() and u.email_confirmed_at is not null
    and i.email_normalized=app_private.normalize_invitation_email(u.email)
  where i.state='pending' and i.expires_at>statement_timestamp()
    and not exists(select 1 from public.drafts d where d.league_id=i.league_id and (d.started_at is not null or d.frozen_at is not null));
$$;

-- Fixed owners and explicit, signature-specific ACLs; no schema-wide changes.
alter function app_private.normalize_invitation_email(text) owner to postgres;
alter function app_private.mutate_invitation(text,uuid,uuid,uuid,text,text) owner to postgres;
revoke all on function app_private.normalize_invitation_email(text),
  app_private.mutate_invitation(text,uuid,uuid,uuid,text,text) from public,anon,authenticated,service_role;
alter function public.issue_invitation(uuid,uuid,text,text) owner to postgres;
alter function public.prepare_invitation_resend(uuid,uuid,uuid) owner to postgres;
alter function public.revoke_invitation(uuid,uuid,uuid) owner to postgres;
alter function public.claim_invitation(uuid,uuid,uuid) owner to postgres;
alter function public.list_commissioner_invitations(uuid) owner to postgres;
alter function public.list_my_invitations() owner to postgres;
revoke all on function public.issue_invitation(uuid,uuid,text,text),public.prepare_invitation_resend(uuid,uuid,uuid),
  public.revoke_invitation(uuid,uuid,uuid),public.claim_invitation(uuid,uuid,uuid),
  public.list_commissioner_invitations(uuid),public.list_my_invitations() from public,anon,authenticated,service_role;
grant execute on function public.issue_invitation(uuid,uuid,text,text),public.prepare_invitation_resend(uuid,uuid,uuid),
  public.revoke_invitation(uuid,uuid,uuid),public.claim_invitation(uuid,uuid,uuid),
  public.list_commissioner_invitations(uuid),public.list_my_invitations() to authenticated;

commit;
