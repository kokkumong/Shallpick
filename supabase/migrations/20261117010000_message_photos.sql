-- Shallpick: 채팅 메시지에 폴더 사진 첨부 (질문)
-- 폴더 화면/채팅방의 수달 버튼으로 고른 사진 id 를 고른 순서대로 남깁니다.
-- 같은 폴더의 사진만 붙일 수 있고, 사진이 나중에 지워지면 앱에서 빈 자리는 건너뜁니다.

alter table public.messages
  add column photo_ids uuid[] not null default '{}'
    constraint messages_photo_ids_max check (cardinality(photo_ids) <= 30);

comment on column public.messages.photo_ids is '첨부한 폴더 사진 (public.photos.id, 고른 순서)';

create function public.check_message_photos()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
    from unnest(new.photo_ids) as attached(photo_id)
    where not exists (
      select 1 from public.photos p
      where p.id = attached.photo_id
        and p.folder_id = new.folder_id
    )
  ) then
    raise exception '같은 폴더의 사진만 첨부할 수 있어요' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger messages_check_photos
  before insert or update of photo_ids, folder_id on public.messages
  for each row
  when (cardinality(new.photo_ids) > 0)
  execute function public.check_message_photos();
