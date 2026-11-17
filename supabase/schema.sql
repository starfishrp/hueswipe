-- Hue Swipe database schema
-- Run once in Supabase: Dashboard → SQL Editor → New query → paste all of this → Run.

------------------------------------------------------------
-- Tables
------------------------------------------------------------

-- One row per user: their @username.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_.]{3,20}$'),
  created_at timestamptz not null default now()
);

-- Friend requests. status = 'pending' until the addressee accepts.
create table public.friendships (
  id bigint generated always as identity primary key,
  requester uuid not null,
  addressee uuid not null,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  constraint friendships_requester_fkey foreign key (requester) references public.profiles (id) on delete cascade,
  constraint friendships_addressee_fkey foreign key (addressee) references public.profiles (id) on delete cascade,
  check (requester <> addressee)
);
-- Only one friendship row per pair of people, whichever direction it was sent.
create unique index friendships_pair_idx
  on public.friendships (least(requester, addressee), greatest(requester, addressee));

-- Posted colours.
create table public.posts (
  id bigint generated always as identity primary key,
  author uuid not null default auth.uid(),
  hex text not null check (hex ~ '^#[0-9a-f]{6}$'),
  caption text check (char_length(caption) <= 140),
  created_at timestamptz not null default now(),
  constraint posts_author_fkey foreign key (author) references public.profiles (id) on delete cascade
);
create index posts_author_created_idx on public.posts (author, created_at desc);
create index posts_created_idx on public.posts (created_at desc);

create table public.likes (
  post_id bigint not null references public.posts (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table public.comments (
  id bigint generated always as identity primary key,
  post_id bigint not null references public.posts (id) on delete cascade,
  author uuid not null default auth.uid(),
  body text not null check (char_length(body) between 1 and 300),
  created_at timestamptz not null default now(),
  constraint comments_author_fkey foreign key (author) references public.profiles (id) on delete cascade
);
create index comments_post_idx on public.comments (post_id, created_at desc);

-- People you've blocked: no friendship, no requests, no comments on each other's posts.
create table public.blocks (
  blocker uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  blocked uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);

-- Reports. Only you can read these, in the dashboard: Table Editor → reports.
create table public.reports (
  id bigint generated always as identity primary key,
  reporter uuid default auth.uid() references public.profiles (id) on delete set null,
  reported_user uuid references public.profiles (id) on delete set null,
  post_id bigint references public.posts (id) on delete set null,
  comment_id bigint references public.comments (id) on delete set null,
  reason text not null check (char_length(reason) between 1 and 200),
  details text check (char_length(details) <= 1000),
  created_at timestamptz not null default now()
);

-- Settings only the database functions below can read.
create table public.app_settings (
  key text primary key,
  value text not null
);
-- Everyone who signs up is automatically friends with this account, so Home is
-- never empty. Create an account with this @ and post from it. To change it later:
--   update public.app_settings set value = 'yourname' where key = 'official_username';
insert into public.app_settings (key, value) values ('official_username', 'hueswipe');

------------------------------------------------------------
-- Helper functions
------------------------------------------------------------
create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester = a and f.addressee = b) or (f.requester = b and f.addressee = a))
  );
$$;

create or replace function public.is_blocked_between(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocks
    where (blocker = a and blocked = b) or (blocker = b and blocked = a)
  );
$$;

------------------------------------------------------------
-- Row Level Security: who can read / write what
------------------------------------------------------------
alter table public.profiles     enable row level security;
alter table public.friendships  enable row level security;
alter table public.posts        enable row level security;
alter table public.likes        enable row level security;
alter table public.comments     enable row level security;
alter table public.blocks       enable row level security;
alter table public.reports      enable row level security;
alter table public.app_settings enable row level security;  -- no policies: hidden from the app

-- Profiles: any signed-in user can look up usernames (for friend search and invite links).
create policy "Signed-in users can see profiles"
  on public.profiles for select to authenticated using (true);
create policy "Users create their own profile"
  on public.profiles for insert to authenticated with check (id = auth.uid());

-- Friendships: you only see rows you're part of.
create policy "See your own friendships"
  on public.friendships for select to authenticated
  using (auth.uid() in (requester, addressee));
create policy "Send friend requests"
  on public.friendships for insert to authenticated
  with check (
    requester = auth.uid()
    and status = 'pending'
    and not public.is_blocked_between(requester, addressee)
  );
create policy "Accept requests sent to you"
  on public.friendships for update to authenticated
  using (addressee = auth.uid())
  with check (addressee = auth.uid() and status = 'accepted');
create policy "Decline, cancel or unfriend"
  on public.friendships for delete to authenticated
  using (auth.uid() in (requester, addressee));
-- Accepting may only change the status column (stops anyone rewriting who the request is between).
revoke update on public.friendships from authenticated;
grant update (status) on public.friendships to authenticated;

-- Posts: you see your own posts and your friends' posts.
create policy "See own and friends' posts"
  on public.posts for select to authenticated
  using (author = auth.uid() or public.are_friends(auth.uid(), author));
create policy "Post as yourself"
  on public.posts for insert to authenticated with check (author = auth.uid());
create policy "Delete your own posts"
  on public.posts for delete to authenticated using (author = auth.uid());

-- Likes: visible / allowed only on posts you can see.
create policy "See likes on visible posts"
  on public.likes for select to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id));
create policy "Like visible posts as yourself"
  on public.likes for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id));
create policy "Remove your own likes"
  on public.likes for delete to authenticated using (user_id = auth.uid());

-- Comments: visible on posts you can see; no commenting across a block;
-- post authors can remove comments on their own posts.
create policy "See comments on visible posts"
  on public.comments for select to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id));
create policy "Comment on visible posts as yourself"
  on public.comments for insert to authenticated
  with check (
    author = auth.uid()
    and exists (
      select 1 from public.posts p
      where p.id = post_id and not public.is_blocked_between(auth.uid(), p.author)
    )
  );
create policy "Delete own comments or comments on your posts"
  on public.comments for delete to authenticated
  using (
    author = auth.uid()
    or exists (select 1 from public.posts p where p.id = post_id and p.author = auth.uid())
  );

-- Blocks: private to the person blocking.
create policy "See who you've blocked"
  on public.blocks for select to authenticated using (blocker = auth.uid());
create policy "Block people"
  on public.blocks for insert to authenticated with check (blocker = auth.uid());
create policy "Unblock people"
  on public.blocks for delete to authenticated using (blocker = auth.uid());

-- Reports: anyone signed in can file one; nobody can read them through the app.
create policy "File reports as yourself"
  on public.reports for insert to authenticated with check (reporter = auth.uid());

------------------------------------------------------------
-- Rate limits
-- enforce_rate_limit('<user column>', '<max rows>', '<time window>')
------------------------------------------------------------
create or replace function public.enforce_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  col text := tg_argv[0];
  max_rows int := tg_argv[1]::int;
  win interval := tg_argv[2]::interval;
  uid uuid;
  n int;
begin
  execute format('select ($1).%I', col) into uid using new;
  execute format(
    'select count(*) from %I.%I where %I = $1 and created_at > now() - $2',
    tg_table_schema, tg_table_name, col
  ) into n using uid, win;
  if n >= max_rows then
    raise exception 'rate limit reached, try again later' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger posts_rate_limit before insert on public.posts
  for each row execute function public.enforce_rate_limit('author', '20', '1 hour');
create trigger comments_rate_limit before insert on public.comments
  for each row execute function public.enforce_rate_limit('author', '60', '1 hour');
create trigger likes_rate_limit before insert on public.likes
  for each row execute function public.enforce_rate_limit('user_id', '300', '1 hour');
create trigger friend_requests_rate_limit before insert on public.friendships
  for each row when (new.status = 'pending')
  execute function public.enforce_rate_limit('requester', '30', '1 day');
create trigger reports_rate_limit before insert on public.reports
  for each row execute function public.enforce_rate_limit('reporter', '20', '1 day');

------------------------------------------------------------
-- Delete my account: removes the login and, through the cascades above,
-- their profile, posts, likes, comments, friendships and blocks.
------------------------------------------------------------
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

------------------------------------------------------------
-- Official account: everyone is automatically friends with it
------------------------------------------------------------
create or replace function public.befriend_official_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  official text := (select value from public.app_settings where key = 'official_username');
  official_id uuid;
begin
  if official is null then
    return new;
  end if;

  if new.username = official then
    -- The official account was just created: befriend everyone already here.
    insert into public.friendships (requester, addressee, status)
      select new.id, p.id, 'accepted' from public.profiles p where p.id <> new.id
      on conflict do nothing;
  else
    select id into official_id from public.profiles where username = official;
    if official_id is not null then
      insert into public.friendships (requester, addressee, status)
        values (official_id, new.id, 'accepted')
        on conflict do nothing;
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_befriend_official after insert on public.profiles
  for each row execute function public.befriend_official_account();
