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
	property HomeassistantFanScreen homeassistantFanScreen
	property url fanScreenUrl: "HomeassistantFanScreen.qml"
	property HomeassistantClimateScreen homeassistantClimateScreen
	property url climateScreenUrl: "HomeassistantClimateScreen.qml"
	property HomeassistantMediaScreen homeassistantMediaScreen
	property url mediaScreenUrl: "HomeassistantMediaScreen.qml"
	property HomeassistantCameraScreen homeassistantCameraScreen
	property url cameraScreenUrl: "HomeassistantCameraScreen.qml"
	property HomeassistantPersonScreen homeassistantPersonScreen
	property url personScreenUrl: "HomeassistantPersonScreen.qml"
	property HomeassistantTileSetupScreen homeassistantTileSetupScreen
	property url tileSetupScreenUrl: "HomeassistantTileSetupScreen.qml"
	property HomeassistantEnergySetupScreen homeassistantEnergySetupScreen
	property url energySetupScreenUrl: "HomeassistantEnergySetupScreen.qml"

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
	property variant areaOrder: []            // your order of the areas (web editor); areas not in it follow in HA's order. "" is Overig
	property string defaultTab: "*last"       // the tab the main screen opens on: "*last" (the last one), "*fav", "*energy", an area, "" (Overig)
	property variant tileEntities: []         // what the tile shows (at most 4, in this order); empty: the favourites
	// the Energie tab: its own entities, apart from the cards. Every field is a list (summed: e.g. the
	// two tariffs of a smart meter, or the three phases)
	property variant energy: ({})             // {power, usage, export, solarPower, solar, gas, water}: [entity ids]
	// the person screen's map: {z}, {x}, {y} are filled in. OpenStreetMap's own tile servers and CARTO refuse
	// a client like the Toon (no API key, no own User-Agent); Esri's street map answers
	property string mapTileUrl: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}"

	// ---- live data ----
	property variant haStates: ({})             // entity id -> {state, unit, name (HA's), area}
	property variant allEntities: []          // everything HA has: [{id, name, area, state, domain, unit, deviceClass}] (entity chooser, web editor)
	property var allIndex: ({})                // entity id -> its entry in allEntities (looking up without walking the list)
	property var chosenIndex: ({})             // entity id -> its position in entities
	property double allVersion: 0              // when allEntities was fetched (ms): the web editor keeps its own copy until this changes
	property string allMessage: ""             // the web editor's "entities" message, made once per fetch
	property int allMaxAgeHours: 6             // the cached list is fetched again after this, or when you ask (⟳, Entiteiten kiezen)
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
	FileIO { id: entitiesCache; source: "file:///mnt/data/tsc/homeassistantExtended.entities.json" }
	FileIO { id: versionFile; source: "file:///qmf/qml/apps/homeassistantExtended/version.txt" }
	FileIO { id: pageSource; source: "file:///qmf/qml/apps/homeassistantExtended/webeditor.html" }
	FileIO { id: pageTarget; source: "file:///qmf/www/" + webPage }
	FileIO { id: iptablesFile; source: "file:///etc/default/iptables.conf" }
	FileIO { id: tcpFile; source: "file:///proc/net/tcp" }
	FileIO { id: fibFile; source: "file:///proc/net/fib_trie" }

	function init() {
		registry.registerWidget("tile", tileUrl, this, null, {thumbLabel: qsTr("Home-Assistant"), thumbIcon: thumbnailIcon, thumbCategory: "general", thumbWeight: 30, baseTileWeight: 10, thumbIconVAlignment: "center"});
		registry.registerWidget("screen", screenUrl, this, "homeassistantScreen");
		registry.registerWidget("screen", setupScreenUrl, this, "homeassistantSetupScreen");
		registry.registerWidget("screen", entitiesScreenUrl, this, "homeassistantEntitiesScreen");
		registry.registerWidget("screen", alarmScreenUrl, this, "homeassistantAlarmScreen");
		registry.registerWidget("screen", lightScreenUrl, this, "homeassistantLightScreen");
		registry.registerWidget("screen", climateScreenUrl, this, "homeassistantClimateScreen");
		registry.registerWidget("screen", fanScreenUrl, this, "homeassistantFanScreen");
		registry.registerWidget("screen", mediaScreenUrl, this, "homeassistantMediaScreen");
		registry.registerWidget("screen", cameraScreenUrl, this, "homeassistantCameraScreen");
		registry.registerWidget("screen", personScreenUrl, this, "homeassistantPersonScreen");
		registry.registerWidget("screen", energySetupScreenUrl, this, "homeassistantEnergySetupScreen");
		registry.registerWidget("screen", tileSetupScreenUrl, this, "homeassistantTileSetupScreen");
		registry.registerWidget("systrayIcon", trayUrl, this, "homeassistantTray");
	}

	Component.onCompleted: {
		loadSettings();
		wsServer.listen = true;
		try { appVersion = versionFile.read().trim(); } catch (e) {}
		publishWebPage();
		openFirewallPort();
		toonAddress = findToonAddress();
		var cacheAge = loadEntitiesCache();
		if (isConfigured()) {
			pollStates();
			liveStart();
			if (cacheAge < 0 || cacheAge > allMaxAgeHours * 3600 * 1000) loadAllEntities();
			loadEnergyHistory();
		}
	}

	onEntitiesChanged: {
		var map = {};
		for (var i = 0; i < entities.length; i++) map[entities[i].id] = i;
		chosenIndex = map;
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
			if (typeof s.defaultTab === "string") defaultTab = s.defaultTab;
			tileEntities = cleanTile(s.tileEntities || []);
			energy = cleanEnergy(s.energy || {});
			if (s.mapTileUrl) mapTileUrl = s.mapTileUrl;
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
			defaultTab: defaultTab,
			tileEntities: tileEntities,
			energy: energy,
			mapTileUrl: mapTileUrl,
			webPort: webPort
		}, null, 1));
	}

	property variant energyKeys: ["power", "usage", "export", "solarPower", "solar", "gas", "water", "priceUsage", "priceExport", "priceGas", "priceWater"]

	function cleanEnergy(e) {
		var out = {};
		for (var i = 0; i < energyKeys.length; i++) {
			var k = energyKeys[i];
			var list = e[k] || [];
			if (typeof list === "string") list = list ? [list] : [];
			var ids = [];
			for (var j = 0; j < list.length; j++) if (list[j] && ids.indexOf(String(list[j])) < 0) ids.push(String(list[j]));
			out[k] = ids;
		}
		return out;
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
		liveFailed = false;
		liveStop();
		if (isConfigured()) {
			liveStart();
			pollStates();
			loadAllEntities();
		}
		broadcastState();
	}

	// ======================================================================
	// the chosen entities
	// ======================================================================

	function indexOf(id) {
		var i = chosenIndex[id];
		return i === undefined ? -1 : i;
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
		var e = allIndex[id];
		return e && e.name ? e.name : id;
	}

	function areaOf(id) {
		var s = haStates[id];
		if (s && s.area) return s.area;
		var e = allIndex[id];
		return e ? e.area || "" : "";
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
		var own = areaOrder.indexOf(area || "");
		if (own >= 0) return own;                     // also Overig (""), when you moved it
		if (!area) return 100000;
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
		if (energyConfigured()) out.push({key: "*energy", label: "Energie"});
		var areas = [];
		for (var k in used) areas.push(k);
		if (hasNoArea) areas.push("");                // Overig: last, unless you moved it
		areas.sort(function(a, b) { return (areaRank(a) - areaRank(b)) || (a < b ? -1 : (a > b ? 1 : 0)); });
		for (var r = 0; r < areas.length; r++) out.push({key: areas[r], label: areas[r] || "Overig"});
		return out;
	}

	// the choices for the tab to open on: [{key, label}]
	function defaultTabChoices() {
		return [{key: "*last", label: "Laatst gekozen"}].concat(tabList());
	}

	function defaultTabLabel() {
		var list = defaultTabChoices();
		for (var i = 0; i < list.length; i++) if (list[i].key === defaultTab) return list[i].label;
		return defaultTab === "" ? "Overig" : defaultTab;          // not there now (no entities in it): kept anyway
	}

	function setDefaultTab(key) {
		defaultTab = key;
		saveSettings();
		broadcastState();
	}

	// the main screen from the tile or the systray: on your tab, or the last one
	function openMain() {
		if (!isConfigured()) { stage.openFullscreen(setupScreenUrl); return; }
		if (defaultTab !== "*last") currentTab = defaultTab;
		stage.openFullscreen(screenUrl);
	}

	// the entity ids of a tab, in your own order
	function tabEntities(key) {
		var out = [];
		if (key === "*energy") return out;
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
		for (var i = 0; i < ids.length; i++) if ((actionOf(ids[i]) === "toggle" || domainOf(ids[i]) === "fan") && isOn(ids[i])) n++;
		return n;
	}

	// the icon for an entity: drawables/icons/<name>.svg (-on.svg when on, -dim.svg dimmed)
	function iconName(id) {
		var d = domainOf(id);
		var unit = haStates[id] ? haStates[id].unit : "";
		var map = {light: "bulb", "switch": "plug", fan: "fan", cover: "blinds", lock: "lock", alarm_control_panel: "shield",
			scene: "play", script: "play", button: "button", input_button: "button", climate: "thermometer", water_heater: "flame",
			media_player: "speaker", person: "person", device_tracker: "person", binary_sensor: "eye", input_boolean: "toggle",
			automation: "bolt", vacuum: "robot", humidifier: "droplet", camera: "camera", weather: "sun"};
		if (d === "climate" && attr(id, "hvac_action") === "heating") return "flame";
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
		var d = domainOf(id);
		var variant = dim ? "-dim" : (isLit(id) ? "-on" : "");
		if (!dim && (d === "person" || d === "device_tracker") && haStates[id] && haStates[id].state === "home") variant = "-ok";
		return Qt.resolvedUrl("drawables/icons/" + iconName(id) + variant + ".svg");
	}

	// lit up (warm yellow): on, or a thermostat that is heating, a speaker that plays
	function isLit(id) {
		var d = domainOf(id);
		var s = haStates[id] ? haStates[id].state : "";
		if (d === "climate") {
			var a = attr(id, "hvac_action");
			return a ? ["heating", "cooling", "drying", "fan"].indexOf(a) >= 0 : (s !== "off" && s !== "" && s !== "unavailable");
		}
		if (d === "humidifier" || d === "fan") return s === "on";
		if (d === "binary_sensor") return s === "on";          // motion, a door open, …
		if (d === "media_player") return s === "playing";
		return actionOf(id) === "toggle" && isOn(id);
	}

	// a picture of the entity from Home Assistant (a person's photo, album art), else ""
	function pictureUrl(id) {
		var p = attr(id, "entity_picture");
		if (!p) return "";
		return p.indexOf("://") > 0 ? p : haUrl + p;
	}

	// how many grid cells a card takes: an alarm panel, a speaker, a camera and the weather are double cards
	function cardSlots(id) { return ["alarm_control_panel", "media_player", "camera", "weather"].indexOf(domainOf(id)) >= 0 ? 2 : 1; }

	// the QML file of an entity's card
	function cardFile(id) {
		return {alarm_control_panel: "HaAlarmCard.qml", media_player: "HaMediaCard.qml", camera: "HaCameraCard.qml",
			weather: "HaWeatherCard.qml"}[domainOf(id)] || "HaCard.qml";
	}

	// a sensor shows its value big: "21,4°"; a thermostat its room temperature; the rest a word
	function isValueCard(id) {
		var d = domainOf(id);
		if (d === "climate") return typeof attr(id, "current_temperature") === "number";
		if (d === "humidifier") return typeof attr(id, "current_humidity") === "number";
		if (d !== "sensor" && d !== "input_number" && d !== "number") return false;
		var s = haStates[id];
		return s && /^-?\d+(\.\d+)?$/.test(s.state);
	}

	// the big text of a value card
	function valueText(id) {
		var d = domainOf(id);
		if (d === "climate") return degrees(attr(id, "current_temperature"));
		if (d === "humidifier") return Math.round(attr(id, "current_humidity")) + "%";
		return stateText(id);
	}

	// the small line under the name of a value card ("" = none)
	function detailText(id) {
		var d = domainOf(id);
		var s = haStates[id] ? haStates[id].state : "";
		if (d === "climate") {
			if (s === "off") return "Uit";
			var t = climateTargetText(id);
			var a = hvacActionText(attr(id, "hvac_action"));
			return (t ? "Naar " + t : hvacModeText(s)) + (a ? " · " + a : "");
		}
		if (d === "humidifier") {
			if (s !== "on") return "Uit";
			return typeof attr(id, "humidity") === "number" ? "Naar " + Math.round(attr(id, "humidity")) + "%" : "Aan";
		}
		return "";
	}

	function degrees(v) {
		if (typeof v !== "number") return "-";
		return i18n.number(v, 1, i18n.omit_trail_zeros) + "°";
	}

	function friendlyError(err) {
		if (err === "geen verbinding") return "Geen verbinding met Home Assistant";
		if (err === "token ongeldig (401)") return "Home Assistant weigert het token";
		return "Dat lukte niet (" + err + ")";
	}

	property int tileMax: 4

	function cleanTile(list) {
		var out = [];
		for (var i = 0; i < list.length && out.length < tileMax; i++) if (list[i] && out.indexOf(String(list[i])) < 0) out.push(String(list[i]));
		return out;
	}

	function setTileEntities(list) {
		tileEntities = cleanTile(list);
		saveSettings();
		selectionChanged();
		broadcastState();
	}

	// what the tile shows: your choice (those still chosen), else the favourites, else the first chosen ones
	function tileList() {
		var out = [];
		for (var i = 0; i < tileEntities.length; i++) if (isSelected(tileEntities[i])) out.push(tileEntities[i]);
		if (out.length > 0) return out;
		return favouriteList().slice(0, tileMax);
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
	// the attributes fetched per domain (beyond the light and alarm ones): a list of values in this order
	property variant extKeys: ({
		climate: ["current_temperature", "temperature", "target_temp_low", "target_temp_high", "hvac_action", "hvac_modes",
			"min_temp", "max_temp", "target_temp_step", "preset_mode", "preset_modes", "current_humidity"],
		humidifier: ["current_humidity", "humidity", "min_humidity", "max_humidity", "mode", "available_modes", "action"],
		weather: ["temperature", "temperature_unit", "humidity", "wind_speed", "wind_speed_unit", "wind_bearing"],
		media_player: ["media_title", "media_artist", "media_album_name", "app_name", "volume_level", "is_volume_muted",
			"entity_picture", "source", "source_list"],
		camera: ["entity_picture"],
		fan: ["percentage", "percentage_step", "preset_mode", "preset_modes", "oscillating", "direction"],
		person: ["latitude", "longitude", "gps_accuracy", "entity_picture"],
		device_tracker: ["latitude", "longitude", "gps_accuracy", "entity_picture"]
	})

	// an extra attribute of an entity (see extKeys), undefined when not fetched
	function attr(id, key) {
		var s = haStates[id];
		return s && s.attrs ? s.attrs[key] : undefined;
	}

	// the ids polled: the chosen entities and the Energie tab's
	function pollIds() {
		var out = [];
		for (var i = 0; i < entities.length; i++) out.push(entities[i].id);
		var e = energyIds();
		for (var j = 0; j < e.length; j++) if (out.indexOf(e[j]) < 0) out.push(e[j]);
		return out;
	}

	property int pollSeq: 0
	property int pollApplied: 0

	function pollStates() {
		var list = pollIds();
		if (!isConfigured() || list.length === 0) return;
		if (liveConnected) liveSubscribe();            // the selection may have changed: the live updates follow it
		else if (!haSocket.active && !liveReconnect.running) liveStart();
		var ids = [];
		for (var i = 0; i < list.length; i++) ids.push(jsonString(list[i]));
		var tpl = "{%- set ext = " + JSON.stringify(extKeys) + " -%}"
			+ "[{%- for i in [" + ids.join(",") + "] -%}"
			+ "{%- set ns = namespace(v=[]) -%}{%- for k in ext.get(i.split('.')[0], []) -%}{%- set ns.v = ns.v + [state_attr(i, k)] -%}{%- endfor -%}"
			+ "{{ [i, states(i), state_attr(i, 'unit_of_measurement'), state_attr(i, 'friendly_name'), area_name(i), state_attr(i, 'code_format'), state_attr(i, 'code_arm_required'), state_attr(i, 'supported_features'), "
			+ "([state_attr(i, 'brightness'), state_attr(i, 'supported_color_modes'), state_attr(i, 'hs_color'), state_attr(i, 'color_temp_kelvin'), "
			+ "state_attr(i, 'min_color_temp_kelvin'), state_attr(i, 'max_color_temp_kelvin'), state_attr(i, 'color_mode')] if i.startswith('light.') else none), "
			+ "ns.v, (as_timestamp(states[i].last_changed) if i.split('.')[0] in ['person', 'device_tracker'] and states[i] else none)] | tojson }}"
			+ "{%- if not loop.last %},{% endif -%}{%- endfor -%}]";
		var seq = ++pollSeq;
		template(tpl, function(list, err) {
			// an answer to an older poll that comes in after a newer one (another selection by then): not used
			if (seq < pollApplied) return;
			pollApplied = seq;
			if (list === null) {
				if (liveConnected) return;            // live updates carry on
				connected = false;
				lastError = err;
				statesUpdated();
				return;
			}
			// merged into what is there (what live updates brought in since stays), for the ids polled now
			var keep = {}, wanted = pollIds();
			for (var w0 = 0; w0 < wanted.length; w0++) keep[wanted[w0]] = true;
			var map = {};
			for (var id0 in haStates) if (keep[id0]) map[id0] = haStates[id0];
			for (var j = 0; j < list.length; j++) {
				var r = list[j];
				if (!keep[r[0]]) continue;
				var polled = {state: r[1], unit: r[2] || "", name: r[3] || "", area: r[4] || "",
					codeFormat: r[5] || "", codeArmRequired: r[6] !== false, features: r[7] || 0, light: lightInfo(r[8]),
					attrs: extAttrs(r[0], r[9]), changed: r[10] || 0};
				if (liveConnected && liveRaw[r[0]] && map[r[0]]) {
					// live is newer than a poll's answer: only the area (live doesn't send it)
					map[r[0]] = copyState(map[r[0]], {area: polled.area});
					continue;
				}
				map[r[0]] = polled;
				applyHold(map, r[0]);
			}
			var hadWeather = false;
			for (var w in map) if (domainOf(w) === "weather" && !forecasts[w]) hadWeather = true;
			haStates = map;
			connected = true;
			lastError = "";
			cameraTick++;
			var now = new Date();
			if (!toonAddress) toonAddress = findToonAddress();   // the Toon may have had no address or connection at the start
			lastUpdate = ("0" + now.getHours()).slice(-2) + ":" + ("0" + now.getMinutes()).slice(-2) + ":" + ("0" + now.getSeconds()).slice(-2);
			statesUpdated();
			if (hadWeather) loadForecasts();
		});
	}

	// the extra attribute values (a list in extKeys order) -> {key: value}
	function extAttrs(id, values) {
		var keys = extKeys[domainOf(id)];
		if (!keys || !values) return {};
		var out = {};
		for (var i = 0; i < keys.length && i < values.length; i++) out[keys[i]] = values[i];
		return out;
	}

	// ======================================================================
	// live updates: Home Assistant's WebSocket API (subscribe_entities). A change in Home Assistant shows at
	// once, without asking every 10 seconds. Without it (no connection, an old Home Assistant): polling.
	// ======================================================================

	property bool liveConnected: false
	// with live updates a poll only now and then (names, areas); without them every pollSeconds
	property int pollInterval: liveConnected ? 5 * 60 * 1000 : pollSeconds * 1000
	property bool liveFailed: false           // Home Assistant has no subscribe_entities (older than 2022.4): polling only
	property int liveMsgId: 1
	property int liveSubId: 0
	property string liveSubKey: ""            // the ids subscribed to, joined
	property var liveRaw: ({})                // entity id -> {s, a (all attributes), lc}
	property int liveRetry: 0

	function liveUrl() { return haUrl.replace(/^http/, "ws") + "/api/websocket"; }

	function liveStart() {
		if (!isConfigured() || liveFailed || pollIds().length === 0) return;
		liveReconnect.stop();
		haSocket.active = false;
		haSocket.url = liveUrl();
		haSocket.active = true;
	}

	function liveStop() {
		liveReconnect.stop();
		liveConnected = false;
		liveSubId = 0;
		liveSubKey = "";
		haSocket.active = false;
	}

	function liveSend(obj) {
		if (haSocket.status !== WebSocket.Open) return;
		try { haSocket.sendTextMessage(JSON.stringify(obj)); } catch (e) {}
	}

	// (again) subscribe to the chosen entities and the Energie tab's
	function liveSubscribe() {
		var ids = pollIds();
		var key = ids.join(",");
		if (key === liveSubKey) return;
		if (liveSubId) liveSend({id: liveMsgId++, type: "unsubscribe_events", subscription: liveSubId});
		liveSubKey = key;
		liveRaw = {};
		if (ids.length === 0) { liveSubId = 0; return; }
		liveSubId = liveMsgId++;
		liveSend({id: liveSubId, type: "subscribe_entities", entity_ids: ids});
	}

	function liveMessage(text) {
		var m;
		try { m = JSON.parse(text); } catch (e) { return; }
		if (m.type === "auth_required") {
			liveSend({type: "auth", access_token: haToken});
		} else if (m.type === "auth_ok") {
			liveRetry = 0;
			liveConnected = true;
			liveSubKey = "";
			liveSubscribe();
		} else if (m.type === "auth_invalid") {
			lastError = "token ongeldig (401)";
			liveStop();
			liveReconnect.interval = 5 * 60 * 1000;
			liveReconnect.restart();
		} else if (m.type === "result" && m.id === liveSubId && !m.success) {
			// an older Home Assistant: no subscribe_entities. Polling it is
			console.log("homeassistant: no live updates (" + (m.error ? m.error.message : "?") + "), polling");
			liveFailed = true;
			liveStop();
		} else if (m.type === "event" && m.id === liveSubId && m.event) {
			applyLive(m.event);
		}
	}

	// subscribe_entities sends {a: {id: {s, a, lc}}} (everything, at first), {c: {id: {"+": {s, a, lc}, "-": {a: [keys]}}}} (changes)
	// and {r: [ids]} (removed)
	function applyLive(ev) {
		var raw = liveRaw;
		var changed = [];
		var id;
		if (ev.a) {
			for (id in ev.a) {
				raw[id] = {s: ev.a[id].s, a: ev.a[id].a || {}, lc: ev.a[id].lc || 0};
				changed.push(id);
			}
		}
		if (ev.c) {
			for (id in ev.c) {
				var d = ev.c[id];
				var r = raw[id] || {s: "", a: {}, lc: 0};
				var plus = d["+"];
				if (plus) {
					if (plus.s !== undefined) r.s = plus.s;
					if (plus.lc !== undefined) r.lc = plus.lc;
					if (plus.a) for (var k in plus.a) r.a[k] = plus.a[k];
				}
				var minus = d["-"];
				if (minus && minus.a) for (var j = 0; j < minus.a.length; j++) delete r.a[minus.a[j]];
				raw[id] = r;
				changed.push(id);
			}
		}
		if (ev.r) {
			for (var q = 0; q < ev.r.length; q++) {
				raw[ev.r[q]] = {s: "unavailable", a: raw[ev.r[q]] ? raw[ev.r[q]].a : {}, lc: 0};
				changed.push(ev.r[q]);
			}
		}
		liveRaw = raw;
		if (changed.length === 0) return;
		var map = haStates;
		var newWeather = false, any = false;
		for (var n = 0; n < changed.length; n++) {
			id = changed[n];
			var before = map[id] ? JSON.stringify(map[id]) : "";
			map[id] = liveState(id, raw[id], map[id]);
			applyHold(map, id);
			if (JSON.stringify(map[id]) !== before) any = true;
			if (domainOf(id) === "weather" && !forecasts[id]) newWeather = true;
		}
		var wasConnected = connected;
		connected = true;
		lastError = "";
		if (!any && wasConnected) return;            // nothing the cards show: no redraw (and no button rebuilt under a finger)
		haStates = map;
		statesUpdated();
		if (newWeather) loadForecasts();
	}

	// Home Assistant's state and attributes -> what the cards read (the same as a poll gives)
	function liveState(id, r, prev) {
		var a = r.a || {};
		var d = domainOf(id);
		var keys = extKeys[d] || [];
		var values = [];
		for (var i = 0; i < keys.length; i++) values.push(a[keys[i]] === undefined ? null : a[keys[i]]);
		var area = prev && prev.area ? prev.area : (allIndex[id] ? allIndex[id].area : "");
		return {state: r.s, unit: a.unit_of_measurement || "", name: a.friendly_name || "", area: area || "",
			codeFormat: a.code_format || "", codeArmRequired: a.code_arm_required !== false, features: a.supported_features || 0,
			light: d === "light" ? lightInfo([a.brightness, a.supported_color_modes, a.hs_color, a.color_temp_kelvin,
				a.min_color_temp_kelvin, a.max_color_temp_kelvin, a.color_mode]) : null,
			attrs: extAttrs(id, values), changed: d === "person" || d === "device_tracker" ? r.lc || 0 : 0};
	}

	WebSocket {
		id: haSocket
		active: false
		onTextMessageReceived: liveMessage(message)
		onStatusChanged: {
			if (status !== WebSocket.Closed && status !== WebSocket.Error) return;
			var was = liveConnected;
			liveConnected = false;
			liveSubId = 0;
			liveSubKey = "";
			if (!active || liveFailed || !isConfigured()) return;
			active = false;
			// try again: 2, 4, 8 … seconds, at most a minute; polling meanwhile
			liveReconnect.interval = Math.min(60000, 2000 * Math.pow(2, Math.min(liveRetry, 5)));
			liveRetry++;
			liveReconnect.restart();
			if (was) pollStates();
		}
	}

	Timer { id: liveReconnect; onTriggered: liveStart() }

	Timer {
		// camera images: renewed as often as a poll would (live updates don't change the picture)
		interval: pollSeconds * 1000
		repeat: true
		running: liveConnected
		onTriggered: cameraTick++
	}

	// ======================================================================
	// weather: the forecast (weather.get_forecasts, every 30 minutes)
	// ======================================================================

	property variant forecasts: ({})          // weather entity id -> [{time (ms), condition, temp, low, rain}]

	function loadForecasts() {
		var ids = pollIds();
		for (var i = 0; i < ids.length; i++) if (domainOf(ids[i]) === "weather") loadForecast(ids[i], "daily");
	}

	// HA 2024.x: a service with a response; a weather entity without a daily forecast gets the hourly one
	function loadForecast(id, type) {
		request("POST", "/api/services/weather/get_forecasts?return_response", {entity_id: id, type: type}, function(text, err) {
			var list = null;
			try {
				var f = JSON.parse(text).service_response[id].forecast;
				list = [];
				for (var i = 0; i < f.length; i++) {
					list.push({time: parseTime(f[i].datetime).getTime(), condition: f[i].condition || "", temp: f[i].temperature,
						low: f[i].templow, rain: f[i].precipitation, daily: type === "daily"});
				}
			} catch (e) {}
			if (list === null || list.length === 0) {
				if (type === "daily") loadForecast(id, "hourly");
				else if (!forecasts[id]) { var none = copyState(forecasts, {}); none[id] = []; forecasts = none; }
				return;
			}
			var map = copyState(forecasts, {});
			map[id] = list;
			forecasts = map;
			statesUpdated();
		});
	}

	function weatherConditionText(c) {
		return {"clear-night": "Helder", cloudy: "Bewolkt", exceptional: "Waarschuwing", fog: "Mist", hail: "Hagel",
			lightning: "Onweer", "lightning-rainy": "Onweer en regen", partlycloudy: "Half bewolkt", pouring: "Hevige regen",
			rainy: "Regen", snowy: "Sneeuw", "snowy-rainy": "Natte sneeuw", sunny: "Zonnig", windy: "Winderig",
			"windy-variant": "Winderig, bewolkt"}[c] || c;
	}

	function weatherIconUrl(c) {
		var known = ["clear-night", "cloudy", "exceptional", "fog", "hail", "lightning", "lightning-rainy", "partlycloudy",
			"pouring", "rainy", "snowy", "snowy-rainy", "sunny", "windy", "windy-variant"];
		return Qt.resolvedUrl("drawables/icons/weather-" + (known.indexOf(c) >= 0 ? c : "cloudy") + ".svg");
	}

	Timer {
		interval: 30 * 60 * 1000
		repeat: true
		running: isConfigured()
		onTriggered: loadForecasts()
	}

	// ======================================================================
	// the Energie tab: today's totals from the meter readings (history since midnight)
	// ======================================================================

	property variant energyHistory: ({})      // entity id -> {today: [24], yesterday: [24], last, day}: increments per hour (a meter)
	                                          // or the value in each hour (a price)
	property variant priceForecast: ({})      // price entity id -> [24] today's prices from its attributes (dynamic contracts)

	// [{key, label, units: accepted units, total: a meter reading (true) or power now (false), price: a tariff}]
	function energyFields() {
		var power = ["W", "kW"], kwh = ["kWh", "Wh", "MWh"];
		var perKwh = ["EUR/kWh", "€/kWh", "ct/kWh", "EUR/MWh", "€/MWh"], perM3 = ["EUR/m³", "€/m³", "EUR/m3", "€/m3"];
		return [
			{key: "power", label: "Stroom: verbruik nu", units: power, total: false},
			{key: "usage", label: "Stroom: meterstand verbruik", units: kwh, total: true},
			{key: "export", label: "Stroom: meterstand teruglevering", units: kwh, total: true},
			{key: "solarPower", label: "Zonnepanelen: vermogen nu", units: power, total: false},
			{key: "solar", label: "Zonnepanelen: opgewekt (totaal)", units: kwh, total: true},
			{key: "gas", label: "Gas: meterstand", units: ["m³", "ft³", "CCF"], total: true},
			{key: "water", label: "Water: meterstand", units: ["L", "m³", "gal", "ft³"], total: true},
			{key: "priceUsage", label: "Stroomprijs (per kWh)", units: perKwh, total: false, price: true},
			{key: "priceExport", label: "Terugleververgoeding (per kWh)", units: perKwh, total: false, price: true},
			{key: "priceGas", label: "Gasprijs (per m³)", units: perM3, total: false, price: true},
			{key: "priceWater", label: "Waterprijs (per m³)", units: perM3, total: false, price: true}];
	}

	function energyIds() {
		var out = [];
		for (var i = 0; i < energyKeys.length; i++) {
			var list = energy[energyKeys[i]] || [];
			for (var j = 0; j < list.length; j++) if (out.indexOf(list[j]) < 0) out.push(list[j]);
		}
		return out;
	}

	function energyConfigured() { return energyIds().length > 0; }

	function setEnergy(e) {
		energy = cleanEnergy(e || {});
		saveSettings();
		energyHistory = {};
		energyHistUntil = 0;
		selectionChanged();
		pollStates();
		loadEnergyHistory();
		broadcastState();
	}

	function setEnergyField(key, ids) {
		var e = copyState(energy, {});
		e[key] = ids;
		setEnergy(e);
	}

	function pad2(n) { return (n < 10 ? "0" : "") + n; }

	// Home Assistant's times have microseconds ("…T10:00:00.123456+00:00"): the Toon's JavaScript wants at most 3 digits
	function parseTime(s) {
		return new Date(String(s || "").replace(/(\.\d{3})\d+/, "$1"));
	}

	// the readings since yesterday midnight (Home Assistant's history) -> per hour, for today and yesterday:
	// the increments of a meter, the value of a price
	property double energyHistUntil: 0        // up to when the history is in (ms); the next fetch only asks for what came after
	property string energyHistKey: ""         // for which day and entities: another day or other entities -> everything again

	function loadEnergyHistory() {
		if (!isConfigured()) return;
		var ids = [], priceIds = [];
		var keys = ["usage", "export", "solar", "gas", "water", "priceUsage", "priceExport", "priceGas", "priceWater"];
		for (var i = 0; i < keys.length; i++) {
			var list = energy[keys[i]] || [];
			for (var j = 0; j < list.length; j++) {
				if (ids.indexOf(list[j]) < 0) ids.push(list[j]);
				if (keys[i].indexOf("price") === 0 && priceIds.indexOf(list[j]) < 0) priceIds.push(list[j]);
			}
		}
		if (ids.length === 0) return;
		var now = new Date();
		var midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate());
		var yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
		var day = midnight.toDateString();
		var key = day + "|" + ids.join(",");
		// a meter that reports every few seconds has thousands of readings a day: everything since yesterday only
		// once (a new day, other entities), after that only what came since the last time
		var full = key !== energyHistKey || energyHistUntil <= 0 || energyHistUntil < midnight.getTime();
		var from = full ? yesterday : new Date(energyHistUntil);
		// end_time: without it Home Assistant gives one day from the start
		request("GET", "/api/history/period/" + from.toISOString() + "?end_time=" + encodeURIComponent(now.toISOString())
			+ "&filter_entity_id=" + ids.join(",") + "&minimal_response&no_attributes", null, function(text, err) {
			if (text === null) return;
			var res;
			try { res = JSON.parse(text); } catch (e) { return; }
			var map = full ? {} : copyState(energyHistory, {});
			for (var r = 0; r < res.length; r++) {
				var rows = res[r];
				if (!rows || rows.length === 0 || !rows[0].entity_id) continue;
				var id = rows[0].entity_id;
				var isPrice = priceIds.indexOf(id) >= 0;
				if (full || !map[id]) map[id] = isPrice ? priceHistory(rows, yesterday, midnight, day) : meterHistory(rows, yesterday, midnight, day);
				else map[id] = isPrice ? priceMore(map[id], rows, midnight) : meterMore(map[id], rows, midnight);
			}
			energyHistory = map;
			energyHistKey = key;
			energyHistUntil = now.getTime();
			statesUpdated();
		});
		if (priceIds.length > 0) loadPriceForecast(priceIds);
	}

	// the readings since the last time, added to a meter's hours of today
	function meterMore(hist, rows, midnight) {
		var out = {today: hist.today.slice(0), yesterday: hist.yesterday, last: hist.last, day: hist.day};
		for (var k = 0; k < rows.length; k++) {
			var v = parseFloat(rows[k].state);
			if (isNaN(v)) continue;
			var t = parseTime(rows[k].last_changed || rows[k].last_updated);
			if (out.last !== null) {
				var inc = increment(out.last, v);
				// the first row is the state at the start of the period, often from earlier: it counts in this hour
				var hour = isNaN(t.getTime()) || t < midnight ? new Date().getHours() : t.getHours();
				out.today[hour] += inc;
			}
			out.last = v;
		}
		return out;
	}

	// a price's values since the last time: from its hour on
	function priceMore(hist, rows, midnight) {
		var out = {today: hist.today.slice(0), yesterday: hist.yesterday, last: hist.last, day: hist.day, price: true};
		for (var k = 0; k < rows.length; k++) {
			var v = parseFloat(rows[k].state);
			var t = parseTime(rows[k].last_changed || rows[k].last_updated);
			if (isNaN(v) || isNaN(t.getTime()) || t < midnight) continue;
			for (var h = t.getHours(); h < 24; h++) out.today[h] = v;
			out.last = v;
		}
		return out;
	}

	function zeros() { var z = []; for (var h = 0; h < 24; h++) z.push(0); return z; }

	// a meter's readings -> its increments per hour, yesterday and today
	function meterHistory(rows, yesterday, midnight, day) {
		var out = {today: zeros(), yesterday: zeros(), last: null, day: day};
		for (var k = 0; k < rows.length; k++) {
			var v = parseFloat(rows[k].state);
			if (isNaN(v)) continue;
			var t = parseTime(rows[k].last_changed || rows[k].last_updated);
			if (out.last !== null && !isNaN(t.getTime())) {
				var inc = increment(out.last, v);
				if (t >= midnight) out.today[t.getHours()] += inc;
				else if (t >= yesterday) out.yesterday[t.getHours()] += inc;
			}
			out.last = v;
		}
		return out.last === null ? null : out;
	}

	// a price's values -> the price in each hour (the last value at the start of the hour, else in it), yesterday and today
	function priceHistory(rows, yesterday, midnight, day) {
		var points = [];
		for (var k = 0; k < rows.length; k++) {
			var v = parseFloat(rows[k].state);
			var t = parseTime(rows[k].last_changed || rows[k].last_updated);
			if (!isNaN(v) && !isNaN(t.getTime())) points.push({t: t.getTime(), v: v});
		}
		if (points.length === 0) return null;
		var out = {today: [], yesterday: [], last: points[points.length - 1].v, day: day, price: true};
		for (var h = 0; h < 48; h++) {
			var start = yesterday.getTime() + h * 3600 * 1000;
			var value = null;
			for (var p = 0; p < points.length; p++) {
				if (points[p].t <= start + 30 * 60 * 1000) value = points[p].v;      // the last change before half past
				else break;
			}
			if (value === null) value = points[0].v;
			(h < 24 ? out.yesterday : out.today).push(value);
		}
		return out;
	}

	// a dynamic contract's prices for today, from the price entity's attributes when it has them:
	// Nordpool (today: [24 or 96 numbers], raw_today: [{start, value}]), ENTSO-e (prices_today: [{time, price}]),
	// others (prices: [{from|start|time, price|value}])
	function loadPriceForecast(ids) {
		var parts = [];
		for (var i = 0; i < ids.length; i++) {
			var q = jsonString(ids[i]);
			parts.push(q + ": [state_attr(" + q + ", 'today'), state_attr(" + q + ", 'raw_today'), state_attr(" + q + ", 'prices_today'), state_attr(" + q + ", 'prices')]");
		}
		template("{# energy prices #}{{ {" + parts.join(", ") + "} | tojson }}", function(res, err) {
			if (res === null) return;
			var map = {};
			for (var id in res) {
				var hours = priceHours(res[id]);
				if (hours) map[id] = hours;
			}
			priceForecast = map;
			statesUpdated();
		});
	}

	// the attributes -> 24 prices (an hour's average when they come per quarter), or null
	function priceHours(a) {
		if (!a) return null;
		var today = new Date().toDateString();
		var sums = zeros(), counts = zeros(), any = false;
		function add(h, v) { if (typeof v === "number" && h >= 0 && h < 24) { sums[h] += v; counts[h]++; any = true; } }
		if (a[0] && a[0].length) {                       // today: [24] or [96]
			var per = a[0].length >= 96 ? 4 : (a[0].length >= 48 ? 2 : 1);
			for (var i = 0; i < a[0].length; i++) add(Math.floor(i / per), a[0][i]);
		} else {
			var lists = [a[1], a[2], a[3]];
			for (var l = 0; l < lists.length; l++) {
				var list = lists[l];
				if (!list || !list.length) continue;
				for (var k = 0; k < list.length; k++) {
					var e = list[k];
					var t = parseTime(e.start || e.from || e.time || e.startsAt);
					if (isNaN(t.getTime()) || t.toDateString() !== today) continue;
					add(t.getHours(), typeof e.value === "number" ? e.value : (typeof e.price === "number" ? e.price : e.total));
				}
				if (any) break;
			}
		}
		if (!any) return null;
		var out = [];
		for (var h = 0; h < 24; h++) out.push(counts[h] ? sums[h] / counts[h] : null);
		return out;
	}

	// a meter reading went from a to b: the use in between. A drop is a reset (a daily meter, a new meter)
	function increment(a, b) {
		if (b >= a) return b - a;
		return b < a * 0.5 ? b : 0;      // a small dip is noise of the sensor
	}

	// a reading in the unit the Energie tab shows: kWh, m³ for gas, litres for water, W for power
	function energyFactor(unit, key) {
		if (unit === "Wh") return 0.001;
		if (unit === "MWh") return 1000;
		if (unit === "kW") return 1000;
		if (key === "water" && unit === "m³") return 1000;
		if (key === "water" && unit === "gal") return 3.785;
		if (key === "water" && unit === "ft³") return 28.317;
		if (key === "gas" && unit === "ft³") return 0.02832;
		if (key === "gas" && unit === "CCF") return 2.832;
		return 1;
	}

	function energyUnit(key) {
		return {power: "W", solarPower: "W", usage: "kWh", "export": "kWh", solar: "kWh", gas: "m³", water: "L"}[key] || "";
	}

	// power now (W) of a field, summed; null when none of its entities has a number
	function energyNow(key) {
		var list = energy[key] || [];
		var sum = 0, any = false;
		for (var i = 0; i < list.length; i++) {
			var s = haStates[list[i]];
			var v = s ? parseFloat(s.state) : NaN;
			if (isNaN(v)) continue;
			sum += v * energyFactor(s.unit, key);
			any = true;
		}
		return any ? sum : null;
	}

	// today's use of a meter field: {total, hours: [24]} in energyUnit(key); null when unknown yet
	function energyToday(key) {
		var list = energy[key] || [];
		var hours = [], any = false;
		for (var h = 0; h < 24; h++) hours.push(0);
		var nowHour = new Date().getHours();
		var today = new Date().toDateString();
		for (var i = 0; i < list.length; i++) {
			var hist = energyHistory[list[i]];
			if (!hist || hist.day !== today || hist.price) continue;
			var s = haStates[list[i]];
			var f = energyFactor(s ? s.unit : "", key);
			for (var k = 0; k < 24; k++) hours[k] += hist.today[k] * f;
			// what the meter did since the history was fetched
			var v = s ? parseFloat(s.state) : NaN;
			if (!isNaN(v)) hours[nowHour] += increment(hist.last, v) * f;
			any = true;
		}
		if (!any) return null;
		var total = 0;
		for (var t = 0; t < 24; t++) total += hours[t];
		return {total: total, hours: hours};
	}

	// yesterday's use of a meter field: {total, hours: [24], sameTime: up to this time of day}; null when unknown
	function energyYesterday(key) {
		var list = energy[key] || [];
		var hours = zeros(), any = false;
		var today = new Date().toDateString();
		for (var i = 0; i < list.length; i++) {
			var hist = energyHistory[list[i]];
			if (!hist || hist.day !== today || hist.price) continue;
			var s = haStates[list[i]];
			var f = energyFactor(s ? s.unit : "", key);
			for (var k = 0; k < 24; k++) hours[k] += hist.yesterday[k] * f;
			any = true;
		}
		if (!any) return null;
		var now = new Date(), total = 0, same = 0;
		for (var h = 0; h < 24; h++) {
			total += hours[h];
			if (h < now.getHours()) same += hours[h];
			else if (h === now.getHours()) same += hours[h] * now.getMinutes() / 60;
		}
		return {total: total, hours: hours, sameTime: same};
	}

	// a price field in euro per kWh (or per m³), per hour of today: [24] or null. From the attributes (a dynamic
	// contract's prices), else the history, else the price now. More entities are added up (e.g. a price and a surcharge)
	function priceToday(key) {
		var list = energy[key] || [];
		if (list.length === 0) return null;
		var out = zeros(), any = false;
		var today = new Date().toDateString(), nowHour = new Date().getHours();
		for (var i = 0; i < list.length; i++) {
			var id = list[i];
			var s = haStates[id];
			var f = priceFactor(s ? s.unit : "");
			var now = s ? parseFloat(s.state) : NaN;
			var fc = priceForecast[id], hist = energyHistory[id];
			for (var h = 0; h < 24; h++) {
				var v = null;
				if (fc && typeof fc[h] === "number") v = fc[h];
				else if (hist && hist.price && hist.day === today && h <= nowHour) v = hist.today[h];
				if (h === nowHour && !isNaN(now) && !(fc && typeof fc[h] === "number")) v = now;
				if (v === null && !isNaN(now)) v = now;             // a fixed tariff: the same all day
				if (v !== null) { out[h] += v * f; any = true; }
			}
		}
		return any ? out : null;
	}

	function priceNow(key) {
		var p = priceToday(key);
		return p ? p[new Date().getHours()] : null;
	}

	function priceFactor(unit) {
		if (unit === "ct/kWh") return 0.01;
		if (unit === "EUR/MWh" || unit === "€/MWh") return 0.001;
		return 1;
	}

	// today's costs of a panel in euro, or null without a price: electricity (use minus what went back), gas, water
	function energyCost(panel) {
		var cost = 0;
		if (panel === "electricity") {
			var use = energyToday("usage"), back = energyToday("export");
			var pu = priceToday("priceUsage"), pe = priceToday("priceExport") || pu;
			if (!pu || (!use && !back)) return null;
			for (var h = 0; h < 24; h++) {
				if (use) cost += use.hours[h] * pu[h];
				if (back && pe) cost -= back.hours[h] * pe[h];
			}
			return cost;
		}
		var key = panel === "gas" ? "gas" : "water";
		var t = energyToday(key), p = priceToday(panel === "gas" ? "priceGas" : "priceWater");
		if (!t || !p) return null;
		var perUnit = key === "water" ? 0.001 : 1;         // water is in litres, its price per m³
		for (var k = 0; k < 24; k++) cost += t.hours[k] * perUnit * p[k];
		return cost;
	}

	function euro(v, digits) {
		if (v === null || v === undefined) return "-";
		return (v < 0 ? "− " : "") + "€ " + i18n.number(Math.abs(v), digits === undefined ? 2 : digits, 0);
	}

	function energyNumber(v, key) {
		if (v === null || v === undefined) return "-";
		var unit = energyUnit(key);
		if (unit === "W" && Math.abs(v) >= 1000) return i18n.number(v / 1000, 2, i18n.omit_trail_zeros) + " kW";
		var digits = unit === "W" || unit === "L" ? 0 : (Math.abs(v) >= 100 ? 0 : (Math.abs(v) >= 10 ? 1 : 2));
		return i18n.number(v, digits, i18n.omit_trail_zeros) + " " + unit;
	}

	Timer {
		// the history: every 5 minutes (a new day starts by itself)
		interval: 5 * 60 * 1000
		repeat: true
		running: isConfigured() && energyConfigured()
		onTriggered: loadEnergyHistory()
	}

	// every entity HA has, with its area, plus HA's list of areas (for choosing)
	function loadAllEntities() {
		if (!isConfigured()) return;
		loadingAll = true;
		var tpl = "{\"areas\": {{ areas() | map('area_name') | list | tojson }}, \"entities\": ["
			+ "{%- for s in states -%}{{ [s.entity_id, s.name, area_name(s.entity_id), s.state, s.attributes.get('unit_of_measurement'), s.attributes.get('device_class')] | tojson }}"
			+ "{%- if not loop.last %},{% endif -%}{%- endfor -%}]}";
		template(tpl, function(res, err) {
			loadingAll = false;
			if (res === null) {
				lastError = err;
				allEntitiesLoaded();
				broadcastState();
				return;
			}
			setAllEntities(res.entities, res.areas || [], new Date().getTime());
			connected = true;
			saveEntitiesCache(res.entities);
			allEntitiesLoaded();
			selectionChanged();
			broadcastState();
		});
	}

	// rows [id, name, area, state, unit, device_class] (HA's answer, or the cache) -> allEntities, the index and
	// the web editor's message
	function setAllEntities(rows, areas, version) {
		var list = [], index = {};
		for (var i = 0; i < rows.length; i++) {
			var r = rows[i];
			var e = {id: r[0], name: r[1] || "", area: r[2] || "", state: r[3], domain: r[0].split(".")[0], unit: r[4] || "", deviceClass: r[5] || ""};
			list.push(e);
			index[e.id] = e;
		}
		list.sort(function(a, b) { return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0); });
		allIndex = index;
		allEntities = list;
		areaNames = areas;
		allVersion = version;
		var compact = [];
		for (var k = 0; k < list.length; k++) compact.push([list[k].id, list[k].name, list[k].area, list[k].state, list[k].unit]);
		allMessage = JSON.stringify({type: "entities", app: "homeassistantExtended", version: version, list: compact});
	}

	function saveEntitiesCache(rows) {
		try {
			entitiesCache.write(JSON.stringify({url: haUrl, time: allVersion, areas: areaNames, rows: rows}));
		} catch (e) {}
	}

	// forget the cached list (file and memory) and fetch it again from Home Assistant: e.g. after renaming
	// or moving entities in Home Assistant. The web editor's copy goes too: its version no longer matches.
	function clearEntitiesCache() {
		try { entitiesCache.write(""); } catch (e) {}
		allIndex = {};
		allEntities = [];
		allMessage = "";
		allVersion = 0;
		allEntitiesLoaded();
		broadcastState();
		loadAllEntities();
	}

	// the list from the last time (for this Home Assistant): the age in ms, or -1 when there is none
	function loadEntitiesCache() {
		try {
			var c = JSON.parse(entitiesCache.read());
			if (!c || c.url !== haUrl || !c.rows) return -1;
			setAllEntities(c.rows, c.areas || [], c.time || 0);
			return new Date().getTime() - (c.time || 0);
		} catch (e) {
			return -1;
		}
	}

	// ======================================================================
	// switching
	// ======================================================================

	function domainOf(id) { return id.split(".")[0]; }

	// what a tap on the entity does: "toggle", "press", "run" or "" (read only)
	function actionOf(id) {
		var d = domainOf(id);
		if (["light", "switch", "input_boolean", "automation", "siren", "cover", "lock", "vacuum", "group"].indexOf(d) >= 0) return "toggle";
		if (["fan", "climate", "humidifier", "media_player", "camera", "person", "device_tracker"].indexOf(d) >= 0) return "open";
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
		if (actionOf(id) === "open") { openDetail(id); return; }
		var on = isOn(id);
		var service = "";
		if (d === "button" || d === "input_button") service = "press";
		else if (d === "script" || d === "scene") service = "turn_on";
		else if (d === "lock") service = on ? "lock" : "unlock";
		else if (d === "cover") service = on ? "close_cover" : "open_cover";
		else if (d === "vacuum") { service = on ? "turn_off" : "turn_on"; }
		// on or off as the card shows it, not "toggle": a lamp that is still fading out is "on" for Home Assistant,
		// so off-and-at-once-on again would switch it off a second time
		else if (actionOf(id) === "toggle") service = on ? "turn_off" : "turn_on";
		if (!service) return;
		if (d === "vacuum" && service === "turn_on") service = "start";
		if (d === "vacuum" && service === "turn_off") service = "return_to_base";

		// show the new state at once, HA's answer follows with the next poll
		if (actionOf(id) === "toggle" && haStates[id]) {
			var map = haStates;
			var guess = {lock: on ? "locked" : "unlocked", cover: on ? "closing" : "opening"}[d] || (on ? "off" : "on");
			var before = map[id].state;
			map[id] = copyState(map[id], {state: guess});
			haStates = map;
			hold(id, before);
			statesUpdated();
		}
		request("POST", "/api/services/" + d + "/" + service, {entity_id: id}, function(text, err) {
			if (text === null) { lastError = "Schakelen mislukt: " + err; release(id); }
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
		if (d === "climate") {
			var cur = attr(id, "current_temperature"), target = climateTargetText(id);
			if (v === "off") return (typeof cur === "number" ? degrees(cur) + " · " : "") + "Uit";
			return (typeof cur === "number" ? degrees(cur) : hvacModeText(v)) + (target ? " → " + target : "");
		}
		if (d === "humidifier") {
			var hum = attr(id, "current_humidity");
			if (v !== "on") return (typeof hum === "number" ? Math.round(hum) + "% · " : "") + "Uit";
			return (typeof hum === "number" ? Math.round(hum) + "%" : "Aan") + (typeof attr(id, "humidity") === "number" ? " → " + Math.round(attr(id, "humidity")) + "%" : "");
		}
		if (d === "weather") return (typeof attr(id, "temperature") === "number" ? degrees(attr(id, "temperature")) + " " : "") + weatherConditionText(v);
		if (d === "media_player") {
			if (v === "playing" || v === "paused") {
				var title = attr(id, "media_title");
				return (v === "paused" ? "Pauze" : "Speelt") + (title ? ": " + title : "");
			}
			return {off: "Uit", on: "Aan", idle: "Inactief", standby: "Stand-by", buffering: "Laden…"}[v] || v;
		}
		if (d === "camera") return {idle: "Inactief", recording: "Neemt op", streaming: "Live"}[v] || v;
		if (d === "person" || d === "device_tracker") return v === "home" ? "Thuis" : (v === "not_home" ? "Weg" : v);
		var words = {on: "Aan", off: "Uit", open: "Open", closed: "Dicht", opening: "Gaat open", closing: "Gaat dicht",
			locked: "Op slot", unlocked: "Open", home: "Thuis", not_home: "Weg", playing: "Speelt", paused: "Pauze",
			idle: "Inactief", heat: "Verwarmen", cool: "Koelen", auto: "Auto", detected: "Gedetecteerd", clear: "Vrij"};
		if (d === "light" && v === "on" && s.light && s.light.dimmable && s.light.brightness > 0) return "Aan " + lightPercent(id) + "%";
		if (d === "fan" && v === "on") {
			var pct = attr(id, "percentage"), preset = attr(id, "preset_mode");
			if (typeof pct === "number" && pct > 0 && fanSupports(id, "speed")) return "Aan " + Math.round(pct) + "%";
			return preset ? "Aan · " + presetText(preset) : "Aan";
		}
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

	// after a command the card shows the new state at once. A poll that comes in right after can still have
	// the old state (a lamp that fades out reports "on" for a moment), or a state in between (off and at once
	// on again: "off" for a moment). The new state is held until Home Assistant reports it, or for at most
	// 6 seconds after the last tap. A cover or lock may skip the state we guessed ("opening"): any new state counts.
	property var holds: ({})                  // entity id -> {entry (what the card shows), before (the old state), until}
	property int holdMs: 6000

	function hold(id, before) {
		var h = holds;
		var keep = h[id] && h[id].until > Date.now() ? h[id].before : before;    // quick taps: the state before the first
		h[id] = {entry: haStates[id], before: keep, until: Date.now() + holdMs};
		holds = h;
	}

	function release(id) {
		var h = holds;
		delete h[id];
		holds = h;
	}

	// in a poll's answer: keep the held state while HA still reports the old one
	function applyHold(map, id) {
		var h = holds[id];
		if (!h) return;
		var ha = map[id].state, expected = h.entry ? h.entry.state : ha;
		var done = Date.now() >= h.until || !h.entry
			|| (expected !== h.before && (ha === expected || (["cover", "lock"].indexOf(domainOf(id)) >= 0 && ha !== h.before)));
		// expected === before (a brightness or volume change, or off and on again): held until the time is up
		if (done) release(id);
		else map[id] = h.entry;
	}

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
		var before = map[id].state;
		map[id] = copyState(map[id], {state: state, light: copyState(map[id].light, changes)});
		haStates = map;
		hold(id, before);
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
			if (text === null) { lastError = "Lamp: " + err; release(id); }
			actionResult(id, text !== null, text !== null ? "" : friendlyError(err));
			refreshSoon.restart();
		});
	}

	// the Toon's keyboard with another word on its button ("Zoek" instead of "Opslaan"): the firmware sets
	// its own word when the keyboard shows, so ours goes on right after it, only this once
	function openKeyboard(title, text, onDone, buttonText) {
		if (buttonText) {
			var relabel = function() {
				qkeyboard.shown.disconnect(relabel);
				qkeyboard.addCustomTopRightButton(buttonText);
			};
			qkeyboard.shown.connect(relabel);
		}
		qkeyboard.open(title, text, onDone);
	}

	function openLight(id) {
		stage.openFullscreen(lightScreenUrl, {entityId: id});
	}

	// the screen of a thermostat, humidifier, speaker, camera or person
	function openDetail(id) {
		var d = domainOf(id);
		var url = {fan: fanScreenUrl, climate: climateScreenUrl, humidifier: climateScreenUrl, media_player: mediaScreenUrl, camera: cameraScreenUrl,
			person: personScreenUrl, device_tracker: personScreenUrl}[d];
		if (url) stage.openFullscreen(url, {entityId: id});
	}

	// ======================================================================
	// thermostats (climate), humidifiers, speakers (media_player)
	// ======================================================================

	// a command for any domain; the change shown at once (state and attributes), HA's answer follows
	function service(id, domain, name, data, localState, localAttrs) {
		if (haStates[id] && (localState || localAttrs)) {
			var map = haStates;
			var changes = {};
			if (localState) changes.state = localState;
			if (localAttrs) changes.attrs = copyState(map[id].attrs || {}, localAttrs);
			var before = map[id].state;
			map[id] = copyState(map[id], changes);
			haStates = map;
			hold(id, before);
			statesUpdated();
		}
		data = data || {};
		data.entity_id = id;
		request("POST", "/api/services/" + domain + "/" + name, data, function(text, err) {
			if (text === null) { lastError = domain + ": " + err; release(id); }
			actionResult(id, text !== null, text !== null ? "" : friendlyError(err));
			refreshSoon.restart();
		});
	}

	function hvacModeText(m) {
		return {off: "Uit", heat: "Verwarmen", cool: "Koelen", heat_cool: "Verwarmen/koelen", auto: "Automatisch",
			dry: "Drogen", fan_only: "Ventileren"}[m] || m;
	}

	function hvacActionText(a) {
		return {heating: "verwarmt", cooling: "koelt", idle: "rust", drying: "droogt", fan: "ventileert", preheating: "voorverwarmen",
			defrosting: "ontdooit"}[a] || "";
	}

	function presetText(p) {
		return {none: "Geen", eco: "Eco", away: "Weg", boost: "Boost", comfort: "Comfort", home: "Thuis", sleep: "Slapen",
			activity: "Actief", normal: "Normaal", baby: "Baby", auto: "Auto"}[p] || (p ? p.charAt(0).toUpperCase() + p.substring(1) : p);
	}

	// "20,5°", or "19°–23°" for a range (heat_cool); "" when the thermostat has no target
	function climateTargetText(id) {
		var t = attr(id, "temperature");
		if (typeof t === "number") return degrees(t);
		var lo = attr(id, "target_temp_low"), hi = attr(id, "target_temp_high");
		if (typeof lo === "number" && typeof hi === "number") return degrees(lo) + "–" + degrees(hi);
		return "";
	}

	function climateSetTemperature(id, t) { service(id, "climate", "set_temperature", {temperature: t}, null, {temperature: t}); }
	function climateSetRange(id, lo, hi) {
		service(id, "climate", "set_temperature", {target_temp_low: lo, target_temp_high: hi}, null, {target_temp_low: lo, target_temp_high: hi});
	}
	function climateSetMode(id, mode) { service(id, "climate", "set_hvac_mode", {hvac_mode: mode}, mode, null); }
	function climateSetPreset(id, preset) { service(id, "climate", "set_preset_mode", {preset_mode: preset}, null, {preset_mode: preset}); }

	// a fan's features (HA's supported_features bits)
	function fanSupports(id, what) {
		var f = haStates[id] ? haStates[id].features : 0;
		var bits = {speed: 1, oscillate: 2, direction: 4, preset: 8};
		return (f & bits[what]) !== 0;
	}
	// more than on/off: the card gets the tune button, holding it opens the fan screen
	function fanAdjustable(id) {
		return domainOf(id) === "fan" && (fanSupports(id, "speed") || fanSupports(id, "oscillate") || fanSupports(id, "direction")
			|| (fanSupports(id, "preset") && (attr(id, "preset_modes") || []).length > 0));
	}
	function fanStep(id) {
		var st = attr(id, "percentage_step");
		return typeof st === "number" && st > 0 ? st : 10;
	}
	// percent 0..100 (0 switches off), rounded to the fan's own steps
	function fanSetPercentage(id, pct) {
		var st = fanStep(id);
		pct = Math.max(0, Math.min(100, Math.round(Math.round(pct / st) * st)));
		service(id, "fan", "set_percentage", {percentage: pct}, pct > 0 ? "on" : "off", {percentage: pct});
	}
	function fanSetPreset(id, p) { service(id, "fan", "set_preset_mode", {preset_mode: p}, "on", {preset_mode: p}); }
	function fanOscillate(id, on) { service(id, "fan", "oscillate", {oscillating: on}, null, {oscillating: on}); }
	function fanDirection(id, dir) { service(id, "fan", "set_direction", {direction: dir}, null, {direction: dir}); }
	function fanPower(id, on) { service(id, "fan", on ? "turn_on" : "turn_off", {}, on ? "on" : "off", null); }
	function openFan(id) { stage.openFullscreen(fanScreenUrl, {entityId: id}); }

	function humidifierSetHumidity(id, h) { service(id, "humidifier", "set_humidity", {humidity: h}, null, {humidity: h}); }
	function humidifierSetMode(id, mode) { service(id, "humidifier", "set_mode", {mode: mode}, null, {mode: mode}); }
	function humidifierPower(id, on) { service(id, "humidifier", on ? "turn_on" : "turn_off", {}, on ? "on" : "off", null); }

	// a speaker's features (HA's supported_features bits)
	function mediaSupports(id, what) {
		var f = haStates[id] ? haStates[id].features : 0;
		var bits = {pause: 1, volume: 4, mute: 8, previous: 16, next: 32, on: 128, off: 256, step: 1024, source: 2048, stop: 4096, play: 16384};
		return (f & bits[what]) !== 0;
	}

	function mediaPlayPause(id) {
		var playing = haStates[id] && haStates[id].state === "playing";
		service(id, "media_player", "media_play_pause", {}, playing ? "paused" : "playing", null);
	}
	function mediaNext(id) { service(id, "media_player", "media_next_track", {}, null, null); }
	function mediaPrevious(id) { service(id, "media_player", "media_previous_track", {}, null, null); }
	function mediaPower(id, on) { service(id, "media_player", on ? "turn_on" : "turn_off", {}, on ? "on" : "off", null); }
	function mediaSetVolume(id, v) {
		v = Math.round(Math.max(0, Math.min(1, v)) * 100) / 100;
		service(id, "media_player", "volume_set", {volume_level: v}, null, {volume_level: v});
	}
	function mediaVolumeStep(id, up) {
		var v = attr(id, "volume_level");
		if (typeof v === "number" && mediaSupports(id, "volume")) mediaSetVolume(id, v + (up ? 0.05 : -0.05));
		else service(id, "media_player", up ? "volume_up" : "volume_down", {}, null, null);
	}
	function mediaMute(id) {
		var m = attr(id, "is_volume_muted") === true;
		service(id, "media_player", "volume_mute", {is_volume_muted: !m}, null, {is_volume_muted: !m});
	}
	function mediaSource(id, source) { service(id, "media_player", "select_source", {source: source}, null, {source: source}); }
	function mediaIsOff(id) {
		var s = haStates[id] ? haStates[id].state : "";
		return s === "off" || s === "standby" || s === "unavailable" || s === "";
	}

	// a camera's still image: Home Assistant's camera proxy (entity_picture holds a token), with a new
	// number each time so it is fetched again
	property int cameraTick: 0
	// animated: a moving picture (a rain radar): not fetched again every few seconds, only when Home
	// Assistant gives a new token in entity_picture (about every 5 minutes), and it plays in between
	function cameraUrl(id, animated) {
		var p = attr(id, "entity_picture");
		if (!p) return "";
		if (animated) return haUrl + p;
		return haUrl + p + (p.indexOf("?") >= 0 ? "&" : "?") + "t=" + cameraTick;
	}

	// "sinds 14:05" / "sinds gisteren" for a person's state
	function sinceText(id) {
		var c = haStates[id] ? haStates[id].changed : 0;
		if (!c) return "";
		var t = new Date(c * 1000), now = new Date();
		var hm = pad2(t.getHours()) + ":" + pad2(t.getMinutes());
		if (t.toDateString() === now.toDateString()) return "sinds " + hm;
		var y = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
		if (t.toDateString() === y.toDateString()) return "sinds gisteren " + hm;
		return "sinds " + t.getDate() + "-" + (t.getMonth() + 1) + " " + hm;
	}

	// mode: the button pressed on the alarm card when the panel needs a code (the screen asks for it)
	function openAlarm(id, mode) {
		stage.openFullscreen(alarmScreenUrl, {entityId: id, mode: mode || ""});
	}

	Timer {
		id: pollTimer
		interval: pollInterval
		repeat: true
		running: isConfigured() && pollIds().length > 0
		onTriggered: pollStates()
	}

	// after a command: Home Assistant's state a second later, and once more a bit after that.
	// A lamp that fades in or out still reports its old state right away.
	Timer {
		id: refreshSoon
		interval: 1000
		onTriggered: {
			if (liveConnected) return;                 // Home Assistant tells us itself
			pollStates();
			refreshLater.restart();
		}
	}

	Timer {
		id: refreshLater
		interval: 2000
		onTriggered: pollStates()
	}

	Timer {
		// the list of all entities changes rarely: fetched again when it is older than allMaxAgeHours, and when
		// you ask (⟳ in the web editor, opening Entiteiten kiezen)
		interval: 30 * 60 * 1000
		repeat: true
		running: isConfigured()
		onTriggered: if (new Date().getTime() - allVersion > allMaxAgeHours * 3600 * 1000) loadAllEntities()
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

	// the Toon's own IP address: from the kernel's address list, else from a connection it has open
	function findToonAddress() {
		// /proc/net/fib_trie: "|-- 192.168.1.23" followed by "/32 host LOCAL"
		try {
			var fib = fibFile.read().split("\n");
			for (var f = 1; f < fib.length; f++) {
				if (fib[f].indexOf("/32 host LOCAL") < 0) continue;
				var m = fib[f - 1].match(/(\d+)\.(\d+)\.(\d+)\.(\d+)\s*$/);
				if (m && m[1] !== "127" && m[1] !== "0") return m[1] + "." + m[2] + "." + m[3] + "." + m[4];
			}
		} catch (e1) {}
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

	function webEditorKnown() { return toonAddress !== ""; }

	function webEditorUrl() {
		if (toonAddress) return "http://" + toonAddress + "/" + webPage;
		return "http://<ip-van-toon>/" + webPage;
	}

	function stateMessage() {
		return JSON.stringify({
			type: "state",
			app: "homeassistantExtended",          // the web editor ignores other apps on the same port
			version: appVersion,
			url: haUrl,
			hasToken: haToken !== "",
			connected: connected,
			error: lastError,
			loading: loadingAll,
			sortMode: sortMode,
			systray: enableSystray,
			areaOrder: areaOrder,
			defaultTab: defaultTab,
			tabs: defaultTabChoices(),
			tileEntities: tileEntities,
			energy: energy,
			energyFields: energyFields(),
			entities: entities,
			areas: areaNames,
			allVersion: allVersion,              // the list of all entities comes apart ("entities"), only when the page's copy is older
			allCount: allEntities.length
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
		} else if (m.type === "entities") {
			// the page has a copy of this version (its browser keeps it): no need to send 100 kB again
			if (m.version === allVersion && allVersion > 0) sendTo(socket, JSON.stringify({type: "entities", app: "homeassistantExtended", version: allVersion, same: true}));
			else if (allMessage) sendTo(socket, allMessage);
		} else if (m.type === "clearCache") {
			clearEntitiesCache();
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
			// answer first, then the work (saving, the screens): the page doesn't wait for the slow part
			sendTo(socket, JSON.stringify({type: "saved"}));
			pendingSave = m;
			saveLater.restart();
		}
	}

	property var pendingSave: null
	Timer {
		id: saveLater
		interval: 50
		onTriggered: {
			var m = pendingSave;
			pendingSave = null;
			if (!m) return;
			if (m.sortMode) sortMode = m.sortMode;
			if (m.systray !== undefined) enableSystray = m.systray === true;
			if (m.areaOrder) areaOrder = m.areaOrder;
			if (typeof m.defaultTab === "string") defaultTab = m.defaultTab;
			if (m.tileEntities) tileEntities = cleanTile(m.tileEntities);
			if (m.energy) {
				energy = cleanEnergy(m.energy);
				energyHistory = {};
				energyHistUntil = 0;
				loadEnergyHistory();
			}
			setEntities(m.entities || []);
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
