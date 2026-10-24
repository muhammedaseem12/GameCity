-- KMCT Community requested chat/poll permissions.
-- Run once in Supabase SQL Editor after the existing schema/migrations.
-- Presence records are created by the existing auth-user trigger.
drop policy if exists "users edit own messages" on public.messages;
create policy "users edit own messages" on public.messages
for update to authenticated
using (sender_id = auth.uid() and public.is_conversation_member(conversation_id, auth.uid()))
with check (sender_id = auth.uid() and public.is_conversation_member(conversation_id, auth.uid()));

drop policy if exists "users delete own messages" on public.messages;
create policy "users delete own messages" on public.messages
for delete to authenticated
using (sender_id = auth.uid() and public.is_conversation_member(conversation_id, auth.uid()));

drop policy if exists "users change own poll vote" on public.poll_votes;
create policy "users change own poll vote" on public.poll_votes
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

grant select, insert, update, delete on public.messages to authenticated;
grant select, insert, update on public.poll_votes to authenticated;
grant select, update on public.user_presence to authenticated;

-- Only authenticated members may read global chat membership/message rows;
-- the existing RLS policies enforce this and direct-message creation checks accepted friendship.
