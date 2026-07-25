<script>

// Shared JavaScript for all tabs. Appended to every template, so it may use
// TMPL_VAR tags for localized strings. Data comes from ajax.cgi (relative URL).

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
			"<tr><td>" + irheadEsc(r.name) + "</td><td>" + irheadEsc(r.device) +
			"</td><td>" + irheadEsc(r.target) + "</td><td>" + irheadEsc(r.serial) +
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
		var button = '<button type="button" class="lb-btn lb-btn-icon lb-btn-danger lb-btn-sm irhead-remove" data-device="' +
			irheadEsc(r.device) + '" title="' + irheadEsc(irheadRemove_title) + '">&times;</button>';
		body.append("<tr><td>" + irheadEsc(r.name) + "</td><td>" + irheadEsc(r.device) + "</td><td>" + button + "</td></tr>");
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

</script>
