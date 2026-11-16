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
	property HomeassistantTimerScreen homeassistantTimerScreen
	property url timerScreenUrl: "HomeassistantTimerScreen.qml"
	property HomeassistantInputScreen homeassistantInputScreen
	property url inputScreenUrl: "HomeassistantInputScreen.qml"
	property HomeassistantTileSetupScreen homeassistantTileSetupScreen
	property url tileSetupScreenUrl: "HomeassistantTileSetupScreen.qml"
	property HomeassistantEnergySetupScreen homeassistantEnergySetupScreen
	property url energySetupScreenUrl: "HomeassistantEnergySetupScreen.qml"
	property HomeassistantAreaSetupScreen homeassistantAreaSetupScreen
	property url areaSetupScreenUrl: "HomeassistantAreaSetupScreen.qml"

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
	// per area the sensors whose temperature and humidity show under the area's name on its tab ("" is Overig)
	property variant areaSensors: ({})        // {area: {temperature: entity id, humidity: entity id}}
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

	// ---- the parts in their own files: they work on this app's properties and call its functions ----
	property alias live: liveConnection         // HaLive.qml: live updates over Home Assistant's WebSocket API
	property alias energyData: energyModel      // HaEnergy.qml: the Energie tab's history, prices and costs
	HaLive { id: liveConnection }
	HaEnergy { id: energyModel }

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
		registry.registerWidget("screen", inputScreenUrl, this, "homeassistantInputScreen");
		registry.registerWidget("screen", timerScreenUrl, this, "homeassistantTimerScreen");
		registry.registerWidget("screen", energySetupScreenUrl, this, "homeassistantEnergySetupScreen");
		registry.registerWidget("screen", tileSetupScreenUrl, this, "homeassistantTileSetupScreen");
		registry.registerWidget("screen", areaSetupScreenUrl, this, "homeassistantAreaSetupScreen");
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
			live.liveStart();
			if (cacheAge < 0 || cacheAge > allMaxAgeHours * 3600 * 1000) loadAllEntities();
			energyData.loadEnergyHistory();
		}
	}

	onEntitiesChanged: {
		var map = {};
		for (var index = 0; index < entities.length; index++) map[entities[index].id] = index;
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
			areaSensors = cleanAreaSensors(saved.areaSensors || {});
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
			areaSensors: areaSensors,
			energy: energy,
			mapTileUrl: mapTileUrl,
			webPort: webPort
		}, null, 1));
	}

	property variant energyKeys: ["power", "usage", "export", "solarPower", "solar", "gas", "water", "priceUsage", "priceExport", "priceGas", "priceWater"]

	function cleanEnergy(source) {
		var out = {};
		for (var index = 0; index < energyKeys.length; index++) {
			var fieldKey = energyKeys[index];
			var list = source[fieldKey] || [];
			if (typeof list === "string") list = list ? [list] : [];
			var ids = [];
			for (var innerIndex = 0; innerIndex < list.length; innerIndex++) if (list[innerIndex] && ids.indexOf(String(list[innerIndex])) < 0) ids.push(String(list[innerIndex]));
			out[fieldKey] = ids;
		}
		return out;
	}

	function cleanEntities(list) {
		var out = [];
		var seen = {};
		for (var index = 0; index < list.length; index++) {
			var entity = list[index];
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
		live.liveStop();
		if (isConfigured()) {
			live.liveStart();
			pollStates();
			loadAllEntities();
		}
		broadcastState();
	}

	// ======================================================================
	// the chosen entities
	// ======================================================================

	function indexOf(id) {
		var index = chosenIndex[id];
		return index === undefined ? -1 : index;
	}

	function isSelected(id) { return indexOf(id) >= 0; }

	// a whole new selection (the web editor's save): saved and polled at once
	function setEntities(list) {
		entities = cleanEntities(list);
		saveSoon.stop();
		pollSoon.stop();
		saveSettings();
		selectionChanged();
		pollStates();
		broadcastState();
	}

	// a tap on the Toon (a tick, a star, a name): the screens follow at once, the settings file and the poll
	// a moment after the last tap. Ten ticks in a row are one write to the Toon's flash and one request
	function changeEntities(list) {
		entities = cleanEntities(list);
		selectionChanged();
		saveSettingsSoon();
		pollSoon.restart();
		broadcastState();
	}

	function saveSettingsSoon() { saveSoon.restart(); }

	Timer { id: saveSoon; interval: 2000; onTriggered: saveSettings() }
	Timer { id: pollSoon; interval: 700; onTriggered: pollStates() }
	// the GUI stops (a restart) while a save is still waiting: written now
	Component.onDestruction: if (saveSoon.running) saveSettings()

	function toggleSelected(id) {
		var list = entities.slice(0);
		var position = indexOf(id);
		if (position >= 0) list.splice(position, 1); else list.push({id: id, name: "", fav: false});
		changeEntities(list);
	}

	function toggleFavourite(id) {
		var list = entities.slice(0);
		var position = indexOf(id);
		if (position < 0) return;
		list[position] = {id: list[position].id, name: list[position].name, fav: !list[position].fav};
		changeEntities(list);
	}

	function rename(id, name) {
		var list = entities.slice(0);
		var position = indexOf(id);
		if (position < 0) return;
		list[position] = {id: list[position].id, name: (name || "").trim(), fav: list[position].fav};
		changeEntities(list);
	}

	function setSortMode(mode) { sortMode = mode; saveSettingsSoon(); selectionChanged(); }
	function setFavouritesOnly(enabled) { favouritesOnly = enabled; saveSettingsSoon(); selectionChanged(); }
	function setSystray(enabled) { enableSystray = enabled; saveSettings(); broadcastState(); }

	// the name to show: your own, else HA's friendly name, else the entity id
	function displayName(id) {
		var index = indexOf(id);
		if (index >= 0 && entities[index].name) return entities[index].name;
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
		for (var index = 0; index < entities.length; index++) {
			var entity = entities[index];
			if (onlyFavs && !entity.fav) continue;
			var area = areaOf(entity.id);
			out.push({id: entity.id, name: displayName(entity.id), area: area, fav: entity.fav, order: index,
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
		var index = areaNames.indexOf(area);
		return index >= 0 ? 1000 + index : 50000 + area.toLowerCase().charCodeAt(0);
	}

	// ======================================================================
	// the main screen: tabs per area, icons
	// ======================================================================

	property variant currentTab: null         // the tab the main screen showed last (not saved); null = none yet ("" is Overig)

	// [{key, label}]: Favorieten (when there are any), HA's areas that have chosen entities, then Overig
	function tabList() {
		var out = [];
		var hasFav = false, hasNoArea = false, used = {};
		for (var entityIndex = 0; entityIndex < entities.length; entityIndex++) {
			if (entities[entityIndex].fav) hasFav = true;
			var first = areaOf(entities[entityIndex].id);
			if (first) used[first] = true; else hasNoArea = true;
		}
		if (hasFav) out.push({key: "*fav", label: "Favorieten"});
		if (energyData.energyConfigured()) out.push({key: "*energy", label: "Energie"});
		var areas = [];
		for (var usedArea in used) areas.push(usedArea);
		if (hasNoArea) areas.push("");                // Overig: last, unless you moved it
		areas.sort(function(first, second) { return (areaRank(first) - areaRank(second)) || (first < second ? -1 : (first > second ? 1 : 0)); });
		for (var index = 0; index < areas.length; index++) out.push({key: areas[index], label: areas[index] || "Overig"});
		return out;
	}

	// ---- per area: a temperature and a humidity sensor ----

	property variant areaSensorKinds: ["temperature", "humidity"]

	function cleanAreaSensors(source) {
		var out = {};
		for (var area in source) {
			var sensors = source[area] || {};
			var kept = {}, any = false;
			for (var kindIndex = 0; kindIndex < areaSensorKinds.length; kindIndex++) {
				var kind = areaSensorKinds[kindIndex];
				if (typeof sensors[kind] === "string" && sensors[kind] !== "") { kept[kind] = sensors[kind]; any = true; }
			}
			if (any) out[area] = kept;
		}
		return out;
	}

	function areaSensorIds() {
		var out = [];
		for (var area in areaSensors) {
			for (var kindIndex = 0; kindIndex < areaSensorKinds.length; kindIndex++) {
				var id = areaSensors[area][areaSensorKinds[kindIndex]];
				if (id && out.indexOf(id) < 0) out.push(id);
			}
		}
		return out;
	}

	function areaSensor(area, kind) {
		var sensors = areaSensors[area || ""];
		return sensors && sensors[kind] ? sensors[kind] : "";
	}

	// id "" = none
	function setAreaSensor(area, kind, id) {
		var settings = {};
		for (var key in areaSensors) settings[key] = copyState(areaSensors[key], {});
		if (!settings[area || ""]) settings[area || ""] = {};
		settings[area || ""][kind] = id;
		areaSensors = cleanAreaSensors(settings);
		saveSettings();
		selectionChanged();
		pollStates();
		broadcastState();
	}

	// does the entity fit as an area's temperature / humidity: its device class, or else its unit
	function fitsAreaSensor(entity, kind) {
		if (!entity) return false;
		if (kind === "temperature") return entity.deviceClass === "temperature" || (!entity.deviceClass && ["°C", "°F", "K"].indexOf(entity.unit) >= 0);
		return entity.deviceClass === "humidity" || (!entity.deviceClass && entity.unit === "%" && /humid|vocht/i.test(entity.id + " " + entity.name));
	}

	// "21,3°" / "54%" ("" when there is no sensor or no number yet)
	function areaSensorText(area, kind) {
		var id = areaSensor(area, kind);
		var entry = id ? haStates[id] : null;
		if (!entry || !/^-?\d+(\.\d+)?$/.test(entry.state)) return "";
		var value = parseFloat(entry.state);
		if (kind === "temperature") return entry.unit === "°F" ? i18n.number(value, 0, i18n.omit_trail_zeros) + "°F" : degrees(value);
		return Math.round(value) + "%";
	}

	// the line under an area's name: "21,3° · 54%"
	function areaClimateText(area) {
		var parts = [];
		for (var kindIndex = 0; kindIndex < areaSensorKinds.length; kindIndex++) {
			var text = areaSensorText(area, areaSensorKinds[kindIndex]);
			if (text) parts.push(text);
		}
		return parts.join(" · ");
	}

	// the areas you can give sensors: the area tabs (with chosen entities), then HA's other areas
	function sensorAreaList() {
		var out = [], seen = {};
		var tabs = tabList();
		for (var index = 0; index < tabs.length; index++) {
			if (tabs[index].key.charAt(0) === "*") continue;
			out.push({key: tabs[index].key, label: tabs[index].label});
			seen[tabs[index].key] = true;
		}
		for (var areaIndex = 0; areaIndex < areaNames.length; areaIndex++) {
			if (seen[areaNames[areaIndex]]) continue;
			out.push({key: areaNames[areaIndex], label: areaNames[areaIndex]});
			seen[areaNames[areaIndex]] = true;
		}
		for (var savedArea in areaSensors) if (!seen[savedArea]) out.push({key: savedArea, label: savedArea || "Overig"});
		return out;
	}

	// the choices for the tab to open on: [{key, label}]
	function defaultTabChoices() {
		return [{key: "*last", label: "Laatst gekozen"}].concat(tabList());
	}

	function defaultTabLabel() {
		var list = defaultTabChoices();
		for (var index = 0; index < list.length; index++) if (list[index].key === defaultTab) return list[index].label;
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
		for (var index = 0; index < entities.length; index++) {
			var entity = entities[index];
			if (key === "*fav" ? entity.fav : areaOf(entity.id) === key) out.push(entity.id);
		}
		return out;
	}

	// how many lights/switches are on in a tab: shown next to its name
	function tabOnCount(key) {
		var ids = tabEntities(key);
		var count = 0;
		for (var index = 0; index < ids.length; index++) if ((actionOf(ids[index]) === "toggle" || domainOf(ids[index]) === "fan") && isOn(ids[index])) count++;
		return count;
	}

	// the icon for an entity: drawables/icons/<name>.svg (-on.svg when on, -dim.svg dimmed)
	function iconName(id) {
		var domain = domainOf(id);
		var unit = haStates[id] ? haStates[id].unit : "";
		var map = {light: "bulb", "switch": "plug", fan: "fan", cover: "blinds", lock: "lock", alarm_control_panel: "shield",
			scene: "palette", script: "play", button: "button", input_button: "button", climate: "thermometer", water_heater: "flame",
			media_player: "speaker", person: "person", device_tracker: "person", binary_sensor: "eye", input_boolean: "toggle",
			automation: "bolt", vacuum: "robot", humidifier: "droplet", camera: "camera", weather: "sun", valve: "valve",
			select: "list", input_select: "list", timer: "timer", counter: "counter"};
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
		if (domain === "timer") return stateNow === "active";
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
		if (domain === "climate" || domain === "water_heater") return typeof attr(id, "current_temperature") === "number";
		if (domain === "humidifier") return typeof attr(id, "current_humidity") === "number";
		if (domain === "sensor" && deviceClass(id) === "timestamp") return false;
		if (domain !== "sensor" && domain !== "input_number" && domain !== "number" && domain !== "counter") return false;
		var entry = haStates[id];
		return entry && /^-?\d+(\.\d+)?$/.test(entry.state);
	}

	// the big text of a value card
	function valueText(id) {
		var domain = domainOf(id);
		if (domain === "climate" || domain === "water_heater") return degrees(attr(id, "current_temperature"));
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
		if (domain === "water_heater") {
			if (stateNow === "off") return "Uit";
			var heaterTarget = climateTargetText(id);
			return heaterTarget ? "Naar " + heaterTarget : waterHeaterModeText(stateNow);
		}
		return "";
	}

	function degrees(value) {
		if (typeof value !== "number") return "-";
		return i18n.number(value, 1, i18n.omit_trail_zeros) + "°";
	}

	function friendlyError(errorText) {
		if (errorText === "geen verbinding") return "Geen verbinding met Home Assistant";
		if (errorText === "token ongeldig (401)") return "Home Assistant weigert het token";
		return "Dat lukte niet (" + errorText + ")";
	}

	property int tileMax: 4

	function cleanTile(list) {
		var out = [];
		for (var index = 0; index < list.length && out.length < tileMax; index++) if (list[index] && out.indexOf(String(list[index])) < 0) out.push(String(list[index]));
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
		for (var index = 0; index < tileEntities.length; index++) if (isSelected(tileEntities[index])) out.push(tileEntities[index]);
		if (out.length > 0) return out;
		return favouriteList().slice(0, tileMax);
	}

	function favouriteList() {
		var out = [];
		for (var index = 0; index < entities.length; index++) if (entities[index].fav) out.push(entities[index].id);
		if (out.length === 0) for (var innerIndex = 0; innerIndex < entities.length; innerIndex++) out.push(entities[innerIndex].id);   // no favourites: the first ones
		return out;
	}

	// ======================================================================
	// Home Assistant REST API
	// ======================================================================

	function request(method, path, body, onDone) {
		var httpRequest = new XMLHttpRequest();
		httpRequest.open(method, haUrl + path, true);
		httpRequest.setRequestHeader("Authorization", "Bearer " + haToken);
		httpRequest.setRequestHeader("Content-Type", "application/json");
		httpRequest.onreadystatechange = function() {
			if (httpRequest.readyState !== 4) return;
			if (httpRequest.status >= 200 && httpRequest.status < 300) {
				onDone(httpRequest.responseText, "");
			} else {
				var errorText = httpRequest.status === 0 ? "geen verbinding" : (httpRequest.status === 401 ? "token ongeldig (401)" : "HTTP " + httpRequest.status);
				onDone(null, errorText);
			}
		};
		httpRequest.send(body ? JSON.stringify(body) : null);
	}

	function template(templateText, onDone) {
		request("POST", "/api/template", {template: templateText}, function(text, errorText) {
			if (text === null) { onDone(null, errorText); return; }
			try { onDone(JSON.parse(text), ""); } catch (error) { onDone(null, "onverwacht antwoord"); }
		});
	}

	// test with an address and token that are not saved yet; onDone(ok, message)
	function testConnection(url, token, onDone) {
		var httpRequest = new XMLHttpRequest();
		httpRequest.open("GET", cleanUrl(url) + "/api/", true);
		httpRequest.setRequestHeader("Authorization", "Bearer " + (token || haToken));
		httpRequest.onreadystatechange = function() {
			if (httpRequest.readyState !== 4) return;
			if (httpRequest.status === 200) {
				var messageText = "OK";
				try { messageText = JSON.parse(httpRequest.responseText).message || "OK"; } catch (error) {}
				onDone(true, messageText);
			} else if (httpRequest.status === 401) {
				onDone(false, "Bereikbaar, maar het token klopt niet (401)");
			} else if (httpRequest.status === 0) {
				onDone(false, "Geen verbinding met " + cleanUrl(url));
			} else {
				onDone(false, "Fout: HTTP " + httpRequest.status);
			}
		};
		httpRequest.send();
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
		sensor: ["device_class"],
		cover: ["device_class"],
		valve: ["device_class"],
		select: ["options"],
		input_select: ["options"],
		number: ["min", "max", "step", "mode"],
		input_number: ["min", "max", "step", "mode"],
		timer: ["duration", "remaining", "finishes_at"],
		counter: ["initial", "step", "minimum", "maximum"],
		water_heater: ["current_temperature", "temperature", "min_temp", "max_temp", "target_temp_step", "operation_mode", "operation_list"],
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
		for (var index = 0; index < entities.length; index++) out.push(entities[index].id);
		var energyList = energyData.energyIds();
		for (var innerIndex = 0; innerIndex < energyList.length; innerIndex++) if (out.indexOf(energyList[innerIndex]) < 0) out.push(energyList[innerIndex]);
		var sensorList = areaSensorIds();
		for (var sensorIndex = 0; sensorIndex < sensorList.length; sensorIndex++) if (out.indexOf(sensorList[sensorIndex]) < 0) out.push(sensorList[sensorIndex]);
		return out;
	}

	property int pollSeq: 0
	property int pollApplied: 0

	function pollStates() {
		var list = pollIds();
		if (!isConfigured() || list.length === 0) return;
		live.liveFollow();
		var ids = [];
		for (var idIndex = 0; idIndex < list.length; idIndex++) ids.push(jsonString(list[idIndex]));
		var templateText = "{%- set ext = " + JSON.stringify(extKeys) + " -%}"
			+ "[{%- for i in [" + ids.join(",") + "] -%}"
			+ "{%- set ns = namespace(v=[]) -%}{%- for k in ext.get(i.split('.')[0], []) -%}{%- set ns.v = ns.v + [state_attr(i, k)] -%}{%- endfor -%}"
			+ "{{ [i, states(i), state_attr(i, 'unit_of_measurement'), state_attr(i, 'friendly_name'), area_name(i), state_attr(i, 'code_format'), state_attr(i, 'code_arm_required'), state_attr(i, 'supported_features'), "
			+ "([state_attr(i, 'brightness'), state_attr(i, 'supported_color_modes'), state_attr(i, 'hs_color'), state_attr(i, 'color_temp_kelvin'), "
			+ "state_attr(i, 'min_color_temp_kelvin'), state_attr(i, 'max_color_temp_kelvin'), state_attr(i, 'color_mode')] if i.startswith('light.') else none), "
			+ "ns.v, (as_timestamp(states[i].last_changed) if i.split('.')[0] in ['person', 'device_tracker'] and states[i] else none), "
			+ "(as_timestamp(states[i].last_updated) if states[i] else none)] | tojson }}"
			+ "{%- if not loop.last %},{% endif -%}{%- endfor -%}]";
		var pollNumber = ++pollSeq;
		template(templateText, function(list, errorText) {
			// an answer to an older poll that comes in after a newer one (another selection by then): not used
			if (pollNumber < pollApplied) return;
			pollApplied = pollNumber;
			if (list === null) {
				if (liveConnected) return;            // live updates carry on
				connected = false;
				lastError = errorText;
				statesUpdated();
				return;
			}
			// merged into what is there (what live updates brought in since stays), for the ids polled now
			var keep = {}, wanted = pollIds();
			for (var index = 0; index < wanted.length; index++) keep[wanted[index]] = true;
			var map = {};
			var liveIsStale = false;
			for (var known in haStates) if (keep[known]) map[known] = haStates[known];
			for (var innerIndex = 0; innerIndex < list.length; innerIndex++) {
				var row = list[innerIndex];
				if (!keep[row[0]]) continue;
				var polled = {state: row[1], unit: row[2] || "", name: row[3] || "", area: row[4] || "",
					codeFormat: row[5] || "", codeArmRequired: row[6] !== false, features: row[7] || 0, light: lightInfo(row[8]),
					attrs: extAttrs(row[0], row[9]), changed: row[10] || 0};
				if (liveConnected && liveRaw[row[0]] && map[row[0]]) {
					var heldNow = holds[row[0]] && holds[row[0]].until > Date.now();
					if (heldNow || !live.liveMissed(liveRaw[row[0]], polled.state, row[11])) {
						// live is as new as the poll's answer, or newer: only the area (live doesn't send it)
						map[row[0]] = copyState(map[row[0]], {area: polled.area});
						continue;
					}
					// Home Assistant has a newer state than live brought: the live connection may be dead without
					// knowing it (a sleeping computer, a router restart). The poll counts, live connects again
					liveIsStale = true;
				}
				map[row[0]] = polled;
				applyHold(map, row[0]);
			}
			var hadWeather = false;
			for (var id in map) if (domainOf(id) === "weather" && !forecasts[id]) hadWeather = true;
			haStates = map;
			if (liveIsStale) live.liveRestart("a poll differs from the live states");
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
		for (var index = 0; index < keys.length && index < values.length; index++) out[keys[index]] = values[index];
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

	// a connection can die without the socket noticing (a sleeping computer, a router or Wi-Fi gone for a
	// moment): then "live" would stay on while nothing comes in. So a ping every liveHeartbeatMs; when
	// nothing at all came back for a while, the connection counts as dead: a poll at once, and connect again
	property double liveLastMessage: 0
	property int liveHeartbeatMs: 30000

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
		for (var index = 0; index < ids.length; index++) if (domainOf(ids[index]) === "weather") loadForecast(ids[index], "daily");
	}

	// HA 2024.x: a service with a response; a weather entity without a daily forecast gets the hourly one
	function loadForecast(id, type) {
		request("POST", "/api/services/weather/get_forecasts?return_response", {entity_id: id, type: type}, function(text, errorText) {
			var list = null;
			try {
				var forecast = JSON.parse(text).service_response[id].forecast;
				list = [];
				for (var index = 0; index < forecast.length; index++) {
					list.push({time: parseTime(forecast[index].datetime).getTime(), condition: forecast[index].condition || "", temp: forecast[index].temperature,
						low: forecast[index].templow, rain: forecast[index].precipitation, daily: type === "daily"});
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

	function pad2(number) { return (number < 10 ? "0" : "") + number; }

	// Home Assistant's times have microseconds ("…T10:00:00.123456+00:00"): the Toon's JavaScript wants at most 3 digits
	function parseTime(text) {
		return new Date(String(text || "").replace(/(\.\d{3})\d+/, "$1"));
	}

	// the readings since yesterday midnight (Home Assistant's history) -> per hour, for today and yesterday:
	// the increments of a meter, the value of a price
	property double energyHistUntil: 0        // up to when the history is in (ms); the next fetch only asks for what came after
	property string energyHistKey: ""         // for which day and entities: another day or other entities -> everything again

	// every entity HA has, with its area, plus HA's list of areas (for choosing)
	function loadAllEntities() {
		if (!isConfigured()) return;
		loadingAll = true;
		var templateText = "{\"areas\": {{ areas() | map('area_name') | list | tojson }}, \"entities\": ["
			+ "{%- for s in states -%}{{ [s.entity_id, s.name, area_name(s.entity_id), s.state, s.attributes.get('unit_of_measurement'), s.attributes.get('device_class')] | tojson }}"
			+ "{%- if not loop.last %},{% endif -%}{%- endfor -%}]}";
		template(templateText, function(answer, errorText) {
			loadingAll = false;
			if (answer === null) {
				lastError = errorText;
				allEntitiesLoaded();
				broadcastState();
				return;
			}
			setAllEntities(answer.entities, answer.areas || [], new Date().getTime());
			connected = true;
			saveEntitiesCache(answer.entities);
			allEntitiesLoaded();
			selectionChanged();
			broadcastState();
		});
	}

	// rows [id, name, area, state, unit, device_class] (HA's answer, or the cache) -> allEntities, the index and
	// the web editor's message
	function setAllEntities(rows, areas, version) {
		var list = [], index = {};
		for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
			var row = rows[rowIndex];
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
		for (var listIndex = 0; listIndex < list.length; listIndex++) compact.push([list[listIndex].id, list[listIndex].name, list[listIndex].area, list[listIndex].state, list[listIndex].unit, list[listIndex].deviceClass]);
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
		if (["light", "switch", "input_boolean", "automation", "siren", "cover", "lock", "vacuum", "group", "valve"].indexOf(domain) >= 0) return "toggle";
		if (["fan", "climate", "humidifier", "media_player", "camera", "person", "device_tracker", "water_heater", "select", "input_select",
			"number", "input_number", "timer", "counter"].indexOf(domain) >= 0) return "open";
		if (domain === "button" || domain === "input_button") return "press";
		if (domain === "script" || domain === "scene") return "run";
		if (domain === "alarm_control_panel") return "alarm";
		return "";
	}

	function isOn(id) {
		var stateNow = haStates[id] ? haStates[id].state : "";
		return ["on", "open", "opening", "unlocked", "playing", "heat", "cool", "heat_cool", "auto", "cleaning", "home", "active"].indexOf(stateNow) >= 0;
	}

	// what opening this entity lets into the house: "" (nothing to ask), else the question before a tap does it.
	// A lock that unlocks, a garage door or gate that opens: one stray tap on the Toon must not do that
	function confirmQuestion(id) {
		var domain = domainOf(id);
		if (isOn(id)) return "";                           // locking, closing: no question
		if (domain === "lock") return displayName(id) + " ontgrendelen?";
		if (domain === "cover" && ["garage", "gate", "door"].indexOf(deviceClass(id)) >= 0) return displayName(id) + " openen?";
		return "";
	}

	// a tap on a card or on the tile. confirmed: the question (confirmQuestion) was answered with yes.
	// Returns true when a command went to Home Assistant (the card pulses until the answer)
	function activate(id, confirmed) {
		var domain = domainOf(id);
		if (domain === "alarm_control_panel") { openAlarm(id); return false; }
		if (actionOf(id) === "open") { openDetail(id); return false; }
		var question = confirmed === true ? "" : confirmQuestion(id);
		if (question !== "") {
			qdialog.showDialog(qdialog.SizeLarge, "Home Assistant", question, "Annuleren", function() {},
				domain === "lock" ? "Ontgrendelen" : "Openen", function() { activate(id, true); });
			return false;
		}
		var wasOn = isOn(id);
		var service = "";
		// an old-style group has no services of its own: Home Assistant's general turn_on / turn_off
		var serviceDomain = domain === "group" ? "homeassistant" : domain;
		if (domain === "button" || domain === "input_button") service = "press";
		else if (domain === "script" || domain === "scene") service = "turn_on";
		else if (domain === "lock") service = wasOn ? "lock" : "unlock";
		else if (domain === "cover") service = wasOn ? "close_cover" : "open_cover";
		else if (domain === "valve") service = wasOn ? "close_valve" : "open_valve";
		else if (domain === "vacuum") { service = wasOn ? "turn_off" : "turn_on"; }
		// on or off as the card shows it, not "toggle": a lamp that is still fading out is "on" for Home Assistant,
		// so off-and-at-once-on again would switch it off a second time
		else if (actionOf(id) === "toggle") service = wasOn ? "turn_off" : "turn_on";
		if (!service) return false;
		if (domain === "vacuum" && service === "turn_on") service = "start";
		if (domain === "vacuum" && service === "turn_off") service = "return_to_base";

		// show the new state at once, HA's answer follows with the next poll
		if (actionOf(id) === "toggle" && haStates[id]) {
			var map = haStates;
			var guess = {lock: wasOn ? "locked" : "unlocked", cover: wasOn ? "closing" : "opening", valve: wasOn ? "closing" : "opening"}[domain]
				|| (wasOn ? "off" : "on");
			var before = map[id].state;
			map[id] = copyState(map[id], {state: guess});
			haStates = map;
			hold(id, before);
			statesUpdated();
		}
		request("POST", "/api/services/" + serviceDomain + "/" + service, {entity_id: id}, function(text, errorText) {
			if (text === null) { lastError = "Schakelen mislukt: " + errorText; release(id); }
			actionResult(id, text !== null, text !== null ? "" : friendlyError(errorText));
			refreshSoon.restart();
		});
		return true;
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
			var currentTemperature = attr(id, "current_temperature"), target = climateTargetText(id);
			if (value === "off") return (typeof currentTemperature === "number" ? degrees(currentTemperature) + " · " : "") + "Uit";
			return (typeof currentTemperature === "number" ? degrees(currentTemperature) : hvacModeText(value)) + (target ? " → " + target : "");
		}
		if (domain === "humidifier") {
			var currentHumidity = attr(id, "current_humidity");
			if (value !== "on") return (typeof currentHumidity === "number" ? Math.round(currentHumidity) + "% · " : "") + "Uit";
			return (typeof currentHumidity === "number" ? Math.round(currentHumidity) + "%" : "Aan") + (typeof attr(id, "humidity") === "number" ? " → " + Math.round(attr(id, "humidity")) + "%" : "");
		}
		if (domain === "water_heater") {
			var waterNow = attr(id, "current_temperature"), waterTarget = climateTargetText(id);
			if (value === "off") return (typeof waterNow === "number" ? degrees(waterNow) + " · " : "") + "Uit";
			return (typeof waterNow === "number" ? degrees(waterNow) : waterHeaterModeText(value)) + (waterTarget ? " → " + waterTarget : "");
		}
		if (domain === "timer") return timerText(id, value);
		if (domain === "sensor" && deviceClass(id) === "timestamp") return momentText(parseTime(value)) || value;
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
			var percentage = attr(id, "percentage"), preset = attr(id, "preset_mode");
			if (typeof percentage === "number" && percentage > 0 && fanSupports(id, "speed")) return "Aan " + Math.round(percentage) + "%";
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

	// a moment as the cards say it: "10:42" (today), "morgen 10:42", "gisteren 10:42", "14-11 10:42"; "" for no date
	function momentText(moment) {
		if (!moment || isNaN(moment.getTime())) return "";
		var now = new Date();
		var clock = pad2(moment.getHours()) + ":" + pad2(moment.getMinutes());
		var dayStart = new Date(moment.getFullYear(), moment.getMonth(), moment.getDate()).getTime();
		var todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
		var daysAway = Math.round((dayStart - todayStart) / (24 * 3600 * 1000));
		if (daysAway === 0) return clock;
		if (daysAway === 1) return "morgen " + clock;
		if (daysAway === -1) return "gisteren " + clock;
		return moment.getDate() + "-" + (moment.getMonth() + 1) + " " + clock;
	}

	// a timer: "Loopt tot 10:42", "Pauze · 4:32 over", "Inactief"
	function timerText(id, value) {
		if (value === "active") {
			var finishes = momentText(parseTime(attr(id, "finishes_at")));
			return finishes ? "Loopt tot " + finishes : "Loopt";
		}
		if (value === "paused") {
			var remaining = String(attr(id, "remaining") || "").replace(/^0:0?/, "");      // "0:04:32" -> "4:32"
			return remaining ? "Pauze · " + remaining + " over" : "Pauze";
		}
		return value === "idle" ? "Inactief" : value;
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
		for (var index = 0; index < all.length; index++) if (features & all[index].bit) out.push({mode: all[index].mode, label: all[index].label});
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
		request("POST", "/api/services/alarm_control_panel/alarm_" + mode, body, function(text, errorText) {
			if (text === null) {
				lastError = "Alarm: " + errorText;
				var messageText = errorText === "HTTP 400" || errorText === "HTTP 500" ? "Geweigerd (verkeerde code?)" : errorText;
				if (onDone) onDone(false, messageText);
				actionResult(id, false, messageText);
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
			|| (expected !== held.before && (haState === expected || (["cover", "lock", "valve"].indexOf(domainOf(id)) >= 0 && haState !== held.before)));
		// expected === before (a brightness or volume change, or off and on again): held until the time is up
		if (done) release(id);
		else map[id] = held.entry;
	}

	function copyState(source, changes) {
		var out = {};
		for (var sourceKey in source) out[sourceKey] = source[sourceKey];
		for (var key in changes) out[key] = changes[key];
		return out;
	}

	// HA's light attributes -> what the light screen needs; null for other domains
	function lightInfo(attributes) {
		if (!attributes) return null;
		var modes = attributes[1] || [];
		var colorModes = ["hs", "xy", "rgb", "rgbw", "rgbww"];
		var color = false, dimmable = false;
		for (var index = 0; index < modes.length; index++) {
			if (colorModes.indexOf(modes[index]) >= 0) color = true;
			if (modes[index] !== "onoff") dimmable = true;
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
		request("POST", "/api/services/light/" + service, data, function(text, errorText) {
			if (text === null) { lastError = "Lamp: " + errorText; release(id); }
			actionResult(id, text !== null, text !== null ? "" : friendlyError(errorText));
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
		var url = {fan: fanScreenUrl, climate: climateScreenUrl, humidifier: climateScreenUrl, water_heater: climateScreenUrl,
			media_player: mediaScreenUrl, camera: cameraScreenUrl, person: personScreenUrl, device_tracker: personScreenUrl,
			select: inputScreenUrl, input_select: inputScreenUrl, number: inputScreenUrl, input_number: inputScreenUrl,
			timer: timerScreenUrl, counter: inputScreenUrl}[domain];
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
		request("POST", "/api/services/" + domain + "/" + name, data, function(text, errorText) {
			if (text === null) { lastError = domain + ": " + errorText; release(id); }
			actionResult(id, text !== null, text !== null ? "" : friendlyError(errorText));
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

	// a water heater (boiler): its target and its way of heating (operation mode)
	function waterHeaterModeText(mode) {
		return {off: "Uit", eco: "Eco", electric: "Elektrisch", performance: "Krachtig", high_demand: "Veel vraag",
			heat_pump: "Warmtepomp", gas: "Gas"}[mode] || presetText(mode);
	}
	function waterHeaterSetTemperature(id, temperature) { service(id, "water_heater", "set_temperature", {temperature: temperature}, null, {temperature: temperature}); }
	function waterHeaterSetMode(id, mode) { service(id, "water_heater", "set_operation_mode", {operation_mode: mode}, mode, {operation_mode: mode}); }

	// a timer's screen: command is start, pause, finish (as if its time was up) or cancel
	function timerCommand(id, command) {
		service(id, "timer", command, {}, {start: "active", pause: "paused", finish: "idle", cancel: "idle"}[command], null);
	}

	// a counter: command is increment, decrement (by the counter's own step, within its minimum and maximum)
	// or reset (back to its initial value). The new count shows at once
	function counterCommand(id, command) {
		var count = haStates[id] ? parseFloat(haStates[id].state) : NaN;
		var countStep = typeof attr(id, "step") === "number" ? attr(id, "step") : 1;
		var next = command === "reset" ? attr(id, "initial") : count + (command === "increment" ? countStep : -countStep);
		if (typeof attr(id, "minimum") === "number") next = Math.max(attr(id, "minimum"), next);
		if (typeof attr(id, "maximum") === "number") next = Math.min(attr(id, "maximum"), next);
		service(id, "counter", command, {}, typeof next === "number" && !isNaN(next) ? String(next) : null, null);
	}
	function counterSetValue(id, value) { service(id, "counter", "set_value", {value: Math.round(value)}, String(Math.round(value)), null); }

	// a choice (select, input_select) and a number that can be set (number, input_number)
	function selectOption(id, option) { service(id, domainOf(id), "select_option", {option: option}, option, null); }
	function numberSetValue(id, value) { service(id, domainOf(id), "set_value", {value: value}, String(value), null); }

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
	function fanSetPercentage(id, percentage) {
		var step = fanStep(id);
		percentage = Math.max(0, Math.min(100, Math.round(Math.round(percentage / step) * step)));
		service(id, "fan", "set_percentage", {percentage: percentage}, percentage > 0 ? "on" : "off", {percentage: percentage});
	}
	function fanSetPreset(id, preset) { service(id, "fan", "set_preset_mode", {preset_mode: preset}, "on", {preset_mode: preset}); }
	function fanOscillate(id, oscillating) { service(id, "fan", "oscillate", {oscillating: oscillating}, null, {oscillating: oscillating}); }
	function fanDirection(id, direction) { service(id, "fan", "set_direction", {direction: direction}, null, {direction: direction}); }
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
			var firewallRules = iptablesFile.read();
			if (!firewallRules || firewallRules.indexOf("--dport " + webPort + " ") >= 0) return;
			var rule = "-A HCB-INPUT -p tcp -m tcp --dport " + webPort + " --tcp-flags SYN,RST,ACK SYN -j ACCEPT\n";
			var position = firewallRules.indexOf("-A HCB-INPUT -p tcp -m tcp --tcp-flags SYN,RST,ACK SYN -j DROP");
			if (position < 0) return;
			iptablesFile.write(firewallRules.substring(0, position) + rule + firewallRules.substring(position));
			console.log("homeassistant: port " + webPort + " added to iptables.conf (active after \"Flush firewall rules\" or a reboot)");
		} catch (error) {}
	}

	// the Toon's own IP address: from the kernel's address list, else from a connection it has open
	function findToonAddress() {
		// /proc/net/fib_trie: "|-- 192.168.1.23" followed by "/32 host LOCAL"
		try {
			var routeLines = fibFile.read().split("\n");
			for (var line = 1; line < routeLines.length; line++) {
				if (routeLines[line].indexOf("/32 host LOCAL") < 0) continue;
				var match = routeLines[line - 1].match(/(\d+)\.(\d+)\.(\d+)\.(\d+)\s*$/);
				if (match && match[1] !== "127" && match[1] !== "0") return match[1] + "." + match[2] + "." + match[3] + "." + match[4];
			}
		} catch (error) {}
		try {
			var lines = tcpFile.read().split("\n");
			for (var index = 1; index < lines.length; index++) {
				var parts = lines[index].trim().split(/\s+/);
				if (parts.length < 4 || parts[3] !== "01") continue;      // established connections know our address
				var hexAddress = parts[1].split(":")[0];
				if (hexAddress.length !== 8) continue;
				var address = [parseInt(hexAddress.substr(6, 2), 16), parseInt(hexAddress.substr(4, 2), 16), parseInt(hexAddress.substr(2, 2), 16), parseInt(hexAddress.substr(0, 2), 16)];
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
			areaSensors: areaSensors,
			energy: energy,
			energyFields: energyData.energyFields(),
			entities: entities,
			areas: areaNames,
			allVersion: allVersion,              // the list of all entities comes apart ("entities"), only when the page's copy is older
			allCount: allEntities.length
		});
	}

	function sendTo(socket, messageText) {
		try {
			if (socket && socket.status === WebSocket.Open) { socket.sendTextMessage(messageText); return true; }
		} catch (error) {}
		return false;
	}

	function broadcastState() {
		if (wsClients.length === 0) return;          // no web editor open: nothing to put together
		var messageText = stateMessage();
		for (var index = 0; index < wsClients.length; index++) sendTo(wsClients[index], messageText);
	}

	function dropClient(socket) {
		var list = [];
		for (var index = 0; index < wsClients.length; index++) if (wsClients[index] !== socket) list.push(wsClients[index]);
		wsClients = list;
	}

	// the token for a request from the web editor: the one it sent, else the saved one, but the saved one only
	// for the saved address. Anyone on the network can reach the web editor's port: with another address and
	// no token, the saved token would be sent to an address of their choosing. "" = no token to use
	function webEditorToken(address, sentToken) {
		var typedToken = typeof sentToken === "string" ? sentToken.trim() : "";
		if (typedToken !== "") return typedToken;
		return haUrl !== "" && cleanUrl(address) === haUrl ? haToken : "";
	}

	function tokenNeededMessage() {
		return JSON.stringify({type: "test", ok: false, message: haToken === "" ? "Vul het token in"
			: "Een ander adres: vul het token opnieuw in (het opgeslagen token gaat alleen naar het opgeslagen adres)"});
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
			var testAddress = message.url || haUrl;
			var testToken = webEditorToken(testAddress, message.token);
			if (testToken === "") { sendTo(socket, tokenNeededMessage()); return; }
			testConnection(testAddress, testToken, function(ok, messageText) {
				sendTo(socket, JSON.stringify({type: "test", ok: ok, message: messageText}));
			});
		} else if (message.type === "connection") {
			var newToken = webEditorToken(message.url, message.token);
			if (newToken === "") { sendTo(socket, tokenNeededMessage()); return; }
			setConnection(message.url, newToken);
			sendTo(socket, JSON.stringify({type: "test", ok: true, message: "opgeslagen, entiteiten worden opgehaald…"}));
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
			if (save.areaSensors) areaSensors = cleanAreaSensors(save.areaSensors);
			if (save.energy) {
				energy = cleanEnergy(save.energy);
				energyHistory = {};
				energyHistUntil = 0;
				energyData.loadEnergyHistory();
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
