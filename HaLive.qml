// Live updates for Home-Assistant Extended: Home Assistant's WebSocket API (subscribe_entities). A change in
// Home Assistant shows at once, without asking every few seconds. Without it (no connection, an old Home
// Assistant) the app polls.
//
// Created inside HomeassistantExtendedApp.qml (app.live): the state (liveConnected, liveRaw, haStates, ...) is
// the app's own and is read and written here by its plain name, as are the app's functions.

import QtQuick 2.1
import QtWebSockets 1.1

Item {
	id: liveConnection

	// did the live connection miss a change that the poll has? By Home Assistant's own time of the state
	// (last_updated): a sensor that changes every second differs from a poll's answer all the time, and then
	// it is the poll that is a moment older. Without that time (an entity that is gone): by the state
	function liveMissed(liveEntry, polledState, polledUpdated) {
		if (typeof polledUpdated === "number" && liveEntry.lu > 0) return polledUpdated > liveEntry.lu + 0.01;
		return polledState !== liveEntry.s;
	}

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

	// with every poll: the selection may have changed (the live updates follow it); not connected and not
	// trying either: connect
	function liveFollow() {
		if (liveConnected) liveSubscribe();
		else if (!haSocket.active && !liveReconnect.running) liveStart();
	}

	function liveStop() {
		liveReconnect.stop();
		liveConnected = false;
		liveSubId = 0;
		liveSubKey = "";
		haSocket.active = false;
	}

	function liveSend(payload) {
		if (haSocket.status !== WebSocket.Open) return;
		try { haSocket.sendTextMessage(JSON.stringify(payload)); } catch (error) {}
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
				// lu (last_updated) is left out when it is the same as lc (last_changed)
				raw[id] = {s: event.a[id].s, a: event.a[id].a || {}, lc: event.a[id].lc || 0, lu: event.a[id].lu || event.a[id].lc || 0};
				changed.push(id);
			}
		}
		if (event.c) {
			for (id in event.c) {
				var change = event.c[id];
				var entry = raw[id] || {s: "", a: {}, lc: 0, lu: 0};
				var plus = change["+"];
				if (plus) {
					if (plus.s !== undefined) entry.s = plus.s;
					if (plus.lc !== undefined) entry.lc = plus.lc;
					if (plus.lu !== undefined) entry.lu = plus.lu;
					else if (plus.lc !== undefined) entry.lu = plus.lc;
					if (plus.a) for (var key in plus.a) entry.a[key] = plus.a[key];
				}
				var minus = change["-"];
				if (minus && minus.a) for (var innerIndex = 0; innerIndex < minus.a.length; innerIndex++) delete entry.a[minus.a[innerIndex]];
				raw[id] = entry;
				changed.push(id);
			}
		}
		if (event.r) {
			for (var index = 0; index < event.r.length; index++) {
				raw[event.r[index]] = {s: "unavailable", a: raw[event.r[index]] ? raw[event.r[index]].a : {}, lc: 0, lu: 0};
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
		for (var index = 0; index < keys.length; index++) values.push(attributes[keys[index]] === undefined ? null : attributes[keys[index]]);
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
			var wasLive = liveConnected;
			liveConnected = false;
			liveSubId = 0;
			liveSubKey = "";
			if (!active || liveFailed || !isConfigured()) return;
			active = false;
			// try again: 2, 4, 8 … seconds, at most a minute; polling meanwhile
			liveReconnect.interval = Math.min(60000, 2000 * Math.pow(2, Math.min(liveRetry, 5)));
			liveRetry++;
			liveReconnect.restart();
			if (wasLive) pollStates();
		}
	}

	Timer { id: liveReconnect; onTriggered: liveStart() }

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
}
