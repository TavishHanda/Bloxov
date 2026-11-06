// Bloxov player history (0.30.7): paste this into a Google Sheet's Apps Script (Extensions > Apps Script) and
// deploy it as a web app. The game server posts its player counts here every 5 minutes (Heroku config var
// STATS_URL = the web app URL). Numbers only: no names, no addresses. Steps: docs/PLAYER_HISTORY.md.
function doPost(e) {
  var d = JSON.parse(e.postData.contents);
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheets()[0];
  if (sheet.getLastRow() == 0) {
    sheet.appendRow(["Time", "Online", "In hideout", "In raids", "Raids", "Version"]);
  }
  var n = function (v) { return Math.max(0, Math.min(1000, Number(v) || 0)); };
  sheet.appendRow([new Date(), n(d.online), n(d.hideout), n(d.in_raids), n(d.raids), String(d.version || "").slice(0, 12)]);
  return ContentService.createTextOutput("ok");
}
