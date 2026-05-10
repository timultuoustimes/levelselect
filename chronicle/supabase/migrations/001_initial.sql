-- Chronicle: Personal timeline app
-- Run this in your Supabase SQL editor to set up the schema.

-- Devices (anonymous identity — device_id stored in localStorage)
CREATE TABLE IF NOT EXISTS devices (
  id         TEXT PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- User-defined categories
CREATE TABLE IF NOT EXISTS categories (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id  TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  color      TEXT NOT NULL,
  icon       TEXT,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Events
CREATE TABLE IF NOT EXISTS events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  parent_id   UUID REFERENCES events(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  subtitle    TEXT,
  start_date  DATE NOT NULL,
  end_date    DATE,
  category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
  notes       TEXT,
  location    TEXT,
  tags        TEXT[]  DEFAULT '{}',
  people      TEXT[]  DEFAULT '{}',
  links       JSONB   DEFAULT '[]',
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

-- Photos (stored in Supabase Storage bucket "event-photos")
CREATE TABLE IF NOT EXISTS event_photos (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id     UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  device_id    TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  storage_path TEXT NOT NULL,
  caption      TEXT,
  sort_order   INT DEFAULT 0,
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- Row-Level Security
ALTER TABLE devices      ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories   ENABLE ROW LEVEL SECURITY;
ALTER TABLE events       ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_photos ENABLE ROW LEVEL SECURITY;

-- Permissive policies for anon key (app enforces device_id scoping in queries)
CREATE POLICY "anon_all_devices"      ON devices      FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all_categories"   ON categories   FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all_events"       ON events       FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_all_event_photos" ON event_photos FOR ALL TO anon USING (true) WITH CHECK (true);

-- Index for fast per-device timeline queries
CREATE INDEX IF NOT EXISTS events_device_date_idx ON events (device_id, start_date DESC);
CREATE INDEX IF NOT EXISTS events_parent_idx      ON events (parent_id);

-- Storage bucket setup (run in Supabase dashboard or via CLI):
-- 1. Create a bucket named "event-photos"
-- 2. Set bucket to private (photos served via signed URLs or public — your choice)
-- 3. Add storage policy allowing anon insert/select/delete on own prefix:
--    INSERT: (bucket_id = 'event-photos')
--    SELECT: (bucket_id = 'event-photos')
--    DELETE: (bucket_id = 'event-photos')
