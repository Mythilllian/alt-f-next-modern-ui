# Installing the modern interface

There are two ways to get it. The first one takes a couple of minutes and does not touch the firmware. The second one builds it into a firmware image.

## Option 1: install with the script

The script copies the interface to a running box over SSH. It can also put the original pages back.

### What you need

- A computer on the same network as the NAS, with `ssh` and `tar` installed. Linux and macOS have both. Windows 10 and 11 have both in PowerShell, but the script itself needs a shell: use WSL or Git Bash.
- The NAS address. This is its name (for example `dns-xxxxxx`, the name you gave it in Alt-F) or its IP address, which you can find in your router's list of connected devices.
- SSH switched on in the NAS. Open the classic pages, go to Advanced, then Services, then Network, and turn on the SSH service.
- The NAS password. It is also the password for the `root` user over SSH.

### Steps

1. Get the files. Either download the repository as a ZIP from GitHub and unpack it, or run `git clone https://github.com/Mythilllian/alt-f-next-modern-ui`.
2. Open a terminal in that folder.
3. Look at the box first. This changes nothing:
   ```sh
   sh board/dns32x/webui-install.sh --status nas-name-or-address
   ```
   It reports whether the interface is installed and whether a copy would survive a reboot (see below).
4. Install:
   ```sh
   sh board/dns32x/webui-install.sh nas-name-or-address
   ```
   Type the NAS password when asked. Answer `y` to the question.
5. Open `http://nas-name-or-address/` in a browser and sign in as usual. Press Ctrl+Shift+R once so the browser drops old copies of the pages.

SSH asks for the password several times. To avoid that, set up an SSH key, or ignore it: nothing is wrong.

### Will it still be there after a reboot?

That depends on the box. The script tells you in step 3 and again before it copies anything.

- Alt-F keeps its system in a read-only image, with a layer in memory on top. A copy made to that layer disappears when the box restarts. Restarting is a safe way to undo the install.
- If you have an `Alt-F` folder on a disk, and Alt-F is using it, that folder is part of the system. The copy is then kept across restarts.

### Update

Run the same install command again. It replaces the files and keeps any changes you made to `/etc/web-session.conf`.

### Remove

```sh
sh board/dns32x/webui-install.sh --remove nas-name-or-address
```

Before the first install the script saves the files it replaces in `/usr/share/webui-backup` on the NAS. `--remove` puts them back and deletes the files it added. Do not delete the copied files by hand: on this kind of file system a manual delete hides the original underneath too.

### Options

| Option | Meaning |
| --- | --- |
| `--status` | Show whether the interface is installed and whether the copy is permanent. Changes nothing. |
| `--remove` | Put the original files back. |
| `--yes` | Do not ask before changing the box. |
| `user@host` | Connect as another user. The default is `root`. |

### If something goes wrong

- "could not reach the box over ssh": check the address, and that SSH is on in the NAS.
- A password prompt keeps coming back: the password is wrong. It is the same one you use to sign in to the web pages.
- The old pages still show: press Ctrl+Shift+R, or open the address in a private window.
- You are signed out right after signing in over HTTPS: set `SESSION_BIND_IP=no` in `/etc/web-session.conf`. See the [technical reference](WEBUI.md#change-the-timeouts).

## Option 2: build it into the firmware

Building takes a few hours and tens of gigabytes of disk space. You need a Linux computer that can build Buildroot. The files live in the root filesystem skeleton at `board/dns32x/customroot/`, so a normal Alt-F build includes them. There is nothing to switch on.

1. Pick the configuration for your model:

   | Your model | Configuration |
   | --- | --- |
   | DNS-321, DNS-323, CH3SNAS, DUO-35LR | `alt-f_dns323_defconfig` |
   | DNS-320, DNS-320L, DNS-325 | `alt-f_dns325_defconfig` |
   | DNS-327L | `alt-f_dns327_defconfig` |

2. Build:
   ```sh
   make alt-f_dns325_defconfig    # use the line for your model
   make >& build.log
   ```
3. The images are in the binaries directory, named `Alt-F-<version>-<model>.bin`. One build produces an image for each model in its group, so pick the file with your model and hardware revision in its name.
4. Flash the image the usual way, as described in `board/dns32x/README.INSTALL`. Flashing replaces the firmware on the box, so read those instructions first and use the file for your exact model and revision.

The firmware build itself is unchanged by the modern interface, so the build steps are the same as for any other Alt-F build.

This repository's changes have not been through a full firmware build yet. If you try it, a report of how it went is welcome.
