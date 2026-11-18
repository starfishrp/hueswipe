# Hue Swipe

A colour-only social app. Swipe through colours, post your favourites, and see your friends' colours.

**Tabs:** Home (friends' posts) · Doomscroll (endless colours) · Post · Friends · Me

It's free to run: GitHub Pages hosts the app, and Supabase stores accounts and posts.

---

## Setup (about 15 minutes, easiest on a computer)

### 1. Make the database

1. Go to [supabase.com](https://supabase.com), sign up, and click **New project**.
   - Name: `hueswipe`
   - Database password: anything (save it somewhere)
   - Region: **Sydney**
2. When it's ready, click **SQL Editor** in the left sidebar.
3. Open `supabase/schema.sql` from this folder, copy everything, paste it in, and click **Run**.
   You should see *Success. No rows returned.*

### 2. Connect the app to it

1. In Supabase, click **Project Settings** (cog icon) → **API Keys**.
2. Copy two things:
   - **Project URL** (looks like `https://abcdefgh.supabase.co`)
   - **Publishable key** (starts with `sb_publishable_`; on older projects it's called the **anon public** key)
3. Open `index.html` in any text editor, search for `CONFIG`, and paste them in:

   ```js
   const CONFIG = {
     supabaseUrl: 'https://abcdefgh.supabase.co',
     supabaseAnonKey: 'sb_publishable_...',
     siteUrl: '',
   };
   ```

   Never paste the **secret** / `service_role` key here.

### 3. Put it online

1. On [github.com](https://github.com), click **New repository**. Name it `hueswipe`, make it **Public**, and create it.
2. Click **uploading an existing file**, then drag in **everything inside** the `hueswipe` folder (the files *and* the `icons` and `supabase` folders). Click **Commit changes**.
3. Go to **Settings → Pages**. Under *Branch*, pick `main` and `/ (root)`, then **Save**.
4. Wait a minute and refresh. Your site's address appears at the top, like
   `https://yourname.github.io/hueswipe/`.

### 4. Tell Supabase your site's address

In Supabase: **Authentication → URL Configuration**

- **Site URL:** your GitHub Pages address
- **Redirect URLs:** click **Add URL** and add the same address

(This is where "confirm your email" and "reset password" links send people.)

### 5. Make the official account

Everyone who signs up is automatically friends with **@hueswipe**, so their Home feed is never empty.

1. Open your site → **Me** → create an account, confirm the email, and pick the username **hueswipe**.
2. Post a few colours from it.
3. Sign out and make your own personal account.

**That's it, you're live.** 🎉

---

## Before you share it widely

- **Email sending.** Supabase's built-in email only sends a few emails an hour, so a burst of signups will stall. Fix: make a free account at [resend.com](https://resend.com), then in Supabase go to **Authentication → Emails → SMTP Settings** and enter the details Resend gives you.
- **Your contact email.** Open `privacy.html` and replace `your-email@example.com` (it appears twice on one line).

### Handy while testing

To skip email confirmation: **Authentication → Sign In / Providers → Email**, turn off **Confirm email**. Turn it back on before sharing.

---

## Running it day to day

- **Reports** land in Supabase → **Table Editor → reports**. Each row says what was reported and why.
- **Removing something:** in **Table Editor**, open `posts`, `comments` or `profiles`, find the row, and delete it. Deleting a profile removes everything that person posted.
- **Changing the official account:** in the SQL Editor run
  `update public.app_settings set value = 'newname' where key = 'official_username';`
- **Free plan note:** Supabase pauses free projects after about a week with no visitors. Unpausing is one click on its dashboard.

---

## Optional: your own domain

1. Buy a domain (Cloudflare, Porkbun or Namecheap; a `.com` is roughly US$10–15 a year).
2. In the domain's DNS settings, add these records:

   | Type | Name | Value |
   | --- | --- | --- |
   | A | `@` | `185.199.108.153` |
   | A | `@` | `185.199.109.153` |
   | A | `@` | `185.199.110.153` |
   | A | `@` | `185.199.111.153` |
   | CNAME | `www` | `yourname.github.io` |

3. GitHub repo → **Settings → Pages → Custom domain**: type your domain, **Save**. When the check passes, tick **Enforce HTTPS**.
4. Update the two addresses in Supabase (step 4 above) to `https://yourdomain.com`.
5. In `index.html` and `404.html`, replace `hueswipe.com` with your domain (it's in the link-preview tags), and set `siteUrl: 'https://yourdomain.com'` in `CONFIG`.

---

## What's in here

| File | What it is |
| --- | --- |
| `index.html` | The whole app |
| `supabase/schema.sql` | Database tables and security rules (run once, for a brand-new project) |
| `supabase/002_profile_update.sql` | Update for databases set up before profile colours and friends lists existed (safe to run again) |
| `404.html` | Makes share links (`/3a7fd2`) and invite links (`/@name`) work |
| `privacy.html` | Rules & privacy page, linked from sign-up |
| `manifest.webmanifest`, `icons/` | App icon and "Add to Home Screen" support |
| `og.png` | The image shown when a link to the site is shared |

### What's protected, and how

The rules in `schema.sql` run inside the database itself, so they hold even if someone pokes at the app:

- Posts, likes and comments are visible only to the author and their friends.
- You can only post, like, comment, block and report as yourself.
- Blocked people can't send requests or comment on your posts.
- Post authors can delete any comment on their posts.
- Reports and the settings table can't be read through the app.
- Rate limits: 20 posts and 60 comments an hour, 30 friend requests a day.
- **Delete my account** removes the login and everything that person posted.

### Troubleshooting

- **Red "Couldn't load the accounts library" banner:** usually a connection issue. If it persists, delete the `integrity="..."` line near the top of `index.html`.
- **"Slow down a little":** a rate limit kicked in. It resets within the hour.
- **Invite or colour links show a GitHub 404 page:** make sure `404.html` was uploaded.
- **Link previews for colour/invite links:** the main address shows a nice preview card, but colour and invite links may not, because GitHub Pages can't make a page per link.
