// The Energie tab of Home-Assistant Extended: today's and yesterday's use per hour from the meter readings
// (Home Assistant's history), the prices per hour, the costs, and how the numbers are written.
//
// Created inside HomeassistantExtendedApp.qml (app.energyData): the settings and the data (energy, haStates,
// energyHistory, priceForecast, ...) are the app's own and are read and written here by their plain names,
// as are the app's functions (request, template, copyState, ...).

import QtQuick 2.1

Item {
	id: energyModel

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
		for (var index = 0; index < energyKeys.length; index++) {
			var list = energy[energyKeys[index]] || [];
			for (var innerIndex = 0; innerIndex < list.length; innerIndex++) if (out.indexOf(list[innerIndex]) < 0) out.push(list[innerIndex]);
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

	function loadEnergyHistory() {
		if (!isConfigured()) return;
		var ids = [], priceIds = [];
		var keys = ["usage", "export", "solar", "gas", "water", "priceUsage", "priceExport", "priceGas", "priceWater"];
		for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
			var list = energy[keys[keyIndex]] || [];
			for (var innerIndex = 0; innerIndex < list.length; innerIndex++) {
				if (ids.indexOf(list[innerIndex]) < 0) ids.push(list[innerIndex]);
				if (keys[keyIndex].indexOf("price") === 0 && priceIds.indexOf(list[innerIndex]) < 0) priceIds.push(list[innerIndex]);
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
			+ "&filter_entity_id=" + ids.join(",") + "&minimal_response&no_attributes", null, function(text, errorText) {
			if (text === null) return;
			var answer;
			try { answer = JSON.parse(text); } catch (error) { return; }
			var map = full ? {} : copyState(energyHistory, {});
			for (var index = 0; index < answer.length; index++) {
				var rows = answer[index];
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
	function meterMore(history, rows, midnight) {
		var out = {today: history.today.slice(0), yesterday: history.yesterday, last: history.last, day: history.day};
		for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
			var value = parseFloat(rows[rowIndex].state);
			if (isNaN(value)) continue;
			var time = parseTime(rows[rowIndex].last_changed || rows[rowIndex].last_updated);
			if (out.last !== null) {
				var increase = increment(out.last, value);
				// the first row is the state at the start of the period, often from earlier: it counts in this hour
				var hour = isNaN(time.getTime()) || time < midnight ? new Date().getHours() : time.getHours();
				out.today[hour] += increase;
			}
			out.last = value;
		}
		return out;
	}

	// a price's values since the last time: from its hour on
	function priceMore(history, rows, midnight) {
		var out = {today: history.today.slice(0), yesterday: history.yesterday, last: history.last, day: history.day, price: true};
		for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
			var value = parseFloat(rows[rowIndex].state);
			var time = parseTime(rows[rowIndex].last_changed || rows[rowIndex].last_updated);
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
		for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
			var value = parseFloat(rows[rowIndex].state);
			if (isNaN(value)) continue;
			var time = parseTime(rows[rowIndex].last_changed || rows[rowIndex].last_updated);
			if (out.last !== null && !isNaN(time.getTime())) {
				var increase = increment(out.last, value);
				if (time >= midnight) out.today[time.getHours()] += increase;
				else if (time >= yesterday) out.yesterday[time.getHours()] += increase;
			}
			out.last = value;
		}
		return out.last === null ? null : out;
	}

	// a price's values -> the price in each hour (the last value at the start of the hour, else in it), yesterday and today
	function priceHistory(rows, yesterday, midnight, day) {
		var points = [];
		for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
			var value = parseFloat(rows[rowIndex].state);
			var time = parseTime(rows[rowIndex].last_changed || rows[rowIndex].last_updated);
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
		for (var index = 0; index < ids.length; index++) {
			var quoted = jsonString(ids[index]);
			parts.push(quoted + ": [state_attr(" + quoted + ", 'today'), state_attr(" + quoted + ", 'raw_today'), state_attr(" + quoted + ", 'prices_today'), state_attr(" + quoted + ", 'prices')]");
		}
		template("{# energy prices #}{{ {" + parts.join(", ") + "} | tojson }}", function(answer, errorText) {
			if (answer === null) return;
			var map = {};
			for (var id in answer) {
				var hours = priceHours(answer[id]);
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
			var partsPerHour = attributes[0].length >= 96 ? 4 : (attributes[0].length >= 48 ? 2 : 1);
			for (var slotIndex = 0; slotIndex < attributes[0].length; slotIndex++) add(Math.floor(slotIndex / partsPerHour), attributes[0][slotIndex]);
		} else {
			var lists = [attributes[1], attributes[2], attributes[3]];
			for (var index = 0; index < lists.length; index++) {
				var list = lists[index];
				if (!list || !list.length) continue;
				for (var itemIndex = 0; itemIndex < list.length; itemIndex++) {
					var item = list[itemIndex];
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
		for (var index = 0; index < list.length; index++) {
			var entry = haStates[list[index]];
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
		for (var entityIndex = 0; entityIndex < list.length; entityIndex++) {
			var history = energyHistory[list[entityIndex]];
			if (!history || history.day !== today || history.price) continue;
			var entry = haStates[list[entityIndex]];
			var factor = energyFactor(entry ? entry.unit : "", key);
			for (var hourIndex = 0; hourIndex < 24; hourIndex++) hours[hourIndex] += history.today[hourIndex] * factor;
			// what the meter did since the history was fetched
			var value = entry ? parseFloat(entry.state) : NaN;
			if (!isNaN(value)) hours[nowHour] += increment(history.last, value) * factor;
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
		for (var index = 0; index < list.length; index++) {
			var history = energyHistory[list[index]];
			if (!history || history.day !== today || history.price) continue;
			var entry = haStates[list[index]];
			var factor = energyFactor(entry ? entry.unit : "", key);
			for (var hourIndex = 0; hourIndex < 24; hourIndex++) hours[hourIndex] += history.yesterday[hourIndex] * factor;
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
		for (var index = 0; index < list.length; index++) {
			var id = list[index];
			var entry = haStates[id];
			var factor = priceFactor(entry ? entry.unit : "");
			var now = entry ? parseFloat(entry.state) : NaN;
			var forecast = priceForecast[id], history = energyHistory[id];
			for (var hour = 0; hour < 24; hour++) {
				var value = null;
				if (forecast && typeof forecast[hour] === "number") value = forecast[hour];
				else if (history && history.price && history.day === today && hour <= nowHour) value = history.today[hour];
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
		for (var hourIndex = 0; hourIndex < 24; hourIndex++) cost += today.hours[hourIndex] * perUnit * prices[hourIndex];
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
}
