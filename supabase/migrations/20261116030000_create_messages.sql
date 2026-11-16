-- Shallpick: 폴더 채팅 (실시간)
-- 같은 폴더 멤버끼리만 읽고 쓸 수 있고, 새 메시지는 Supabase Realtime 으로 바로 전달됩니다.

create table public.messages (
  -- 앱에서 id 를 만들어 보내서, 내가 보낸 메시지가 Realtime 으로 다시 와도 중복으로 안 보이게 합니다.
  id          uuid primary key default gen_random_uuid(),
  folder_id   uuid not null references public.folders (id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  body        text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at  timestamptz not null default now()
);

create index messages_folder_id_created_at_idx on public.messages (folder_id, created_at desc);

comment on table public.messages is '폴더 채팅 메시지';

alter table public.messages enable row level security;

create policy "참여한 폴더 메시지 조회"
  on public.messages for select
  to authenticated
  using (public.is_folder_member(folder_id));

create policy "참여한 폴더에 내 이름으로 메시지 보내기"
  on public.messages for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and public.is_folder_member(folder_id)
  );

-- Realtime 으로 insert 를 받기 위해 publication 에 추가
alter publication supabase_realtime add table public.messages;

-- 채팅방에 보일 멤버 이름/사진. profiles 는 본인 것만 조회되므로 이 함수로 내려줍니다.
create function public.folder_member_profiles(target_folder_id uuid)
returns table (
  user_id     uuid,
  nickname    text,
  avatar_url  text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    m.user_id,
    coalesce(p.nickname, '샬픽 사용자') as nickname,
    p.avatar_url
  from public.folder_members m
  left join public.profiles p on p.id = m.user_id
  where m.folder_id = target_folder_id
    and public.is_folder_member(target_folder_id);
$$;

revoke execute on function public.folder_member_profiles(uuid) from public, anon;
grant execute on function public.folder_member_profiles(uuid) to authenticated;
