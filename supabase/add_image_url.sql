-- Vorschaubilder (Cover) für Rezepte in der Familien-Cloud.
-- In Supabase: SQL Editor → New query → diese Zeile → Run

alter table recipes add column if not exists image_url text;
