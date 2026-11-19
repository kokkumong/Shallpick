-- One source of truth: comments are projected into chat, never copied into messages.
create or replace view public.folder_chat_timeline
with (security_invoker = true)
as
select
  'message:' || m.id::text as entry_id,
  m.id, m.folder_id, m.user_id, m.body, m.created_at,
  m.photo_ids, m.recipient_ids, null::uuid as source_comment_id
from public.messages m
union all
select
  'photo_comment:' || c.id::text as entry_id,
  c.id, p.folder_id, c.user_id, c.body, c.created_at,
  array[c.photo_id]::uuid[] as photo_ids,
  '{}'::uuid[] as recipient_ids,
  c.id as source_comment_id
from public.photo_comments c
join public.photos p on p.id = c.photo_id;

comment on view public.folder_chat_timeline is
  'Folder messages and ordinary photo comments; excludes question_pins. Underlying RLS applies.';

revoke all on public.folder_chat_timeline from public, anon;
grant select on public.folder_chat_timeline to authenticated;

-- Realtime is an invalidation signal; clients re-read through the RLS-protected view.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'photo_comments'
     ) then
    alter publication supabase_realtime add table public.photo_comments;
  end if;
end $$;
