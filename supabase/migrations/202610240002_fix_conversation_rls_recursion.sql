-- Fix infinite-recursion RLS on conversation_members.
-- The old membership SELECT policy queried conversation_members itself, causing:
-- "infinite recursion detected in policy for relation conversation_members".
-- A narrowly scoped SECURITY DEFINER helper reads membership without re-entering RLS.

create or replace function public.is_conversation_member(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = p_conversation_id
      and cm.user_id = auth.uid()
  );
$$;

revoke all on function public.is_conversation_member(uuid) from public;
grant execute on function public.is_conversation_member(uuid) to authenticated;

drop policy if exists "members can see membership" on public.conversation_members;
create policy "members can see membership"
on public.conversation_members
for select to authenticated
using (public.is_conversation_member(conversation_id));

drop policy if exists "conversation members read conversations" on public.conversations;
create policy "conversation members read conversations"
on public.conversations
for select to authenticated
using (public.is_conversation_member(id));

drop policy if exists "conversation members read messages" on public.messages;
create policy "conversation members read messages"
on public.messages
for select to authenticated
using (public.is_conversation_member(conversation_id));

drop policy if exists "members send messages only as self" on public.messages;
create policy "members send messages only as self"
on public.messages
for insert to authenticated
with check (
  sender_id = auth.uid()
  and public.is_conversation_member(conversation_id)
);
