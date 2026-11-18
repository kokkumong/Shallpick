-- Shallpick: 사진 반응(이모지) + 사진 댓글 ("사진에 대한 생각")
-- 폴더 멤버만 보고 남길 수 있습니다. 사진이 지워지면 같이 지워집니다.

-- 사진 id 로 폴더 멤버인지 (RLS 안에서 photos 를 다시 거르지 않게 security definer)
create function public.is_photo_member(target_photo_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.photos p
    join public.folder_members m on m.folder_id = p.folder_id
    where p.id = target_photo_id
      and m.user_id = (select auth.uid())
  );
$$;

revoke execute on function public.is_photo_member(uuid) from public, anon;
grant execute on function public.is_photo_member(uuid) to authenticated;

-- 반응: 한 사람이 한 사진에 이모지마다 하나씩 (같은 이모지를 다시 누르면 앱에서 지움)
create table public.photo_reactions (
  photo_id    uuid not null references public.photos (id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  emoji       text not null check (char_length(emoji) between 1 and 16),
  created_at  timestamptz not null default now(),
  primary key (photo_id, user_id, emoji)
);

comment on table public.photo_reactions is '사진에 남긴 이모지 반응';

alter table public.photo_reactions enable row level security;

create policy "폴더 사진 반응 조회"
  on public.photo_reactions for select
  to authenticated
  using (public.is_photo_member(photo_id));

create policy "사진에 반응 남기기"
  on public.photo_reactions for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and public.is_photo_member(photo_id)
  );

create policy "내 반응 지우기"
  on public.photo_reactions for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- 댓글
create table public.photo_comments (
  id          uuid primary key default gen_random_uuid(),
  photo_id    uuid not null references public.photos (id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  body        text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at  timestamptz not null default now()
);

create index photo_comments_photo_id_created_at_idx on public.photo_comments (photo_id, created_at);

comment on table public.photo_comments is '사진에 남긴 생각(댓글)';

alter table public.photo_comments enable row level security;

create policy "폴더 사진 댓글 조회"
  on public.photo_comments for select
  to authenticated
  using (public.is_photo_member(photo_id));

create policy "사진에 댓글 남기기"
  on public.photo_comments for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and public.is_photo_member(photo_id)
  );

create policy "내 댓글 지우기"
  on public.photo_comments for delete
  to authenticated
  using ((select auth.uid()) = user_id);
