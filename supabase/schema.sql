-- Tabellen für die Familien-App "Rezept Nachkochen"
-- In Supabase: SQL Editor öffnen → dieses Skript einfügen → Run

create table if not exists recipes (
  id text primary key,
  family_code text not null,
  title text not null,
  ingredients jsonb not null default '[]'::jsonb,
  steps jsonb not null default '[]'::jsonb,
  source_url text default '',
  created_at timestamptz not null default now(),
  servings text,
  prep_time_minutes int,
  notes text
);

create table if not exists shopping_items (
  id text primary key,
  family_code text not null,
  name text not null,
  checked boolean not null default false,
  updated_at timestamptz not null default now(),
  recipe_id text,
  recipe_title text
);

create table if not exists meal_plan_entries (
  id text primary key,
  family_code text not null,
  date date not null,
  recipe_id text not null,
  recipe_title text not null,
  updated_at timestamptz not null default now()
);

create index if not exists recipes_family_code_idx on recipes (family_code);
create index if not exists shopping_items_family_code_idx on shopping_items (family_code);
create index if not exists meal_plan_entries_family_code_idx on meal_plan_entries (family_code);
create index if not exists meal_plan_entries_family_date_idx on meal_plan_entries (family_code, date);

-- Für den privaten Familiengebrauch: anon key darf lesen/schreiben.
-- (Später kannst du das strenger machen.)
alter table recipes enable row level security;
alter table shopping_items enable row level security;
alter table meal_plan_entries enable row level security;

drop policy if exists "family recipes access" on recipes;
create policy "family recipes access"
  on recipes
  for all
  using (true)
  with check (true);

drop policy if exists "family shopping access" on shopping_items;
create policy "family shopping access"
  on shopping_items
  for all
  using (true)
  with check (true);

drop policy if exists "family meal plan access" on meal_plan_entries;
create policy "family meal plan access"
  on meal_plan_entries
  for all
  using (true)
  with check (true);
