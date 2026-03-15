# SimpleUI for KOReader

A clean, distraction-free UI plugin for KOReader that transforms your reading experience. SimpleUI adds a **dedicated Desktop home screen**, a customisable bottom navigation bar, and a top status bar, giving you instant access to your library, history, collections, and reading stats without navigating through nested menus.

---

## Features

### Home Screen
The centrepiece of SimpleUI. A home screen that gives you everything at a glance:

- **Clock & Date** — a large, readable clock with full date display, always visible on your home screen
- **Currently Reading** — shows your active book with cover art, title, author, reading progress bar, percentage read, and estimated time left
- **Recent Books** — a row of up to 5 recent books with cover thumbnails and progress indicators; tap any to resume reading
- **Collections** — your KOReader collections displayed as tappable cards, right on the home screen
- **Reading Goals** — visual progress tracker for your daily, weekly or monthly reading goals
- **Reading Stats** — compact stat cards showing your reading activity at a glance
- **Quick Actions** — up to 3 customisable rows of shortcut buttons (Library, History, Wi-Fi toggle, Brightness, Stats, and more)
- **Quote of the Day** — optional literary quote header, randomly picked from a curated list of 100+ quotes
- **Custom Header** — choose between clock, clock + date, a custom text label, or the Quote of the Day as your Desktop header
- **Module ordering** — rearrange Desktop modules in any order to match your workflow
- **Start with Desktop** — set the Desktop as the first screen KOReader opens, so your home screen greets you every time you pick up your device

### Bottom Navigation Bar
A persistent tab bar at the bottom of the screen for one-tap navigation:

- Up to **5 fully customisable tabs**: Library, History, Collections, Favorites, Continue Reading, Desktop, Wi-Fi Toggle, Brightness, Stats, and custom folder/collection shortcuts
- **3 display modes**: icons only, text only, or icons + text
- **Hold anywhere on the bar** to instantly open the navigation settings

### Top Status Bar
A slim status bar always visible at the top of the screen:

- Displays **clock, battery level, Wi-Fi status, frontlight brightness, disk usage, and RAM** — all configurable
- Each item can be placed on the **left or right** side independently

### Quick Actions
Shortcut buttons configurable both in the Desktop and in the bottom bar:

- Assign any tab to a **custom folder**, **collection**, or **KOReader plugin action**
- Quick **Wi-Fi toggle** and **frontlight control** directly from the bar
- **Power menu** (Sleep, Restart, Shutdown) accessible as a tab

### Settings
All features are accessible via **Menu → Tools → SimpleUI**

---

## Installation

1. Download this repository as a ZIP — click **Code → Download ZIP**
2. Extract the folder and confirm it is named `simpleui.koplugin`
3. Copy the folder to the `plugins/` directory on your KOReader device
4. Restart KOReader
5. Go to **Menu → Tools → SimpleUI** to enable and configure the plugin

> **Tip:** After enabling the plugin, tap the **Desktop** tab in the bottom bar to open your new home screen.

> **Tip:** To make the Desktop your default start screen, go to **Menu → Tools → SimpleUI → Desktop → Start with Desktop**. From then on, KOReader opens directly to your home screen every time you turn on your device.

---

## 🔧 Customising Quotes

To add, remove or edit the Quote of the Day pool, open `quotes.lua` inside the plugin folder. Each entry follows this format:

```lua
{ q = "Quote text.", a = "Author Name", b = "Book Title (optional)" }
```

Changes take effect the next time the Desktop is opened.

---

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to get started.

To report a bug, open an **Issue** and include your KOReader version and device model.

---

## 📄 License

MIT — see [LICENSE](LICENSE) for details.
