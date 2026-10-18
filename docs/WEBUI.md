# Modern web interface: technical reference

This page is for people who maintain Alt-F, build it, or want to know how the interface works. To install it see [webui-install.md](webui-install.md). To use it see [webui-guide.md](webui-guide.md).

The interface sits next to the classic one. Every classic page is still there under Advanced, and SSH is untouched.

## What changed

| Area | Details |
| --- | --- |
| Look | One stylesheet (`alt-f.css`). Light and dark themes follow the system, with an Automatic, Light and Dark switch in the footer. Layouts run from a 320 px phone to a 4K screen, with 44 px tap targets, visible focus rings and reduced-motion support. |
| Home | Four cards: Files, Disk health and space, Shared folders, Is everything OK? |
| Health | The old status page rebuilt on the shared page shell, with a plain-language summary on top. All the technical tables are still there. |
| Files | A browser for `/mnt`: downloads and uploads of files and whole folders, a tree on wide screens and a plain list on phones, breadcrumbs, a `..` row, sorting, a filter box, on-request folder sizes. |
| Sign-in | One session per device. Sessions slide with activity (8 hours idle, 7 days at most by default), with a "keep me signed in" option and a Sign out button. |
| Advanced | Every classic settings page, built from the `.men` menu files, plus read-only SSH status and Restart and Switch off. Pages that can erase data or break the network ask for confirmation first. |

The static payload is `alt-f.css` (15.2 KB), `alt-f.js` (3.3 KB) and `files.js` (20.0 KB), about 38.5 KB uncompressed. There are no fonts, no CDNs and no build step.

### Files in the change

New under `board/dns32x/customroot/usr/www/`: `alt-f.css`, `alt-f.js`, `files.js`, and in `cgi-bin/`: `home.cgi`, `shares.cgi`, `advanced.cgi`, `confirm.cgi`, `classic.cgi`, `files.cgi`, `files_list.cgi`, `files_get.cgi`, `files_put.cgi`, `files_size.cgi` and `fs_common.sh`.

New under `customroot/etc/`: `web-session.conf`, plus a line for it in `/etc/settings` so that Save settings keeps it.

Changed: `cgi-bin/common.sh` (new helpers and a new `check_cookie`), `status.cgi`, `login.cgi`, `login_proc.cgi`, `logout.cgi`, `sys_utils_proc.cgi` (one line that clears sessions when the web password is reset) and `index.html` (it now lands on Home).

Also added: `board/dns32x/webui-install.sh` with its file list `webui-files.txt`, and `board/dns32x/webui-tests/`.

Untouched: every other classic page, the Dropbear and OpenSSH configuration, and everything outside `board/dns32x/customroot/` apart from the files listed above. There is no change to `configs/`, `package/`, `busybox.config`, `mkfw.sh` or `configfs`, so the firmware build is what it was.

### Every model gets the same files

All the Alt-F configurations (`alt-f_dns323_defconfig`, `alt-f_dns325_defconfig`, `alt-f_dns327_defconfig`, `alt-f_base_defconfig`, `alt-f_qemu_defconfig`) use `board/dns32x/customroot` as their root filesystem skeleton, and `mkfw.sh` builds every model's image from its board's root filesystem. The interface contains no model-specific code. The only reads that depend on the hardware are the model name, the temperature and fan sensors, and the disks present, and the health page handles a missing sensor the way the old status page did.

## How sign-in worked before, and how it works now

Before:

- The web password lives in plain text in `/etc/web-secret`. It is also the root, Samba and rsync password. That is unchanged.
- The login page made a random salt, saved it in one file (`/tmp/salt`), and the browser sent `md5(password + salt)`.
- A successful login wrote one random id to `/tmp/cookie`. Any other login, from any device, replaced it, so every other browser had to sign in again. The timeout was 30 minutes of inactivity. `status.cgi` did not check the cookie.

Now:

- Each login attempt gets its own one-time salt in `/tmp/sessions/salt.<hex>`. It is deleted on first use and valid for 10 minutes. The browser still sends `md5(password + salt)`. Without JavaScript the form sends the password and the server does the hashing, so signing in always works.
- A good login creates `/tmp/sessions/<64 hex characters>` (tmpfs, mode 600) holding the creation time, last-seen time, client address and the keep flag. It sets `ALTSID=<token>; Path=/; HttpOnly; SameSite=Strict`, plus `Secure` when you signed in over HTTPS and `Max-Age` when "keep me signed in" is ticked.
- Many devices can be signed in at once.
- `check_cookie` in `common.sh` is the one function every protected page calls. It validates the token (64 hex characters, so it can never name another file), checks idle and absolute expiry and the client address, and slides the idle clock.
- Cross-site protection: a POST must carry an `Origin` (or `Referer`) whose host equals the `Host` header, or it gets a 403. The cookie is also `SameSite=Strict`.
- Background requests without a session get a 401 instead of a redirect page.
- Expired sessions and stale challenges are deleted on every login, so there is no cron job.
- A wrong password waits 2 seconds and is logged. After login the browser is only ever sent to a page under `/cgi-bin/`.
- `status.cgi` now requires a login like every other page.

How the password is stored is unchanged.

### Change the timeouts

Edit `/etc/web-session.conf`. It uses shell syntax and applies on the next request, with no restart:

```sh
SESSION_IDLE=28800     # seconds of inactivity before sign-in is needed again (8 h)
SESSION_ABS=604800     # longest a session can live, active or not (7 days)
SESSION_BIND_IP=yes    # no: let a session follow you if your address changes
```

Use Advanced, then Settings, then Save so that the change survives a reboot. If the file is missing, the defaults above apply.

When you use the HTTPS port, stunnel starts httpd directly and the address httpd sees may be empty. Sessions with no address are not bound. If you are signed out right after signing in over HTTPS, set `SESSION_BIND_IP=no`.

## The file browser

- Only `/mnt` is shown. A symlink that points outside `/mnt` is hidden and cannot be opened. Every path goes through `realpath`, must start with `/mnt` before and after resolving, and is refused if it holds a control character or NUL.
- Names come from the shell, not `ls`. This BusyBox has no Unicode support, and `ls` prints every non-ASCII byte as `?`. Dot files, `lost+found` and names with control characters are not listed. A folder shows at most 1000 entries, and a note says so.
- Alt-F's own items at the top of each disk are hidden: `Alt-F`, `ffp`, `opt`, `lost+found`, `aquota.user`, `aquota.group`, the boot logs `alt-f.log` and `alt-f.log-previous`, and leftover temporary files of the `zip` program. They are not listed or openable, they are left out of whole-disk archives, and nothing can be uploaded under those names. A folder with one of those names deeper down is treated normally. Use SSH or the classic pages to work with them.
- A zip leftover is a file named `zi` plus six letters or digits that is owned by root, readable by root only, and starts with the zip signature (`PK 03 04`). Every condition must hold, so look-alike names are never hidden. An interrupted `zip` leaves these behind, sometimes many gigabytes each. They can be deleted over SSH.
- Folders download as a `.tar` archive. The image has no `zip` program, and adding one would change the firmware build. Links inside a folder are stored as links and never followed. The archive is streamed without a size, so the browser shows no percentage. The All disks view cannot be downloaded.
- Downloads have no resume, because BusyBox `httpd` has no Range support. HTML, SVG and unknown types always download. Only images, PDF, audio, video and plain text can open in the browser.
- Uploads: each file is one request, sent in turn. The body is streamed to a hidden temporary file in the target folder and renamed when complete, so a dropped connection leaves nothing behind. An existing file is never replaced, and the new one is saved as `name (2).ext`. New files take the owner and group of the folder and mode 664 (folders 775), so Samba users can still change them. The page checks free space before the first byte. Without JavaScript the simple page has a single-file upload form.
- Upload limits: 2 GB per file, because BusyBox `httpd` reads the length as a signed 32-bit number. Empty folders are not uploaded. Choosing a folder needs a desktop browser. Names with control characters, `.`, `..` or a leading `.upload-` are refused, and so is a symlink anywhere in the target path. The All disks root cannot be uploaded into.
- Folder sizes: `files_size.cgi` runs `du -skx` only when someone presses a Size button. One count runs at a time under a lock in `/tmp/fs-size.lock`, at low priority, and it stops after 60 seconds with a 504. At the top of a disk each item is counted on its own so hidden items can be left out. The figure is disk space used, so it can be a little more than the file sizes added up. Drives mounted inside the folder are not counted.
- A file swapped for a symlink in the instant between the path check and the read could in theory escape. Only someone who can already write to the shared disks could try it.
- The "settings are not saved" notice only appears on Advanced, not on Home.
- A few classic pages still use the old look. They open inside the original frames from Advanced. The first-time setup wizard is made of classic pages and runs inside those frames too.

## Install script

`board/dns32x/webui-install.sh` copies the files over SSH. See [webui-install.md](webui-install.md) for how to use it. How it works:

- It reads the list of files from `webui-files.txt`. Keep that list in step with the files when you add one.
- Before the first install it saves what it is about to replace in `/usr/share/webui-backup`: a tar of the existing files, and lists of the files that existed and the ones that are new. `--remove` extracts the tar over `/` and deletes the new files. It does not delete originals, because on aufs a delete hides the lower copy.
- A re-install keeps an edited `/etc/web-session.conf` and adds the `/etc/settings` line only once.
- Whether a copy survives a reboot depends on the box. The root is a read-only image with a RAM layer on top. If an `Alt-F` folder on a disk is in use, `aufs.sh` adds it as the top writable layer, and the copy is written there.
- Host names are checked against a short list of safe characters before they reach `ssh`.

## Tests

`board/dns32x/webui-tests/` is not shipped in the image. It runs the real scripts under a BusyBox `httpd` on your computer, in a sandbox, and changes nothing outside `/tmp`:

```sh
BB=/path/to/busybox SHELLCHECK=/path/to/shellcheck sh board/dns32x/webui-tests/run-all.sh
```

`BB` needs the `httpd`, `ash`, `hexdump`, `md5sum` and `realpath` applets. To match the NAS, build BusyBox 1.31.1 with `board/dns32x/pkgs/busybox.config` and the patches in `package/busybox/`. On a modern computer set `CONFIG_TC=n` and `CONFIG_FEATURE_MOUNT_NFS=n`, which do not compile against current headers.

What the tests check:

- The syntax of every script, with host `sh -n` and BusyBox `ash -n`, and `shellcheck -s sh` on the new scripts.
- `test-auth.sh` (56 checks): first-time password, wrong and right password, the one-time challenge, cookie flags, return-to-page safety (open redirect, header injection, classic pages coming back inside their frames), the first-time wizard, forged and malformed cookies, two devices at once, idle and absolute timeouts, expiry cleanup, address binding, cross-site POSTs and sign out.
- `test-files.sh` (148 checks) and `test-upload.sh` (86 checks): `../`, `%2e%2e`, double encoding, NUL, newline and control characters, `//`, look-alike folders such as `/mntx`, symlinks that leave `/mnt` and ones that stay inside, a 401 without a session, exact bytes and `Content-Length` for downloads, odd names (spaces, quotes, `&`, `<>`, `;`, accents, emoji), `Content-Disposition` encoding, HTML never shown inline, truncation of huge folders, escaping in the no-JavaScript page, hidden items, folder sizes (locking, timeout, stale locks), no overwriting, nested folders, disk space, a 200 MB binary, an interrupted upload and the multipart form.
- `test-install.sh` (12 checks): `webui-install.sh` against a fake box in a user namespace. It checks the copy, the executable bits, a second run keeping edited settings, `--remove` restoring the originals and bad host names being refused. It skips itself where user namespaces are unavailable.

The last run passed all 56, 148, 86 and 12 checks on BusyBox 1.31.1 built from the repository configuration. The first three also passed on BusyBox 1.20.2 before the most recent changes, and the files suite passed on 1.20.2 after them. A headless Chromium rendered Login, Home, Files, Health, Shared folders and Advanced at 320, 768, 1280 and 2560 px in light and dark, with no horizontal scrolling and no console errors.

Not tested: every individual model, real disks beyond one test box, HTTPS through stunnel, and a full Buildroot build.

## Older Alt-F releases (BusyBox 1.20)

A box still running an older Alt-F release has BusyBox 1.20.2, which differs from the 1.31.1 in this repository. The new pages are written for both, and the test suite passes on both:

- `ls` has no `--full-time` there, only `-e`. The file browser asks which one works.
- `awk -F'\t'` does not unescape the tab there, so the file list sets `FS` inside the program.
- `httpd` hides most request headers there: no `Origin`, no `Sec-Fetch-*` and no `X-Requested-With`. The cross-site check falls back to `Referer`, which browsers always send on same-site form and upload posts. File and status requests ask for a 401 explicitly, and a server that ignores `Status:` is handled by checking the JSON body.
- Shell arithmetic is 32 bits there, so disk sizes are formatted in awk.

To test against 1.20, build `busybox-1.20.2` with `make defconfig` plus `CONFIG_EXTRA_CFLAGS="-include compat.h"`. The header `compat.h` includes `sys/resource.h` and defines a stub `stime`. Disable `FEATURE_INETD_RPC` and `FEATURE_MOUNT_NFS`.
