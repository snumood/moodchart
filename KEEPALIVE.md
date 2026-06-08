# Moodchart Supabase Keepalive

Moodchart keeps its Supabase project awake with a lightweight read-only request:

```bash
node tools/supabase_keepalive.mjs
```

The request calls:

```text
/auth/v1/settings
```

It does not read or write application rows.

Safety nets:

- VM user systemd timer: primary keepalive every 12 hours.
- GitHub Actions workflow: secondary keepalive every 12 hours and manual dispatch.
- VM monthly audit: checks Supabase, GitHub workflow presence/latest run, and VM timer status.

VM commands:

```bash
systemctl --user status moodchart-supabase-keepalive.timer
journalctl --user -u moodchart-supabase-keepalive.service -n 50 --no-pager
systemctl --user status moodchart-monthly-safety-audit.timer
cat /home/ubuntu/moodchart-keepalive/monthly-audit/latest.json
```
