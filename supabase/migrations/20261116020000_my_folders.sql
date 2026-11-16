-- Shallpick: 메인 화면 폴더 목록
-- profiles 는 본인 것만 조회되므로, 같은 폴더 멤버의 닉네임은 이 함수로만 내려줍니다.

create function public.my_folders()
returns table (
  id            uuid,
  name          text,
  owner_id      uuid,
  invite_code   text,
  created_at    timestamptz,
  member_names  text[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    f.id,
    f.name,
    f.owner_id,
    f.invite_code,
    f.created_at,
    array_agg(coalesce(p.nickname, '샬픽 사용자') order by m.joined_at) as member_names
  from public.folder_members me
  join public.folders f on f.id = me.folder_id
  join public.folder_members m on m.folder_id = f.id
  left join public.profiles p on p.id = m.user_id
  where me.user_id = (select auth.uid())
  group by f.id, me.joined_at
  -- 최근에 만들거나 참여한 폴더가 위로
  order by me.joined_at desc;
$$;

revoke execute on function public.my_folders() from public, anon;
grant execute on function public.my_folders() to authenticated;
