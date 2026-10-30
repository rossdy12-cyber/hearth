# Hearth

Hearth is a home-cinema app for iPhone that brings your own servers together in one place:

- **Movies and TV shows** from **Jellyfin**: a large featured banner, scrolling rows (Continue Watching, Recently Added, genres), a page for each title with seasons and episodes, and full-screen playback that remembers where you stopped.
- **Music** from **Navidrome**: albums, artists and playlists, a mini player, a full-screen player, and playback that continues with the screen locked, with controls on the lock screen.
- **Search** covers both servers at once.

Hearth only connects to your own servers, over Tailscale. It has no accounts or tracking of its own.

You don't need a Mac or a paid Apple developer account. GitHub builds the app for you in the cloud, and **Sideloadly** installs it on your iPhone with your normal (free) Apple ID.

There's also a **desktop version for Windows and Ubuntu**. See [Hearth on Windows and Ubuntu](#hearth-on-windows-and-ubuntu) near the end.

---

## What you need

- A Windows PC.
- Your iPhone (iOS 16 or newer) and its USB cable.
- Your normal Apple ID (the free one you use for the App Store).
- Tailscale switched on, on both the iPhone and the NAS.
- The addresses of your Jellyfin and Navidrome apps (step 0).

---

## Step 0: Find your server addresses

1. On your PC, open the TrueNAS web page and go to **Apps**.
2. Click **Jellyfin**. On the app's page, note the **port number** (on TrueNAS this is often `30013`; the standard Jellyfin port is `8096`).
3. Do the same for **Navidrome** (often `30043` on TrueNAS; the standard Navidrome port is `4533`).
4. Your addresses are your NAS's **Tailscale IP** plus the port, for example:
   - Jellyfin: `http://100.101.102.103:30013`
   - Navidrome: `http://100.101.102.103:30043`

   To check one, paste it into a browser on any device that has Tailscale on. You should see the Jellyfin or Navidrome sign-in page.

---

## Step 1: Make a free GitHub account

1. Go to <https://github.com/signup>.
2. Enter an email, a password and a username, then confirm your email.

GitHub is where your app gets built. The build runs on one of GitHub's Macs, so you don't need one.

---

## Step 2: Create a repository and upload this folder

A "repository" (repo) is a folder on GitHub.

1. Click the **+** at the top right of GitHub, then **New repository**.
2. **Repository name:** `hearth`.
3. Choose **Public**. Public repos get unlimited free builds. This code holds no passwords or server addresses: you type those into the app on your phone, and the app keeps them in the iPhone Keychain.
   *(Private also works, but the free plan only gives about 200 Mac build minutes a month, which is roughly 20 builds.)*
4. Leave everything else as it is and click **Create repository**.
5. On the next page, click the link **uploading an existing file**.
6. Open this project folder in File Explorer, select **everything inside it** (including the `.github` folder), and drag it all onto the GitHub page.
   - Check that the `.github` folder is included. It holds the build instructions.
7. Scroll down and click **Commit changes**.

> **Using Git instead?** If you have Git or GitHub Desktop, you can push this folder to the repo's `main` branch instead. The result is the same.

---

## Step 3: Build the app on GitHub

1. In your repo, click the **Actions** tab.
2. If GitHub asks, click **I understand my workflows, go ahead and enable them**.
3. On the left, click **Build unsigned IPA**.
4. Click **Run workflow**, then the green **Run workflow** button.
   (Uploading new code to `main` also starts a build on its own.)
5. Wait about 5â€“15 minutes. A green tick means the build worked. A red cross means it failed; click it to see why.

---

## Step 4: Download the app file (.ipa)

1. Click the finished (green) run.
2. Scroll down to **Artifacts** and click **Hearth-ipa**. A `.zip` file downloads.
3. Right-click the zip, choose **Extract Allâ€¦**, and extract it. Inside is **`Hearth.ipa`**: that file is the app.

---

## Step 5: Install Sideloadly and Apple's helper apps

Sideloadly installs the .ipa on your iPhone and signs it with your Apple ID.

1. Install **iTunes** and **iCloud** using the **downloads from Apple's website**, not the Microsoft Store versions. Sideloadly needs Apple's versions:
   - iTunes: <https://www.apple.com/itunes/> (choose the "Windows" download, not the Microsoft Store link)
   - iCloud: Sideloadly's site links to the correct installer.
2. Download Sideloadly for Windows from <https://sideloadly.io> and install it.

---

## Step 6: Put Hearth on your iPhone

1. Connect the iPhone to the PC with the cable. Unlock it and tap **Trust** if it asks.
2. Open **Sideloadly**.
3. Drag **`Hearth.ipa`** onto the Sideloadly window (or click the IPA icon and choose it).
4. Check that your iPhone shows in the **iDevice** box.
5. Type your **Apple ID email** in the **Apple account** box and click **Start**.
6. Enter your Apple ID password when Sideloadly asks, and the 6-digit code if your phone shows one.
   - Sideloadly only sends these to Apple, to create a free 7-day signing certificate.
7. Wait until it says **Done**.

### Trust the app on the iPhone (first time only)

1. On the iPhone, open **Settings â†’ General â†’ VPN & Device Management**.
2. Under **Developer App**, tap your Apple ID, then **Trust**.
3. Turn on **Developer Mode** if iOS asks for it: **Settings â†’ Privacy & Security â†’ Developer Mode â†’ On**. The iPhone restarts; confirm **Turn On** afterwards.
   (The Developer Mode switch only appears after you've installed a sideloaded app once.)

---

## Step 7: Sign in to your servers

1. Make sure **Tailscale is on** on the iPhone.
2. Open **Hearth**. Settings opens on its own the first time, or tap the âš™ï¸ gear at the top right.
3. **Jellyfin:** enter the address from Step 0 (e.g. `http://100.101.102.103:30013`), your Jellyfin username and password, then tap **Sign In**.
4. **Navidrome:** the same, with the Navidrome address and account.
5. Tap **Done**. Home fills with your movies and shows, and the Music tab with your music.

Hearth keeps your sign-ins in the iPhone Keychain. For Jellyfin it stores a sign-in token, not your password.

---

## Every 7 days: re-sign the app

Free Apple IDs sign apps for **7 days only**. After that Hearth won't open (it shows "unavailable" or closes immediately). Nothing is lost; you just sign it again:

1. Plug the iPhone into the PC and open Sideloadly.
2. Choose the same `Hearth.ipa`, same Apple ID, and click **Start**.

Your sign-ins and settings stay, because the app ID doesn't change.

**Tip:** Sideloadly can refresh over Wi-Fi without the cable. In Sideloadly, turn on **Wi-Fi sync** for the phone (or in iTunes, tick "Sync with this iPhone over Wi-Fi") and enable **Automatic refresh** in Sideloadly's options. The PC needs to be on, with Sideloadly running, at least once a week.

Free Apple IDs also allow at most **3 sideloaded apps** on a phone at once.

---

## Updating Hearth

When the code changes (for example after a fix), upload the new files to GitHub as in Step 2. That starts a new build. Download the new `Hearth.ipa` (Step 4) and install it with Sideloadly over the old one (Step 6). Your settings are kept.

---

## Hearth on Windows and Ubuntu

The `desktop` folder holds a desktop version of Hearth with the same look: the big banner, poster rows, title pages with seasons and episodes, Music, and Search. Videos play full screen (press **F** to switch full screen, **Esc** to go back, **Space** to pause, **←/→** to skip 10 seconds). Music plays in a bar at the bottom, and your keyboard's media keys work. Progress syncs with Jellyfin, so you can stop a film on the PC and resume it on the iPhone.

The desktop version doesn't need Sideloadly and never expires.

### Download it

1. In your GitHub repo, open **Actions** and click **Build desktop apps** on the left.
   (It runs by itself whenever anything in `desktop/` changes. To start it by hand, click **Run workflow**.)
2. Click the latest green run and scroll to **Artifacts**:
   - **Hearth-Windows** contains `Hearth-Setup-1.0.0.exe`.
   - **Hearth-Linux** contains `Hearth-1.0.0-x86_64.AppImage` and `Hearth-1.0.0-amd64.deb`.
3. Download the one you need and extract the zip.

### Install on Windows

1. Double-click `Hearth-Setup-1.0.0.exe`.
2. Windows may show **"Windows protected your PC"**, because the app isn't signed with a paid certificate. Click **More info**, then **Run anyway**. You only see this once.
3. Follow the installer. Hearth appears in the Start menu.

### Install on Ubuntu

Either:
- **.deb (recommended):** double-click `Hearth-1.0.0-amd64.deb` and click **Install**, or run `sudo apt install ./Hearth-1.0.0-amd64.deb` in a terminal. Hearth appears in your app list.
- **AppImage (no install):** right-click the `.AppImage` → **Properties** → **Permissions** → tick **Allow executing file as program**, then double-click it. On Ubuntu 22.04 and newer you may first need `sudo apt install libfuse2`.

### Sign in

The first time it opens, Hearth shows Settings. Enter the same addresses as on the iPhone (Step 0), with your usernames and passwords, and make sure Tailscale is connected on the computer. Sign-ins are encrypted with Windows' or Ubuntu's own secure storage.

### Updating

Download and install the newest build the same way. Your sign-ins are kept.

---

## Troubleshooting

| Problem | What to try |
|---|---|
| "Couldn't reach the server" | Check that Tailscale is on, on the iPhone. Open the same address in Safari on the phone: if Safari can't open it either, the address or port is wrong. |
| "Wrong username or password" | Check them by signing in on the server's own web page. |
| "Doesn't look like Jellyfin/Navidrome" | The port is probably the other app's. Swap them, or check the ports in TrueNAS. |
| A video spins or won't start | Hearth asks Jellyfin to convert files the iPhone can't play. That needs CPU on the NAS; give it a moment. Check the Jellyfin dashboard for errors. |
| Hearth won't open after a week | Re-sign it with Sideloadly ("Every 7 days" above). |
| Sideloadly can't see the iPhone | Re-install the Apple (not Microsoft Store) versions of iTunes/iCloud, unlock the phone, and tap Trust. |
| GitHub build has a red cross | Click the failed run and open the red step to see the error. |

---

## For the curious: how it's built

- `project.yml`: an [XcodeGen](https://github.com/yonaskolb/XcodeGen) description of the Xcode project. The Xcode project itself is generated on the build machine.
- `.github/workflows/build-ipa.yml`: on a GitHub macOS machine, installs XcodeGen, builds for iPhone with code signing turned off, puts `Hearth.app` into `Payload/` and zips that as `Hearth.ipa`. Sideloadly signs it later.
- `Hearth/`: the SwiftUI app (iOS 16+).
  - `Jellyfin/`: sign-in via `/Users/AuthenticateByName`, browsing, artwork, and `PlaybackInfo` with an iPhone device profile. Compatible files play directly; anything else comes from Jellyfin's HLS transcoder (`/Videos/{id}/master.m3u8`). Progress goes to `/Sessions/Playing*`, which is what powers Continue Watching and resume.
  - `Navidrome/`: Subsonic API with token + salt auth (`t = md5(password + salt)`), the AVPlayer music queue, and lock-screen controls via `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.
  - `Info.plist` (generated from `project.yml`) allows plain-http connections, because Tailscale addresses use http, and turns on background audio.
- `desktop/`: the Electron app for Windows and Linux, with no framework or bundler.
  - `main.js` serves the UI from a private `hearth://` scheme and stores sign-ins encrypted with Electron `safeStorage`.
  - `renderer/` is the UI in plain HTML, CSS and JavaScript modules. Transcoded video streams play through hls.js.
  - `.github/workflows/build-desktop.yml` builds the Windows NSIS installer and the Linux AppImage and .deb with electron-builder.
  - To run it locally: `cd desktop`, `npm install`, `npm start`.
