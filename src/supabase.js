import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !key) {
  // eslint-disable-next-line no-console
  console.error("مفقود VITE_SUPABASE_URL أو VITE_SUPABASE_ANON_KEY في متغيرات البيئة");
}

export const supabase = createClient(url, key);
