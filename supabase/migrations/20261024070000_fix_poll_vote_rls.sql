-- Repair poll voting: one vote per user per poll, and allow changing a vote.
ALTER TABLE public.poll_votes ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE p RECORD;
BEGIN
  FOR p IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'poll_votes'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.poll_votes', p.policyname);
  END LOOP;
END $$;

CREATE POLICY "Signed-in users can read poll votes"
ON public.poll_votes FOR SELECT TO authenticated
USING (true);

CREATE POLICY "Users can cast their own poll votes"
ON public.poll_votes FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can change their own poll votes"
ON public.poll_votes FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE UNIQUE INDEX IF NOT EXISTS poll_votes_one_vote_per_user
ON public.poll_votes (post_id, user_id);
