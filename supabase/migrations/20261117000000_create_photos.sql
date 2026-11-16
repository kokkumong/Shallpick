-- Shallpick: 폴더 사진
-- 파일은 Storage 의 비공개 버킷 photos 에 "<folder_id>/<photo_id>.jpg" 로 올리고,
-- public.photos 에 한 줄 남깁니다. 폴더 멤버만 보고 올릴 수 있습니다.

create table public.photos (
  id            uuid primary key default gen_random_uuid(),
  folder_id     uuid not null references public.folders (id) on delete cascade,
  uploader_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  storage_path  text not null unique,
  created_at    timestamptz not null default now(),
  check (storage_path like folder_id::text || '/%')
);

create index photos_folder_id_created_at_idx on public.photos (folder_id, created_at desc);

comment on table public.photos is '폴더에 올린 사진 (파일은 storage.objects 의 photos 버킷)';

alter table public.photos enable row level security;

create policy "폴더 사진 조회"
  on public.photos for select
  to authenticated
  using (public.is_folder_member(folder_id));

create policy "폴더에 사진 올리기"
  on public.photos for insert
  to authenticated
  with check (
    (select auth.uid()) = uploader_id
    and public.is_folder_member(folder_id)
  );

create policy "내가 올린 사진 삭제"
  on public.photos for delete
  to authenticated
  using ((select auth.uid()) = uploader_id);

-- Storage 버킷 (비공개, 사진만, 10MB 까지)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 10485760, array['image/jpeg'])
on conflict (id) do nothing;

-- 경로 첫 폴더가 folder_id. uuid 가 아니면 null 로 보고 거절
create function public.photo_object_folder_id(object_name text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return (storage.foldername(object_name))[1]::uuid;
exception when others then
  return null;
end;
$$;

create policy "폴더 사진 파일 보기"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'photos'
    and public.is_folder_member(public.photo_object_folder_id(name))
  );

create policy "폴더 사진 파일 올리기"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'photos'
    and public.is_folder_member(public.photo_object_folder_id(name))
  );

create policy "내가 올린 사진 파일 삭제"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'photos'
    and owner_id = (select auth.uid())::text
  );
