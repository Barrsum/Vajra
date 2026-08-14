# Exporting a standalone build

The goal here is a folder you can zip and send to someone who does not have
Godot, does not have the repo, and does not want to think about either.

## One-time setup: export templates

Godot's editor cannot produce a standalone build on its own. It needs **export
templates** — the prebuilt engine binaries that get stapled to your game data.
They are a ~1 GB download and are *not* part of the editor executable.

In the editor: **Editor → Manage Export Templates → Download and Install**.

The version must match your editor exactly. Templates for 4.7.1 will not work
with 4.7.2. If you ever upgrade Godot, re-download them.

> Offline or on a slow connection: grab `Godot_v4.7.1-stable_export_templates.tpz`
> from the [archive](https://godotengine.org/download/archive/) and use
> **Install from File** in the same dialog.

---

## Creating the presets

**Project → Export → Add…** and pick a platform. Do this once per platform; the
settings are saved to `export_presets.cfg`.

For each preset:

- **Binary → Embed PCK** — on. Without it you get a `.exe` *and* a `.pck` data
  file that must travel together. Embedding gives you one file, which is much
  harder for a friend to break by moving it.
- **Resources → Export Mode** — leave on *Export all resources in the project*.
- **Exclude filter** — worth setting to `tests/*, docs/*, shots/*` so the test
  scenes and screenshots do not ship. Not required, just tidy.

Then **Export Project…**, pick an output path, and untick *Export With Debug*
for anything you are handing to another person. Debug builds print to a console
window and run slower.

Send the whole output folder, zipped.

---

## Windows

Preset: **Windows Desktop**. Output: `vajra.exe`.

With *Embed PCK* on, that single `.exe` is the entire game. Nothing to install,
no runtime, no dependencies.

Two things worth knowing:

**SmartScreen will warn on first run.** Unsigned executables downloaded from the
internet get a blue "Windows protected your PC" dialog. Your friends click *More
info → Run anyway*. Making it go away means buying a code-signing certificate,
which for a project like this is not worth it — just warn them it will happen.

**Antivirus false positives are common** for Godot exports, because the pattern
of a self-extracting executable resembles a packer. If someone reports their
antivirus eating it, that is why, and it is not something you can fix from this
end.

---

## Linux

Preset: **Linux/X11** (called *Linux* in newer Godot). Output: `vajra.x86_64`.

The executable bit does not survive a zip file, so tell people to run:

```sh
chmod +x vajra.x86_64
./vajra.x86_64
```

Godot 4 requires Vulkan. On very old hardware or in a VM the Forward+ renderer
will fail to start. If that comes up, the fix is a second export preset with
**Project Settings → Rendering → Renderer → Rendering Method** set to
`gl_compatibility`, exported separately.

You can export a Linux build from Windows. It does not need a Linux machine.

---

## macOS

This is the awkward one, and the honest answer is: **you can export a macOS
build from Windows, but you cannot make it open cleanly on someone else's Mac.**

Preset: **macOS**. Output: `vajra.zip` (a zipped `.app` bundle).

What stops it being simple:

**Gatekeeper blocks unsigned apps.** macOS refuses to run an app that is neither
signed with an Apple Developer ID nor notarised by Apple. A friend
double-clicking your `.app` gets *"cannot be opened because the developer cannot
be verified"* with no obvious way forward.

**Signing requires a Mac and $99/year.** Notarisation means uploading the build
to Apple from macOS with an Apple Developer Program membership. There is no way
to do it from Windows and no free tier.

**The workaround your friends can use:** right-click the app → **Open** →
**Open** in the dialog. That grants a one-time exception. On recent macOS they
may instead need **System Settings → Privacy & Security**, then *Open Anyway*
next to the blocked app. Or from a terminal:

```sh
xattr -dr com.apple.quarantine /path/to/vajra.app
```

Practically: if you have Mac friends, either walk them through the right-click
trick, or skip macOS. For a passion project the certificate is hard to justify.

---

## Exporting from the command line

Once the presets exist, you never need to open the editor again:

```sh
godot --headless --path . --export-release "Windows Desktop" build/vajra.exe
godot --headless --path . --export-release "Linux/X11"       build/vajra.x86_64
godot --headless --path . --export-release "macOS"           build/vajra.zip
```

The preset name must match what is in `export_presets.cfg` exactly, quotes
included. `build/` is gitignored.

Useful for a release script, or a GitHub Action that builds all three on a tag.

---

## A note on `export_presets.cfg`

It is currently gitignored, because for some platforms it can hold signing
credentials. This project is desktop-only and has none, so if you want everyone
cloning the repo to be able to export without setting presets up themselves,
it is safe to commit — drop the line from `.gitignore`.

Do not commit it if you ever add an Android preset. Those store keystore
passwords in plain text.
