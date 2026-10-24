-- Mutual /clear for private conversations.
-- A single user's request never deletes history. Both participants must request it.
CREATE TABLE IF NOT EXISTS public.private_chat_clear_requests (
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);

ALTER TABLE public.private_chat_clear_requests ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.request_private_chat_clear(p_conversation_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  requester UUID := auth.uid();
  member_count INTEGER;
  request_count INTEGER;
BEGIN
  IF requester IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;

  SELECT COUNT(*) INTO member_count
  FROM public.conversation_members
  WHERE conversation_id = p_conversation_id;

  IF member_count <> 2 OR NOT EXISTS (
    SELECT 1 FROM public.conversation_members
    WHERE conversation_id = p_conversation_id AND user_id = requester
  ) THEN
    RAISE EXCEPTION 'This is not a valid private conversation.';
  END IF;

  INSERT INTO public.private_chat_clear_requests (conversation_id, user_id, requested_at)
  VALUES (p_conversation_id, requester, now())
  ON CONFLICT (conversation_id, user_id)
  DO UPDATE SET requested_at = EXCLUDED.requested_at;

  SELECT COUNT(*) INTO request_count
  FROM public.private_chat_clear_requests r
  JOIN public.conversation_members cm
    ON cm.conversation_id = r.conversation_id AND cm.user_id = r.user_id
  WHERE r.conversation_id = p_conversation_id;

  IF request_count >= 2 THEN
    DELETE FROM public.messages WHERE conversation_id = p_conversation_id;
    DELETE FROM public.private_chat_clear_requests WHERE conversation_id = p_conversation_id;
    RETURN 'cleared';
  END IF;

  RETURN 'requested';
END;
$$;

REVOKE ALL ON FUNCTION public.request_private_chat_clear(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_private_chat_clear(UUID) TO authenticated;
