# Alt-F modern web interface

The modern interface is a simpler, friendlier way to use an Alt-F NAS from a browser. It sits next to the classic interface. Nothing was removed: every classic page is still there under Advanced.

It works the same on every box that runs Alt-F. It ships as part of the root filesystem, which every supported model builds from, so a build for any of them contains the same pages.

## What you get

- A home page with four cards: Files, Disk health and space, Shared folders, and a plain "Is everything OK?" check.
- A file browser. Open folders, download files, download a whole folder as one archive, upload files and folders by dragging them in, and count how much space a folder uses.
- A health page that says in a sentence whether anything needs attention, with the full technical tables below it.
- Light and dark themes that follow your device, with an Automatic, Light and Dark switch in the footer.
- A layout that works from a small phone to a large monitor, with large tap targets and visible keyboard focus.
- One sign-in per device, a "Keep me signed in on this device" option and a Sign out button.
- Alt-F's own system folders hidden in the file browser, so they can't be changed or deleted by accident.
- An Advanced page with every classic setting, plus power buttons. Pages that can erase data or break the network ask for confirmation first.

It needs no extra software on the NAS. The pages are plain HTML, one stylesheet and a little JavaScript. They also work with JavaScript turned off.

## Get started

Pick the way that suits you.

| I want to | Read |
| --- | --- |
| Try it on my NAS now, without flashing anything | [Install with the script](webui-install.md#option-1-install-with-the-script) |
| Have it built into my firmware | [Build the firmware](webui-install.md#option-2-build-it-into-the-firmware) |
| Learn how to use it | [User guide](webui-guide.md) |
| Understand how it works, or change it | [Technical reference](WEBUI.md) |

The quick version, from a copy of this repository on your computer:

```sh
sh board/dns32x/webui-install.sh nas-name-or-address
```

Then open `http://nas-name-or-address/` in a browser and sign in with your usual NAS password.

To go back to the original pages at any time:

```sh
sh board/dns32x/webui-install.sh --remove nas-name-or-address
```

## What it does not change

- How the password is stored.
- The SSH server settings. SSH keeps working as before.
- Anything in the firmware build apart from the web files.

## Supported boxes

Every box built from these configurations gets the same web files:

| Build with | Models |
| --- | --- |
| `alt-f_dns323_defconfig` | DNS-321, DNS-323, CH3SNAS, DUO-35LR |
| `alt-f_dns325_defconfig` | DNS-320, DNS-320L, DNS-325 |
| `alt-f_dns327_defconfig` | DNS-327L |

Only hardware readings differ between models, for example the temperature and fan sensors that the health page shows, and how many disks a box has. The sign-in, file browser, upload and install steps are identical.

## Other Alt-F documents

The files in this folder written before the modern interface (`README`, `README.diskimage`, `manual/` and the `.html` pages) belong to the original Alt-F and Buildroot projects.
