#!/usr/bin/env bash
# Runs the app against the live Supabase project.
#
# The URL and the anon/publishable key are NOT secrets — they ship inside every
# build of this app and can be read out of the web bundle. Keeping them in a
# checked-in script is fine and saves retyping them.
#
# The SERVICE ROLE key is a different thing entirely: it bypasses RLS. It must
# never appear here, in a --dart-define, or in any file the app is built from.
#
#   bash run_supabase.sh            # chrome
#   bash run_supabase.sh windows    # or any other device id
set -euo pipefail

DEVICE="${1:-chrome}"

SUPABASE_URL="https://nomgavgvkjdlzjgwozuv.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5vbWdhdmd2a2pkbHpqZ3dvenV2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY0Nzg1ODksImV4cCI6MjEwMjA1NDU4OX0.lPtS1ooNMn9kVji28x37qgjUG8jvMPxYoiWz4OLb7d8"

exec flutter run -d "$DEVICE" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  "${@:2}"
