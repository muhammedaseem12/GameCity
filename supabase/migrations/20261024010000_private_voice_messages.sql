-- Private voice-message storage for KMCT Community.
-- Apply this migration to the existing Supabase project.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('voice-messages', 'voice-messages', false, 10485760, array['audio/webm','audio/mp4','audio/ogg','audio/mpeg'])
on conflict (id) do update set public=false, file_size_limit=10485760,
  allowed_mime_types=array['audio/webm','audio/mp4','audio/ogg','audio/mpeg'];

drop policy if exists "voice upload by conversation sender" on storage.objects;
create policy "voice upload by conversation sender"
on storage.objects for insert to authenticated
with check (
  bucket_id='voice-messages'
  and (storage.foldername(name))[1]=auth.uid()::text
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id=((storage.foldername(name))[2])::uuid
      and cm.user_id=auth.uid()
  )
);

drop policy if exists "voice read by conversation members" on storage.objects;
create policy "voice read by conversation members"
on storage.objects for select to authenticated
using (
  bucket_id='voice-messages'
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id=((storage.foldername(name))[2])::uuid
      and cm.user_id=auth.uid()
  )
);

drop policy if exists "voice delete by sender" on storage.objects;
create policy "voice delete by sender"
on storage.objects for delete to authenticated
using (
  bucket_id='voice-messages'
  and (storage.foldername(name))[1]=auth.uid()::text
);
