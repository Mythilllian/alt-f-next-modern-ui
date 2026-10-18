# Using the modern interface

This guide is for anyone who uses the NAS day to day. You do not need to know anything technical.

## Signing in

Open the NAS address in your browser and type the NAS password.

Tick "Keep me signed in on this device" on your own computer or phone, so you stay signed in after closing the browser. Leave it unticked on someone else's. Either way you are signed out after 8 hours without activity, and after 7 days at most. You can sign in from several devices at once.

Tap Sign out when you finish on a computer that is not yours.

If you have never set a password, the first visit asks you to choose one.

## The home page

The home page has four cards.

- Files opens the file browser.
- Disk health and space shows how full the disks are.
- Shared folders lists the folders other computers on your network can open, and how to open them.
- Is everything OK? gives a one-sentence answer. It is green when all is well. If it turns yellow or red, open it, read the sentence, and pass it on to whoever looks after the NAS.

## Finding and downloading files

1. Open Files.
2. Pick a disk, then open folders until you find what you want. On a large screen, the arrow next to a folder shows what is inside without leaving the page. On a phone you open one folder at a time.
3. Tap a file to download it. Pictures, PDFs, music, video and text files also have an "Open in browser" link.
4. To get a whole folder, use Download folder on its row, or Download this folder at the top of the page. It arrives as one `.tar` file. Windows 10 (version 1803 or later) and macOS open `.tar` files. Older Windows needs a free tool such as 7-Zip.

Use the box at the top to type part of a name. The menu beside it sorts by name, by size (biggest first) or by date (newest first).

The `..` row at the top of every folder takes you up one level. The path above the list (All disks, then the disk, then each folder) also works as a set of links.

## Adding files

Open a folder on a disk, then either:

- drag files or whole folders onto the dashed box, or
- tap Upload files or Upload a folder and choose them.

Each file shows its progress, and Stop cancels the rest. Things to know:

- A file is never replaced. If a file with the same name is already there, the new one is saved as `name (2).ext`.
- Folders keep their structure.
- Other people on the network can still change files you upload. They get the same access as the rest of the folder.
- The limit is 2 GB per file. The page checks there is enough free space before it starts.
- Choosing a whole folder needs a desktop browser. Phones can upload files.
- You can't upload into the All disks page. Open a disk first.

## How much space does a folder use?

Each folder row has a Size button, and each folder page has Folder size. Press one to count. Nothing is counted until you ask, because counting reads every file in the folder and keeps the disk busy. If a folder is too big to count in about a minute, the page says so. Open it and count the folders inside instead.

The figure is the space used on the disk, which can be a little more than the total of the file sizes.

## Items you won't see

Alt-F's own files at the top of each disk are hidden so that nobody can change or delete them by accident. These are `Alt-F`, `ffp`, `opt`, `lost+found`, the quota files, the boot logs `alt-f.log` and `alt-f.log-previous`, and the leftover temporary files an interrupted `zip` run can leave behind. Files that start with a dot are also hidden. A folder with one of these names deeper down, such as `Photos/opt`, shows as normal.

## Changing the look

The footer has an Automatic, Light and Dark switch. Automatic follows your device. The choice is remembered on that device.

## Advanced

Advanced holds every setting Alt-F has: disks, network, users, services, packages and the rest, as in the classic interface. You never need it for everyday use.

Pages that can erase a disk, change the network, update the firmware or restart the box ask "Are you sure?" first, and you can always go back. Advanced also has Restart and Switch off.

## If something looks wrong

- "Your session ended": sign in again. This happens after the idle limit, or after the NAS password is reset.
- The page looks old after an update: press Ctrl+Shift+R.
- A folder looks empty or a disk is missing: check the drive is plugged in, then refresh.
- You are signed out right after signing in over HTTPS: ask whoever manages the NAS to set `SESSION_BIND_IP=no`. The [technical reference](WEBUI.md#change-the-timeouts) explains how.
