-- Shallpick: 사진 질문 "확인하러가기" 기록
-- 사진이 붙은 메시지(질문)를 받은 사람이 "확인하러가기"를 누르면 한 번 남깁니다.
-- 보낸 사람은 말풍선 아래에서 누가 확인했는지 봅니다. 폴더 멤버만 보고 남길 수 있습니다.

create table public.message_checks (
  message_id  uuid not null references public.messages (id) on delete cascade,
  -- Realtime 을 폴더로 거르려고 같이 저장 (메시지의 폴더와 같아야 함)
  folder_id   uuid not null references public.folders (id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  checked_at  timestamptz not null default now(),
  primary key (message_id, user_id)
);

create index message_checks_folder_id_idx on public.message_checks (folder_id);

comment on table public.message_checks is '사진 질문을 확인한 멤버';

alter table public.message_checks enable row level security;

create policy "참여한 폴더 질문 확인 조회"
  on public.message_checks for select
  to authenticated
  using (public.is_folder_member(folder_id));

create policy "참여한 폴더 질문 확인 남기기"
  on public.message_checks for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and public.is_folder_member(folder_id)
    and exists (
      select 1 from public.messages msg
      where msg.id = message_id
        and msg.folder_id = message_checks.folder_id
    )
  );

alter publication supabase_realtime add table public.message_checks;
