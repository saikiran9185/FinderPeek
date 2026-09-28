# FinderPeek

**Auto-hide for the macOS Finder sidebar.**

The sidebar stays out of the way. Push the pointer to the left edge of a Finder window and it appears instantly; move back to your files and it hides again. It works like the auto-hiding Dock, but for Finder's sidebar.

macOS has no built-in way to do this. The only options are View ▸ Hide/Show Sidebar or ⌃⌘S by hand.

## Features

- **Instant reveal.** The sidebar opens about 50 ms after the pointer reaches the window's left edge.
- **Hides on its own** as soon as the pointer leaves the sidebar.
- **Safe for drag-and-drop.** It never hides while a mouse button is down, so you can drag files onto sidebar favourites.
- **Only normal Finder windows.** The desktop, Get Info panels and sheets are left alone.
- **Works in any language.** It finds the toggle by its ⌃⌘S shortcut, not by the menu item's name.
- **Lightweight menu-bar app.** There's no Dock icon, and you can turn it on or off or set it to open at login from the menu.

## Install

You need macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/saikiran9185/FinderPeek.git
cd FinderPeek
./build.sh
```

`build.sh` compiles the app, signs it, copies it to `/Applications` and launches it.

On first launch, grant **Accessibility** access: System Settings ▸ Privacy & Security ▸ Accessibility ▸ turn on **FinderPeek**. The menu also has a **Grant Accessibility Access…** shortcut until it's allowed.

Then choose **Open at Login** from the menu-bar icon (sidebar symbol) so it starts automatically.

## How it works

FinderPeek is a single Swift file with no dependencies. It uses the macOS Accessibility API to:

1. **Watch the pointer** with a global mouse-move monitor, so it reacts immediately instead of polling.
2. **Read the focused Finder window's layout.** When the sidebar is showing, the window's split view contains a scroll area holding an `AXOutline`. That's how it knows whether the sidebar is open and how wide it is.
3. **Toggle the sidebar** by pressing Finder's own View ▸ Show/Hide Sidebar menu item (`AXPress`). Finder does all the drawing and animation; nothing is injected into Finder.

After each toggle it waits until Finder reports the new state before acting again, which prevents double toggles without adding a fixed delay.

## Tuning

The constants are at the top of the `Peek` class in `FinderPeek.swift`:

| Constant | Default | What it does |
|---|---|---|
| `edgeWidth` | 8 px | How close to the left edge the pointer must be to reveal the sidebar |
| `hideMargin` | 24 px | Extra room past the sidebar before it counts as "left" |
| `hideDelay` | 0.08 s | Short grace period so overshooting the edge doesn't flicker |
| `toolbarHeight` | 52 px | The toolbar strip that's ignored, so the window buttons don't trigger it |

Run with `PEEK_DEBUG=1` to log decisions to stderr:

```sh
open --env PEEK_DEBUG=1 --stderr /tmp/finderpeek.log /Applications/FinderPeek.app
```

## Notes

- If you build without an Apple Development certificate, the app is signed ad-hoc. macOS may then ask you to grant Accessibility access again after each rebuild.
- The hide feels slightly slower than the reveal because Finder plays its own slide-away animation.

## License

MIT
