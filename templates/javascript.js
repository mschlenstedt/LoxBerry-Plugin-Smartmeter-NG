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
	if ($("#irheads-auto-body").length) {
		irheadLoad();
		// Keep the manual name field to letters, digits, underscore and hyphen.
		$("#irhead-name").on("input", function() {
			this.value = this.value.replace(/[^A-Za-z0-9_-]/g, "");
		});
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
		$("#meter-protocol").on("change", function() { meterApplyProto($(this).val(), true); });
		$("#meter-device").on("change", meterPrefillName);
		$(document).on("click", ".meter-edit", function() { meterEdit($(this).data("name")); });
		$(document).on("click", ".meter-del", function() { meterDelete($(this).data("name")); });
		meterLoadDevices();
		meterLoadList();
		meterApplyProto($("#meter-protocol").val(), false);
	}
});

// ============================================================ I/R READING HEADS

var irheadMsg = {
	UI_IRHEAD_INVALID_DEVICE: "<TMPL_VAR VZLOGGER.UI_IRHEAD_INVALID_DEVICE>",
	UI_IRHEAD_INVALID_NAME:   "<TMPL_VAR VZLOGGER.UI_IRHEAD_INVALID_NAME>",
	UI_IRHEAD_DUPLICATE:      "<TMPL_VAR VZLOGGER.UI_IRHEAD_DUPLICATE>",
	UI_IRHEAD_NOT_FOUND:      "<TMPL_VAR VZLOGGER.UI_IRHEAD_NOT_FOUND>",
	UI_POST_REQUIRED:         "<TMPL_VAR VZLOGGER.UI_POST_REQUIRED>",
	UI_UNKNOWN_ACTION:        "<TMPL_VAR VZLOGGER.UI_UNKNOWN_ACTION>",
	UI_AJAX_FAILED:           "<TMPL_VAR VZLOGGER.UI_AJAX_FAILED>"
};
var irheadNone   = "<TMPL_VAR VZLOGGER.IRHEAD_NONE>";
var irheadRemove_title = "<TMPL_VAR VZLOGGER.IRHEAD_REMOVE>";

function irheadEsc(value) {
	return $("<div>").text(value == null ? "" : value).html();
}

function irheadStatus(message, ok) {
	$("#irhead-status").text(message).css("display", "block").toggleClass("lb-callout-warning", !ok);
}

function irheadClearStatus() {
	$("#irhead-status").css("display", "none").removeClass("lb-callout-warning");
}

function irheadRenderAuto(rows) {
	var body = $("#irheads-auto-body").empty();
	if (!rows || !rows.length) {
		body.append('<tr><td colspan="6">' + irheadEsc(irheadNone) + '</td></tr>');
		return;
	}
	rows.forEach(function(r) {
		var hw = [r.vendor, r.model].filter(Boolean).join(" ");
		body.append(
			"<tr><td>" + irheadEsc(r.name) + "</td><td style=\"font-family:var(--lb-font-mono)\">" + irheadEsc(r.device) +
			"</td><td style=\"font-family:var(--lb-font-mono)\">" + irheadEsc(r.target) + "</td><td>" + irheadEsc(r.serial) +
			"</td><td>" + irheadEsc(r.usbport) + "</td><td>" + irheadEsc(hw) + "</td></tr>"
		);
	});
}

function irheadRenderManual(rows) {
	var body = $("#irheads-manual-body").empty();
	if (!rows || !rows.length) {
		body.append('<tr><td colspan="3">' + irheadEsc(irheadNone) + '</td></tr>');
		return;
	}
	rows.forEach(function(r) {
		var button = '<button type="button" class="lb-btn lb-btn-icon lb-btn-danger lb-btn-sm irhead-remove" style="padding:1px 8px; font-size:15px; line-height:1.4;" data-device="' +
			irheadEsc(r.device) + '" title="' + irheadEsc(irheadRemove_title) + '">&times;</button>';
		body.append("<tr><td>" + irheadEsc(r.name) + "</td><td style=\"font-family:var(--lb-font-mono)\">" + irheadEsc(r.device) + "</td><td>" + button + "</td></tr>");
	});
}

function irheadApply(data) {
	irheadRenderAuto(data.auto);
	irheadRenderManual(data.manual);
}

function irheadLoad() {
	$.ajax({ url: "ajax.cgi", type: "GET", dataType: "json", data: { action: "irheads-list" } })
		.done(function(data) { if (data && data.ok) { irheadApply(data); } })
		.fail(function() { irheadStatus(irheadMsg.UI_AJAX_FAILED, false); });
}

function irheadAdd() {
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
				irheadClearStatus();
			} else {
				irheadStatus((data && irheadMsg[data.error_key]) || irheadMsg.UI_AJAX_FAILED, false);
				if (data && data.auto) { irheadApply(data); }
			}
		})
		.fail(function() { irheadStatus(irheadMsg.UI_AJAX_FAILED, false); });
}

function irheadRemove(device) {
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: "irheads-remove", device: device } })
		.done(function(data) {
			if (data && data.ok) { irheadApply(data); irheadClearStatus(); }
			else { irheadStatus((data && irheadMsg[data.error_key]) || irheadMsg.UI_AJAX_FAILED, false); }
		})
		.fail(function() { irheadStatus(irheadMsg.UI_AJAX_FAILED, false); });
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

function smServiceRender() {
	document.getElementById("vz-service").innerHTML =
		'<div class="vzsvc">' +
			'<div class="vzsvc-info">' +
				'<div class="vzsvc-label">' + smEsc(smSvc.LABEL) + '</div>' +
				'<div id="vz-svc-icon"><img src="images/unknown_20.png" alt=""></div>' +
				'<div class="vzsvc-box" id="vz-svc-box">' + smEsc(smSvc.UNKNOWN) + '</div>' +
			'</div>' +
			'<div class="vzsvc-btns">' +
				'<a href="#" class="vzsvc-btn" onclick="smServiceRestart(); return false;"><span class="vzsvc-ico"><i class="pi pi-check"></i></span>' + smEsc(smSvc.RESTART) + '</a>' +
				'<a href="#" class="vzsvc-btn" onclick="smServiceStop(); return false;"><span class="vzsvc-ico"><i class="pi pi-times"></i></span>' + smEsc(smSvc.STOP) + '</a>' +
			'</div>' +
		'</div><hr><br>';
}

function smServiceIcon(name) {
	$("#vz-svc-icon").html('<img src="images/' + name + '" alt="">');
}

function smServiceBox(style, html) {
	$("#vz-svc-box").attr("style", style).html(html);
}

function smServiceFailed() {
	smServiceBox("background:#dfdfdf; color:red", smEsc(smSvc.FAILED));
	smServiceIcon("unknown_20.png");
}

function smServiceShow(data) {
	if (data && data.ok && data.running && data.pid) {
		smServiceBox("background:#6dac20; color:black", '<span class="vzsvc-small">PID: ' + smEsc(data.pid) + '</span>');
		smServiceIcon("check_20.png");
	} else if (data && data.ok) {
		smServiceBox("background:#FF6339; color:black", smEsc(smSvc.STOPPED));
		smServiceIcon("error_20.png");
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
	smServiceIcon("unknown_20.png");
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: action } })
		.done(smServiceShow)
		.fail(smServiceFailed)
		.always(function() { smInterval = window.setInterval(smServiceStatus, 5000); });
}

function smServiceRestart() { smServiceRun("vz-restart"); }
function smServiceStop() { smServiceRun("vz-stop"); }

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
		var edit = '<button type="button" class="lb-btn lb-btn-sm meter-edit" data-name="' + smEsc(m.name) + '">' + smEsc(meterText.EDITBTN) + '</button>';
		var del  = '<button type="button" class="lb-btn lb-btn-sm lb-btn-danger meter-del" data-name="' + smEsc(m.name) + '">' + smEsc(meterText.DELBTN) + '</button>';
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
		max:                   $("#meter-max").val()
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
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: action, meter: JSON.stringify(form) } })
		.done(function(data) {
			if (meterApply(data)) { meterFormReset(); meterStatus(meterText.SAVED, "ok"); }
		})
		.fail(function() { meterStatus(meterMsg.UI_AJAX_FAILED, "error"); });
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
	$("#meter-form-title").text(meterText.ADD);
	meterStatusClear();
}

</script>
