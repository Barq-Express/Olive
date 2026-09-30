import { createClient } from "@supabase/supabase-js";

const url = "https://qzehlgvoxoofkugtcfzs.supabase.co";
const key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF6ZWhsZ3ZveG9vZmt1Z3RjZnpzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA3OTMzNzMsImV4cCI6MjEwNjM2OTM3M30.ocZvNDjwc8I6XTe7ESl0P1p0kPDr31MSsxlglTa9NLg";

if (!url || !key) {
  // eslint-disable-next-line no-console
  console.error("مفقود VITE_SUPABASE_URL أو VITE_SUPABASE_ANON_KEY في متغيرات البيئة");
}

export const supabase = createClient(url, key);
