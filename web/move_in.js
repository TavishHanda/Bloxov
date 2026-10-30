// Bloxov's move to bloxov.com (0.25.5): brings a player's save over from the old site.
//
// Saves live in the browser per site, so tavishhanda.github.io's save can't be read from bloxov.com. Once the game
// is on bloxov.com, GitHub sends the old address straight here, so the old page never runs. Instead, the first time
// a browser opens bloxov.com with no save, this sends it once to the move page on the old site
// (MOVE_PAGE, web/move/index.html in the repo). That page reads the old save and comes back to
// bloxov.com/#move=<save>, and this puts it where the game looks for its save (localStorage, see Profile._web_read
// and GameSettings._web_read). A browser that already has a save here is never sent, and never overwritten.
// Runs before the game loads (export_presets.cfg head_include); does nothing on any other site.
(function () {
  var MOVE_PAGE = "https://tavishhanda.github.io/bloxov-move/";
  var host = location.hostname;
  if (host !== "bloxov.com" && host !== "www.bloxov.com") return;
  try {
    var store = window.localStorage;
    var hash = location.hash;
    if (hash.indexOf("#move=") === 0) {
      history.replaceState(null, "", location.pathname + location.search);
      store.setItem("bloxov_move", "done");
      var save = hash.length > 6 ? JSON.parse(decodeURIComponent(hash.slice(6))) : null;
      if (save && save.format === "bloxov-save" && !store.getItem("bloxov_profile")) {
        if (typeof save.profile === "string" && save.profile) store.setItem("bloxov_profile", save.profile);
        if (typeof save.settings === "string" && save.settings && !store.getItem("bloxov_settings"))
          store.setItem("bloxov_settings", save.settings);
      }
      return;
    }
    if (store.getItem("bloxov_move") || store.getItem("bloxov_profile")) return;
    store.setItem("bloxov_move", "asked");  // set first: never more than one trip, even if the move page fails
    location.replace(MOVE_PAGE);
  } catch (e) {}
})();
