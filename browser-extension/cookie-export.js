/**
 * @typedef {Object} BankConfig
 * @property {string} id
 * @property {string} label
 * @property {RegExp} matchHost
 * @property {string[]} origins
 * @property {string} [sessionHost]
 * @property {string[]} critical
 * @property {string[]} allowDuplicateNames
 * @property {string[]} priority
 */

/**
 * @typedef {Object} CookieEntry
 * @property {string} name
 * @property {string} value
 * @property {string} [domain]
 * @property {string} [path]
 */

/**
 * @param {string} hostname
 * @param {Record<string, BankConfig>} banks
 * @returns {BankConfig | null}
 */
export function detectBank(hostname, banks) {
  const host = hostname.replace(/^www\./, '');
  for (const bank of Object.values(banks)) {
    const originHosts = bank.origins.map((origin) => new URL(origin).hostname);
    const isConfiguredParent = originHosts.some(
      (originHost) => originHost.endsWith(`.${host}`),
    );
    if (
      (originHosts.includes(hostname) || isConfiguredParent)
      && bank.matchHost.test(host)
    ) {
      return bank;
    }
  }
  return null;
}

/**
 * @param {CookieEntry[]} cookies
 * @param {BankConfig} bank
 */
export function formatCookieExport(cookies, bank) {
  const pairs = [];
  const usedNames = new Set();

  for (const dupName of bank.allowDuplicateNames) {
    const matches = cookies.filter((cookie) => cookie.name === dupName);
    for (const cookie of matches) {
      pairs.push(`${cookie.name}=${cookie.value}`);
    }
    if (matches.length > 0) {
      usedNames.add(dupName);
    }
  }

  for (const name of bank.priority) {
    if (usedNames.has(name)) {
      continue;
    }
    const match = cookies.find((cookie) => cookie.name === name);
    if (match) {
      pairs.push(`${match.name}=${match.value}`);
      usedNames.add(name);
    }
  }

  const rest = cookies
    .filter((cookie) => !usedNames.has(cookie.name))
    .sort((a, b) => a.name.localeCompare(b.name));
  for (const cookie of rest) {
    pairs.push(`${cookie.name}=${cookie.value}`);
  }

  return `COOKIE:${pairs.join(';')}`;
}

/**
 * @param {CookieEntry[]} cookies
 * @param {BankConfig} bank
 */
export function missingCritical(cookies, bank) {
  return bank.critical.filter(
    (name) => !cookies.some((cookie) => cookie.name === name),
  );
}

/** @typedef {'permission' | 'empty' | 'partial'} ExportBlockReason */

/**
 * Fehlende Cookies blockieren den Export nicht: Es werden immer alle
 * verfügbaren Cookies kopiert. Nur wenn gar keine Cookies lesbar sind,
 * ist kein sinnvoller Export möglich.
 *
 * @param {CookieEntry[]} cookies
 * @param {string[]} failedOrigins
 * @returns {ExportBlockReason | null}
 */
export function exportBlockReason(cookies, failedOrigins) {
  if (failedOrigins.length > 0 && cookies.length === 0) {
    return 'permission';
  }
  if (cookies.length === 0) {
    return 'empty';
  }
  if (failedOrigins.length > 0) {
    return 'partial';
  }
  return null;
}

/**
 * @param {BankConfig} bank
 * @param {string[]} missing
 * @param {string} tabHost
 */
export function buildHint(bank, missing, tabHost) {
  if (missing.length === 0) {
    return '';
  }
  if (bank.sessionHost && tabHost !== bank.sessionHost) {
    return `Bitte ${bank.sessionHost} öffnen (eingeloggt, Kontoseite).`;
  }
  if (bank.id === 'fidelity') {
    return 'Portfolio Summary öffnen, „Don\'t ask again on this device“ bei MFA.';
  }
  if (bank.id === 'boa') {
    return 'Kontoübersicht auf secure.bankofamerica.com öffnen.';
  }
  return `Fehlende Cookies: ${missing.join(', ')}`;
}

/**
 * @typedef {Object} CookieCollectResult
 * @property {CookieEntry[]} cookies
 * @property {string[]} failedOrigins Origins, deren cookies.getAll fehlgeschlagen ist
 */

/**
 * Ermittelt die Cookie-Speicher, die abgefragt werden müssen.
 *
 * Safari (ab macOS 26) legt die Cookies der laufenden Sitzung in einem
 * eigenen Store ab. Ohne storeId liefert cookies.getAll dort eine leere
 * Liste. Abgefragt wird deshalb der Store des aktiven Tabs.
 *
 * @param {import('./config.js').browserApi} api
 * @param {number | undefined} tabId
 * @returns {Promise<string[]>}
 */
async function resolveCookieStoreIds(api, tabId) {
  const stores = await api.cookies.getAllCookieStores();
  const activeStores = typeof tabId === 'number'
    ? stores.filter((store) => store.tabIds?.includes(tabId))
    : [];
  const selected = activeStores.length > 0 ? activeStores : stores;
  const storeIds = selected
    .map((store) => store.id)
    .filter((storeId) => typeof storeId === 'string' && storeId.length > 0);

  if (storeIds.length === 0) {
    throw new Error('Kein Cookie-Speicher gefunden');
  }
  return storeIds;
}

/**
 * @param {import('./config.js').browserApi} api
 * @param {BankConfig} bank
 * @param {string} [activeUrl]
 * @param {number} [tabId]
 * @returns {Promise<CookieCollectResult>}
 */
export async function collectCookies(api, bank, activeUrl, tabId) {
  /** @type {Map<string, CookieEntry>} */
  const merged = new Map();
  /** @type {string[]} */
  const failedOrigins = [];
  const failedOriginSet = new Set();

  /**
   * @param {string} label
   */
  function markFailure(label) {
    if (failedOriginSet.has(label)) {
      return;
    }
    failedOriginSet.add(label);
    failedOrigins.push(label);
  }

  /**
   * @param {chrome.cookies.Cookie} item
   */
  function cookieKey(item) {
    return `${item.name}|${item.domain}|${item.path}|${item.storeId ?? ''}`;
  }

  /**
   * @param {chrome.cookies.Cookie[]} list
   */
  function mergeList(list) {
    for (const item of list) {
      if (!item?.name) {
        continue;
      }
      merged.set(cookieKey(item), {
        name: item.name,
        value: item.value,
        domain: item.domain,
        path: item.path,
      });
    }
  }

  let storeIds;
  try {
    storeIds = await resolveCookieStoreIds(api, tabId);
  } catch (error) {
    markFailure(error instanceof Error ? error.message : String(error));
    return { cookies: [], failedOrigins };
  }

  /**
   * @param {Record<string, string>} details
   * @param {string} failureLabel
   */
  async function addQuery(details, failureLabel) {
    let queryFailed = false;

    for (const storeId of storeIds) {
      const query = { ...details, storeId };
      try {
        const list = await api.cookies.getAll(query);
        mergeList(list);
      } catch {
        queryFailed = true;
      }
    }

    if (queryFailed) {
      markFailure(failureLabel);
    }
  }

  /**
   * @param {string} origin
   */
  async function addFromOrigin(origin) {
    const url = `${origin}/`;
    const hostname = new URL(origin).hostname;
    await addQuery({ url }, origin);
    await addQuery({ domain: hostname }, origin);
  }

  // host_permissions == origins (keine *.domain-Wildcards wegen Safari 27)
  for (const origin of bank.origins) {
    await addFromOrigin(origin);
  }

  let active;
  if (activeUrl) {
    try {
      active = new URL(activeUrl);
    } catch {
      markFailure(activeUrl);
    }
  }

  if (active) {
    await addQuery({ url: activeUrl }, active.origin);

    const labels = active.hostname.split('.');
    while (labels.length > 2) {
      labels.shift();
      const domain = labels.join('.');
      await addQuery({ domain }, `https://${domain}`);
    }
  }

  return {
    cookies: Array.from(merged.values()),
    failedOrigins,
  };
}
