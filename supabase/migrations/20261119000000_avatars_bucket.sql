-- Shallpick: 프로필 사진
-- 파일은 Storage 의 공개 버킷 avatars 에 "<user_id>/<uuid>.jpg" 로 올리고,
-- public.profiles.avatar_url 에 공개 주소를 넣습니다. 본인 폴더에만 올리고 지울 수 있습니다.

-- 공개 버킷 (주소만 알면 누구나 볼 수 있음, jpeg 만, 5MB 까지)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

create policy "내 프로필 사진 파일 올리기"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "내 프로필 사진 파일 보기"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "내 프로필 사진 파일 삭제"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
