# Costs and limits

Everything here starts free. Figures are from my knowledge and can change: check each provider's current pricing and limits before relying on them.

| Service | Free allowance (as I know it) | What happens at the limit |
|---|---|---|
| Supabase database | 500 MB | Writes can be blocked until you delete data or upgrade |
| Supabase storage (photos) | 1 GB (about 3,000 compressed photos) | Uploads fail until you free space or upgrade |
| Supabase traffic | a monthly data-transfer cap | Throttling or upgrade prompt |
| Supabase pausing | Free projects pause after about a week of no activity | Click **Restore project**; open the app weekly |
| Supabase backups | none restorable on free (see BACKUP_AND_RECOVERY) | Use monthly CSV exports |
| Vercel Hobby | free, for personal non-commercial use, with usage caps | Check terms before real business use; Pro is paid |
| GitHub private repo | free | n/a |
| WhatsApp | no cost: staff send from their own WhatsApp | Official API (optional later) is paid per message |
| Custom domain | optional, yearly fee | n/a |

**How this system stays small:** no Edge Functions, no Realtime, no polling; text-only alerts; photos shrunk to ~300 KB; old alerts and handled messages deleted after 90 days. **Monitor:** app **Settings** (usage bars, warn at 60%), Supabase **Settings, Usage**, Vercel **Usage**. **If you outgrow free:** Supabase Pro (daily backups, bigger limits) and a Vercel paid plan are the natural upgrades. Nothing is promised to stay free forever.
