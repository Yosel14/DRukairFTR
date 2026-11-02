# Drukair FTR System - Deployment Guide (about 30 minutes, free tier is enough)

## 1. Create the database (Supabase)
1. Sign up at supabase.com, click New project, pick a region close to Bhutan (Singapore), and save the database password.
2. Open SQL Editor, paste all of `schema.sql`, click Run. It must finish with "Success".
3. Authentication > Sign In / Providers > Email: turn OFF "Allow new users to sign up" (only you create accounts).

## 2. Create the accounts
1. Authentication > Users > Add user > Create new user (tick "Auto Confirm"). Create yourself, each senior and the administrator.
2. SQL Editor, then set roles (replace the emails):
```sql
update profiles set role = 'dispatcher' where email = 'you@drukair.com.bt';
update profiles set role = 'approver'   where email in ('senior1@drukair.com.bt','senior2@drukair.com.bt');
update profiles set role = 'admin'      where email = 'admin@drukair.com.bt';
```
Roles: dispatcher = enter flights, payments, invoices, submit for approval. approver = read everything, approve / reject / reopen. admin = dispatcher rights plus rates and invoice settings. Admins cannot approve; that stays with the seniors.

## 3. Connect the app
1. Project Settings > API: copy the Project URL and the `anon public` key.
2. Open `index.html` in a text editor, find `PASTE_SUPABASE_PROJECT_URL` and `PASTE_SUPABASE_ANON_KEY`, paste both, save. (The anon key is meant to be public; the database rules in schema.sql protect the data.)

## 4. Publish the page (pick one)
- Netlify: app.netlify.com/drop, drag the folder containing `index.html`. You get a https link in seconds. Site settings > Change site name to something clean.
- Cloudflare Pages or GitHub Pages also work: upload `index.html` as the only file.
- Drukair IT: hand `index.html` to IT to host on an internal web server; nothing else is needed.
Then Authentication > URL Configuration > set Site URL to your published link.

## 5. Test before showing seniors (all must pass)
1. Sign in as dispatcher, add a flight, refresh the page: it is still there. Open it on your phone with the same login: it shows there too.
2. Click "Submit for approval". Sign in as a senior on another device: the Approval column shows Submitted; click Approve.
3. As dispatcher, the Edit and Delete buttons are gone for that FTR, but Payment & Proof still works.
4. Generate an invoice: number should be 261, the next one 262, even if two people do it at once.
5. Import CSV: export first, then import a file with one new row; check the row appears.
6. Sign in as a senior and try Hourly Rates: it must refuse to save.

## 6. Go live and operate
- Add the first real data with Import CSV (same columns as Export CSV). Proof images and old invoice numbers are not imported.
- Backup: Supabase > Database > Backups, plus a weekly Export CSV from the Records tab.
- Audit trail: SQL Editor, `select * from ftr_audit order by at desc;`
- Forgot password: Authentication > Users > the user > Send password recovery.
- Leaving a user out: delete them in Authentication > Users.
