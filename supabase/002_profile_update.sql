-- Hue Swipe update: profile colours + friends lists on profiles
-- Run once in Supabase: SQL Editor → New query → paste all of this → Run.
-- Safe to run more than once.

-- Each profile can store a chosen colour. Empty = a colour worked out from the username.
alter table public.profiles
  add column if not exists avatar_hex text check (avatar_hex ~ '^#[0-9a-f]{6}$');

-- People may change their own colour, and nothing else about their profile
-- (usernames stay fixed).
revoke update on public.profiles from authenticated, anon;
grant update (avatar_hex) on public.profiles to authenticated;

drop policy if exists "Change your own profile colour" on public.profiles;
create policy "Change your own profile colour"
  on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Someone's friends list. You get it only for yourself or for people you're friends with.
create or replace function public.friends_of(target uuid)
returns table (id uuid, username text, avatar_hex text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.username, p.avatar_hex
  from public.friendships f
  join public.profiles p
    on p.id = case when f.requester = target then f.addressee else f.requester end
  where f.status = 'accepted'
    and target in (f.requester, f.addressee)
    and (auth.uid() = target or public.are_friends(auth.uid(), target))
  order by p.username;
$$;
revoke execute on function public.friends_of(uuid) from public, anon;
grant execute on function public.friends_of(uuid) to authenticated;
