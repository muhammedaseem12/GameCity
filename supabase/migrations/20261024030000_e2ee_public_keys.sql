-- End-to-end encryption public-key directory for private chats.
-- Run this in Supabase SQL Editor before using encrypted chat.
alter table public.profiles
  add column if not exists e2ee_public_key text;

comment on column public.profiles.e2ee_public_key is
  'Public ECDH P-256 key used by clients to derive private-chat encryption keys. Never store private keys here.';
