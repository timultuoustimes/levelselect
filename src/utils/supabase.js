import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = 'https://sextftevxqrtodlmnyve.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_JqjZjggOXqBc72mNKrEDhg_D7ZarqkB';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
