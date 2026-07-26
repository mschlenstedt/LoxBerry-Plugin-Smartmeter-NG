<script>

// Shared JavaScript for all tabs. Appended to every template, so it may use
// TMPL_VAR tags for localized strings. Data comes from ajax.cgi (relative URL).

// Inject shared styles that are not part of the LoxBerry Design System: the
// vzLogger service-status block and the grey "?" help button placed next to a
// form label (linking into the Volkszaehler wiki).
(function() {
	var css =
		".sm-service{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:10px;margin-bottom:10px;}" +
		".sm-service-info{display:flex;align-items:center;gap:10px;flex-wrap:wrap;}" +
		".sm-service-label{font-weight:600;}" +
		".sm-service-badge{display:inline-flex;align-items:center;gap:6px;padding:4px 12px;border-radius:14px;font-size:0.9rem;color:#fff;}" +
		".sm-service-badge-ok{background:#4a9e2f;}" +
		".sm-service-badge-off{background:#d9534f;}" +
		".sm-service-badge-unknown{background:#8a8a8a;}" +
		".sm-service-btns{display:flex;gap:6px;flex-wrap:wrap;}" +
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
		window.setInterval(smServiceStatus, 5000);
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

var smSvc = {
	LABEL:   "<TMPL_VAR COMMON.SERVICE_LABEL>",
	RESTART: "<TMPL_VAR COMMON.SERVICE_RESTART>",
	STOP:    "<TMPL_VAR COMMON.SERVICE_STOP>",
	RUNNING: "<TMPL_VAR COMMON.SERVICE_RUNNING>",
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
		'<div class="sm-service">' +
			'<div class="sm-service-info">' +
				'<span class="sm-service-label">' + smEsc(smSvc.LABEL) + '</span>' +
				'<span class="sm-service-badge sm-service-badge-unknown" id="sm-service-badge">' +
					'<i class="pi pi-question-circle"></i> <span>' + smEsc(smSvc.UNKNOWN) + '</span>' +
				'</span>' +
			'</div>' +
			'<div class="sm-service-btns">' +
				'<button type="button" class="lb-btn lb-btn-sm lb-btn-primary" onclick="smServiceRestart(); return false;">' + smEsc(smSvc.RESTART) + '</button>' +
				'<button type="button" class="lb-btn lb-btn-sm" onclick="smServiceStop(); return false;">' + smEsc(smSvc.STOP) + '</button>' +
			'</div>' +
		'</div><hr>';
}

function smServiceBadge(kind, text) {
	var icon = kind === "ok" ? "pi-check-circle" : (kind === "off" ? "pi-times-circle" : "pi-question-circle");
	$("#sm-service-badge")
		.removeClass("sm-service-badge-ok sm-service-badge-off sm-service-badge-unknown")
		.addClass("sm-service-badge-" + kind)
		.html('<i class="pi ' + icon + '"></i> <span>' + smEsc(text) + '</span>');
}

function smServiceShow(data) {
	if (data && data.ok) {
		if (data.running) {
			smServiceBadge("ok", smSvc.RUNNING + (data.pid ? " · PID " + data.pid : ""));
		} else {
			smServiceBadge("off", smSvc.STOPPED);
		}
	} else {
		smServiceBadge("unknown", smSvc.FAILED);
	}
}

function smServiceStatus() {
	$.ajax({ url: "ajax.cgi", type: "GET", dataType: "json", data: { action: "vz-status" } })
		.done(smServiceShow)
		.fail(function() { smServiceBadge("unknown", smSvc.FAILED); });
}

function smServiceRun(action) {
	smServiceBadge("unknown", smSvc.WORKING);
	$.ajax({ url: "ajax.cgi", type: "POST", dataType: "json", data: { action: action } })
		.done(smServiceShow)
		.fail(function() { smServiceBadge("unknown", smSvc.FAILED); });
}

function smServiceRestart() { smServiceRun("vz-restart"); }
function smServiceStop() { smServiceRun("vz-stop"); }

</script>
