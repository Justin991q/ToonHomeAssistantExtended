//
// Home-Assistant Extended for Toon - shows and switches entities of your own Home Assistant.
//
// - Setup on the Toon (address + long-lived access token) or in the web editor
// - Choose entities, rename them, mark favourites; grouped per Home Assistant area
// - Web editor: http://<toon-ip>/homeassistant.html (served from /qmf/www), it talks to this app over
//   a WebSocket on port 8137 (opened in /etc/default/iptables.conf; on a real Toon: TSC's "Flush firewall rules" or a reboot)
//
// Home Assistant's REST API is used: /api/ (check), /api/template (entity list with areas, the states
// of the chosen entities in one small request) and /api/services/<domain>/<service> (switching).
//
// Qt 5.11 on the Toon: ES5 JavaScript only (no let/const, arrow functions or template strings).
//

import QtQuick 2.1
import qb.components 1.0
import qb.base 1.0
import FileIO 1.0
import QtWebSockets 1.1

App {
	id: homeassistantApp

	property bool debugOutput: false

	property url tileUrl: "HomeassistantTile.qml"
	property url thumbnailIcon: "drawables/ha-logo.svg"
	property url logoUrl: "drawables/ha-logo.svg"
	// the title bar shows its icon through the Toon's image provider, which wants the device path
	property url titleIconUrl: "file:///qmf/qml/apps/homeassistantExtended/drawables/ha-logo.svg"
	property url trayUrl: "HomeassistantTray.qml"
	property SystrayIcon homeassistantTray
	property HomeassistantAlarmScreen homeassistantAlarmScreen
	property url alarmScreenUrl: "HomeassistantAlarmScreen.qml"
	property HomeassistantLightScreen homeassistantLightScreen
	property url lightScreenUrl: "HomeassistantLightScreen.qml"

	property HomeassistantScreen homeassistantScreen
	property url screenUrl: "HomeassistantScreen.qml"
	property HomeassistantSetupScreen homeassistantSetupScreen
	property url setupScreenUrl: "HomeassistantSetupScreen.qml"
	property HomeassistantEntitiesScreen homeassistantEntitiesScreen
	property url entitiesScreenUrl: "HomeassistantEntitiesScreen.qml"

	property string appName: "Home-Assistant Extended"
	property string appVersion: ""

	// ---- settings (homeassistantExtended.userSettings.json) ----
	property string haUrl: ""                 // e.g. http://192.168.1.10:8123
	property string haToken: ""               // long-lived access token
	property int pollSeconds: 10
	property variant entities: []             // the chosen ones, in your own order: [{id, name, fav}]
	property string sortMode: "area"          // screen: "area", "name" or "own"
	property bool favouritesOnly: false       // screen: only the favourites
	property bool enableSystray: false        // the Home Assistant icon in the systray (top of the screen)
	property variant areaOrder: []            // your order of the areas (web editor); areas not in it follow in HA's order

	// ---- live data ----
	property variant haStates: ({})             // entity id -> {state, unit, name (HA's), area}
	property variant allEntities: []          // everything HA has: [{id, name, area, state, domain}] (entity chooser, web editor)
	property variant areaNames: []            // HA's areas, in HA's order
	property bool connected: false
	property string lastError: ""
	property string lastUpdate: ""
	property bool loadingAll: false

	// ---- web editor ----
	property int webPort: 8137                // "webPort" in the settings file for another one
	property string webPage: "homeassistant.html"
	property string toonAddress: ""           // for showing the web editor's address
	property var wsClients: []                 // var, not variant: keeps the sockets referenced for the garbage collector

	signal statesUpdated()
	signal selectionChanged()
	signal allEntitiesLoaded()
	signal actionResult(string entityId, bool ok, string message)   // a tap's command came back: for the card's feedback

	FileIO { id: settingsFile; source: "file:///mnt/data/tsc/homeassistantExtended.userSettings.json" }
	FileIO { id: versionFile; source: "file:///qmf/qml/apps/homeassistantExtended/version.txt" }
	FileIO { id: pageSource; source: "file:///qmf/qml/apps/homeassistantExtended/webeditor.html" }
	FileIO { id: pageTarget; source: "file:///qmf/www/" + webPage }
	FileIO { id: iptablesFile; source: "file:///etc/default/iptables.conf" }
	FileIO { id: tcpFile; source: "file:///proc/net/tcp" }

	function init() {
		registry.registerWidget("tile", tileUrl, this, null, {thumbLabel: qsTr("Home-Assistant"), thumbIcon: thumbnailIcon, thumbCategory: "general", thumbWeight: 30, baseTileWeight: 10, thumbIconVAlignment: "center"});
		registry.registerWidget("screen", screenUrl, this, "homeassistantScreen");
		registry.registerWidget("screen", setupScreenUrl, this, "homeassistantSetupScreen");
		registry.registerWidget("screen", entitiesScreenUrl, this, "homeassistantEntitiesScreen");
		registry.registerWidget("screen", alarmScreenUrl, this, "homeassistantAlarmScreen");
		registry.registerWidget("screen", lightScreenUrl, this, "homeassistantLightScreen");
		registry.registerWidget("systrayIcon", trayUrl, this, "homeassistantTray");
	}

	Component.onCompleted: {
		loadSettings();
		wsServer.listen = true;
		try { appVersion = versionFile.read().trim(); } catch (e) {}
		publishWebPage();
		openFirewallPort();
		toonAddress = findToonAddress();
		if (isConfigured()) {
			pollStates();
			loadAllEntities();
		}
	}

	// ======================================================================
	// settings
	// ======================================================================

	function loadSettings() {
		try {
			var s = JSON.parse(settingsFile.read());
			haUrl = s.url || "";
			haToken = s.token || "";
			if (s.pollSeconds >= 2) pollSeconds = s.pollSeconds;
			entities = cleanEntities(s.entities || []);
			sortMode = s.sortMode || "area";
			favouritesOnly = s.favouritesOnly === true;
			enableSystray = s.enableSystray === true;
			areaOrder = s.areaOrder || [];
			if (s.webPort > 0) webPort = s.webPort;
		} catch (e) {
			// first start: nothing saved yet
		}
	}

	function saveSettings() {
		settingsFile.write(JSON.stringify({
			url: haUrl,
			token: haToken,
			pollSeconds: pollSeconds,
			entities: entities,
			sortMode: sortMode,
			favouritesOnly: favouritesOnly,
			enableSystray: enableSystray,
			areaOrder: areaOrder,
			webPort: webPort
		}, null, 1));
	}

	function cleanEntities(list) {
		var out = [];
		var seen = {};
		for (var i = 0; i < list.length; i++) {
			var e = list[i];
			if (!e || !e.id || seen[e.id]) continue;
			seen[e.id] = true;
			out.push({id: String(e.id), name: e.name ? String(e.name) : "", fav: e.fav === true});
		}
		return out;
	}

	function isConfigured() {
		return haUrl !== "" && haToken !== "";
	}

	function cleanUrl(url) {
		url = (url || "").trim();
		if (url === "") return "";
		if (url.indexOf("://") < 0) url = "http://" + url;
		while (url.charAt(url.length - 1) === "/") url = url.substring(0, url.length - 1);
		if (/^https?:\/\/[^\/:]+$/.test(url)) url += ":8123";    // no port: HA's default
		return url;
	}

	function setConnection(url, token) {
		haUrl = cleanUrl(url);
		if (token !== undefined && token !== null && token !== "") haToken = token.trim();
		saveSettings();
		connected = false;
		lastError = "";
		haStates = {};
		if (isConfigured()) {
			pollStates();
			loadAllEntities();
		}
		broadcastState();
	}

	// ======================================================================
	// the chosen entities
	// ======================================================================

	function indexOf(id) {
		for (var i = 0; i < entities.length; i++) if (entities[i].id === id) return i;
		return -1;
	}

	function isSelected(id) { return indexOf(id) >= 0; }

	function setEntities(list) {
		entities = cleanEntities(list);
		saveSettings();
		selectionChanged();
		pollStates();
		broadcastState();
	}

	function toggleSelected(id) {
		var list = entities.slice(0);
		var i = indexOf(id);
		if (i >= 0) list.splice(i, 1); else list.push({id: id, name: "", fav: false});
		setEntities(list);
	}

	function toggleFavourite(id) {
		var list = entities.slice(0);
		var i = indexOf(id);
		if (i < 0) return;
		list[i] = {id: list[i].id, name: list[i].name, fav: !list[i].fav};
		setEntities(list);
	}

	function rename(id, name) {
		var list = entities.slice(0);
		var i = indexOf(id);
		if (i < 0) return;
		list[i] = {id: list[i].id, name: (name || "").trim(), fav: list[i].fav};
		setEntities(list);
	}

	function setSortMode(mode) { sortMode = mode; saveSettings(); selectionChanged(); }
	function setFavouritesOnly(on) { favouritesOnly = on; saveSettings(); selectionChanged(); }
	function setSystray(on) { enableSystray = on; saveSettings(); broadcastState(); }

	// the name to show: your own, else HA's friendly name, else the entity id
	function displayName(id) {
		var i = indexOf(id);
		if (i >= 0 && entities[i].name) return entities[i].name;
		var s = haStates[id];
		if (s && s.name) return s.name;
		for (var j = 0; j < allEntities.length; j++) if (allEntities[j].id === id && allEntities[j].name) return allEntities[j].name;
		return id;
	}

	function areaOf(id) {
		var s = haStates[id];
		if (s && s.area) return s.area;
		for (var j = 0; j < allEntities.length; j++) if (allEntities[j].id === id) return allEntities[j].area || "";
		return "";
	}

	// the chosen entities as the screen shows them: [{id, name, area, fav, section}] sorted by sortMode
	function sortedEntities(onlyFavs, mode) {
		var out = [];
		for (var i = 0; i < entities.length; i++) {
			var e = entities[i];
			if (onlyFavs && !e.fav) continue;
			var area = areaOf(e.id);
			out.push({id: e.id, name: displayName(e.id), area: area, fav: e.fav, order: i,
				section: mode === "area" ? (area || "Geen ruimte") : (mode === "name" ? displayName(e.id).charAt(0).toUpperCase() : "")});
		}
		if (mode === "area") {
			out.sort(function(a, b) {
				var ra = areaRank(a.area), rb = areaRank(b.area);
				if (ra !== rb) return ra - rb;
				return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0);
			});
		} else if (mode === "name") {
			out.sort(function(a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0); });
		}
		return out;
	}

	// HA's area order, entities without an area last
	// your order first (areaOrder), then HA's order, then areas HA's list does not have; no area last
	function areaRank(area) {
		if (!area) return 100000;
		var own = areaOrder.indexOf(area);
		if (own >= 0) return own;
		var i = areaNames.indexOf(area);
		return i >= 0 ? 1000 + i : 50000 + area.toLowerCase().charCodeAt(0);
	}

	// ======================================================================
	// the main screen: tabs per area, icons
	// ======================================================================

	property variant currentTab: null         // the tab the main screen showed last (not saved); null = none yet ("" is Overig)

	// [{key, label}]: Favorieten (when there are any), HA's areas that have chosen entities, then Overig
	function tabList() {
		var out = [];
		var hasFav = false, hasNoArea = false, used = {};
		for (var i = 0; i < entities.length; i++) {
			if (entities[i].fav) hasFav = true;
			var a = areaOf(entities[i].id);
			if (a) used[a] = true; else hasNoArea = true;
		}
		if (hasFav) out.push({key: "*fav", label: "Favorieten"});
		var areas = [];
		for (var k in used) areas.push(k);
		areas.sort(function(a, b) { return (areaRank(a) - areaRank(b)) || (a < b ? -1 : (a > b ? 1 : 0)); });
		for (var r = 0; r < areas.length; r++) out.push({key: areas[r], label: areas[r]});
		if (hasNoArea) out.push({key: "", label: "Overig"});
		return out;
	}

	// the entity ids of a tab, in your own order
	function tabEntities(key) {
		var out = [];
		for (var i = 0; i < entities.length; i++) {
			var e = entities[i];
			if (key === "*fav" ? e.fav : areaOf(e.id) === key) out.push(e.id);
		}
		return out;
	}

	// how many lights/switches are on in a tab: shown next to its name
	function tabOnCount(key) {
		var ids = tabEntities(key);
		var n = 0;
		for (var i = 0; i < ids.length; i++) if (actionOf(ids[i]) === "toggle" && isOn(ids[i])) n++;
		return n;
	}

	// the icon for an entity: drawables/icons/<name>.svg (-on.svg when on, -dim.svg dimmed)
	function iconName(id) {
		var d = domainOf(id);
		var unit = haStates[id] ? haStates[id].unit : "";
		var map = {light: "bulb", "switch": "plug", fan: "fan", cover: "blinds", lock: "lock", alarm_control_panel: "shield",
			scene: "play", script: "play", button: "button", input_button: "button", climate: "flame", water_heater: "flame",
			media_player: "speaker", person: "person", device_tracker: "person", binary_sensor: "eye", input_boolean: "toggle",
			automation: "bolt", vacuum: "robot", humidifier: "droplet"};
		if (map[d]) return map[d];
		if (d === "sensor" || d === "input_number" || d === "number") {
			if (unit === "°C" || unit === "°F") return "thermometer";
			if (unit === "%") return "droplet";
			if (unit === "W" || unit === "kW" || unit === "kWh" || unit === "Wh" || unit === "V" || unit === "A") return "bolt";
			return "gauge";
		}
		return "generic";
	}

	function iconUrl(id, dim) {
		return Qt.resolvedUrl("drawables/icons/" + iconName(id) + (dim ? "-dim" : (actionOf(id) === "toggle" && isOn(id) ? "-on" : "")) + ".svg");
	}

	// how many grid cells a card takes: an alarm panel is a double card (state and its buttons)
	function cardSlots(id) { return domainOf(id) === "alarm_control_panel" ? 2 : 1; }

	// a sensor shows its value big: "21,4°"; the rest a word
	function isValueCard(id) {
		var d = domainOf(id);
		if (d !== "sensor" && d !== "input_number" && d !== "number") return false;
		var s = haStates[id];
		return s && /^-?\d+(\.\d+)?$/.test(s.state);
	}

	function friendlyError(err) {
		if (err === "geen verbinding") return "Geen verbinding met Home Assistant";
		if (err === "token ongeldig (401)") return "Home Assistant weigert het token";
		return "Dat lukte niet (" + err + ")";
	}

	function favouriteList() {
		var out = [];
		for (var i = 0; i < entities.length; i++) if (entities[i].fav) out.push(entities[i].id);
		if (out.length === 0) for (var j = 0; j < entities.length; j++) out.push(entities[j].id);   // no favourites: the first ones
		return out;
	}

	// ======================================================================
	// Home Assistant REST API
	// ======================================================================

	function request(method, path, body, onDone) {
		var xhr = new XMLHttpRequest();
		xhr.open(method, haUrl + path, true);
		xhr.setRequestHeader("Authorization", "Bearer " + haToken);
		xhr.setRequestHeader("Content-Type", "application/json");
		xhr.onreadystatechange = function() {
			if (xhr.readyState !== 4) return;
			if (xhr.status >= 200 && xhr.status < 300) {
				onDone(xhr.responseText, "");
			} else {
				var err = xhr.status === 0 ? "geen verbinding" : (xhr.status === 401 ? "token ongeldig (401)" : "HTTP " + xhr.status);
				onDone(null, err);
			}
		};
		xhr.send(body ? JSON.stringify(body) : null);
	}

	function template(tpl, onDone) {
		request("POST", "/api/template", {template: tpl}, function(text, err) {
			if (text === null) { onDone(null, err); return; }
			try { onDone(JSON.parse(text), ""); } catch (e) { onDone(null, "onverwacht antwoord"); }
		});
	}

	// test with an address and token that are not saved yet; onDone(ok, message)
	function testConnection(url, token, onDone) {
		var xhr = new XMLHttpRequest();
		xhr.open("GET", cleanUrl(url) + "/api/", true);
		xhr.setRequestHeader("Authorization", "Bearer " + (token || haToken));
		xhr.onreadystatechange = function() {
			if (xhr.readyState !== 4) return;
			if (xhr.status === 200) {
				var msg = "OK";
				try { msg = JSON.parse(xhr.responseText).message || "OK"; } catch (e) {}
				onDone(true, msg);
			} else if (xhr.status === 401) {
				onDone(false, "Bereikbaar, maar het token klopt niet (401)");
			} else if (xhr.status === 0) {
				onDone(false, "Geen verbinding met " + cleanUrl(url));
			} else {
				onDone(false, "Fout: HTTP " + xhr.status);
			}
		};
		xhr.send();
	}

	function jsonString(s) { return JSON.stringify(String(s)); }

	// the states of the chosen entities, with HA's name and area, in one request
	function pollStates() {
		if (!isConfigured() || entities.length === 0) return;
		var ids = [];
		for (var i = 0; i < entities.length; i++) ids.push(jsonString(entities[i].id));
		var tpl = "[{%- for i in [" + ids.join(",") + "] -%}"
			+ "{{ [i, states(i), state_attr(i, 'unit_of_measurement'), state_attr(i, 'friendly_name'), area_name(i), state_attr(i, 'code_format'), state_attr(i, 'code_arm_required'), state_attr(i, 'supported_features'), "
			+ "([state_attr(i, 'brightness'), state_attr(i, 'supported_color_modes'), state_attr(i, 'hs_color'), state_attr(i, 'color_temp_kelvin'), "
			+ "state_attr(i, 'min_color_temp_kelvin'), state_attr(i, 'max_color_temp_kelvin'), state_attr(i, 'color_mode')] if i.startswith('light.') else none)] | tojson }}"
			+ "{%- if not loop.last %},{% endif -%}{%- endfor -%}]";
		template(tpl, function(list, err) {
			if (list === null) {
				connected = false;
				lastError = err;
				statesUpdated();
				return;
			}
			var map = {};
			for (var j = 0; j < list.length; j++) {
				var r = list[j];
				map[r[0]] = {state: r[1], unit: r[2] || "", name: r[3] || "", area: r[4] || "",
					codeFormat: r[5] || "", codeArmRequired: r[6] !== false, features: r[7] || 0, light: lightInfo(r[8])};
			}
			haStates = map;
			connected = true;
			lastError = "";
			var now = new Date();
			lastUpdate = ("0" + now.getHours()).slice(-2) + ":" + ("0" + now.getMinutes()).slice(-2) + ":" + ("0" + now.getSeconds()).slice(-2);
			statesUpdated();
		});
	}

	// every entity HA has, with its area, plus HA's list of areas (for choosing)
	function loadAllEntities() {
		if (!isConfigured()) return;
		loadingAll = true;
		var tpl = "{\"areas\": {{ areas() | map('area_name') | list | tojson }}, \"entities\": ["
			+ "{%- for s in states -%}{{ [s.entity_id, s.name, area_name(s.entity_id), s.state] | tojson }}"
			+ "{%- if not loop.last %},{% endif -%}{%- endfor -%}]}";
		template(tpl, function(res, err) {
			loadingAll = false;
			if (res === null) {
				lastError = err;
				allEntitiesLoaded();
				broadcastState();
				return;
			}
			var list = [];
			for (var i = 0; i < res.entities.length; i++) {
				var r = res.entities[i];
				list.push({id: r[0], name: r[1] || "", area: r[2] || "", state: r[3], domain: r[0].split(".")[0]});
			}
			list.sort(function(a, b) { return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0); });
			allEntities = list;
			areaNames = res.areas || [];
			connected = true;
			allEntitiesLoaded();
			selectionChanged();
			broadcastState();
		});
	}

	// ======================================================================
	// switching
	// ======================================================================

	function domainOf(id) { return id.split(".")[0]; }

	// what a tap on the entity does: "toggle", "press", "run" or "" (read only)
	function actionOf(id) {
		var d = domainOf(id);
		if (["light", "switch", "input_boolean", "fan", "automation", "humidifier", "siren", "cover", "lock", "media_player", "climate", "vacuum", "group"].indexOf(d) >= 0) return "toggle";
		if (d === "button" || d === "input_button") return "press";
		if (d === "script" || d === "scene") return "run";
		if (d === "alarm_control_panel") return "alarm";
		return "";
	}

	function isOn(id) {
		var s = haStates[id] ? haStates[id].state : "";
		return ["on", "open", "opening", "unlocked", "playing", "heat", "cool", "heat_cool", "auto", "cleaning", "home"].indexOf(s) >= 0;
	}

	function activate(id) {
		var d = domainOf(id);
		if (d === "alarm_control_panel") { openAlarm(id); return; }
		var on = isOn(id);
		var service = "";
		if (d === "button" || d === "input_button") service = "press";
		else if (d === "script" || d === "scene") service = "turn_on";
		else if (d === "lock") service = on ? "lock" : "unlock";
		else if (d === "cover") service = on ? "close_cover" : "open_cover";
		else if (d === "climate" || d === "media_player" || d === "vacuum") { service = on ? "turn_off" : "turn_on"; }
		else if (actionOf(id) === "toggle") service = "toggle";
		if (!service) return;
		if (d === "vacuum" && service === "turn_on") service = "start";
		if (d === "vacuum" && service === "turn_off") service = "return_to_base";

		// show the new state at once, HA's answer follows with the next poll
		if (actionOf(id) === "toggle" && haStates[id]) {
			var map = haStates;
			var guess = {lock: on ? "locked" : "unlocked", cover: on ? "closing" : "opening"}[d] || (on ? "off" : "on");
			map[id] = copyState(map[id], {state: guess});
			haStates = map;
			statesUpdated();
		}
		request("POST", "/api/services/" + d + "/" + service, {entity_id: id}, function(text, err) {
			if (text === null) lastError = "Schakelen mislukt: " + err;
			actionResult(id, text !== null, text !== null ? "" : friendlyError(err));
			refreshSoon.restart();
		});
	}

	function stateText(id) {
		var s = haStates[id];
		if (!s) return connected ? "?" : "";
		var v = s.state;
		if (v === "unavailable") return "n.b.";
		if (v === "unknown") return "-";
		var d = domainOf(id);
		if (d === "script" || d === "scene" || d === "button" || d === "input_button") return "";
		if (d === "alarm_control_panel") return alarmStateText(v);
		var words = {on: "Aan", off: "Uit", open: "Open", closed: "Dicht", opening: "Gaat open", closing: "Gaat dicht",
			locked: "Op slot", unlocked: "Open", home: "Thuis", not_home: "Weg", playing: "Speelt", paused: "Pauze",
			idle: "Inactief", heat: "Verwarmen", cool: "Koelen", auto: "Auto", detected: "Gedetecteerd", clear: "Vrij"};
		if (d === "light" && v === "on" && s.light && s.light.dimmable && s.light.brightness > 0) return "Aan " + lightPercent(id) + "%";
		if (words[v] && s.unit === "") return words[v];
		var n = parseFloat(v);
		if (/^-?\d+(\.\d+)?$/.test(v)) {
			var digits = Math.abs(n) >= 100 ? 0 : (Math.abs(n) >= 10 ? 1 : 2);
			if (n === Math.round(n)) digits = 0;
			return i18n.number(n, digits, i18n.omit_trail_zeros) + (s.unit ? " " + s.unit : "");
		}
		return v + (s.unit ? " " + s.unit : "");
	}

	// ======================================================================
	// alarm panels (alarm_control_panel)
	// ======================================================================

	function alarmStateText(v) {
		return {disarmed: "Uitgeschakeld", armed_home: "Aan (thuis)", armed_away: "Aan (afwezig)", armed_night: "Aan (nacht)",
			armed_vacation: "Aan (vakantie)", armed_custom_bypass: "Aan (aangepast)", pending: "Vertraging…", arming: "Inschakelen…",
			disarming: "Uitschakelen…", triggered: "ALARM!"}[v] || v;
	}

	function isArmed(id) {
		var s = haStates[id] ? haStates[id].state : "";
		return s.indexOf("armed_") === 0 || s === "triggered" || s === "pending" || s === "arming";
	}

	// the modes the panel offers (HA's supported_features): [{mode, label}], always "disarm" last
	function alarmModes(id) {
		var f = haStates[id] ? haStates[id].features : 0;
		var all = [{bit: 2, mode: "arm_away", label: "Afwezig"}, {bit: 1, mode: "arm_home", label: "Thuis"},
			{bit: 4, mode: "arm_night", label: "Nacht"}, {bit: 32, mode: "arm_vacation", label: "Vakantie"},
			{bit: 16, mode: "arm_custom_bypass", label: "Aangepast"}];
		var out = [];
		for (var i = 0; i < all.length; i++) if (f & all[i].bit) out.push({mode: all[i].mode, label: all[i].label});
		if (out.length === 0) out.push({mode: "arm_away", label: "Afwezig"}, {mode: "arm_home", label: "Thuis"});   // features unknown
		out.push({mode: "disarm", label: "Uitschakelen"});
		return out;
	}

	// "" = no code, "number" = keypad, "text" = keyboard
	function alarmCodeFormat(id) { return haStates[id] ? haStates[id].codeFormat : ""; }

	function alarmNeedsCode(id, mode) {
		var s = haStates[id];
		if (!s || !s.codeFormat) return false;
		return mode === "disarm" || s.codeArmRequired;
	}

	// mode: arm_away, arm_home, arm_night, arm_vacation, arm_custom_bypass or disarm; onDone(ok, message)
	function alarmCommand(id, mode, code, onDone) {
		var body = {entity_id: id};
		if (code) body.code = code;
		request("POST", "/api/services/alarm_control_panel/alarm_" + mode, body, function(text, err) {
			if (text === null) {
				lastError = "Alarm: " + err;
				var msg = err === "HTTP 400" || err === "HTTP 500" ? "Geweigerd (verkeerde code?)" : err;
				if (onDone) onDone(false, msg);
				actionResult(id, false, msg);
			} else {
				if (onDone) onDone(true, "");
				actionResult(id, true, "");
			}
			refreshSoon.restart();
		});
	}

	// ======================================================================
	// lights: brightness, colour, colour temperature
	// ======================================================================

	function copyState(s, changes) {
		var out = {};
		for (var k in s) out[k] = s[k];
		for (var c in changes) out[c] = changes[c];
		return out;
	}

	// HA's light attributes -> what the light screen needs; null for other domains
	function lightInfo(a) {
		if (!a) return null;
		var modes = a[1] || [];
		var colorModes = ["hs", "xy", "rgb", "rgbw", "rgbww"];
		var color = false, dimmable = false;
		for (var i = 0; i < modes.length; i++) {
			if (colorModes.indexOf(modes[i]) >= 0) color = true;
			if (modes[i] !== "onoff") dimmable = true;
		}
		return {brightness: a[0] || 0, dimmable: dimmable, color: color, colorTemp: modes.indexOf("color_temp") >= 0,
			hue: a[2] ? a[2][0] : 0, saturation: a[2] ? a[2][1] : 0, kelvin: a[3] || 0,
			minKelvin: a[4] || 2000, maxKelvin: a[5] || 6500, colorMode: a[6] || ""};
	}

	function lightOf(id) { return haStates[id] ? haStates[id].light : null; }

	function lightPercent(id) {
		var l = lightOf(id);
		return l ? Math.max(1, Math.round(l.brightness / 2.55)) : 0;
	}

	// a light change shown at once, before HA answers
	function setLightLocally(id, state, changes) {
		if (!haStates[id] || !haStates[id].light) return;
		var map = haStates;
		map[id] = copyState(map[id], {state: state, light: copyState(map[id].light, changes)});
		haStates = map;
		statesUpdated();
	}

	// percent 1..100; 0 switches off
	function setBrightness(id, percent) {
		percent = Math.round(Math.max(0, Math.min(100, percent)));
		if (percent === 0) {
			setLightLocally(id, "off", {});
			lightService(id, "turn_off", {});
			return;
		}
		setLightLocally(id, "on", {brightness: Math.round(percent * 2.55)});
		lightService(id, "turn_on", {brightness_pct: percent});
	}

	// hue 0..360, saturation 0..100
	function setColor(id, hue, saturation) {
		setLightLocally(id, "on", {hue: hue, saturation: saturation, colorMode: "hs"});
		lightService(id, "turn_on", {hs_color: [Math.round(hue), Math.round(saturation)]});
	}

	function setColorTemp(id, kelvin) {
		kelvin = Math.round(kelvin);
		setLightLocally(id, "on", {kelvin: kelvin, colorMode: "color_temp"});
		lightService(id, "turn_on", {color_temp_kelvin: kelvin});
	}

	function lightService(id, service, data) {
		data.entity_id = id;
		request("POST", "/api/services/light/" + service, data, function(text, err) {
			if (text === null) lastError = "Lamp: " + err;
			actionResult(id, text !== null, text !== null ? "" : friendlyError(err));
			refreshSoon.restart();
		});
	}

	function openLight(id) {
		stage.openFullscreen(lightScreenUrl, {entityId: id});
	}

	// mode: the button pressed on the alarm card when the panel needs a code (the screen asks for it)
	function openAlarm(id, mode) {
		stage.openFullscreen(alarmScreenUrl, {entityId: id, mode: mode || ""});
	}

	Timer {
		id: pollTimer
		interval: pollSeconds * 1000
		repeat: true
		running: isConfigured() && entities.length > 0
		onTriggered: pollStates()
	}

	Timer {
		id: refreshSoon
		interval: 700
		onTriggered: pollStates()
	}

	Timer {
		// the list of all entities changes rarely: every 30 minutes, and when the web editor asks
		interval: 30 * 60 * 1000
		repeat: true
		running: isConfigured()
		onTriggered: loadAllEntities()
	}

	// ======================================================================
	// web editor
	// ======================================================================

	function publishWebPage() {
		try {
			var page = pageSource.read();
			if (!page) return;
			page = page.split("__WS_PORT__").join(String(webPort));
			var old = "";
			try { old = pageTarget.read(); } catch (e) {}
			if (old !== page) pageTarget.write(page);
		} catch (e) {
			console.log("homeassistant: could not publish the web editor: " + e);
		}
	}

	// the Toon's firewall lets only known ports in: add ours (active after "Flush firewall rules" or a reboot)
	function openFirewallPort() {
		try {
			var conf = iptablesFile.read();
			if (!conf || conf.indexOf("--dport " + webPort + " ") >= 0) return;
			var rule = "-A HCB-INPUT -p tcp -m tcp --dport " + webPort + " --tcp-flags SYN,RST,ACK SYN -j ACCEPT\n";
			var at = conf.indexOf("-A HCB-INPUT -p tcp -m tcp --tcp-flags SYN,RST,ACK SYN -j DROP");
			if (at < 0) return;
			iptablesFile.write(conf.substring(0, at) + rule + conf.substring(at));
			console.log("homeassistant: port " + webPort + " added to iptables.conf (active after \"Flush firewall rules\" or a reboot)");
		} catch (e) {}
	}

	// the Toon's own IP address, from a listening socket in /proc/net/tcp
	function findToonAddress() {
		try {
			var lines = tcpFile.read().split("\n");
			for (var i = 1; i < lines.length; i++) {
				var parts = lines[i].trim().split(/\s+/);
				if (parts.length < 4 || parts[3] !== "01") continue;      // established connections know our address
				var hex = parts[1].split(":")[0];
				if (hex.length !== 8) continue;
				var ip = [parseInt(hex.substr(6, 2), 16), parseInt(hex.substr(4, 2), 16), parseInt(hex.substr(2, 2), 16), parseInt(hex.substr(0, 2), 16)];
				if (ip[0] === 127 || ip[0] === 0) continue;
				return ip.join(".");
			}
		} catch (e) {}
		return "";
	}

	function webEditorUrl() {
		if (toonAddress) return "http://" + toonAddress + "/" + webPage;
		return "http://<ip-van-toon>/" + webPage;
	}

	function stateMessage() {
		return JSON.stringify({
			type: "state",
			version: appVersion,
			url: haUrl,
			hasToken: haToken !== "",
			connected: connected,
			error: lastError,
			loading: loadingAll,
			sortMode: sortMode,
			systray: enableSystray,
			areaOrder: areaOrder,
			entities: entities,
			areas: areaNames,
			all: allEntities
		});
	}

	function sendTo(socket, msg) {
		try {
			if (socket && socket.status === WebSocket.Open) { socket.sendTextMessage(msg); return true; }
		} catch (e) {}
		return false;
	}

	function broadcastState() {
		var msg = stateMessage();
		for (var i = 0; i < wsClients.length; i++) sendTo(wsClients[i], msg);
	}

	function dropClient(socket) {
		var list = [];
		for (var i = 0; i < wsClients.length; i++) if (wsClients[i] !== socket) list.push(wsClients[i]);
		wsClients = list;
	}

	function handleMessage(socket, text) {
		var m;
		try { m = JSON.parse(text); } catch (e) { return; }
		if (m.type === "get") {
			sendTo(socket, stateMessage());
		} else if (m.type === "refresh") {
			loadAllEntities();
			sendTo(socket, stateMessage());
		} else if (m.type === "test") {
			testConnection(m.url || haUrl, m.token || haToken, function(ok, msg) {
				sendTo(socket, JSON.stringify({type: "test", ok: ok, message: msg}));
			});
		} else if (m.type === "connection") {
			setConnection(m.url, m.token);
		} else if (m.type === "save") {
			if (m.sortMode) sortMode = m.sortMode;
			if (m.systray !== undefined) enableSystray = m.systray === true;
			if (m.areaOrder) areaOrder = m.areaOrder;
			setEntities(m.entities || []);
			sendTo(socket, JSON.stringify({type: "saved"}));
		}
	}

	WebSocketServer {
		id: wsServer
		host: "0.0.0.0"
		port: webPort
		listen: false             // switched on after the settings are read (they may give another port)
		accept: true
		onClientConnected: {
			var socket = webSocket;
			var list = wsClients.slice(0);
			list.push(socket);
			wsClients = list;
			socket.onTextMessageReceived.connect(function(message) { handleMessage(socket, message); });
			socket.onStatusChanged.connect(function() {
				if (socket.status === WebSocket.Closed || socket.status === WebSocket.Error) dropClient(socket);
			});
		}
		onErrorStringChanged: console.log("homeassistant: web editor server: " + errorString)
	}
}
