-- Run only against an empty disposable PostgreSQL 15+ database, never production.
\set ON_ERROR_STOP on
create role anon nologin;
create role authenticated nologin;
create schema auth;
create schema storage;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth, storage, public to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
alter default privileges in schema public grant all on tables to authenticated;
create table public.profiles (id uuid primary key, nickname text, avatar_url text);
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key, bucket_id text, name text, owner_id text);
create function storage.foldername(text) returns text[] language sql immutable as
$$ select string_to_array($1, '/') $$;
create publication supabase_realtime;

-- Use the repository's real table definitions and RLS, not test replacements.
\ir ../../supabase/migrations/20261116010000_create_folders.sql
\ir ../../supabase/migrations/20261116030000_create_messages.sql
\ir ../../supabase/migrations/20261117000000_create_photos.sql
\ir ../../supabase/migrations/20261117010000_message_photos.sql
\ir ../../supabase/migrations/20261118000000_message_recipients.sql
\ir ../../supabase/migrations/20261118010000_photo_reactions_comments.sql
\ir ../../supabase/migrations/20261118030000_question_votes_pins.sql
\ir ../../supabase/migrations/20261119162049_photo_comment_chat_timeline.sql
-- Idempotent reapplication must not add the publication table twice.
\ir ../../supabase/migrations/20261119162049_photo_comment_chat_timeline.sql

create function public.assert_true(ok boolean, description text) returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'FAIL: %', description; end if;
  raise notice 'PASS: %', description;
end $$;

insert into auth.users values
 ('00000000-0000-0000-0000-000000000001'),
 ('00000000-0000-0000-0000-000000000002'),
 ('00000000-0000-0000-0000-000000000003');
insert into public.folders(id,name,owner_id) values
 ('10000000-0000-0000-0000-000000000001','Shared','00000000-0000-0000-0000-000000000001');
insert into public.folder_members(folder_id,user_id) values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002');
insert into public.photos(id,folder_id,uploader_id,storage_path) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001/photo.jpg');
insert into public.messages(id,folder_id,user_id,body,photo_ids,created_at) values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','Question',array['20000000-0000-0000-0000-000000000001'::uuid],'2026-11-18T10:00:00Z');

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
-- Deliberately use the same UUID as the ordinary message; entry_id must distinguish them.
insert into public.photo_comments(id,photo_id,body,created_at) values
 ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Keep this one','2026-11-18T11:00:00Z');
insert into public.question_pins(id,message_id,photo_id,folder_id,x,y,body) values
 ('40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',0.5,0.5,'Private to question context');
select assert_true((select count(*)=2 from public.folder_chat_timeline), 'message and ordinary comment appear once; question pin excluded');
select assert_true((select count(distinct entry_id)=2 from public.folder_chat_timeline), 'source IDs avoid message/comment UUID collisions');
select assert_true((select count(*)=1 from public.messages), 'comment is never copied into messages');
select assert_true((select source_comment_id=id and cardinality(photo_ids)=1 and cardinality(recipient_ids)=0 and created_at='2026-11-18T11:00:00Z' from public.folder_chat_timeline where source_comment_id is not null), 'photo, author context, original date preserved');

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select assert_true((select count(*)=2 from public.folder_chat_timeline), 'second folder member sees the same comment');
select assert_true((select count(*)=1 from public.folder_chat_timeline where user_id<>auth.uid() and created_at>'2026-11-18T10:30:00Z'), 'unread count includes new comments but not older messages');
delete from public.photo_comments;
select assert_true((select count(*)=1 from public.photo_comments), 'a different member cannot delete the author comment');

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
select assert_true((select count(*)=0 from public.folder_chat_timeline), 'outsider sees no message or comment through the view');
do $$ begin
  begin
    insert into public.photo_comments(photo_id,body) values ('20000000-0000-0000-0000-000000000001','Blocked');
    raise exception 'outsider insert unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select assert_true(not has_table_privilege('anon','public.folder_chat_timeline','SELECT'), 'anonymous cannot read the view');
select assert_true((select count(*)=1 from pg_publication_tables where pubname='supabase_realtime' and tablename='photo_comments'), 'ordinary comment change events published once');

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
delete from public.photo_comments where id='30000000-0000-0000-0000-000000000001';
select assert_true((select count(*)=1 from public.folder_chat_timeline), 'deleting own comment removes the chat entry immediately');
insert into public.photo_comments(photo_id,body) values ('20000000-0000-0000-0000-000000000001','Another comment');
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
delete from public.photos where id='20000000-0000-0000-0000-000000000001';
select assert_true((select count(*)=0 from public.photo_comments), 'photo deletion cascades to comments');
select assert_true((select count(*)=1 from public.folder_chat_timeline), 'deleted photo comments disappear while original question remains');
reset role;
