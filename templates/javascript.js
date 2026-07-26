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
		".sm-help{display:inline-flex;align-items:center;justify-content:center;width:20px;height:20px;margin-left:6px;padding:0;border-radius:50%;background:#8a8a8a;color:#fff;font-size:12px;line-height:1;text-decoration:none;vertical-align:middle;}" +
		".sm-help:hover{background:#6f6f6f;}";
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
		$("#set-topic, #set-localport, #set-retry").on("blur", setSaveSettings);
		setLoad();
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
		'</div><hr>';
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
var setAutosave = false;

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
		})
		.always(function() { setAutosave = true; });
}

function setSaveSettings() {
	if (!setAutosave) return;
	var patch = {
		retry: $("#set-retry").val(),
		local: { port: $("#set-localport").val() },
		mqtt:  { topic: $("#set-topic").val() }
	};
	$("#set-savinghint").attr("style", "color:blue").html(smEsc(setMsg.SAVING));
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: "vzconf-set-settings", settings: JSON.stringify(patch) } })
		.done(function(data) {
			if (data && data.ok) { $("#set-savinghint").attr("style", "color:orange").html(smEsc(setMsg.SAVED_RESTART)); }
			else { $("#set-savinghint").attr("style", "color:red").html(smEsc(setMsg.SAVING_FAILED)); }
		})
		.fail(function() { $("#set-savinghint").attr("style", "color:red").html(smEsc(setMsg.SAVING_FAILED)); });
}

</script>
