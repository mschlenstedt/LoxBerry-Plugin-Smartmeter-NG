<script>

// Shared JavaScript for all tabs. Appended to every template, so it may use
// TMPL_VAR tags for localized strings. Data comes from ajax.cgi (relative URL).

// Inject shared styles that are not part of the LoxBerry Design System: the
// vzLogger service-status block and the grey "?" help button placed next to a
// form label (linking into the Volkszaehler wiki).
(function() {
	var css =
		".vzsvc{display:flex;flex-wrap:wrap;justify-content:center;align-items:center;gap:10px;text-shadow:none;padding:6px 0;}" +
		".vzsvc-info{display:flex;align-items:center;gap:10px;flex-wrap:wrap;justify-content:center;}" +
		".vzsvc-btns{display:flex;flex-wrap:wrap;gap:4px;justify-content:center;align-items:center;}" +
		".vzsvc-label{color:var(--lb-text);}" +
		".vzsvc-box{padding:7px 12px;box-sizing:border-box;border-radius:5px;background:#dfdfdf;border:1px solid #7E7E7E;min-width:130px;max-width:100%;text-align:center;color:#333;}" +
		".vzsvc-small{font-size:80%;}" +
		".vzsvc-btn{display:inline-flex;align-items:center;gap:8px;background:#f6f6f6;border:1px solid #ddd;border-radius:5px;padding:6px 12px;color:#333;font-size:12.5px;font-weight:bold;line-height:1;text-decoration:none;cursor:pointer;}" +
		".vzsvc-btn:hover{background:#ededed;}" +
		".vzsvc-ico{display:inline-flex;align-items:center;justify-content:center;width:22px;height:22px;border-radius:50%;background:rgba(0,0,0,.3);color:#fff;font-size:12px;}" +
		".sm-help{display:inline-flex;align-items:center;justify-content:center;width:20px;height:20px;margin-left:6px;padding:0;border-radius:50%;background:#8a8a8a;color:#fff;font-size:12px;line-height:1;text-decoration:none;vertical-align:middle;flex:none;}" +
		".sm-help:hover{background:#6f6f6f;}" +
		".lb-form-label{white-space:nowrap;}";
	var style = document.createElement("style");
	style.textContent = css;
	document.head.appendChild(style);
})();

$(function() {
	// I/R reading heads tab: run only when its markup is present.
	if ($("#irheads-body").length) {
		irheadLoad();
		// Keep the manual name field to letters, digits, underscore and hyphen.
		$("#irhead-name").on("input", function() {
			this.value = this.value.replace(/[^A-Za-z0-9_-]/g, "");
		});
		$("#irhead-type").on("change", irheadTypeToggle);
		irheadTypeToggle();
		$(document).on("click", ".irhead-remove", function() {
			irheadRemove($(this).data("device"));
		});
	}

	// vzLogger service status block: present on every tab except Live data and
	// Log files (those templates omit the #vz-service mount point).
	if (document.getElementById("vz-service")) {
		smServiceRender();
		smServiceStatus();
		smInterval = window.setInterval(smServiceStatus, 5000);
	}

	// Settings tab: load current values, then auto-save on blur (like the
	// Audioserver4Home gateway settings). Config changes need a service restart.
	if (document.getElementById("settings-form")) {
		setLoad();
	}

	// Smartmeter tab: meter list plus add/edit form.
	if (document.getElementById("meter-form")) {
		// Restrict the meter name to the characters the server accepts, so the user
		// cannot even type anything else (same as the I/R reading head name field).
		$("#meter-name").on("input", function() {
			this.value = this.value.replace(/[^A-Za-z0-9_-]/g, "");
		});
		$("#meter-protocol").on("change", function() { meterApplyProto($(this).val(), true); });
		$("#meter-device").on("change", meterPrefillName);
		$(document).on("click", ".meter-edit", function() { meterEdit($(this).data("name")); });
		$(document).on("click", ".meter-del", function() { meterDelete($(this).data("name")); });
		meterLoadDevices();
		meterLoadList();
		meterApplyProto($("#meter-protocol").val(), false);
	}

	// Channels tab: list of all channels plus an add/edit form.
	if (document.getElementById("channel-form")) {
		$("#ch-name").on("input", function() { this.value = this.value.replace(/[^A-Za-z0-9_-]/g, ""); });
		$(document).on("click", ".channel-edit", function() { channelEdit($(this).data("meter"), $(this).data("uuid")); });
		$(document).on("click", ".channel-del", function() { channelDelete($(this).data("meter"), $(this).data("uuid")); });
		channelLoad();
		// Poll the current per-channel values from vzLogger's httpd every 5 s.
		channelLivePoll();
		window.setInterval(channelLivePoll, 5000);
	}

	// Upgrade tab: load the vzLogger versions and drive the update button.
	if (document.getElementById("upg-btn")) {
		upgVersions();
	}
});

// ============================================================ I/R READING HEADS

var irheadMsg = {
	UI_IRHEAD_INVALID_DEVICE: "<TMPL_VAR VZLOGGER.UI_IRHEAD_INVALID_DEVICE>",
	UI_IRHEAD_INVALID_NAME:   "<TMPL_VAR VZLOGGER.UI_IRHEAD_INVALID_NAME>",
	UI_IRHEAD_DUPLICATE:      "<TMPL_VAR VZLOGGER.UI_IRHEAD_DUPLICATE>",
	UI_IRHEAD_NOT_FOUND:      "<TMPL_VAR VZLOGGER.UI_IRHEAD_NOT_FOUND>",
	UI_IRHEAD_DEVICE_MISSING: "<TMPL_VAR VZLOGGER.UI_IRHEAD_DEVICE_MISSING>",
	UI_TIBBER_INVALID_HOST:   "<TMPL_VAR VZLOGGER.UI_TIBBER_INVALID_HOST>",
	UI_TIBBER_INVALID_NODE:   "<TMPL_VAR VZLOGGER.UI_TIBBER_INVALID_NODE>",
	UI_TIBBER_UNREACHABLE:    "<TMPL_VAR VZLOGGER.UI_TIBBER_UNREACHABLE>",
	UI_TIBBER_AUTH_FAILED:    "<TMPL_VAR VZLOGGER.UI_TIBBER_AUTH_FAILED>",
	UI_TIBBER_HTTP_ERROR:     "<TMPL_VAR VZLOGGER.UI_TIBBER_HTTP_ERROR>",
	UI_TIBBER_NO_SML:         "<TMPL_VAR VZLOGGER.UI_TIBBER_NO_SML>",
	UI_POST_REQUIRED:         "<TMPL_VAR VZLOGGER.UI_POST_REQUIRED>",
	UI_UNKNOWN_ACTION:        "<TMPL_VAR VZLOGGER.UI_UNKNOWN_ACTION>",
	UI_AJAX_FAILED:           "<TMPL_VAR VZLOGGER.UI_AJAX_FAILED>"
};
var irheadNone   = "<TMPL_VAR VZLOGGER.IRHEAD_NONE>";
var irheadRemove_title = "<TMPL_VAR VZLOGGER.IRHEAD_REMOVE>";
var irheadAdding = "<TMPL_VAR VZLOGGER.IRHEAD_ADDING>";
var irheadAdded  = "<TMPL_VAR VZLOGGER.IRHEAD_ADDED>";
var irheadTibberProbing = "<TMPL_VAR VZLOGGER.IRHEAD_TIBBER_PROBING>";

function irheadEsc(value) {
	return $("<div>").text(value == null ? "" : value).html();
}

// Coloured status under the add button, same look as the Smartmeter tab:
// kind "ok" -> green, "error" -> red, "info" -> blue.
function irheadStatus(message, kind) {
	smStatus("#irhead-status", message, kind);
}

function irheadClearStatus() {
	$("#irhead-status").text("").css("display", "none");
}

// One table for all reading heads: auto-detected ones (with full USB metadata,
// not removable) and manually added ones (name + device, removable via the ×
// button). Rows are merged and sorted by device path so there is no visual split.
function irheadApply(data) {
	var body = $("#irheads-body").empty();
	var rows = [];
	(data.auto   || []).forEach(function(r) { rows.push($.extend({ removable: false }, r)); });
	(data.manual || []).forEach(function(r) { rows.push($.extend({ removable: true  }, r)); });
	if (!rows.length) {
		body.append('<tr><td colspan="8">' + irheadEsc(irheadNone) + '</td></tr>');
		return;
	}
	rows.sort(function(a, b) { return String(a.device || "").localeCompare(String(b.device || "")); });
	var mono = " style=\"font-family:var(--lb-font-mono)\"";
	rows.forEach(function(r) {
		var hw = [r.vendor, r.model].filter(Boolean).join(" ");
		var typ = !r.removable ? "usb-auto" : (r.type === "tibberpulse" ? "tibberpulse" : "seriell-man");
		var action = r.removable ? smIconBtn("irhead-remove", "x", irheadRemove_title, { device: r.device }) : "";
		body.append(
			"<tr><td>" + irheadEsc(r.name) + "</td><td>" + irheadEsc(typ) +
			"</td><td" + mono + ">" + irheadEsc(r.device) +
			"</td><td" + mono + ">" + irheadEsc(r.target) + "</td><td>" + irheadEsc(r.serial) +
			"</td><td>" + irheadEsc(r.usbport) + "</td><td>" + irheadEsc(hw) + "</td><td>" + action + "</td></tr>"
		);
	});
}

// Show serial or Tibber Pulse fields based on the type dropdown.
function irheadTypeToggle() {
	var t = $("#irhead-type").val();
	$(".irhead-serial").toggle(t === "serial");
	$(".irhead-tibber").toggle(t === "tibberpulse");
}

// Add-form submit dispatcher: serial head or Tibber Pulse.
function irheadSave() {
	if ($("#irhead-type").val() === "tibberpulse") { irheadAddTibber(); }
	else { irheadAdd(); }
}

// Adds a Tibber Pulse; the server probes the bridge (reachable + credentials +
// SML) before storing it and starting its bridge process.
function irheadAddTibber() {
	irheadStatus(irheadTibberProbing, "info");
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: {
			action:   "irheads-add-tibberpulse",
			name:     $("#irhead-name").val(),
			host:     $("#irhead-host").val(),
			node:     $("#irhead-node").val(),
			password: $("#irhead-password").val()
		} })
		.done(function(data) {
			if (data && data.ok) {
				irheadApply(data);
				$("#irhead-host, #irhead-password, #irhead-name").val("");
				$("#irhead-node").val("1");
				irheadStatus(irheadAdded, "ok");
			} else {
				irheadStatus((data && irheadMsg[data.error_key]) || irheadMsg.UI_AJAX_FAILED, "error");
			}
		})
		.fail(function() { irheadStatus(irheadMsg.UI_AJAX_FAILED, "error"); });
}

function irheadLoad() {
	$.ajax({ url: "ajax.cgi", type: "GET", dataType: "json", data: { action: "irheads-list" } })
		.done(function(data) { if (data && data.ok) { irheadApply(data); } })
		.fail(function() { irheadStatus(irheadMsg.UI_AJAX_FAILED, "error"); });
}

function irheadAdd() {
	irheadStatus(irheadAdding, "info");
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: {
			action: "irheads-add",
			device: $("#irhead-device").val(),
			name:   $("#irhead-name").val()
		} })
		.done(function(data) {
			if (data && data.ok) {
				irheadApply(data);
				$("#irhead-device").val("");
				$("#irhead-name").val("");
				irheadStatus(irheadAdded, "ok");
			} else {
				irheadStatus((data && irheadMsg[data.error_key]) || irheadMsg.UI_AJAX_FAILED, "error");
				if (data && data.auto) { irheadApply(data); }
			}
		})
		.fail(function() { irheadStatus(irheadMsg.UI_AJAX_FAILED, "error"); });
}

function irheadRemove(device) {
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: "irheads-remove", device: device } })
		.done(function(data) {
			if (data && data.ok) { irheadApply(data); irheadClearStatus(); }
			else { irheadStatus((data && irheadMsg[data.error_key]) || irheadMsg.UI_AJAX_FAILED, "error"); }
		})
		.fail(function() { irheadStatus(irheadMsg.UI_AJAX_FAILED, "error"); });
}

// ============================================================ vzLOGGER SERVICE
// Faithful reproduction of the Audioserver4Home gateway service block: a centred
// label, a status icon image and a coloured status box (grey "unknown", green
// with "PID: n" when running, orange "stopped") plus two grey icon buttons.
// Built with our own CSS because we run the LoxBerry Design System (nojqm), not
// jQuery Mobile; the status icons are the original Audioserver4Home images.

var smInterval = null;

var smSvc = {
	LABEL:   "<TMPL_VAR COMMON.SERVICE_LABEL>",
	RESTART: "<TMPL_VAR COMMON.SERVICE_RESTART>",
	STOP:    "<TMPL_VAR COMMON.SERVICE_STOP>",
	STOPPED: "<TMPL_VAR COMMON.SERVICE_STOPPED>",
	UNKNOWN: "<TMPL_VAR COMMON.SERVICE_UNKNOWN>",
	WORKING: "<TMPL_VAR COMMON.SERVICE_WORKING>",
	FAILED:  "<TMPL_VAR COMMON.SERVICE_FAILED>"
};

function smEsc(value) {
	return $("<div>").text(value == null ? "" : value).html();
}

// Coloured status line shown under a Save button: green = ok, red = error,
// blue = neutral/in progress.
function smStatus(sel, text, kind) {
	var color = kind === "ok" ? "#4a9e2f" : (kind === "error" ? "#c0392b" : "#2274c6");
	$(sel).text(text).css({ display: "block", "text-align": "center", "margin-top": "0.5em", color: color });
}

// Small icon button used across all tabs; uses the PrimeIcons font (.pi) so every
// button has the exact same size. kind: "gear" (edit), "x" (delete, red), "refresh".
function smIconBtn(cls, kind, title, data) {
	var icon   = kind === "gear" ? "pi-cog" : (kind === "refresh" ? "pi-refresh" : "pi-times");
	var danger = kind === "x" ? " lb-btn-danger" : "";
	var attrs  = "";
	for (var k in data) { if (data.hasOwnProperty(k)) { attrs += ' data-' + k + '="' + smEsc(data[k]) + '"'; } }
	// Fixed height + centering so the outline (edit) and filled (delete) buttons
	// are pixel-identical regardless of the glyph.
	return '<button type="button" class="lb-btn lb-btn-icon lb-btn-sm' + danger + ' ' + cls +
		'" style="display:inline-flex; align-items:center; justify-content:center; height:28px; padding:0 9px; font-size:15px; line-height:1; box-sizing:border-box;"' + attrs +
		' title="' + smEsc(title) + '"><i class="pi ' + icon + '"></i></button>';
}

function smServiceRender() {
	document.getElementById("vz-service").innerHTML =
		'<div class="vzsvc">' +
			'<div class="vzsvc-info">' +
				'<div class="vzsvc-label">' + smEsc(smSvc.LABEL) + '</div>' +
				'<div id="vz-svc-icon"></div>' +
				'<div class="vzsvc-box" id="vz-svc-box">' + smEsc(smSvc.UNKNOWN) + '</div>' +
			'</div>' +
			'<div class="vzsvc-btns">' +
				'<a href="#" class="vzsvc-btn" onclick="smServiceRestart(); return false;"><span class="vzsvc-ico"><i class="pi pi-check"></i></span>' + smEsc(smSvc.RESTART) + '</a>' +
				'<a href="#" class="vzsvc-btn" onclick="smServiceStop(); return false;"><span class="vzsvc-ico"><i class="pi pi-times"></i></span>' + smEsc(smSvc.STOP) + '</a>' +
			'</div>' +
		'</div><hr><br>';
	smServiceIcon("unknown");
}

// Non-clickable status badge (a coloured, non-interactive icon button) replacing
// the old status images: green/red/grey background with a white/black centred
// icon. kind: "ok" (running), "error" (stopped/failed), "unknown".
function smServiceIcon(kind) {
	// "error" matches the orange-red of the "stopped" status box (#FF6339).
	var m = kind === "ok"    ? { i: "pi-check", bg: "#4a9e2f", fg: "#fff" }
	      : kind === "error" ? { i: "pi-times", bg: "#FF6339", fg: "#fff" }
	      :                     { i: "pi-question", bg: "#c9c9c9", fg: "#000" };
	$("#vz-svc-icon").html('<button type="button" tabindex="-1" class="lb-btn lb-btn-icon"' +
		' style="pointer-events:none; display:inline-flex; align-items:center; justify-content:center;' +
		' width:30px; height:30px; padding:0; margin:0; font-size:16px; line-height:1; box-sizing:border-box;' +
		' background:' + m.bg + '; border-color:' + m.bg + '; color:' + m.fg + '">' +
		'<i class="pi ' + m.i + '"></i></button>');
}

function smServiceBox(style, html) {
	$("#vz-svc-box").attr("style", style).html(html);
}

function smServiceFailed() {
	smServiceBox("background:#dfdfdf; color:red", smEsc(smSvc.FAILED));
	smServiceIcon("unknown");
}

function smServiceShow(data) {
	if (data && data.ok && data.running && data.pid) {
		smServiceBox("background:#6dac20; color:black", '<span class="vzsvc-small">PID: ' + smEsc(data.pid) + '</span>');
		smServiceIcon("ok");
	} else if (data && data.ok) {
		smServiceBox("background:#FF6339; color:black", smEsc(smSvc.STOPPED));
		smServiceIcon("error");
	} else {
		smServiceFailed();
	}
}

function smServiceStatus() {
	$.ajax({ url: "ajax.cgi", type: "GET", dataType: "json", data: { action: "vz-status" } })
		.done(smServiceShow)
		.fail(smServiceFailed);
}

function smServiceRun(action) {
	clearInterval(smInterval);
	smServiceBox("color:blue", smEsc(smSvc.WORKING));
	smServiceIcon("unknown");
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: action } })
		.done(smServiceShow)
		.fail(smServiceFailed)
		.always(function() { smInterval = window.setInterval(smServiceStatus, 5000); });
}

// While a save or an OBIS discovery runs, lock out the actions that would race
// with it: the Restart/Stop service buttons (<a>, so via pointer-events) and any
// button marked ".sm-busy-disable" (Save / discovery buttons on the current tab).
var smBusy = false;
function smSetBusy(on) {
	smBusy = !!on;
	$(".vzsvc-btn").css({ "pointer-events": on ? "none" : "", opacity: on ? "0.5" : "" });
	$(".sm-busy-disable").prop("disabled", !!on);
}

function smServiceRestart() { if (smBusy) { return; } smServiceRun("vz-restart"); }
function smServiceStop() { if (smBusy) { return; } smServiceRun("vz-stop"); }

// =========================================================== SETTINGS TAB

var setMsg = {
	SAVING:        "<TMPL_VAR COMMON.HINT_SAVING>",
	SAVING_FAILED: "<TMPL_VAR COMMON.HINT_SAVING_FAILED>",
	SAVED_RESTART: "<TMPL_VAR COMMON.HINT_SAVED_RESTART>"
};

function setLoad() {
	$.ajax({ url: "ajax.cgi", type: "GET", dataType: "json", data: { action: "vzconf-get" } })
		.done(function(data) {
			if (data && data.ok && data.config) {
				var mqtt = data.config.mqtt || {};
				var local = data.config.local || {};
				$("#set-topic").val(mqtt.topic || "");
				$("#set-localport").val(local.port || "");
				$("#set-retry").val(data.config.retry != null ? data.config.retry : "");
			}
		});
}

// Saves only when the user clicks the Save button (no auto-save on change).
function setSave() {
	var patch = {
		retry: $("#set-retry").val(),
		local: { port: $("#set-localport").val() },
		mqtt:  { topic: $("#set-topic").val() }
	};
	smStatus("#set-savinghint", setMsg.SAVING, "info");
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: "vzconf-set-settings", settings: JSON.stringify(patch) } })
		.done(function(data) {
			if (data && data.ok) { smStatus("#set-savinghint", setMsg.SAVED_RESTART, "ok"); }
			else { smStatus("#set-savinghint", setMsg.SAVING_FAILED, "error"); }
		})
		.fail(function() { smStatus("#set-savinghint", setMsg.SAVING_FAILED, "error"); });
}

// =========================================================== SMARTMETER TAB

var meterList = [];
var meterMsg = {
	UI_METER_INVALID_NAME:     "<TMPL_VAR VZLOGGER.UI_METER_INVALID_NAME>",
	UI_METER_INVALID_DEVICE:   "<TMPL_VAR VZLOGGER.UI_METER_INVALID_DEVICE>",
	UI_METER_INVALID_PROTOCOL: "<TMPL_VAR VZLOGGER.UI_METER_INVALID_PROTOCOL>",
	UI_METER_DUPLICATE_NAME:   "<TMPL_VAR VZLOGGER.UI_METER_DUPLICATE_NAME>",
	UI_METER_DUPLICATE_DEVICE: "<TMPL_VAR VZLOGGER.UI_METER_DUPLICATE_DEVICE>",
	UI_METER_NOT_FOUND:        "<TMPL_VAR VZLOGGER.UI_METER_NOT_FOUND>",
	UI_METER_COMMAND_REQUIRED: "<TMPL_VAR VZLOGGER.UI_METER_COMMAND_REQUIRED>",
	UI_AJAX_FAILED:            "<TMPL_VAR VZLOGGER.UI_AJAX_FAILED>"
};
var meterText = {
	ADD:        "<TMPL_VAR VZLOGGER.MET_ADD_HEADING>",
	EDIT:       "<TMPL_VAR VZLOGGER.MET_EDIT_HEADING>",
	NONE:       "<TMPL_VAR VZLOGGER.MET_NONE>",
	ACTIVE:     "<TMPL_VAR VZLOGGER.MET_ACTIVE>",
	INACTIVE:   "<TMPL_VAR VZLOGGER.MET_INACTIVE>",
	EDITBTN:    "<TMPL_VAR VZLOGGER.MET_EDIT>",
	DELBTN:     "<TMPL_VAR VZLOGGER.MET_DELETE>",
	DELCONFIRM: "<TMPL_VAR VZLOGGER.MET_DELETE_CONFIRM>",
	SAVED:      "<TMPL_VAR COMMON.HINT_SAVED_RESTART>"
};
var meterDefaults = {
	sml: { baudrate: "9600", parity: "8n1" },
	d0:  { baudrate: "300",  parity: "7e1" },
	oms: { baudrate: "9600", parity: "8n1" }
};

function meterLoadDevices() {
	$.ajax({ url: "ajax.cgi", type: "GET", dataType: "json", data: { action: "irheads-list" } })
		.done(function(data) {
			if (!data || !data.ok) { return; }
			var sel = $("#meter-device").empty();
			var heads = (data.auto || []).concat(data.manual || []);
			heads.forEach(function(h) {
				sel.append($("<option>").val(h.device).text(h.name + " (" + h.device + ")"));
			});
		});
}

function meterPrefillName() {
	if ($("#meter-name").val() !== "") { return; }
	var m = $("#meter-device option:selected").text().match(/^(.*?)\s+\(/);
	if (m) { $("#meter-name").val(m[1]); }
}

function meterApplyProto(proto, resetDefaults) {
	$(".meter-row").each(function() {
		var list = " " + ($(this).data("proto") || "") + " ";
		$(this).toggle(list.indexOf(" " + proto + " ") >= 0);
	});
	if (resetDefaults && meterDefaults[proto]) {
		$("#meter-baudrate").val(meterDefaults[proto].baudrate);
		$("#meter-baudrate-read").val(meterDefaults[proto].baudrate);
		$("#meter-parity").val(meterDefaults[proto].parity);
	}
	if (resetDefaults && proto === "random") {
		$("#meter-min").val("0");
		$("#meter-max").val("100");
	}
}

function meterLoadList() {
	$.ajax({ url: "ajax.cgi", type: "GET", dataType: "json", data: { action: "vzconf-get" } })
		.done(function(data) {
			meterList = (data && data.ok && data.config && data.config.meters) ? data.config.meters : [];
			meterRenderList();
		});
}

function meterRenderList() {
	var body = $("#meters-body").empty();
	if (!meterList.length) {
		body.append('<tr><td colspan="5">' + smEsc(meterText.NONE) + '</td></tr>');
		return;
	}
	meterList.forEach(function(m) {
		var status = m.enabled ? meterText.ACTIVE : meterText.INACTIVE;
		var edit = smIconBtn("meter-edit", "gear", meterText.EDITBTN, { name: m.name });
		var del  = smIconBtn("meter-del", "x", meterText.DELBTN, { name: m.name });
		body.append(
			"<tr><td>" + smEsc(m.name) + "</td><td>" + smEsc((m.protocol || "").toUpperCase()) +
			"</td><td style=\"font-family:var(--lb-font-mono)\">" + smEsc(m.device) + "</td><td>" + smEsc(status) +
			"</td><td>" + edit + " " + del + "</td></tr>"
		);
	});
}

function meterGather() {
	return {
		original_name:         $("#meter-original-name").val(),
		name:                  $("#meter-name").val(),
		enabled:               $("#meter-enabled").is(":checked") ? "1" : "0",
		protocol:              $("#meter-protocol").val(),
		device:                $("#meter-device").val(),
		interval:              $("#meter-interval").val(),
		host:                  $("#meter-host").val(),
		baudrate:              $("#meter-baudrate").val(),
		baudrate_read:         $("#meter-baudrate-read").val(),
		parity:                $("#meter-parity").val(),
		read_timeout:          $("#meter-read-timeout").val(),
		pullseq:               $("#meter-pullseq").val(),
		ackseq:                $("#meter-ackseq").val(),
		wait_sync:             $("#meter-wait-sync").val(),
		baudrate_change_delay: $("#meter-bcd").val(),
		key:                   $("#meter-key").val(),
		use_local_time:        $("#meter-uselocaltime").val(),
		min:                   $("#meter-min").val(),
		max:                   $("#meter-max").val(),
		command:               $("#meter-command").val(),
		format:                $("#meter-format").val()
	};
}

function meterStatus(message, kind) {
	smStatus("#meter-status", message, kind);
}

function meterStatusClear() {
	$("#meter-status").css("display", "none").removeClass("lb-callout-warning");
}

function meterApply(data, ok) {
	if (data && data.ok) {
		meterList = (data.config && data.config.meters) ? data.config.meters : [];
		meterRenderList();
		return true;
	}
	meterStatus((data && meterMsg[data.error_key]) || meterMsg.UI_AJAX_FAILED, "error");
	return false;
}

function meterSave() {
	var form = meterGather();
	var action = form.original_name ? "vzconf-update-meter" : "vzconf-add-meter";
	smSetBusy(true);
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: action, meter: JSON.stringify(form) } })
		.done(function(data) {
			if (meterApply(data)) {
				var savedName = form.name, savedProto = form.protocol;
				meterFormReset();
				// Auto-run OBIS discovery for real protocols; test protocols have none.
				// Discovery keeps the busy lock and releases it when it finishes.
				if (/^(?:sml|d0|oms)$/.test(savedProto)) { meterAutoDiscover(savedName); }
				else { meterStatus(meterText.SAVED, "ok"); smSetBusy(false); }
			} else {
				smSetBusy(false);
			}
		})
		.fail(function() { meterStatus(meterMsg.UI_AJAX_FAILED, "error"); smSetBusy(false); });
}

function meterDelete(name) {
	if (!window.confirm(meterText.DELCONFIRM)) { return; }
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: "vzconf-remove-meter", meter: JSON.stringify({ name: name }) } })
		.done(function(data) { if (meterApply(data)) { meterStatus(meterText.SAVED, "ok"); } })
		.fail(function() { meterStatus(meterMsg.UI_AJAX_FAILED, "error"); });
}

function meterEdit(name) {
	var m = null;
	meterList.forEach(function(x) { if (x.name === name) { m = x; } });
	if (!m) { return; }
	$("#meter-original-name").val(m.name);
	$("#meter-name").val(m.name);
	$("#meter-enabled").prop("checked", m.enabled ? true : false);
	$("#meter-protocol").val(m.protocol);
	meterApplyProto(m.protocol, false);
	$("#meter-device").val(m.device);
	$("#meter-interval").val(m.interval != null ? m.interval : -1);
	$("#meter-host").val(m.host || "");
	$("#meter-baudrate").val(m.baudrate != null ? m.baudrate : "");
	$("#meter-baudrate-read").val(m.baudrate_read != null ? m.baudrate_read : "");
	$("#meter-parity").val(m.parity || "");
	$("#meter-read-timeout").val(m.read_timeout != null ? m.read_timeout : "");
	$("#meter-pullseq").val(m.pullseq || "");
	$("#meter-ackseq").val(m.ackseq || "auto");
	$("#meter-wait-sync").val(m.wait_sync || "off");
	$("#meter-bcd").val(m.baudrate_change_delay != null ? m.baudrate_change_delay : 0);
	$("#meter-key").val(m.key || "");
	$("#meter-uselocaltime").val(m.use_local_time ? "1" : "0");
	$("#meter-min").val(m.min != null ? m.min : "0");
	$("#meter-max").val(m.max != null ? m.max : "100");
	$("#meter-command").val(m.command || "");
	$("#meter-format").val(m.format || "");
	$("#meter-form-title").text(meterText.EDIT);
	meterStatusClear();
}

function meterFormReset() {
	$("#meter-original-name").val("");
	$("#meter-name").val("");
	$("#meter-enabled").prop("checked", true);
	$("#meter-protocol").val("sml");
	meterApplyProto("sml", true);
	$("#meter-device").prop("selectedIndex", 0);
	$("#meter-interval").val("-1");
	$("#meter-host, #meter-pullseq, #meter-key").val("");
	$("#meter-read-timeout").val("10");
	$("#meter-ackseq").val("auto");
	$("#meter-wait-sync").val("off");
	$("#meter-bcd").val("0");
	$("#meter-uselocaltime").val("0");
	$("#meter-min").val("0");
	$("#meter-max").val("100");
	$("#meter-command, #meter-format").val("");
	$("#meter-form-title").text(meterText.ADD);
	meterStatusClear();
}

var meterDiscMsg = {
	RUNNING: "<TMPL_VAR VZLOGGER.MET_DISC_RUNNING>",
	NONE:    "<TMPL_VAR VZLOGGER.MET_DISC_NONE>",
	DONE:    "<TMPL_VAR VZLOGGER.MET_DISC_DONE>"
};

// Runs discovery after saving a meter and adds all newly found channels.
function meterAutoDiscover(name) {
	meterStatus(meterDiscMsg.RUNNING, "info");
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: "meter-discover", meter: name } })
		.done(function(data) {
			var cands = (data && data.ok && data.channels) ? data.channels : [];
			if (!cands.length) { meterStatus(meterDiscMsg.NONE, "info"); smSetBusy(false); return; }
			$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: "vzconf-add-channels", channels: JSON.stringify({ meter: name, channels: cands }) } })
				.done(function(r) {
					if (r && r.ok) { meterStatus(meterDiscMsg.DONE.replace("{n}", cands.length), "ok"); }
					else { meterStatus(meterText.SAVED, "ok"); }
				})
				.fail(function() { meterStatus(meterText.SAVED, "ok"); })
				.always(function() { smSetBusy(false); });
		})
		.fail(function() { meterStatus(meterText.SAVED, "ok"); smSetBusy(false); });
}

// ---- Import a vzlogger.conf snippet into the add form -------------------
//
// vzlogger.conf is JSON with JavaScript-style comments (see the Volkszaehler
// wiki examples): both /* block */ and // line comments are allowed, including
// trailing comments after a value. Standard JSON.parse rejects those, so the
// comments are stripped first. The stripper is string-aware so a "//" or "/*"
// inside a string value (e.g. "http://localhost/...") is left untouched.

var meterImportMsg = {
	EMPTY:   "<TMPL_VAR VZLOGGER.MET_IMPORT_ERR_EMPTY>",
	PARSE:   "<TMPL_VAR VZLOGGER.MET_IMPORT_ERR_PARSE>",
	NOMETER: "<TMPL_VAR VZLOGGER.MET_IMPORT_ERR_NOMETER>",
	MULTI:   "<TMPL_VAR VZLOGGER.MET_IMPORT_ERR_MULTI>",
	PROTO:   "<TMPL_VAR VZLOGGER.MET_IMPORT_ERR_PROTO>",
	OK:      "<TMPL_VAR VZLOGGER.MET_IMPORT_OK>"
};

function meterStripConfComments(src) {
	var out = "", i = 0, n = src.length, inStr = false, esc = false;
	while (i < n) {
		var c = src.charAt(i);
		if (inStr) {
			out += c;
			if (esc) { esc = false; }
			else if (c === "\\") { esc = true; }
			else if (c === '"') { inStr = false; }
			i++;
			continue;
		}
		if (c === '"') { inStr = true; out += c; i++; continue; }
		if (c === "/" && src.charAt(i + 1) === "/") {          // line comment
			i += 2;
			while (i < n && src.charAt(i) !== "\n") { i++; }
			continue;                                          // keep the newline
		}
		if (c === "/" && src.charAt(i + 1) === "*") {          // block comment
			i += 2;
			while (i < n && !(src.charAt(i) === "*" && src.charAt(i + 1) === "/")) { i++; }
			i += 2;
			continue;
		}
		out += c;
		i++;
	}
	return out;
}

// Extracts exactly one meter object from a pasted snippet. Throws a message key
// when the input is empty, not parseable, or not unambiguous (no meter / more
// than one meter).
function meterImportParse(text) {
	if (!text || text.replace(/\s+/g, "") === "") { throw "EMPTY"; }
	var data;
	try { data = JSON.parse(meterStripConfComments(text)); }
	catch (e) { throw "PARSE"; }

	var meters = null;
	if (data && typeof data === "object" && Array.isArray(data.meters)) { meters = data.meters; }
	else if (Array.isArray(data)) { meters = data; }

	if (meters) {
		if (meters.length === 0) { throw "NOMETER"; }
		if (meters.length > 1)  { throw "MULTI"; }
		data = meters[0];
	}
	if (!data || typeof data !== "object" || Array.isArray(data)) { throw "NOMETER"; }
	// A single object is only accepted as a meter if it carries meter fields.
	if (!("protocol" in data) && !("baudrate" in data) && !("device" in data)) { throw "NOMETER"; }
	return data;
}

function meterImportToggle() {
	var panel = $("#meter-import-panel");
	$("#meter-import-status").hide();
	if (panel.is(":visible")) { panel.hide(); }
	else { panel.show(); $("#meter-import-text").focus(); }
}

function meterImportApply() {
	var meter;
	try { meter = meterImportParse($("#meter-import-text").val()); }
	catch (key) {
		smStatus("#meter-import-status", meterImportMsg[key] || meterImportMsg.PARSE, "error");
		return;
	}

	// The protocol drives which parameter rows are shown; only the ones the
	// plugin actually supports can be imported.
	var proto = String(meter.protocol == null ? "" : meter.protocol).toLowerCase();
	if (!/^(?:sml|d0|oms|exec|random)$/.test(proto)) {
		smStatus("#meter-import-status", meterImportMsg.PROTO, "error");
		return;
	}
	$("#meter-protocol").val(proto);
	meterApplyProto(proto, false);

	function has(k)   { return Object.prototype.hasOwnProperty.call(meter, k); }
	function bool(v)  { return (v === true || v === 1 || v === "1" || v === "true"); }

	// Every recognised meter-level parameter that the form has a field for.
	// device and name are deliberately left for the user; channels and all
	// root-level / unknown keys are ignored.
	if (has("enabled"))               { $("#meter-enabled").prop("checked", bool(meter.enabled)); }
	if (has("interval"))              { $("#meter-interval").val(meter.interval); }
	if (has("host"))                  { $("#meter-host").val(meter.host); }
	if (has("baudrate"))              { $("#meter-baudrate").val(String(meter.baudrate)); }
	if (has("baudrate_read"))         { $("#meter-baudrate-read").val(String(meter.baudrate_read)); }
	if (has("parity"))                { $("#meter-parity").val(String(meter.parity)); }
	if (has("read_timeout"))          { $("#meter-read-timeout").val(meter.read_timeout); }
	if (has("pullseq"))               { $("#meter-pullseq").val(meter.pullseq); }
	if (has("ackseq"))                { $("#meter-ackseq").val(meter.ackseq); }
	if (has("wait_sync"))             { $("#meter-wait-sync").val(String(meter.wait_sync)); }
	if (has("baudrate_change_delay")) { $("#meter-bcd").val(meter.baudrate_change_delay); }
	if (has("key"))                   { $("#meter-key").val(meter.key); }
	if (has("use_local_time"))        { $("#meter-uselocaltime").val(bool(meter.use_local_time) ? "1" : "0"); }
	if (has("min"))                   { $("#meter-min").val(meter.min); }
	if (has("max"))                   { $("#meter-max").val(meter.max); }
	if (has("command"))               { $("#meter-command").val(meter.command); }
	if (has("format"))                { $("#meter-format").val(meter.format); }

	$("#meter-import-text").val("");
	$("#meter-import-panel").hide();
	meterStatus(meterImportMsg.OK, "ok");
}

// =========================================================== CHANNELS TAB

var channelMsg = {
	UI_CHANNEL_METER_NOT_FOUND:    "<TMPL_VAR VZLOGGER.UI_CHANNEL_METER_NOT_FOUND>",
	UI_CHANNEL_INVALID_NAME:       "<TMPL_VAR VZLOGGER.UI_CHANNEL_INVALID_NAME>",
	UI_CHANNEL_INVALID_IDENTIFIER: "<TMPL_VAR VZLOGGER.UI_CHANNEL_INVALID_IDENTIFIER>",
	UI_CHANNEL_DUPLICATE_NAME:     "<TMPL_VAR VZLOGGER.UI_CHANNEL_DUPLICATE_NAME>",
	UI_CHANNEL_NOT_FOUND:          "<TMPL_VAR VZLOGGER.UI_CHANNEL_NOT_FOUND>",
	UI_DISCOVER_METER_NOT_FOUND:   "<TMPL_VAR VZLOGGER.UI_DISCOVER_METER_NOT_FOUND>",
	UI_AJAX_FAILED:                "<TMPL_VAR VZLOGGER.UI_AJAX_FAILED>"
};
var discText = {
	RUNNING: "<TMPL_VAR VZLOGGER.DISC_RUNNING>",
	NONE:    "<TMPL_VAR VZLOGGER.DISC_NONE>",
	SAVED:   "<TMPL_VAR COMMON.HINT_SAVED_RESTART>"
};
var channelText = {
	NONE:       "<TMPL_VAR VZLOGGER.CH_NONE>",
	ADD:        "<TMPL_VAR VZLOGGER.CH_ADD_HEADING>",
	EDIT:       "<TMPL_VAR VZLOGGER.CH_EDIT_HEADING>",
	EDITBTN:    "<TMPL_VAR VZLOGGER.CH_EDIT>",
	ADDBTN:     "<TMPL_VAR VZLOGGER.CH_ADD_BUTTON>",
	SAVEBTN:    "<TMPL_VAR VZLOGGER.CH_SAVE>",
	DELBTN:     "<TMPL_VAR VZLOGGER.CH_DELETE>",
	DELCONFIRM: "<TMPL_VAR VZLOGGER.CH_DELETE_CONFIRM>",
	SAVED:      "<TMPL_VAR COMMON.HINT_SAVED_RESTART>"
};

function channelStatus(message, kind) { smStatus("#channel-status", message, kind); }

function channelLoad() {
	$.ajax({ url: "ajax.cgi", type: "GET", dataType: "json", data: { action: "vzconf-get" } })
		.done(function(data) {
			var meters = (data && data.ok && data.config && data.config.meters) ? data.config.meters : [];
			channelFillMeters(meters);
			channelRenderList(meters);
		});
}

function channelFillMeters(meters) {
	["#ch-meter", "#disc-meter"].forEach(function(id) {
		var sel = $(id);
		if (!sel.length) { return; }
		var current = sel.val();
		sel.empty();
		meters.forEach(function(m) { sel.append($("<option>").val(m.name).text(m.name)); });
		if (current) { sel.val(current); }
	});
}

var channelMeters = [];        // last loaded meters (with channels), for edit lookup
var channelLastValues = {};    // last polled live values, keyed by channel uuid

function channelRenderList(meters) {
	channelMeters = meters || [];
	var body = $("#channels-body").empty();
	var rows = 0;
	channelMeters.forEach(function(m) {
		(m.channels || []).forEach(function(ch) {
			rows++;
			var edit = smIconBtn("channel-edit", "gear", channelText.EDITBTN, { meter: m.name, uuid: ch.uuid });
			var del  = smIconBtn("channel-del", "x", channelText.DELBTN, { meter: m.name, uuid: ch.uuid });
			body.append(
				"<tr><td>" + smEsc(m.name) + "</td><td>" + smEsc(ch.name) +
				"</td><td style=\"font-family:var(--lb-font-mono)\">" + smEsc(ch.identifier) +
				"</td><td class=\"ch-value\" data-uuid=\"" + smEsc(ch.uuid) + "\">–</td><td>" + edit + " " + del + "</td></tr>"
			);
		});
	});
	if (!rows) { body.append('<tr><td colspan="5">' + smEsc(channelText.NONE) + '</td></tr>'); }
	channelLiveApply(channelLastValues);
}

function channelFmt(v) {
	if (v == null || isNaN(v)) { return "–"; }
	return (Math.round(Number(v) * 100) / 100).toString();
}

// Every 5 s: fetch the current values from vzLogger's httpd and fill them in.
function channelLivePoll() {
	$.ajax({ url: "ajax.cgi", type: "GET", dataType: "json", data: { action: "vz-live" } })
		.done(function(data) {
			channelLastValues = (data && data.ok && data.values) ? data.values : {};
			channelLiveApply(channelLastValues);
		});
}

function channelLiveApply(values) {
	values = values || {};
	$("#channels-body .ch-value").each(function() {
		var uuid = $(this).attr("data-uuid");
		$(this).text(Object.prototype.hasOwnProperty.call(values, uuid) ? channelFmt(values[uuid]) : "–");
	});
}

function channelEdit(meter, uuid) {
	var found = null;
	channelMeters.forEach(function(m) {
		if (m.name !== meter) { return; }
		(m.channels || []).forEach(function(ch) { if (ch.uuid === uuid) { found = ch; } });
	});
	if (!found) { return; }
	channelFillMeters(channelMeters);
	$("#ch-original-meter").val(meter);
	$("#ch-original-uuid").val(uuid);
	$("#ch-meter").val(meter);
	$("#ch-identifier").val(found.identifier || "");
	$("#ch-name").val(found.name || "");
	$("#channel-form-title").text(channelText.EDIT);
	$("#ch-save-btn").text(channelText.SAVEBTN);
	$("#channel-status").css("display", "none");
}

function channelFormReset() {
	$("#ch-original-meter, #ch-original-uuid").val("");
	$("#ch-identifier, #ch-name").val("");
	$("#channel-form-title").text(channelText.ADD);
	$("#ch-save-btn").text(channelText.ADDBTN);
}

function channelSave() {
	var uuid = $("#ch-original-uuid").val();
	var form = { meter: $("#ch-meter").val(), identifier: $("#ch-identifier").val(), name: $("#ch-name").val() };
	var action = "vzconf-add-channel";
	if (uuid) {
		action = "vzconf-update-channel";
		form.uuid = uuid;
		form.original_meter = $("#ch-original-meter").val();
	}
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: action, channel: JSON.stringify(form) } })
		.done(function(data) {
			if (data && data.ok) {
				var meters = (data.config && data.config.meters) ? data.config.meters : [];
				channelFillMeters(meters);
				channelRenderList(meters);
				channelFormReset();
				channelStatus(channelText.SAVED, "ok");
			} else {
				channelStatus((data && channelMsg[data.error_key]) || channelMsg.UI_AJAX_FAILED, "error");
			}
		})
		.fail(function() { channelStatus(channelMsg.UI_AJAX_FAILED, "error"); });
}

function channelDelete(meter, uuid) {
	if (!window.confirm(channelText.DELCONFIRM)) { return; }
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: "vzconf-remove-channel", channel: JSON.stringify({ meter: meter, uuid: uuid }) } })
		.done(function(data) {
			if (data && data.ok) {
				channelRenderList((data.config && data.config.meters) ? data.config.meters : []);
				channelStatus(channelText.SAVED, "ok");
			} else {
				channelStatus((data && channelMsg[data.error_key]) || channelMsg.UI_AJAX_FAILED, "error");
			}
		})
		.fail(function() { channelStatus(channelMsg.UI_AJAX_FAILED, "error"); });
}

// OBIS auto-discovery: runs vzLogger briefly against the meter and lists the
// found identifiers as candidate channels to pick from.
function discoverStart() {
	var meter = $("#disc-meter").val();
	if (!meter) { return; }
	$("#disc-results").hide();
	smStatus("#disc-status", discText.RUNNING, "info");
	smSetBusy(true);
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: "meter-discover", meter: meter } })
		.done(function(data) {
			if (data && data.ok) {
				var cands = data.channels || [];
				discoverRender(cands);
				if (!cands.length) { smStatus("#disc-status", discText.NONE, "info"); }
				else { $("#disc-status").hide(); }
			} else {
				smStatus("#disc-status", (data && channelMsg[data.error_key]) || channelMsg.UI_AJAX_FAILED, "error");
			}
		})
		.fail(function() { smStatus("#disc-status", channelMsg.UI_AJAX_FAILED, "error"); })
		.always(function() { smSetBusy(false); });
}

function discoverRender(cands) {
	var body = $("#disc-body").empty();
	cands.forEach(function(ch) {
		var row = $("<tr>").attr("data-identifier", ch.identifier);
		row.append('<td><input type="checkbox" class="disc-pick" checked></td>');
		row.append($("<td>").css("font-family", "var(--lb-font-mono)").text(ch.identifier));
		var nameInput = $('<input class="lb-input disc-name" type="text">').val(ch.name);
		nameInput.on("input", function() { this.value = this.value.replace(/[^A-Za-z0-9_-]/g, ""); });
		row.append($("<td>").append(nameInput));
		body.append(row);
	});
	$("#disc-results").toggle(cands.length > 0);
}

function discoverApply() {
	var meter = $("#disc-meter").val();
	var chans = [];
	$("#disc-body tr").each(function() {
		if (!$(this).find(".disc-pick").is(":checked")) { return; }
		var name = $(this).find(".disc-name").val();
		var ident = $(this).attr("data-identifier");
		if (name && ident) { chans.push({ identifier: ident, name: name }); }
	});
	if (!chans.length) { return; }
	smSetBusy(true);
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: "vzconf-add-channels", channels: JSON.stringify({ meter: meter, channels: chans }) } })
		.done(function(data) {
			if (data && data.ok) {
				var meters = (data.config && data.config.meters) ? data.config.meters : [];
				channelFillMeters(meters);
				channelRenderList(meters);
				$("#disc-results").hide();
				smStatus("#disc-status", discText.SAVED, "ok");
			} else {
				smStatus("#disc-status", (data && channelMsg[data.error_key]) || channelMsg.UI_AJAX_FAILED, "error");
			}
		})
		.fail(function() { smStatus("#disc-status", channelMsg.UI_AJAX_FAILED, "error"); })
		.always(function() { smSetBusy(false); });
}

// =============================================================== UPGRADE TAB
var upgText = {
	NOVERSION: "<TMPL_VAR VZLOGGER.UPG_MSG_NOVERSION>",
	AVAILABLE: "<TMPL_VAR VZLOGGER.UPG_HINT_AVAILABLE>",
	UPTODATE:  "<TMPL_VAR VZLOGGER.UPG_HINT_UPTODATE>",
	NOVERHINT: "<TMPL_VAR VZLOGGER.UPG_HINT_NOVERSION>",
	UPGRADING: "<TMPL_VAR VZLOGGER.UPG_HINT_UPGRADING>",
	OK:        "<TMPL_VAR VZLOGGER.UPG_HINT_OK>",
	ERROR:     "<TMPL_VAR VZLOGGER.UPG_HINT_ERROR>"
};

// Loads the installed and available vzLogger versions and enables the update
// button only when a newer version exists.
function upgVersions() {
	$("#upg-current, #upg-available").text("…");
	$.ajax({ url: "ajax.cgi", type: "GET", dataType: "json", data: { action: "upgrade-versions" } })
		.done(function(data) {
			if (!data || !data.ok) { smStatus("#upg-version-hint", upgText.NOVERHINT, "error"); return; }
			$("#upg-current").text(data.current || upgText.NOVERSION);
			$("#upg-available").text(data.available || upgText.NOVERSION);
			if (data.update_available) {
				$("#upg-btn").prop("disabled", false);
				smStatus("#upg-version-hint", upgText.AVAILABLE, "info");
			} else {
				$("#upg-btn").prop("disabled", true);
				var known = data.current && data.available;
				smStatus("#upg-version-hint", known ? upgText.UPTODATE : upgText.NOVERHINT, known ? "ok" : "error");
			}
		})
		.fail(function() { smStatus("#upg-version-hint", upgText.NOVERHINT, "error"); });
}

// Runs the update; the button stays disabled during the run so it cannot be
// started twice. Status messages (blue/green/red) appear below the button.
function upgradeVzlogger() {
	if ($("#upg-btn").prop("disabled")) { return; }
	$("#upg-btn").prop("disabled", true);
	smStatus("#upg-status", upgText.UPGRADING, "info");
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: "upgrade-run" } })
		.done(function(data) {
			var ok = data && data.ok;
			smStatus("#upg-status", ok ? upgText.OK : upgText.ERROR, ok ? "ok" : "error");
			upgVersions();
		})
		.fail(function() { smStatus("#upg-status", upgText.ERROR, "error"); upgVersions(); });
}

</script>
