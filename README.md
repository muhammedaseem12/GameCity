# GameCity

A standalone mobile-first social community frontend with a dark futuristic neon design.

## Included in this initial commit
- Responsive desktop and mobile navigation
- Community feed with sample posts, meme cards, filters and search
- Local-preview interactions for likes, comments and polls
- UI flows for creating memes, polls, anonymous confessions and lost/found posts
- Email login placeholder, messages and notifications screens
- Community guidelines and report UI
- Reduced-motion accessibility support

## Important limitation
This commit is a working **frontend preview**, not yet a complete production social network. Data is held in browser memory and is not shared between users or persisted reliably. Real email/password authentication, database persistence, private messaging, live notifications, image uploads, server-side moderation and secure permissions still require backend setup and testing.

## Production setup plan
1. Create a Supabase project and enable email/password authentication.
2. Add tables for profiles, posts, comments, reactions, polls/votes, conversations/messages, notifications and reports.
3. Apply Row Level Security policies. Keep private conversations visible only to participants; never expose the Supabase service-role key in frontend code.
4. Add a Storage bucket with file-size/type restrictions for images.
5. Connect the Supabase client, add validation and rate limits, and replace preview-only interactions.
6. Deploy the static site through Cloudflare Pages or another static host and configure the deployed URL in Supabase Auth.
7. Test using two separate accounts before inviting students.

Sample events and feed posts are illustrative and are not verified college announcements. Add moderation and reporting before opening the platform to the public.