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
	property double lastDataTime: 0            // when data last came in from Home Assistant (a poll, a live update), ms
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
		try { appVersion = versionFile.read().trim(); } catch (error) {}
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
			var saved = JSON.parse(settingsFile.read());
			haUrl = saved.url || "";
			haToken = saved.token || "";
			if (saved.pollSeconds >= 2) pollSeconds = saved.pollSeconds;
			entities = cleanEntities(saved.entities || []);
			sortMode = saved.sortMode || "area";
			favouritesOnly = saved.favouritesOnly === true;
			enableSystray = saved.enableSystray === true;
			areaOrder = saved.areaOrder || [];
			if (typeof saved.defaultTab === "string") defaultTab = saved.defaultTab;
			tileEntities = cleanTile(saved.tileEntities || []);
			energy = cleanEnergy(saved.energy || {});
			if (saved.mapTileUrl) mapTileUrl = saved.mapTileUrl;
			if (saved.webPort > 0) webPort = saved.webPort;
		} catch (error) {
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

	function cleanEnergy(source) {
		var out = {};
		for (var i = 0; i < energyKeys.length; i++) {
			var k = energyKeys[i];
			var list = source[k] || [];
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
			var entity = list[i];
			if (!entity || !entity.id || seen[entity.id]) continue;
			seen[entity.id] = true;
			out.push({id: String(entity.id), name: entity.name ? String(entity.name) : "", fav: entity.fav === true});
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
	function setFavouritesOnly(enabled) { favouritesOnly = enabled; saveSettings(); selectionChanged(); }
	function setSystray(enabled) { enableSystray = enabled; saveSettings(); broadcastState(); }

	// the name to show: your own, else HA's friendly name, else the entity id
	function displayName(id) {
		var i = indexOf(id);
		if (i >= 0 && entities[i].name) return entities[i].name;
		var entry = haStates[id];
		if (entry && entry.name) return entry.name;
		var entity = allIndex[id];
		return entity && entity.name ? entity.name : id;
	}

	function areaOf(id) {
		var entry = haStates[id];
		if (entry && entry.area) return entry.area;
		var entity = allIndex[id];
		return entity ? entity.area || "" : "";
	}

	// the chosen entities as the screen shows them: [{id, name, area, fav, section}] sorted by sortMode
	function sortedEntities(onlyFavs, mode) {
		var out = [];
		for (var i = 0; i < entities.length; i++) {
			var entity = entities[i];
			if (onlyFavs && !entity.fav) continue;
			var area = areaOf(entity.id);
			out.push({id: entity.id, name: displayName(entity.id), area: area, fav: entity.fav, order: i,
				section: mode === "area" ? (area || "Geen ruimte") : (mode === "name" ? displayName(entity.id).charAt(0).toUpperCase() : "")});
		}
		if (mode === "area") {
			out.sort(function(first, second) {
				var rankFirst = areaRank(first.area), rankSecond = areaRank(second.area);
				if (rankFirst !== rankSecond) return rankFirst - rankSecond;
				return first.name.toLowerCase() < second.name.toLowerCase() ? -1 : (first.name.toLowerCase() > second.name.toLowerCase() ? 1 : 0);
			});
		} else if (mode === "name") {
			out.sort(function(first, second) { return first.name.toLowerCase() < second.name.toLowerCase() ? -1 : (first.name.toLowerCase() > second.name.toLowerCase() ? 1 : 0); });
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
			var first = areaOf(entities[i].id);
			if (first) used[first] = true; else hasNoArea = true;
		}
		if (hasFav) out.push({key: "*fav", label: "Favorieten"});
		if (energyConfigured()) out.push({key: "*energy", label: "Energie"});
		var areas = [];
		for (var k in used) areas.push(k);
		if (hasNoArea) areas.push("");                // Overig: last, unless you moved it
		areas.sort(function(first, second) { return (areaRank(first) - areaRank(second)) || (first < second ? -1 : (first > second ? 1 : 0)); });
		for (var index = 0; index < areas.length; index++) out.push({key: areas[index], label: areas[index] || "Overig"});
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
			var entity = entities[i];
			if (key === "*fav" ? entity.fav : areaOf(entity.id) === key) out.push(entity.id);
		}
		return out;
	}

	// how many lights/switches are on in a tab: shown next to its name
	function tabOnCount(key) {
		var ids = tabEntities(key);
		var count = 0;
		for (var i = 0; i < ids.length; i++) if ((actionOf(ids[i]) === "toggle" || domainOf(ids[i]) === "fan") && isOn(ids[i])) count++;
		return count;
	}

	// the icon for an entity: drawables/icons/<name>.svg (-on.svg when on, -dim.svg dimmed)
	function iconName(id) {
		var domain = domainOf(id);
		var unit = haStates[id] ? haStates[id].unit : "";
		var map = {light: "bulb", "switch": "plug", fan: "fan", cover: "blinds", lock: "lock", alarm_control_panel: "shield",
			scene: "palette", script: "play", button: "button", input_button: "button", climate: "thermometer", water_heater: "flame",
			media_player: "speaker", person: "person", device_tracker: "person", binary_sensor: "eye", input_boolean: "toggle",
			automation: "bolt", vacuum: "robot", humidifier: "droplet", camera: "camera", weather: "sun"};
		if (domain === "climate" && attr(id, "hvac_action") === "heating") return "flame";
		// a motion sensor: someone moving, or the same crossed out (as mdi:motion-sensor / motion-sensor-off)
		if (domain === "binary_sensor" && deviceClass(id) === "motion") return haStates[id] && haStates[id].state === "on" ? "motion" : "motion-off";
		// a door contact: open or closed (as mdi:door-open / door-closed)
		if (domain === "binary_sensor" && deviceClass(id) === "door") return haStates[id] && haStates[id].state === "on" ? "door-open" : "door-closed";
		if (map[domain]) return map[domain];
		if (domain === "sensor" || domain === "input_number" || domain === "number") {
			if (unit === "°C" || unit === "°F") return "thermometer";
			if (unit === "%") return "droplet";
			if (unit === "W" || unit === "kW" || unit === "kWh" || unit === "Wh" || unit === "V" || unit === "A") return "bolt";
			return "gauge";
		}
		return "generic";
	}

	// Home Assistant's device_class (motion, door, …): from the state, else from the list of all entities
	function deviceClass(id) {
		var className = attr(id, "device_class");
		if (className) return className;
		var entity = allIndex[id];
		return entity ? entity.deviceClass || "" : "";
	}

	function iconUrl(id, dim) {
		var domain = domainOf(id);
		var variant = dim ? "-dim" : (isLit(id) ? "-on" : "");
		if (!dim && (domain === "person" || domain === "device_tracker") && haStates[id] && haStates[id].state === "home") variant = "-ok";
		return Qt.resolvedUrl("drawables/icons/" + iconName(id) + variant + ".svg");
	}

	// lit up (warm yellow): on, or a thermostat that is heating, a speaker that plays
	function isLit(id) {
		var domain = domainOf(id);
		var stateNow = haStates[id] ? haStates[id].state : "";
		if (domain === "climate") {
			var action = attr(id, "hvac_action");
			return action ? ["heating", "cooling", "drying", "fan"].indexOf(action) >= 0 : (stateNow !== "off" && stateNow !== "" && stateNow !== "unavailable");
		}
		if (domain === "humidifier" || domain === "fan") return stateNow === "on";
		if (domain === "binary_sensor") return stateNow === "on";          // motion, a door open, …
		if (domain === "media_player") return stateNow === "playing";
		return actionOf(id) === "toggle" && isOn(id);
	}

	// a picture of the entity from Home Assistant (a person's photo, album art), else ""
	function pictureUrl(id) {
		var path = attr(id, "entity_picture");
		if (!path) return "";
		return path.indexOf("://") > 0 ? path : haUrl + path;
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
		var domain = domainOf(id);
		if (domain === "climate") return typeof attr(id, "current_temperature") === "number";
		if (domain === "humidifier") return typeof attr(id, "current_humidity") === "number";
		if (domain !== "sensor" && domain !== "input_number" && domain !== "number") return false;
		var entry = haStates[id];
		return entry && /^-?\d+(\.\d+)?$/.test(entry.state);
	}

	// the big text of a value card
	function valueText(id) {
		var domain = domainOf(id);
		if (domain === "climate") return degrees(attr(id, "current_temperature"));
		if (domain === "humidifier") return Math.round(attr(id, "current_humidity")) + "%";
		return stateText(id);
	}

	// the small line under the name of a value card ("" = none)
	function detailText(id) {
		var domain = domainOf(id);
		var stateNow = haStates[id] ? haStates[id].state : "";
		if (domain === "climate") {
			if (stateNow === "off") return "Uit";
			var targetText = climateTargetText(id);
			var action = hvacActionText(attr(id, "hvac_action"));
			return (targetText ? "Naar " + targetText : hvacModeText(stateNow)) + (action ? " · " + action : "");
		}
		if (domain === "humidifier") {
			if (stateNow !== "on") return "Uit";
			return typeof attr(id, "humidity") === "number" ? "Naar " + Math.round(attr(id, "humidity")) + "%" : "Aan";
		}
		return "";
	}

	function degrees(value) {
		if (typeof value !== "number") return "-";
		return i18n.number(value, 1, i18n.omit_trail_zeros) + "°";
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
			try { onDone(JSON.parse(text), ""); } catch (error) { onDone(null, "onverwacht antwoord"); }
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
				try { msg = JSON.parse(xhr.responseText).message || "OK"; } catch (error) {}
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

	function jsonString(value) { return JSON.stringify(String(value)); }

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
		binary_sensor: ["device_class"],
		fan: ["percentage", "percentage_step", "preset_mode", "preset_modes", "oscillating", "direction"],
		person: ["latitude", "longitude", "gps_accuracy", "entity_picture"],
		device_tracker: ["latitude", "longitude", "gps_accuracy", "entity_picture"]
	})

	// an extra attribute of an entity (see extKeys), undefined when not fetched
	function attr(id, key) {
		var entry = haStates[id];
		return entry && entry.attrs ? entry.attrs[key] : undefined;
	}

	// the ids polled: the chosen entities and the Energie tab's
	function pollIds() {
		var out = [];
		for (var i = 0; i < entities.length; i++) out.push(entities[i].id);
		var energyList = energyIds();
		for (var j = 0; j < energyList.length; j++) if (out.indexOf(energyList[j]) < 0) out.push(energyList[j]);
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
			for (var index = 0; index < wanted.length; index++) keep[wanted[index]] = true;
			var map = {};
			var liveIsStale = false;
			for (var known in haStates) if (keep[known]) map[known] = haStates[known];
			for (var j = 0; j < list.length; j++) {
				var row = list[j];
				if (!keep[row[0]]) continue;
				var polled = {state: row[1], unit: row[2] || "", name: row[3] || "", area: row[4] || "",
					codeFormat: row[5] || "", codeArmRequired: row[6] !== false, features: row[7] || 0, light: lightInfo(row[8]),
					attrs: extAttrs(row[0], row[9]), changed: row[10] || 0};
				if (liveConnected && liveRaw[row[0]] && map[row[0]]) {
					var heldNow = holds[row[0]] && holds[row[0]].until > Date.now();
					if (polled.state === map[row[0]].state || heldNow) {
						// live is newer than a poll's answer: only the area (live doesn't send it)
						map[row[0]] = copyState(map[row[0]], {area: polled.area});
						continue;
					}
					// Home Assistant says otherwise than live did: the live connection may be dead without knowing
					// it (a sleeping computer, a router restart). The poll counts, live connects again
					liveIsStale = true;
				}
				map[row[0]] = polled;
				applyHold(map, row[0]);
			}
			var hadWeather = false;
			for (var id in map) if (domainOf(id) === "weather" && !forecasts[id]) hadWeather = true;
			haStates = map;
			if (liveIsStale) liveRestart("a poll differs from the live states");
			connected = true;
			lastError = "";
			cameraTick++;
			var now = new Date();
			if (!toonAddress) toonAddress = findToonAddress();   // the Toon may have had no address or connection at the start
			lastUpdate = ("0" + now.getHours()).slice(-2) + ":" + ("0" + now.getMinutes()).slice(-2) + ":" + ("0" + now.getSeconds()).slice(-2);
			lastDataTime = now.getTime();
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
		liveLoginTimeout.restart();
	}

	// connected, but no login within 15 seconds (a connection that is dead from the start): again
	Timer {
		id: liveLoginTimeout
		interval: 15000
		onTriggered: if (haSocket.active && !liveConnected && !liveFailed) liveRestart("no login")
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
		try { haSocket.sendTextMessage(JSON.stringify(obj)); } catch (error) {}
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
		var message;
		try { message = JSON.parse(text); } catch (error) { return; }
		liveLastMessage = Date.now();
		if (message.type === "auth_required") {
			liveSend({type: "auth", access_token: haToken});
		} else if (message.type === "auth_ok") {
			liveRetry = 0;
			liveConnected = true;
			liveSubKey = "";
			liveSubscribe();
		} else if (message.type === "auth_invalid") {
			lastError = "token ongeldig (401)";
			liveStop();
			liveReconnect.interval = 5 * 60 * 1000;
			liveReconnect.restart();
		} else if (message.type === "result" && message.id === liveSubId && !message.success) {
			// an older Home Assistant: no subscribe_entities. Polling it is
			console.log("homeassistant: no live updates (" + (message.error ? message.error.message : "?") + "), polling");
			liveFailed = true;
			liveStop();
		} else if (message.type === "event" && message.id === liveSubId && message.event) {
			applyLive(message.event);
		}
	}

	// subscribe_entities sends {a: {id: {s, a, lc}}} (everything, at first), {c: {id: {"+": {s, a, lc}, "-": {a: [keys]}}}} (changes)
	// and {r: [ids]} (removed)
	function applyLive(event) {
		var raw = liveRaw;
		var changed = [];
		var id;
		if (event.a) {
			for (id in event.a) {
				raw[id] = {s: event.a[id].s, a: event.a[id].a || {}, lc: event.a[id].lc || 0};
				changed.push(id);
			}
		}
		if (event.c) {
			for (id in event.c) {
				var change = event.c[id];
				var entry = raw[id] || {s: "", a: {}, lc: 0};
				var plus = change["+"];
				if (plus) {
					if (plus.s !== undefined) entry.s = plus.s;
					if (plus.lc !== undefined) entry.lc = plus.lc;
					if (plus.a) for (var k in plus.a) entry.a[k] = plus.a[k];
				}
				var minus = change["-"];
				if (minus && minus.a) for (var j = 0; j < minus.a.length; j++) delete entry.a[minus.a[j]];
				raw[id] = entry;
				changed.push(id);
			}
		}
		if (event.r) {
			for (var index = 0; index < event.r.length; index++) {
				raw[event.r[index]] = {s: "unavailable", a: raw[event.r[index]] ? raw[event.r[index]].a : {}, lc: 0};
				changed.push(event.r[index]);
			}
		}
		liveRaw = raw;
		lastDataTime = Date.now();                      // also when nothing visible changed: the data is current
		if (changed.length === 0) return;
		var map = haStates;
		var newWeather = false, any = false;
		for (var index = 0; index < changed.length; index++) {
			id = changed[index];
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
	function liveState(id, raw, prev) {
		var attributes = raw.a || {};
		var domain = domainOf(id);
		var keys = extKeys[domain] || [];
		var values = [];
		for (var i = 0; i < keys.length; i++) values.push(attributes[keys[i]] === undefined ? null : attributes[keys[i]]);
		var area = prev && prev.area ? prev.area : (allIndex[id] ? allIndex[id].area : "");
		return {state: raw.s, unit: attributes.unit_of_measurement || "", name: attributes.friendly_name || "", area: area || "",
			codeFormat: attributes.code_format || "", codeArmRequired: attributes.code_arm_required !== false, features: attributes.supported_features || 0,
			light: domain === "light" ? lightInfo([attributes.brightness, attributes.supported_color_modes, attributes.hs_color, attributes.color_temp_kelvin,
				attributes.min_color_temp_kelvin, attributes.max_color_temp_kelvin, attributes.color_mode]) : null,
			attrs: extAttrs(id, values), changed: domain === "person" || domain === "device_tracker" ? raw.lc || 0 : 0};
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

	// a connection can die without the socket noticing (a sleeping computer, a router or Wi-Fi gone for a
	// moment): then "live" would stay on while nothing comes in. So a ping every liveHeartbeatMs; when
	// nothing at all came back for a while, the connection counts as dead: a poll at once, and connect again
	property double liveLastMessage: 0
	property int liveHeartbeatMs: 30000

	Timer {
		id: liveHeartbeat
		interval: liveHeartbeatMs
		repeat: true
		running: liveConnected
		onTriggered: {
			if (Date.now() - liveLastMessage > liveHeartbeatMs * 2.5) liveRestart("no answer to the pings");
			else liveSend({id: liveMsgId++, type: "ping"});
		}
	}

	function liveRestart(reason) {
		console.log("homeassistant: live connection again (" + reason + ")");
		liveConnected = false;
		liveSubId = 0;
		liveSubKey = "";
		haSocket.active = false;
		liveReconnect.interval = 1000;
		liveReconnect.restart();
		pollStates();
	}

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
				var forecast = JSON.parse(text).service_response[id].forecast;
				list = [];
				for (var i = 0; i < forecast.length; i++) {
					list.push({time: parseTime(forecast[i].datetime).getTime(), condition: forecast[i].condition || "", temp: forecast[i].temperature,
						low: forecast[i].templow, rain: forecast[i].precipitation, daily: type === "daily"});
				}
			} catch (error) {}
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

	function weatherConditionText(condition) {
		return {"clear-night": "Helder", cloudy: "Bewolkt", exceptional: "Waarschuwing", fog: "Mist", hail: "Hagel",
			lightning: "Onweer", "lightning-rainy": "Onweer en regen", partlycloudy: "Half bewolkt", pouring: "Hevige regen",
			rainy: "Regen", snowy: "Sneeuw", "snowy-rainy": "Natte sneeuw", sunny: "Zonnig", windy: "Winderig",
			"windy-variant": "Winderig, bewolkt"}[condition] || condition;
	}

	function weatherIconUrl(condition) {
		var known = ["clear-night", "cloudy", "exceptional", "fog", "hail", "lightning", "lightning-rainy", "partlycloudy",
			"pouring", "rainy", "snowy", "snowy-rainy", "sunny", "windy", "windy-variant"];
		return Qt.resolvedUrl("drawables/icons/weather-" + (known.indexOf(condition) >= 0 ? condition : "cloudy") + ".svg");
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

	function setEnergy(settings) {
		energy = cleanEnergy(settings || {});
		saveSettings();
		energyHistory = {};
		energyHistUntil = 0;
		selectionChanged();
		pollStates();
		loadEnergyHistory();
		broadcastState();
	}

	function setEnergyField(key, ids) {
		var settings = copyState(energy, {});
		settings[key] = ids;
		setEnergy(settings);
	}

	function pad2(number) { return (number < 10 ? "0" : "") + number; }

	// Home Assistant's times have microseconds ("…T10:00:00.123456+00:00"): the Toon's JavaScript wants at most 3 digits
	function parseTime(text) {
		return new Date(String(text || "").replace(/(\.\d{3})\d+/, "$1"));
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
			try { res = JSON.parse(text); } catch (error) { return; }
			var map = full ? {} : copyState(energyHistory, {});
			for (var index = 0; index < res.length; index++) {
				var rows = res[index];
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
			var value = parseFloat(rows[k].state);
			if (isNaN(value)) continue;
			var time = parseTime(rows[k].last_changed || rows[k].last_updated);
			if (out.last !== null) {
				var inc = increment(out.last, value);
				// the first row is the state at the start of the period, often from earlier: it counts in this hour
				var hour = isNaN(time.getTime()) || time < midnight ? new Date().getHours() : time.getHours();
				out.today[hour] += inc;
			}
			out.last = value;
		}
		return out;
	}

	// a price's values since the last time: from its hour on
	function priceMore(hist, rows, midnight) {
		var out = {today: hist.today.slice(0), yesterday: hist.yesterday, last: hist.last, day: hist.day, price: true};
		for (var k = 0; k < rows.length; k++) {
			var value = parseFloat(rows[k].state);
			var time = parseTime(rows[k].last_changed || rows[k].last_updated);
			if (isNaN(value) || isNaN(time.getTime()) || time < midnight) continue;
			for (var hour = time.getHours(); hour < 24; hour++) out.today[hour] = value;
			out.last = value;
		}
		return out;
	}

	function zeros() { var list = []; for (var hour = 0; hour < 24; hour++) list.push(0); return list; }

	// a meter's readings -> its increments per hour, yesterday and today
	function meterHistory(rows, yesterday, midnight, day) {
		var out = {today: zeros(), yesterday: zeros(), last: null, day: day};
		for (var k = 0; k < rows.length; k++) {
			var value = parseFloat(rows[k].state);
			if (isNaN(value)) continue;
			var time = parseTime(rows[k].last_changed || rows[k].last_updated);
			if (out.last !== null && !isNaN(time.getTime())) {
				var inc = increment(out.last, value);
				if (time >= midnight) out.today[time.getHours()] += inc;
				else if (time >= yesterday) out.yesterday[time.getHours()] += inc;
			}
			out.last = value;
		}
		return out.last === null ? null : out;
	}

	// a price's values -> the price in each hour (the last value at the start of the hour, else in it), yesterday and today
	function priceHistory(rows, yesterday, midnight, day) {
		var points = [];
		for (var k = 0; k < rows.length; k++) {
			var value = parseFloat(rows[k].state);
			var time = parseTime(rows[k].last_changed || rows[k].last_updated);
			if (!isNaN(value) && !isNaN(time.getTime())) points.push({t: time.getTime(), v: value});
		}
		if (points.length === 0) return null;
		var out = {today: [], yesterday: [], last: points[points.length - 1].v, day: day, price: true};
		for (var hour = 0; hour < 48; hour++) {
			var start = yesterday.getTime() + hour * 3600 * 1000;
			var value = null;
			for (var index = 0; index < points.length; index++) {
				if (points[index].t <= start + 30 * 60 * 1000) value = points[index].v;      // the last change before half past
				else break;
			}
			if (value === null) value = points[0].v;
			(hour < 24 ? out.yesterday : out.today).push(value);
		}
		return out;
	}

	// a dynamic contract's prices for today, from the price entity's attributes when it has them:
	// Nordpool (today: [24 or 96 numbers], raw_today: [{start, value}]), ENTSO-e (prices_today: [{time, price}]),
	// others (prices: [{from|start|time, price|value}])
	function loadPriceForecast(ids) {
		var parts = [];
		for (var i = 0; i < ids.length; i++) {
			var quoted = jsonString(ids[i]);
			parts.push(quoted + ": [state_attr(" + quoted + ", 'today'), state_attr(" + quoted + ", 'raw_today'), state_attr(" + quoted + ", 'prices_today'), state_attr(" + quoted + ", 'prices')]");
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
	function priceHours(attributes) {
		if (!attributes) return null;
		var today = new Date().toDateString();
		var sums = zeros(), counts = zeros(), any = false;
		function add(hour, value) { if (typeof value === "number" && hour >= 0 && hour < 24) { sums[hour] += value; counts[hour]++; any = true; } }
		if (attributes[0] && attributes[0].length) {                       // today: [24] or [96]
			var per = attributes[0].length >= 96 ? 4 : (attributes[0].length >= 48 ? 2 : 1);
			for (var i = 0; i < attributes[0].length; i++) add(Math.floor(i / per), attributes[0][i]);
		} else {
			var lists = [attributes[1], attributes[2], attributes[3]];
			for (var index = 0; index < lists.length; index++) {
				var list = lists[index];
				if (!list || !list.length) continue;
				for (var k = 0; k < list.length; k++) {
					var item = list[k];
					var time = parseTime(item.start || item.from || item.time || item.startsAt);
					if (isNaN(time.getTime()) || time.toDateString() !== today) continue;
					add(time.getHours(), typeof item.value === "number" ? item.value : (typeof item.price === "number" ? item.price : item.total));
				}
				if (any) break;
			}
		}
		if (!any) return null;
		var out = [];
		for (var hour = 0; hour < 24; hour++) out.push(counts[hour] ? sums[hour] / counts[hour] : null);
		return out;
	}

	// a meter reading went from a to b: the use in between. A drop is a reset (a daily meter, a new meter)
	function increment(before, after) {
		if (after >= before) return after - before;
		return after < before * 0.5 ? after : 0;      // a small dip is noise of the sensor
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
			var entry = haStates[list[i]];
			var value = entry ? parseFloat(entry.state) : NaN;
			if (isNaN(value)) continue;
			sum += value * energyFactor(entry.unit, key);
			any = true;
		}
		return any ? sum : null;
	}

	// today's use of a meter field: {total, hours: [24]} in energyUnit(key); null when unknown yet
	function energyToday(key) {
		var list = energy[key] || [];
		var hours = [], any = false;
		for (var hour = 0; hour < 24; hour++) hours.push(0);
		var nowHour = new Date().getHours();
		var today = new Date().toDateString();
		for (var i = 0; i < list.length; i++) {
			var hist = energyHistory[list[i]];
			if (!hist || hist.day !== today || hist.price) continue;
			var entry = haStates[list[i]];
			var factor = energyFactor(entry ? entry.unit : "", key);
			for (var k = 0; k < 24; k++) hours[k] += hist.today[k] * factor;
			// what the meter did since the history was fetched
			var value = entry ? parseFloat(entry.state) : NaN;
			if (!isNaN(value)) hours[nowHour] += increment(hist.last, value) * factor;
			any = true;
		}
		if (!any) return null;
		var total = 0;
		for (var index = 0; index < 24; index++) total += hours[index];
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
			var entry = haStates[list[i]];
			var factor = energyFactor(entry ? entry.unit : "", key);
			for (var k = 0; k < 24; k++) hours[k] += hist.yesterday[k] * factor;
			any = true;
		}
		if (!any) return null;
		var now = new Date(), total = 0, same = 0;
		for (var hour = 0; hour < 24; hour++) {
			total += hours[hour];
			if (hour < now.getHours()) same += hours[hour];
			else if (hour === now.getHours()) same += hours[hour] * now.getMinutes() / 60;
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
			var entry = haStates[id];
			var factor = priceFactor(entry ? entry.unit : "");
			var now = entry ? parseFloat(entry.state) : NaN;
			var forecast = priceForecast[id], hist = energyHistory[id];
			for (var hour = 0; hour < 24; hour++) {
				var value = null;
				if (forecast && typeof forecast[hour] === "number") value = forecast[hour];
				else if (hist && hist.price && hist.day === today && hour <= nowHour) value = hist.today[hour];
				if (hour === nowHour && !isNaN(now) && !(forecast && typeof forecast[hour] === "number")) value = now;
				if (value === null && !isNaN(now)) value = now;             // a fixed tariff: the same all day
				if (value !== null) { out[hour] += value * factor; any = true; }
			}
		}
		return any ? out : null;
	}

	function priceNow(key) {
		var prices = priceToday(key);
		return prices ? prices[new Date().getHours()] : null;
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
			var priceUse = priceToday("priceUsage"), priceBack = priceToday("priceExport") || priceUse;
			if (!priceUse || (!use && !back)) return null;
			for (var hour = 0; hour < 24; hour++) {
				if (use) cost += use.hours[hour] * priceUse[hour];
				if (back && priceBack) cost -= back.hours[hour] * priceBack[hour];
			}
			return cost;
		}
		var key = panel === "gas" ? "gas" : "water";
		var today = energyToday(key), prices = priceToday(panel === "gas" ? "priceGas" : "priceWater");
		if (!today || !prices) return null;
		var perUnit = key === "water" ? 0.001 : 1;         // water is in litres, its price per m³
		for (var k = 0; k < 24; k++) cost += today.hours[k] * perUnit * prices[k];
		return cost;
	}

	function euro(value, digits) {
		if (value === null || value === undefined) return "-";
		return (value < 0 ? "− " : "") + "€ " + i18n.number(Math.abs(value), digits === undefined ? 2 : digits, 0);
	}

	function energyNumber(value, key) {
		if (value === null || value === undefined) return "-";
		var unit = energyUnit(key);
		if (unit === "W" && Math.abs(value) >= 1000) return i18n.number(value / 1000, 2, i18n.omit_trail_zeros) + " kW";
		var digits = unit === "W" || unit === "L" ? 0 : (Math.abs(value) >= 100 ? 0 : (Math.abs(value) >= 10 ? 1 : 2));
		return i18n.number(value, digits, i18n.omit_trail_zeros) + " " + unit;
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
			var row = rows[i];
			var entity = {id: row[0], name: row[1] || "", area: row[2] || "", state: row[3], domain: row[0].split(".")[0], unit: row[4] || "", deviceClass: row[5] || ""};
			list.push(entity);
			index[entity.id] = entity;
		}
		list.sort(function(first, second) { return first.id < second.id ? -1 : (first.id > second.id ? 1 : 0); });
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
		} catch (error) {}
	}

	// forget the cached list (file and memory) and fetch it again from Home Assistant: e.g. after renaming
	// or moving entities in Home Assistant. The web editor's copy goes too: its version no longer matches.
	function clearEntitiesCache() {
		try { entitiesCache.write(""); } catch (error) {}
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
			var cache = JSON.parse(entitiesCache.read());
			if (!cache || cache.url !== haUrl || !cache.rows) return -1;
			setAllEntities(cache.rows, cache.areas || [], cache.time || 0);
			return new Date().getTime() - (cache.time || 0);
		} catch (error) {
			return -1;
		}
	}

	// ======================================================================
	// switching
	// ======================================================================

	function domainOf(id) { return id.split(".")[0]; }

	// what a tap on the entity does: "toggle", "press", "run" or "" (read only)
	function actionOf(id) {
		var domain = domainOf(id);
		if (["light", "switch", "input_boolean", "automation", "siren", "cover", "lock", "vacuum", "group"].indexOf(domain) >= 0) return "toggle";
		if (["fan", "climate", "humidifier", "media_player", "camera", "person", "device_tracker"].indexOf(domain) >= 0) return "open";
		if (domain === "button" || domain === "input_button") return "press";
		if (domain === "script" || domain === "scene") return "run";
		if (domain === "alarm_control_panel") return "alarm";
		return "";
	}

	function isOn(id) {
		var stateNow = haStates[id] ? haStates[id].state : "";
		return ["on", "open", "opening", "unlocked", "playing", "heat", "cool", "heat_cool", "auto", "cleaning", "home"].indexOf(stateNow) >= 0;
	}

	function activate(id) {
		var domain = domainOf(id);
		if (domain === "alarm_control_panel") { openAlarm(id); return; }
		if (actionOf(id) === "open") { openDetail(id); return; }
		var wasOn = isOn(id);
		var service = "";
		if (domain === "button" || domain === "input_button") service = "press";
		else if (domain === "script" || domain === "scene") service = "turn_on";
		else if (domain === "lock") service = wasOn ? "lock" : "unlock";
		else if (domain === "cover") service = wasOn ? "close_cover" : "open_cover";
		else if (domain === "vacuum") { service = wasOn ? "turn_off" : "turn_on"; }
		// on or off as the card shows it, not "toggle": a lamp that is still fading out is "on" for Home Assistant,
		// so off-and-at-once-on again would switch it off a second time
		else if (actionOf(id) === "toggle") service = wasOn ? "turn_off" : "turn_on";
		if (!service) return;
		if (domain === "vacuum" && service === "turn_on") service = "start";
		if (domain === "vacuum" && service === "turn_off") service = "return_to_base";

		// show the new state at once, HA's answer follows with the next poll
		if (actionOf(id) === "toggle" && haStates[id]) {
			var map = haStates;
			var guess = {lock: wasOn ? "locked" : "unlocked", cover: wasOn ? "closing" : "opening"}[domain] || (wasOn ? "off" : "on");
			var before = map[id].state;
			map[id] = copyState(map[id], {state: guess});
			haStates = map;
			hold(id, before);
			statesUpdated();
		}
		request("POST", "/api/services/" + domain + "/" + service, {entity_id: id}, function(text, err) {
			if (text === null) { lastError = "Schakelen mislukt: " + err; release(id); }
			actionResult(id, text !== null, text !== null ? "" : friendlyError(err));
			refreshSoon.restart();
		});
	}

	function stateText(id) {
		var entry = haStates[id];
		if (!entry) return connected ? "?" : "";
		var value = entry.state;
		if (value === "unavailable") return "n.b.";
		if (value === "unknown") return "-";
		var domain = domainOf(id);
		if (domain === "script" || domain === "scene" || domain === "button" || domain === "input_button") return "";
		if (domain === "alarm_control_panel") return alarmStateText(value);
		if (domain === "binary_sensor" && (value === "on" || value === "off")) {
			var className = deviceClass(id);
			if (className === "motion") return value === "on" ? "Beweging" : "Geen beweging";
			if (className === "door" || className === "window" || className === "opening" || className === "garage_door") return value === "on" ? "Open" : "Dicht";
		}
		if (domain === "climate") {
			var cur = attr(id, "current_temperature"), target = climateTargetText(id);
			if (value === "off") return (typeof cur === "number" ? degrees(cur) + " · " : "") + "Uit";
			return (typeof cur === "number" ? degrees(cur) : hvacModeText(value)) + (target ? " → " + target : "");
		}
		if (domain === "humidifier") {
			var hum = attr(id, "current_humidity");
			if (value !== "on") return (typeof hum === "number" ? Math.round(hum) + "% · " : "") + "Uit";
			return (typeof hum === "number" ? Math.round(hum) + "%" : "Aan") + (typeof attr(id, "humidity") === "number" ? " → " + Math.round(attr(id, "humidity")) + "%" : "");
		}
		if (domain === "weather") return (typeof attr(id, "temperature") === "number" ? degrees(attr(id, "temperature")) + " " : "") + weatherConditionText(value);
		if (domain === "media_player") {
			if (value === "playing" || value === "paused") {
				var title = attr(id, "media_title");
				return (value === "paused" ? "Pauze" : "Speelt") + (title ? ": " + title : "");
			}
			return {off: "Uit", on: "Aan", idle: "Inactief", standby: "Stand-by", buffering: "Laden…"}[value] || value;
		}
		if (domain === "camera") return {idle: "Inactief", recording: "Neemt op", streaming: "Live"}[value] || value;
		if (domain === "person" || domain === "device_tracker") return value === "home" ? "Thuis" : (value === "not_home" ? "Weg" : value);
		var words = {on: "Aan", off: "Uit", open: "Open", closed: "Dicht", opening: "Gaat open", closing: "Gaat dicht",
			locked: "Op slot", unlocked: "Open", home: "Thuis", not_home: "Weg", playing: "Speelt", paused: "Pauze",
			idle: "Inactief", heat: "Verwarmen", cool: "Koelen", auto: "Auto", detected: "Gedetecteerd", clear: "Vrij"};
		if (domain === "light" && value === "on" && entry.light && entry.light.dimmable && entry.light.brightness > 0) return "Aan " + lightPercent(id) + "%";
		if (domain === "fan" && value === "on") {
			var pct = attr(id, "percentage"), preset = attr(id, "preset_mode");
			if (typeof pct === "number" && pct > 0 && fanSupports(id, "speed")) return "Aan " + Math.round(pct) + "%";
			return preset ? "Aan · " + presetText(preset) : "Aan";
		}
		if (words[value] && entry.unit === "") return words[value];
		var number = parseFloat(value);
		if (/^-?\d+(\.\d+)?$/.test(value)) {
			var digits = Math.abs(number) >= 100 ? 0 : (Math.abs(number) >= 10 ? 1 : 2);
			if (number === Math.round(number)) digits = 0;
			return i18n.number(number, digits, i18n.omit_trail_zeros) + (entry.unit ? " " + entry.unit : "");
		}
		return value + (entry.unit ? " " + entry.unit : "");
	}

	// ======================================================================
	// alarm panels (alarm_control_panel)
	// ======================================================================

	function alarmStateText(value) {
		return {disarmed: "Uitgeschakeld", armed_home: "Aan (thuis)", armed_away: "Aan (afwezig)", armed_night: "Aan (nacht)",
			armed_vacation: "Aan (vakantie)", armed_custom_bypass: "Aan (aangepast)", pending: "Vertraging…", arming: "Inschakelen…",
			disarming: "Uitschakelen…", triggered: "ALARM!"}[value] || value;
	}

	function isArmed(id) {
		var stateNow = haStates[id] ? haStates[id].state : "";
		return stateNow.indexOf("armed_") === 0 || stateNow === "triggered" || stateNow === "pending" || stateNow === "arming";
	}

	// the modes the panel offers (HA's supported_features): [{mode, label}], always "disarm" last
	function alarmModes(id) {
		var features = haStates[id] ? haStates[id].features : 0;
		var all = [{bit: 2, mode: "arm_away", label: "Afwezig"}, {bit: 1, mode: "arm_home", label: "Thuis"},
			{bit: 4, mode: "arm_night", label: "Nacht"}, {bit: 32, mode: "arm_vacation", label: "Vakantie"},
			{bit: 16, mode: "arm_custom_bypass", label: "Aangepast"}];
		var out = [];
		for (var i = 0; i < all.length; i++) if (features & all[i].bit) out.push({mode: all[i].mode, label: all[i].label});
		if (out.length === 0) out.push({mode: "arm_away", label: "Afwezig"}, {mode: "arm_home", label: "Thuis"});   // features unknown
		out.push({mode: "disarm", label: "Uitschakelen"});
		return out;
	}

	// "" = no code, "number" = keypad, "text" = keyboard
	function alarmCodeFormat(id) { return haStates[id] ? haStates[id].codeFormat : ""; }

	function alarmNeedsCode(id, mode) {
		var entry = haStates[id];
		if (!entry || !entry.codeFormat) return false;
		return mode === "disarm" || entry.codeArmRequired;
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
		var list = holds;
		var keep = list[id] && list[id].until > Date.now() ? list[id].before : before;    // quick taps: the state before the first
		list[id] = {entry: haStates[id], before: keep, until: Date.now() + holdMs};
		holds = list;
	}

	function release(id) {
		var list = holds;
		delete list[id];
		holds = list;
	}

	// in a poll's answer: keep the held state while HA still reports the old one
	function applyHold(map, id) {
		var held = holds[id];
		if (!held) return;
		var haState = map[id].state, expected = held.entry ? held.entry.state : haState;
		var done = Date.now() >= held.until || !held.entry
			|| (expected !== held.before && (haState === expected || (["cover", "lock"].indexOf(domainOf(id)) >= 0 && haState !== held.before)));
		// expected === before (a brightness or volume change, or off and on again): held until the time is up
		if (done) release(id);
		else map[id] = held.entry;
	}

	function copyState(source, changes) {
		var out = {};
		for (var k in source) out[k] = source[k];
		for (var key in changes) out[key] = changes[key];
		return out;
	}

	// HA's light attributes -> what the light screen needs; null for other domains
	function lightInfo(attributes) {
		if (!attributes) return null;
		var modes = attributes[1] || [];
		var colorModes = ["hs", "xy", "rgb", "rgbw", "rgbww"];
		var color = false, dimmable = false;
		for (var i = 0; i < modes.length; i++) {
			if (colorModes.indexOf(modes[i]) >= 0) color = true;
			if (modes[i] !== "onoff") dimmable = true;
		}
		return {brightness: attributes[0] || 0, dimmable: dimmable, color: color, colorTemp: modes.indexOf("color_temp") >= 0,
			hue: attributes[2] ? attributes[2][0] : 0, saturation: attributes[2] ? attributes[2][1] : 0, kelvin: attributes[3] || 0,
			minKelvin: attributes[4] || 2000, maxKelvin: attributes[5] || 6500, colorMode: attributes[6] || ""};
	}

	function lightOf(id) { return haStates[id] ? haStates[id].light : null; }

	function lightPercent(id) {
		var light = lightOf(id);
		return light ? Math.max(1, Math.round(light.brightness / 2.55)) : 0;
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
		var domain = domainOf(id);
		var url = {fan: fanScreenUrl, climate: climateScreenUrl, humidifier: climateScreenUrl, media_player: mediaScreenUrl, camera: cameraScreenUrl,
			person: personScreenUrl, device_tracker: personScreenUrl}[domain];
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

	function hvacModeText(mode) {
		return {off: "Uit", heat: "Verwarmen", cool: "Koelen", heat_cool: "Verwarmen/koelen", auto: "Automatisch",
			dry: "Drogen", fan_only: "Ventileren"}[mode] || mode;
	}

	function hvacActionText(action) {
		return {heating: "verwarmt", cooling: "koelt", idle: "rust", drying: "droogt", fan: "ventileert", preheating: "voorverwarmen",
			defrosting: "ontdooit"}[action] || "";
	}

	function presetText(preset) {
		return {none: "Geen", eco: "Eco", away: "Weg", boost: "Boost", comfort: "Comfort", home: "Thuis", sleep: "Slapen",
			activity: "Actief", normal: "Normaal", baby: "Baby", auto: "Auto"}[preset] || (preset ? preset.charAt(0).toUpperCase() + preset.substring(1) : preset);
	}

	// "20,5°", or "19°–23°" for a range (heat_cool); "" when the thermostat has no target
	function climateTargetText(id) {
		var target = attr(id, "temperature");
		if (typeof target === "number") return degrees(target);
		var low = attr(id, "target_temp_low"), high = attr(id, "target_temp_high");
		if (typeof low === "number" && typeof high === "number") return degrees(low) + "–" + degrees(high);
		return "";
	}

	function climateSetTemperature(id, temperature) { service(id, "climate", "set_temperature", {temperature: temperature}, null, {temperature: temperature}); }
	function climateSetRange(id, low, high) {
		service(id, "climate", "set_temperature", {target_temp_low: low, target_temp_high: high}, null, {target_temp_low: low, target_temp_high: high});
	}
	function climateSetMode(id, mode) { service(id, "climate", "set_hvac_mode", {hvac_mode: mode}, mode, null); }
	function climateSetPreset(id, preset) { service(id, "climate", "set_preset_mode", {preset_mode: preset}, null, {preset_mode: preset}); }

	// a fan's features (HA's supported_features bits)
	function fanSupports(id, what) {
		var features = haStates[id] ? haStates[id].features : 0;
		var bits = {speed: 1, oscillate: 2, direction: 4, preset: 8};
		return (features & bits[what]) !== 0;
	}
	// more than on/off: the card gets the tune button, holding it opens the fan screen
	function fanAdjustable(id) {
		return domainOf(id) === "fan" && (fanSupports(id, "speed") || fanSupports(id, "oscillate") || fanSupports(id, "direction")
			|| (fanSupports(id, "preset") && (attr(id, "preset_modes") || []).length > 0));
	}
	function fanStep(id) {
		var step = attr(id, "percentage_step");
		return typeof step === "number" && step > 0 ? step : 10;
	}
	// percent 0..100 (0 switches off), rounded to the fan's own steps
	function fanSetPercentage(id, pct) {
		var step = fanStep(id);
		pct = Math.max(0, Math.min(100, Math.round(Math.round(pct / step) * step)));
		service(id, "fan", "set_percentage", {percentage: pct}, pct > 0 ? "on" : "off", {percentage: pct});
	}
	function fanSetPreset(id, preset) { service(id, "fan", "set_preset_mode", {preset_mode: preset}, "on", {preset_mode: preset}); }
	function fanOscillate(id, oscillating) { service(id, "fan", "oscillate", {oscillating: oscillating}, null, {oscillating: oscillating}); }
	function fanDirection(id, dir) { service(id, "fan", "set_direction", {direction: dir}, null, {direction: dir}); }
	function fanPower(id, turnOn) { service(id, "fan", turnOn ? "turn_on" : "turn_off", {}, turnOn ? "on" : "off", null); }
	function openFan(id) { stage.openFullscreen(fanScreenUrl, {entityId: id}); }

	function humidifierSetHumidity(id, humidity) { service(id, "humidifier", "set_humidity", {humidity: humidity}, null, {humidity: humidity}); }
	function humidifierSetMode(id, mode) { service(id, "humidifier", "set_mode", {mode: mode}, null, {mode: mode}); }
	function humidifierPower(id, turnOn) { service(id, "humidifier", turnOn ? "turn_on" : "turn_off", {}, turnOn ? "on" : "off", null); }

	// a speaker's features (HA's supported_features bits)
	function mediaSupports(id, what) {
		var features = haStates[id] ? haStates[id].features : 0;
		var bits = {pause: 1, volume: 4, mute: 8, previous: 16, next: 32, on: 128, off: 256, step: 1024, source: 2048, stop: 4096, play: 16384};
		return (features & bits[what]) !== 0;
	}

	function mediaPlayPause(id) {
		var playing = haStates[id] && haStates[id].state === "playing";
		service(id, "media_player", "media_play_pause", {}, playing ? "paused" : "playing", null);
	}
	function mediaNext(id) { service(id, "media_player", "media_next_track", {}, null, null); }
	function mediaPrevious(id) { service(id, "media_player", "media_previous_track", {}, null, null); }
	function mediaPower(id, turnOn) { service(id, "media_player", turnOn ? "turn_on" : "turn_off", {}, turnOn ? "on" : "off", null); }
	function mediaSetVolume(id, volume) {
		volume = Math.round(Math.max(0, Math.min(1, volume)) * 100) / 100;
		service(id, "media_player", "volume_set", {volume_level: volume}, null, {volume_level: volume});
	}
	function mediaVolumeStep(id, louder) {
		var volume = attr(id, "volume_level");
		if (typeof volume === "number" && mediaSupports(id, "volume")) mediaSetVolume(id, volume + (louder ? 0.05 : -0.05));
		else service(id, "media_player", louder ? "volume_up" : "volume_down", {}, null, null);
	}
	function mediaMute(id) {
		var muted = attr(id, "is_volume_muted") === true;
		service(id, "media_player", "volume_mute", {is_volume_muted: !muted}, null, {is_volume_muted: !muted});
	}
	function mediaSource(id, source) { service(id, "media_player", "select_source", {source: source}, null, {source: source}); }
	function mediaIsOff(id) {
		var stateNow = haStates[id] ? haStates[id].state : "";
		return stateNow === "off" || stateNow === "standby" || stateNow === "unavailable" || stateNow === "";
	}

	// a camera's still image: Home Assistant's camera proxy (entity_picture holds a token), with a new
	// number each time so it is fetched again
	property int cameraTick: 0
	// animated: a moving picture (a rain radar): not fetched again every few seconds, only when Home
	// Assistant gives a new token in entity_picture (about every 5 minutes), and it plays in between
	function cameraUrl(id, animated) {
		var path = attr(id, "entity_picture");
		if (!path) return "";
		if (animated) return haUrl + path;
		return haUrl + path + (path.indexOf("?") >= 0 ? "&" : "?") + "t=" + cameraTick;
	}

	// "bijgewerkt 10:42" (today) / "bijgewerkt 14-11 10:42": when data last came in; "" before the first
	function lastDataText() {
		if (!lastDataTime) return "";
		var dataTime = new Date(lastDataTime), now = new Date();
		var clockTime = pad2(dataTime.getHours()) + ":" + pad2(dataTime.getMinutes());
		var dayPart = dataTime.toDateString() === now.toDateString() ? "" : dataTime.getDate() + "-" + (dataTime.getMonth() + 1) + " ";
		return (connected ? "bijgewerkt " : "laatst bijgewerkt ") + dayPart + clockTime;
	}

	// "sinds 14:05" / "sinds gisteren" for a person's state
	function sinceText(id) {
		var changed = haStates[id] ? haStates[id].changed : 0;
		if (!changed) return "";
		var time = new Date(changed * 1000), now = new Date();
		var clock = pad2(time.getHours()) + ":" + pad2(time.getMinutes());
		if (time.toDateString() === now.toDateString()) return "sinds " + clock;
		var yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
		if (time.toDateString() === yesterday.toDateString()) return "sinds gisteren " + clock;
		return "sinds " + time.getDate() + "-" + (time.getMonth() + 1) + " " + clock;
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
			try { old = pageTarget.read(); } catch (error) {}
			if (old !== page) pageTarget.write(page);
		} catch (error) {
			console.log("homeassistant: could not publish the web editor: " + error);
		}
	}

	// the Toon's firewall lets only known ports in: add ours (active after "Flush firewall rules" or a reboot)
	function openFirewallPort() {
		try {
			var conf = iptablesFile.read();
			if (!conf || conf.indexOf("--dport " + webPort + " ") >= 0) return;
			var rule = "-A HCB-INPUT -p tcp -m tcp --dport " + webPort + " --tcp-flags SYN,RST,ACK SYN -j ACCEPT\n";
			var position = conf.indexOf("-A HCB-INPUT -p tcp -m tcp --tcp-flags SYN,RST,ACK SYN -j DROP");
			if (position < 0) return;
			iptablesFile.write(conf.substring(0, position) + rule + conf.substring(position));
			console.log("homeassistant: port " + webPort + " added to iptables.conf (active after \"Flush firewall rules\" or a reboot)");
		} catch (error) {}
	}

	// the Toon's own IP address: from the kernel's address list, else from a connection it has open
	function findToonAddress() {
		// /proc/net/fib_trie: "|-- 192.168.1.23" followed by "/32 host LOCAL"
		try {
			var fib = fibFile.read().split("\n");
			for (var line = 1; line < fib.length; line++) {
				if (fib[line].indexOf("/32 host LOCAL") < 0) continue;
				var match = fib[line - 1].match(/(\d+)\.(\d+)\.(\d+)\.(\d+)\s*$/);
				if (match && match[1] !== "127" && match[1] !== "0") return match[1] + "." + match[2] + "." + match[3] + "." + match[4];
			}
		} catch (error) {}
		try {
			var lines = tcpFile.read().split("\n");
			for (var i = 1; i < lines.length; i++) {
				var parts = lines[i].trim().split(/\s+/);
				if (parts.length < 4 || parts[3] !== "01") continue;      // established connections know our address
				var hex = parts[1].split(":")[0];
				if (hex.length !== 8) continue;
				var address = [parseInt(hex.substr(6, 2), 16), parseInt(hex.substr(4, 2), 16), parseInt(hex.substr(2, 2), 16), parseInt(hex.substr(0, 2), 16)];
				if (address[0] === 127 || address[0] === 0) continue;
				return address.join(".");
			}
		} catch (error) {}
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
		} catch (error) {}
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
		var message;
		try { message = JSON.parse(text); } catch (error) { return; }
		if (message.type === "get") {
			sendTo(socket, stateMessage());
		} else if (message.type === "entities") {
			// the page has a copy of this version (its browser keeps it): no need to send 100 kB again
			if (message.version === allVersion && allVersion > 0) sendTo(socket, JSON.stringify({type: "entities", app: "homeassistantExtended", version: allVersion, same: true}));
			else if (allMessage) sendTo(socket, allMessage);
		} else if (message.type === "clearCache") {
			clearEntitiesCache();
		} else if (message.type === "refresh") {
			loadAllEntities();
			sendTo(socket, stateMessage());
		} else if (message.type === "test") {
			testConnection(message.url || haUrl, message.token || haToken, function(ok, msg) {
				sendTo(socket, JSON.stringify({type: "test", ok: ok, message: msg}));
			});
		} else if (message.type === "connection") {
			setConnection(message.url, message.token);
		} else if (message.type === "save") {
			// answer first, then the work (saving, the screens): the page doesn't wait for the slow part
			sendTo(socket, JSON.stringify({type: "saved"}));
			pendingSave = message;
			saveLater.restart();
		}
	}

	property var pendingSave: null
	Timer {
		id: saveLater
		interval: 50
		onTriggered: {
			var save = pendingSave;
			pendingSave = null;
			if (!save) return;
			if (save.sortMode) sortMode = save.sortMode;
			if (save.systray !== undefined) enableSystray = save.systray === true;
			if (save.areaOrder) areaOrder = save.areaOrder;
			if (typeof save.defaultTab === "string") defaultTab = save.defaultTab;
			if (save.tileEntities) tileEntities = cleanTile(save.tileEntities);
			if (save.energy) {
				energy = cleanEnergy(save.energy);
				energyHistory = {};
				energyHistUntil = 0;
				loadEnergyHistory();
			}
			setEntities(save.entities || []);
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
