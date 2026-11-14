# Home-Assistant Extended for Toon

Shows and controls entities from your own Home Assistant on a (rooted) Toon. You choose the entities and
can rename them. You can mark favourites for the tile, and the full list is grouped by Home Assistant area.
A web editor makes setup easy when there are many entities.

## What you get

- **A tile** with your favourites (no favourites yet: the first chosen entities), each with its state.
  Tap a light or switch row to toggle it, a scene or script row to run it, an alarm row to open the
  alarm panel. Tapping anywhere else opens the full list.
- **A scrollable list** of all chosen entities. You can sort it **per area** (Home Assistant's own areas,
  in Home Assistant's order, with a heading per area), **by name** or in **your own order**, and show
  **only favourites**. Tap the star to make an entity a favourite. Scroll by flicking or with the arrow
  buttons. Each row has an on/off switch, *Start* (scene/script), *Druk* (button) or *Bedien* (alarm).
- **Lights**: tap the row of a dimmable lamp (marked with an arrow) to open its screen with the
  on/off switch, a **brightness** slider with -/+ (10%), and when the lamp supports them a **colour** bar with
  colour buttons (white, red, orange, yellow, green, cyan, blue, purple, pink) and a **colour temperature**
  slider (warm to cool, within the lamp's own range). The command goes out when you let go of a slider.
  The list shows the brightness: "Aan 60%". A lamp that only switches on and off has no screen.
- **Alarm panels** (`alarm_control_panel`): a screen with the state, a button for each arm mode the
  panel supports (Afwezig, Thuis, Nacht, Vakantie, Aangepast) and Uitschakelen.
  - without a code: the buttons work right away;
  - with a numeric code: a keypad, type the code and then press the mode;
  - with a text code: *Code invoeren* opens the keyboard.
  The code is only sent to Home Assistant and is never saved. If Home Assistant refuses a wrong code,
  you get the message "Geweigerd (verkeerde code?)". Arming only asks for a code when the panel
  needs one for arming (`code_arm_required`).
- **The Home Assistant icon in the systray** (optional, see *Instellingen* or the web editor). A tap
  opens the list. A red dot appears on it when one of your alarm panels goes off.
- **A setup screen on the Toon**: address, token, connection test, the systray option, and an entity
  chooser with search, area and type filters, plus rename (pencil) and favourite (star).
- **A web editor** at `http://<toon-ip>/homeassistant.html`.

## Setup

1. In Home Assistant, open your profile, then **Security**, then **Long-lived access tokens**, and create
   a token.
2. On the Toon, add the *Home-Assistant Extended* tile, tap it, then **Instellingen**. Enter the address (e.g.
   `192.168.1.10:8123`; `http://` and port 8123 are added when you leave them out). Typing the token
   on the Toon works, but it is long: the web editor is easier for that.
3. Choose entities on the Toon (**Entiteiten kiezen**) or in the web editor.

Use the IP address of Home Assistant: the Toon usually can't resolve `homeassistant.local`.

## Web editor

The page is published to the Toon's own web server (`/qmf/www/homeassistant.html`). It talks to the
app over a WebSocket on **port 8137**. The app adds that port to `/etc/default/iptables.conf`. **On a
real Toon the firewall doesn't pick up the port by itself.** If the web editor can't connect to the Toon,
press **Flush firewall rules** (Instellingen > TSC); a reboot isn't needed. A reboot works too.

In the web editor you can:
- set the address and token (the token is write-only: the page never gets it back from the Toon);
- tick entities, or tick all entities of an area at once; filter by search, area and type;
- rename entities, mark favourites, set your own order (▲▼, or sort by area, by name or favourites first);
- turn the systray icon on or off.

Press **Opslaan op Toon** to save. The Toon updates right away.

If port 8137 is already in use, add `"webPort": 8140` (or any free port) to the settings file and restart
the GUI. The app writes the port into the published page.

**Security:** anyone on your network who can reach the Toon can open the web editor and change the
selection or the connection. They can't read the token. This is the same trust level as the Toon's other
local pages.

## How it talks to Home Assistant

Only the REST API, with the token as a `Bearer` header:
- `GET /api/` for the connection test;
- `POST /api/template` to get all entities with their area and Home Assistant's area list (when choosing,
  and every 30 minutes). It also fetches the states of the chosen entities in **one small request**
  every 10 seconds (`pollSeconds` in the settings), with the alarm attributes `code_format`,
  `code_arm_required` and `supported_features`, and for lights `brightness`, `supported_color_modes`,
  `hs_color`, `color_temp_kelvin` and its range;
- `POST /api/services/<domain>/<service>` to switch (e.g. `light/toggle`, `light/turn_on` with
  `brightness_pct`, `hs_color` or `color_temp_kelvin`, `scene/turn_on`,
  `alarm_control_panel/alarm_arm_away` with `code`).

## Files

| File | What |
|---|---|
| `HomeassistantExtendedApp.qml` | settings, Home Assistant client, polling, alarm commands, web editor server |
| `HomeassistantTile.qml` | the tile with favourites |
| `HomeassistantScreen.qml` | the scrollable list (area / name / own order, favourites) |
| `HomeassistantSetupScreen.qml` | address, token, test, systray option |
| `HomeassistantEntitiesScreen.qml` | the entity chooser on the Toon |
| `HomeassistantAlarmScreen.qml` | an alarm panel with keypad |
| `HomeassistantLightScreen.qml` | a light: brightness, colour, colour temperature |
| `HaSlider.qml` | the touch slider used on the light screen |
| `HomeassistantTray.qml` | the systray icon |
| `webeditor.html` | the web editor (published to `/qmf/www`) |
| `drawables/ha-logo.svg` | the logo |

Settings: `/mnt/data/tsc/homeassistantExtended.userSettings.json` (`url`, `token`, `entities: [{id, name, fav}]`,
`sortMode`, `favouritesOnly`, `enableSystray`, `pollSeconds`, `webPort`).

Written for the Toon's Qt 5.11, so the QML uses only ES5 JavaScript.

## Tests

`python tools\run_tests.py homeassistant` (also with `--size toon1`) runs `tests\test_homeassistant.py`
against a fake Home Assistant: connection test, choosing/renaming/favourites, sorting, switching,
the screens, the tile, the systray option, alarm panels with and without a code, and light brightness,
colour and colour temperature.
