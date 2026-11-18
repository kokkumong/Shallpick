-- Shallpick: 사진 질문 응답 (좋아/싫어 + 사진 위 한 점에 남기는 댓글)
-- 질문(사진이 붙은 메시지)을 받은 사람이 사진마다 위/아래로 넘겨 좋아/싫어를 남기고,
-- 사진의 한 점을 길게 눌러 댓글을 남깁니다. 질문한 사람은 사진별로 누가 좋아/싫어했는지와 댓글을 봅니다.
-- 폴더 멤버만 보고 남길 수 있습니다.

-- 메시지가 이 폴더의 것이고 사진이 그 메시지에 붙어 있는지 (insert/update 검사용)
create function public.is_question_photo(target_message_id uuid, target_folder_id uuid, target_photo_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.messages msg
    where msg.id = target_message_id
      and msg.folder_id = target_folder_id
      and target_photo_id = any (msg.photo_ids)
  );
$$;

revoke execute on function public.is_question_photo(uuid, uuid, uuid) from public, anon;
grant execute on function public.is_question_photo(uuid, uuid, uuid) to authenticated;

-- 좋아/싫어: 한 사람이 질문의 사진마다 하나 (다시 넘기면 바꿈)
create table public.question_votes (
  message_id  uuid not null references public.messages (id) on delete cascade,
  photo_id    uuid not null references public.photos (id) on delete cascade,
  folder_id   uuid not null references public.folders (id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  vote        text not null check (vote in ('like', 'dislike')),
  created_at  timestamptz not null default now(),
  primary key (message_id, photo_id, user_id)
);

comment on table public.question_votes is '사진 질문에 남긴 좋아/싫어';

alter table public.question_votes enable row level security;

create policy "참여한 폴더 질문 좋아싫어 조회"
  on public.question_votes for select
  to authenticated
  using (public.is_folder_member(folder_id));

create policy "질문 사진에 좋아싫어 남기기"
  on public.question_votes for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and public.is_folder_member(folder_id)
    and public.is_question_photo(message_id, folder_id, photo_id)
  );

create policy "내 좋아싫어 바꾸기"
  on public.question_votes for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and public.is_folder_member(folder_id)
    and public.is_question_photo(message_id, folder_id, photo_id)
  );

create policy "내 좋아싫어 지우기"
  on public.question_votes for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- 사진 위 한 점에 남긴 댓글 (x, y 는 사진 안 비율 0~1)
create table public.question_pins (
  id          uuid primary key default gen_random_uuid(),
  message_id  uuid not null references public.messages (id) on delete cascade,
  photo_id    uuid not null references public.photos (id) on delete cascade,
  folder_id   uuid not null references public.folders (id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  x           double precision not null check (x between 0 and 1),
  y           double precision not null check (y between 0 and 1),
  body        text not null check (char_length(btrim(body)) between 1 and 300),
  created_at  timestamptz not null default now()
);

create index question_pins_message_id_idx on public.question_pins (message_id, created_at);

comment on table public.question_pins is '사진 질문의 사진 위 한 점에 남긴 댓글';

alter table public.question_pins enable row level security;

create policy "참여한 폴더 질문 댓글 조회"
  on public.question_pins for select
  to authenticated
  using (public.is_folder_member(folder_id));

create policy "질문 사진에 댓글 남기기"
  on public.question_pins for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and public.is_folder_member(folder_id)
    and public.is_question_photo(message_id, folder_id, photo_id)
  );

create policy "내 질문 댓글 지우기"
  on public.question_pins for delete
  to authenticated
  using ((select auth.uid()) = user_id);
