# The new Alt-F web interface

This branch (`webui`) adds a simpler, friendlier web interface next to the classic one. It targets the DNS-320L (and every other box built from `alt-f-dns325_defconfig`). Nothing was removed: every classic page is still there under **Advanced**, and SSH is untouched.

## What changed

| Area | What you get |
| --- | --- |
| Look | One stylesheet (`alt-f.css`), light and dark themes that follow the system with an Automatic / Light / Dark switch in the footer, layouts from a 320 px phone to a 4K screen, 44 px tap targets, visible focus rings, reduced-motion support. |
| Home | Four cards: Files, Disk health and space, Shared folders, Is everything OK? Written in plain language. |
| Health | The old status page, rebuilt on the shared shell, with a plain-language summary on top. All the technical tables are still there. |
| Files | A browser for `/mnt`: one folder level at a time, a tree on wide screens and a plain list on phones, breadcrumbs, sort by name/size/date, a filter box, human-readable sizes and dates, and download links. |
| Sign-in | One login per device. Sessions slide with activity (8 hours idle, 7 days at most by default), "Keep me signed in on this device", and a Sign out button. |
| Advanced | Every classic settings page, built from the `.men` menu files, plus SSH status (read-only) and Restart / Switch off. Pages that can erase data or break the network ask for confirmation first. |

Static payload: `alt-f.css` 14.3 KB + `alt-f.js` 3.3 KB + `files.js` 9.1 KB = 26.7 KB uncompressed (8.3 KB gzipped). No fonts, no CDNs, no build step.

### Files

New under `board/dns32x/customroot/usr/www/`:
`alt-f.css`, `alt-f.js`, `files.js`, and in `cgi-bin/`: `home.cgi`, `shares.cgi`, `advanced.cgi`, `confirm.cgi`, `classic.cgi`, `files.cgi`, `files_list.cgi`, `files_get.cgi`, `fs_common.sh`.

New under `customroot/etc/`: `web-session.conf` (and a line for it in `/etc/settings`, so "Save settings" keeps it).

Changed: `cgi-bin/common.sh` (new helpers, new `check_cookie`), `status.cgi`, `login.cgi`, `login_proc.cgi`, `logout.cgi`, `sys_utils_proc.cgi` (one line: clears sessions when the web password is reset), `index.html` (now lands on Home).

Untouched: every other classic page, Dropbear and OpenSSH configuration, and everything outside `board/dns32x/customroot/`. No change to `configs/`, `package/`, `busybox.config`, `mkfw.sh` or `configfs`, so the firmware build is exactly what it was.

## How sign-in worked before, and now

Before:

- The web password lives in plain text in `/etc/web-secret` (it is also the root, Samba and rsync password). That is unchanged.
- The login page made a random salt, saved it in one file (`/tmp/salt`), and the browser sent `md5(password + salt)`.
- A successful login wrote **one** random id to `/tmp/cookie`. Any other login, from any device, replaced it, and every other browser had to sign in again. Timeout was 30 minutes of inactivity. `status.cgi` did not check the cookie at all.

Now:

- Each login attempt gets its own one-time salt (`/tmp/sessions/salt.<hex>`, deleted on first use, valid for 10 minutes). The browser still sends `md5(password + salt)`. Without JavaScript the form sends the password and the server does the hashing, so signing in always works.
- A good login creates `/tmp/sessions/<64 hex chars>` (tmpfs, mode 600) holding creation time, last-seen time, client address and the "keep me signed in" flag, and sets `ALTSID=<token>; Path=/; HttpOnly; SameSite=Strict` (plus `Secure` when you signed in over https, plus `Max-Age` when "keep me signed in" is ticked).
- Many devices can be signed in at once.
- `check_cookie` in `common.sh` is the one function every protected page calls. It validates the token (64 hex characters, so it can never name another file), checks idle and absolute expiry, checks the client address, and slides the idle clock.
- Cross-site protection: a POST must carry an `Origin` (or `Referer`) whose host equals the `Host` header, otherwise it gets a 403. The cookie is also `SameSite=Strict`.
- Background requests without a session get `401` instead of a redirect page.
- Expired sessions and stale challenges are deleted on every login, so there is no cron job.
- Wrong passwords wait 2 seconds and are logged. After login the browser is only ever sent to a page under `/cgi-bin/`.
- `status.cgi` now requires a login like every other page.

Not changed on purpose: how the password is stored.

### Change the timeouts

Edit `/etc/web-session.conf` (shell syntax, applies on the next request, no restart):

```sh
SESSION_IDLE=28800     # seconds of inactivity before sign-in is needed again (8 h)
SESSION_ABS=604800     # longest a session can live, active or not (7 days)
SESSION_BIND_IP=yes    # no: let a session follow you if your address changes
```

Then use **Advanced > Settings > Save** so the change survives a reboot. If the file is missing, the defaults above apply.

Note on `SESSION_BIND_IP`: when you use the https port, stunnel starts httpd directly and the address httpd sees may be empty. Sessions with no address are not bound. If you ever get signed out right after signing in over https, set it to `no`.

## Install on a running 320L (try it without flashing)

The root filesystem is a read-only image with a RAM layer on top (aufs). Files you copy are used immediately and **disappear on reboot**, which makes this a safe way to try the interface.

From the repository root on your PC (use your NAS name or address; SSH works as before):

```sh
cd board/dns32x/customroot
tar cf - \
  usr/www/alt-f.css usr/www/alt-f.js usr/www/files.js usr/www/index.html \
  usr/www/cgi-bin/common.sh usr/www/cgi-bin/fs_common.sh \
  usr/www/cgi-bin/login.cgi usr/www/cgi-bin/login_proc.cgi usr/www/cgi-bin/logout.cgi \
  usr/www/cgi-bin/status.cgi usr/www/cgi-bin/sys_utils_proc.cgi \
  usr/www/cgi-bin/home.cgi usr/www/cgi-bin/shares.cgi usr/www/cgi-bin/advanced.cgi \
  usr/www/cgi-bin/confirm.cgi usr/www/cgi-bin/classic.cgi \
  usr/www/cgi-bin/files.cgi usr/www/cgi-bin/files_list.cgi usr/www/cgi-bin/files_get.cgi \
  etc/web-session.conf | ssh root@NAS 'tar xf - -C /'
ssh root@NAS 'grep -q web-session /etc/settings || echo /etc/web-session.conf >> /etc/settings'
```

Then open `http://NAS/` in a browser. The old password still works.

**Roll back:** reboot the NAS (Advanced > Restart the NAS, or `ssh root@NAS reboot`). Everything you copied is gone and the original pages are back. Do not delete the copied files by hand: on aufs a delete hides the original underneath too. If you saved settings while testing, `/etc/web-session.conf` is also in the saved settings; that is harmless.

## Make it permanent (rebuild the firmware)

The files live in the root filesystem skeleton, so the normal build picks them up. For the DNS-320L:

```sh
make alt-f-dns325_defconfig
make >& build.log
```

The 320L image is `Alt-F-<version>-DNS-320L-rev-Ax.bin` in the binaries directory. Flash it the usual way. (`mkfw.sh` builds the 320L image from the same root filesystem as the 325.)

## Tests

`board/dns32x/webui-tests/` is not shipped in the image. It runs the real scripts under a BusyBox `httpd` on your PC, in a sandbox, with no changes outside `/tmp`:

```sh
BB=/path/to/busybox SHELLCHECK=/path/to/shellcheck sh board/dns32x/webui-tests/run-all.sh
```

`BB` needs the `httpd`, `ash`, `hexdump`, `md5sum` and `realpath` applets. To match the NAS exactly, build BusyBox 1.31.1 with `board/dns32x/pkgs/busybox.config` and the patches in `package/busybox/` (on a modern PC set `CONFIG_TC=n` and `CONFIG_FEATURE_MOUNT_NFS=n`; they do not compile against current headers).

What is checked:

- Syntax of every script (host `sh -n`, BusyBox `ash -n`) and `shellcheck -s sh` on the new scripts.
- `test-auth.sh` (56 checks): first-time password, wrong and right password, one-time challenge, cookie flags, return-to-page safety (open redirect, header injection, classic pages coming back inside their frames), the first-time wizard, forged and malformed cookies, two devices at once, idle and absolute timeouts, expiry cleanup, address binding, cross-site POSTs, sign out.
- `test-files.sh` (92 checks): `../`, `%2e%2e`, double encoding, NUL, newline and control characters, `//`, look-alike folders such as `/mntx`, symlinks that leave `/mnt`, symlinks that stay inside, 401 without a session, exact bytes and `Content-Length` for downloads, names with spaces, quotes, `&`, `<>`, `;`, accents and emoji, `Content-Disposition` encoding, HTML never shown inline, truncation of huge folders, escaping in the no-JavaScript page.

Last run: 56 of 56 and 92 of 92 passed, with BusyBox 1.31.1 built from the NAS configuration. Headless Chromium rendered Login, Home, Files, Health, Shared folders and Advanced at 320, 768, 1280 and 2560 px in light and dark: no horizontal scrolling and no console errors.

What was **not** tested: a real ARM box, real disks, HTTPS through stunnel, and a full Buildroot build.

## Things worth knowing

- The file browser only shows what is inside `/mnt`. A symlink that points outside `/mnt` is hidden and cannot be opened. Every path goes through `realpath`, must start with `/mnt` before and after resolving, and anything with a control character or NUL is refused.
- Names come from the shell, not `ls`: this BusyBox has no Unicode support and `ls` prints every non-ASCII byte as `?`. Dot files, `lost+found` and names containing control characters are not listed. Folders show at most 1000 entries (a note appears).
- Downloads have no resume (BusyBox `httpd` has no Range support). HTML, SVG and unknown types always download; only images, PDF, audio, video and plain text can open in the browser.
- A file swapped for a symlink in the instant between the path check and the read could in theory escape. Only someone who already has write access to the shared disks could try it.
- `status.cgi` used to be open to anyone on the network. It now needs a login.
- The "settings are not saved" notice only appears on Advanced, not on Home.
- A few classic pages still use the old look. They open inside the original frames from Advanced. The first-time setup wizard is made of classic pages, so it runs inside those frames too.

## For your parents

**Signing in.** Open the NAS address in your browser. Type the NAS password. Tick "Keep me signed in on this device" on your own computer or phone, and leave it empty on someone else's. You stay signed in for the day, and for up to a week if you ticked the box.

**Finding a file.** Tap **Files**. Tap a folder to open it. Tap a file to download it. Pictures, PDFs and music also have an "Open in browser" link. Use the box at the top to type part of a name, and the menu next to it to put the newest or biggest files first.

**Is everything OK?** The Home page says so in the green box at the top. If it turns yellow or red, tap it, read the sentence, and show it to whoever looks after the NAS.

**Space left.** The Disk health and space card shows how full the disks are. Nothing to do until it says a disk is almost full.

**Shared folders.** This page lists the folders other computers on your network can see, and how to open them.

**Signing out.** Tap **Sign out** at the top when you are done on a computer that is not yours.

**If something looks wrong.** You never need the Advanced page. Anything there that could erase or switch things off asks "Are you sure?" first, and you can always tap Go back.
