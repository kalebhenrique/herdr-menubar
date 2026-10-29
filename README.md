# Herdr Menu Bar

A macOS menu bar app that shows the live state of every agent in your
[Herdr](https://github.com/herdrdev/herdr) session. Click an agent to jump to its pane.

An unofficial companion app, not affiliated with the Herdr project.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
  <img alt="The Herdr Menu Bar dropdown listing agents grouped by workspace" src="docs/screenshot-light.png" width="378">
</picture>

## Features

- **Menu bar icon** that reflects the most urgent agent state: idle, working,
  waiting on you, or finished.
- **Dropdown** listing every agent, grouped by workspace in Herdr's order.
- **Click to jump**: focuses the agent's pane and brings its terminal to the
  front.
- **Notifications** when an agent needs you, with optional finish
  notifications, sound, and launch at login.

## Requirements

- macOS 14 or later
- Swift 5.10+ (Xcode or the Command Line Tools)
- A running Herdr session

## Install

```bash
./build.sh
cp -R "build/Herdr Menu Bar.app" /Applications/
open "/Applications/Herdr Menu Bar.app"
```

Run it from `/Applications`; macOS handles notifications differently for apps
elsewhere.

For clickable notifications on a local (unsigned) build, install
`terminal-notifier`:

```bash
brew install terminal-notifier
```

## Terminal Integration (Auto-Start & Auto-Stop)

If you don't want the app running continuously in the background, you can integrate it directly with the `herdr` CLI:
- **`herdr`**: Starts Herdr Menu Bar in the background if it's not already running.
- **`herdr server stop`**: Shuts down the Herdr server and closes Herdr Menu Bar automatically.
- **Quit on server stop**: Inside the app's Settings (⚙️), you can also enable **Quit when Herdr stops** so the menu bar automatically closes whenever an active Herdr session ends.

### Option 1: From the Menu Bar App
Open Settings (⚙️) in the menu bar dropdown and click **Add to ~/.zshrc** (or click **Copy shell wrapper**).

### Option 2: Automatic CLI Setup
Run the setup command using the installed app or repository script:

```bash
"/Applications/Herdr Menu Bar.app/Contents/MacOS/HerdrMenuBar" --install
# or from this repository:
./scripts/setup-alias.sh
```

### Option 3: Manual Shell Integration
Add this shell function to your `~/.zshrc` (or `~/.bashrc`):

```bash
herdr() {
    if [[ "$1" == "server" && "$2" == "stop" ]]; then
        command herdr "$@"
        osascript -e 'quit app id "io.github.aditya24sharma.herdr-menubar"' 2>/dev/null || true
    else
        open -b io.github.aditya24sharma.herdr-menubar --background 2>/dev/null || true
        command herdr "$@"
    fi
}
```

Then reload your shell:

```bash
source ~/.zshrc
```

## Debugging

```bash
open --env HERDR_MENUBAR_DEBUG=1 "/Applications/Herdr Menu Bar.app"
tail -f ~/Library/Logs/HerdrMenuBar.log
```
