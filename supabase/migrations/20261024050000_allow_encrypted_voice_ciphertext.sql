-- Encrypted voice recordings are uploaded as ciphertext text, not playable audio.
-- Keep the bucket private; this only removes restrictive MIME filtering that rejects text/plain.
UPDATE storage.buckets
SET allowed_mime_types = NULL
WHERE id = 'voice-messages';
