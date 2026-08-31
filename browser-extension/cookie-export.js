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
    if (bank.matchHost.test(host)) {
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

/** @typedef {'permission' | 'empty' | 'missing' | 'partial'} ExportBlockReason */

/**
 * @param {CookieEntry[]} cookies
 * @param {string[]} missing
 * @param {string[]} failedOrigins
 * @returns {ExportBlockReason | null}
 */
export function exportBlockReason(cookies, missing, failedOrigins) {
  if (failedOrigins.length > 0 && cookies.length === 0) {
    return 'permission';
  }
  if (cookies.length === 0) {
    return 'empty';
  }
  if (missing.length > 0) {
    return 'missing';
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
  if (bank.id === 'mlp') {
    return 'Vertragsübersicht auf vue.mlp.de öffnen, dann erneut exportieren.';
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
 * @param {import('./config.js').browserApi} api
 * @param {BankConfig} bank
 * @returns {Promise<CookieCollectResult>}
 */
export async function collectCookies(api, bank) {
  /** @type {Map<string, CookieEntry>} */
  const merged = new Map();
  /** @type {string[]} */
  const failedOrigins = [];

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

  /**
   * @param {string} origin
   */
  async function addFromOrigin(origin) {
    const url = `${origin}/`;
    const hostname = new URL(origin).hostname;
    let gotAny = false;
    let queryFailed = false;

    for (const details of [{ url }, { domain: hostname }]) {
      try {
        const list = await api.cookies.getAll(details);
        if (list.length > 0) {
          gotAny = true;
        }
        mergeList(list);
      } catch {
        queryFailed = true;
      }
    }

    if (queryFailed && !gotAny) {
      failedOrigins.push(origin);
    }
  }

  // host_permissions == origins (keine *.domain-Wildcards wegen Safari 27)
  for (const origin of bank.origins) {
    await addFromOrigin(origin);
  }

  return {
    cookies: Array.from(merged.values()),
    failedOrigins,
  };
}
