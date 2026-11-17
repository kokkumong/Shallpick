-- Shallpick: 질문 받을 사람
-- 폴더 사진을 골라 수달로 질문을 보낼 때 받을 멤버를 고릅니다.
-- 비어 있으면 보통 채팅(폴더 모두). 메시지는 폴더 모두가 채팅에서 보고, 질문 알림만 받을 사람에게 뜹니다.

alter table public.messages
  add column recipient_ids uuid[] not null default '{}'
    constraint messages_recipient_ids_max check (cardinality(recipient_ids) <= 100);

comment on column public.messages.recipient_ids is '질문 알림을 받을 멤버 (auth.users.id). 비면 폴더 모두';
