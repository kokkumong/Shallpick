-- Existing comments remain readable without a position. No policy or grant changes.
alter table public.photo_comments
    add column x double precision,
    add column y double precision,
    add constraint photo_comments_position_check check (
        (x is null and y is null) or
        (x is not null and y is not null and x between 0 and 1 and y between 0 and 1)
    );

comment on column public.photo_comments.x is '사진 안 댓글 위치의 가로 비율 (0~1)';
comment on column public.photo_comments.y is '사진 안 댓글 위치의 세로 비율 (0~1)';
