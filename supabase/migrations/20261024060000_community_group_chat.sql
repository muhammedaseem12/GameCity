CREATE TABLE IF NOT EXISTS public.community_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
  reply_to UUID NULL REFERENCES public.community_messages(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.community_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can read community messages" ON public.community_messages;
CREATE POLICY "Authenticated users can read community messages"
ON public.community_messages FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Users can send their own community messages" ON public.community_messages;
CREATE POLICY "Users can send their own community messages"
ON public.community_messages FOR INSERT TO authenticated
WITH CHECK (auth.uid() = author_id);
CREATE INDEX IF NOT EXISTS community_messages_created_at_idx
ON public.community_messages (created_at);
ALTER TABLE public.community_messages REPLICA IDENTITY FULL;
