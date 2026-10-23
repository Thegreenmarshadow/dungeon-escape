// The page state lives in the URL hash, so every view can be shared:
//   #/<section>[/<arg>][?player=Ana&mode=normal...]
// "player" is the global filter: it follows every link. The other parameters
// belong to the section that shows them.

export const GLOBAL_PARAMS = ["player"];
export const DEFAULT_SECTION = "ranking";

export function currentRoute() {
  const raw = location.hash.replace(/^#/, "") || `/${DEFAULT_SECTION}`;
  const [path, query = ""] = raw.split("?");
  const [, section = "", arg = ""] = path.split("/");
  let decoded = arg;
  try {
    decoded = decodeURIComponent(arg);
  } catch {
    // A malformed escape: keep the text as it came.
  }
  return { section: section || DEFAULT_SECTION, arg: decoded, params: new URLSearchParams(query) };
}

export function globalParams() {
  const { params } = currentRoute();
  return Object.fromEntries(GLOBAL_PARAMS.filter((key) => params.get(key)).map((key) => [key, params.get(key)]));
}

function buildHash(section, arg, query) {
  const path = `#/${section}${arg !== "" && arg !== undefined && arg !== null ? `/${encodeURIComponent(arg)}` : ""}`;
  const text = query.toString();
  return text ? `${path}?${text}` : path;
}

/** Link to a section that keeps the global filter. extra adds (or, with "",
 * removes) parameters of that section. */
export function hrefTo(section, arg = "", extra = {}) {
  const query = new URLSearchParams(globalParams());
  for (const [key, value] of Object.entries(extra)) {
    if (value === "" || value === null || value === undefined) query.delete(key);
    else query.set(key, value);
  }
  return buildHash(section, arg, query);
}

/** Changes parameters of the current view. push adds a history entry (the
 * global filter); filters of a section replace the current one. */
export function setParams(changes, { push = false } = {}) {
  const { section, arg, params } = currentRoute();
  for (const [key, value] of Object.entries(changes)) {
    if (value === "" || value === null || value === undefined) params.delete(key);
    else params.set(key, value);
  }
  const hash = buildHash(section, arg, params);
  if (hash === location.hash) return;
  if (push) {
    location.hash = hash;
  } else {
    history.replaceState(null, "", hash);
    window.dispatchEvent(new HashChangeEvent("hashchange"));
  }
}
