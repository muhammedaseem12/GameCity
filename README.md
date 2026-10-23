# KMCT Community

A mobile-friendly social community website. This repository currently contains a static frontend and a SQL schema prepared for a Supabase backend.

## Current implementation status
- [x] Responsive community UI with feed, memes, confessions, polls, events and lost & found
- [x] Email/password login interface (UI only)
- [x] SQL schema for profiles, posts, comments, likes, poll votes, friend requests, conversations, messages, online presence and notifications
- [ ] Live Supabase project connected to the frontend
- [ ] Real authentication and persistent posts
- [ ] Friend-request-gated private chat and realtime online status
- [ ] Automated backups configured

**Important:** Posts, likes, comments, and votes in the current frontend are still browser-preview interactions. Login, private messaging, notifications, and online presence are not live yet. Running the SQL alone will not connect the website to a database.

## Configure a free Supabase backend
1. Create a project at https://supabase.com/dashboard. Free-plan limits apply.
2. Open **SQL Editor** and run all of `supabase/schema.sql`.
3. In **Project Settings → API**, copy the Project URL and public anon/publishable key.
4. The frontend must then be updated to use Supabase Auth and the tables. Use only the public anon/publishable key in browser code. **Never expose the service-role key or database password.**
5. Enable Realtime for `messages` and `user_presence` in the Supabase dashboard, if supported by the project settings.
6. Test with two separate accounts: sign up, create a post, send and accept a friend request, then send a private message. Verify each account cannot access other users' private conversations.

## Backups and production safety
- Review the row-level security policies in `supabase/schema.sql` before production.
- Configure backups/exports in the Supabase dashboard and periodically test restoring data. Backup retention and point-in-time recovery depend on plan; do not assume these are included in the free tier.
- Do not store credentials in GitHub or frontend JavaScript.
- Perform security and end-to-end tests before inviting real users.
