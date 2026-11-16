-- Shallpick: 폴더(방) + 멤버 + 초대 코드
-- 폴더 만들기/코드로 참여하기는 아래 RPC 로만 합니다. (테이블 insert 정책 없음)

-- 헷갈리는 글자(0/O, 1/I/L)를 뺀 6자리 대문자 코드
create function public.generate_invite_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(
    substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', (floor(random() * 31) + 1)::int, 1),
    ''
  )
  from generate_series(1, 6);
$$;

create table public.folders (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(btrim(name)) between 1 and 30),
  owner_id     uuid not null references auth.users (id) on delete cascade,
  invite_code  text not null unique default public.generate_invite_code(),
  created_at   timestamptz not null default now()
);

comment on table public.folders is '사진을 같이 모으는 폴더(방)';

create table public.folder_members (
  folder_id  uuid not null references public.folders (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (folder_id, user_id)
);

create index folder_members_user_id_idx on public.folder_members (user_id);

comment on table public.folder_members is '폴더 참여자';

-- RLS 정책 안에서 folder_members 를 다시 조회하면 무한 재귀가 생기므로 security definer 로 분리
create function public.is_folder_member(target_folder_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.folder_members
    where folder_id = target_folder_id
      and user_id = (select auth.uid())
  );
$$;

alter table public.folders enable row level security;
alter table public.folder_members enable row level security;

create policy "참여한 폴더 조회"
  on public.folders for select
  to authenticated
  using (public.is_folder_member(id));

create policy "내 폴더 이름 수정"
  on public.folders for update
  to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

create policy "내 폴더 삭제"
  on public.folders for delete
  to authenticated
  using ((select auth.uid()) = owner_id);

create policy "같은 폴더 멤버 조회"
  on public.folder_members for select
  to authenticated
  using (public.is_folder_member(folder_id));

create policy "폴더 나가기"
  on public.folder_members for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- 새 폴더 만들기: 폴더 생성 + 만든 사람을 멤버로 추가
create function public.create_folder(folder_name text)
returns public.folders
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  new_folder public.folders;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- 초대 코드가 겹치면 다시 시도
  loop
    begin
      insert into public.folders (name, owner_id)
      values (btrim(folder_name), uid)
      returning * into new_folder;
      exit;
    exception when unique_violation then
      -- retry
    end;
  end loop;

  insert into public.folder_members (folder_id, user_id)
  values (new_folder.id, uid);

  return new_folder;
end;
$$;

-- 코드로 참여하기: 이미 참여한 폴더면 그대로 돌려줌
create function public.join_folder(code text)
returns public.folders
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  target public.folders;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into target
  from public.folders
  where invite_code = upper(btrim(code));

  if not found then
    raise exception 'invalid_invite_code' using errcode = 'P0002';
  end if;

  insert into public.folder_members (folder_id, user_id)
  values (target.id, uid)
  on conflict do nothing;

  return target;
end;
$$;

revoke execute on function public.create_folder(text) from public, anon;
revoke execute on function public.join_folder(text) from public, anon;
grant execute on function public.create_folder(text) to authenticated;
grant execute on function public.join_folder(text) to authenticated;
