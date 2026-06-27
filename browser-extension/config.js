/** WebExtension-API (Chrome, Firefox, Safari). */
export const browserApi = globalThis.browser ?? globalThis.chrome;

/**
 * @param {Record<string, unknown>} raw
 * @returns {Record<string, import('./cookie-export.js').BankConfig>}
 */
export function parseBankConfig(raw) {
  /** @type {Record<string, import('./cookie-export.js').BankConfig>} */
  const banks = {};
  for (const [id, entry] of Object.entries(raw)) {
    const item = /** @type {Record<string, unknown>} */ (entry);
    banks[id] = {
      id,
      label: String(item.label),
      matchHost: new RegExp(String(item.match_host), 'i'),
      domains: /** @type {string[]} */ (item.domains),
      origins: /** @type {string[]} */ (item.origins),
      sessionHost: item.session_host ? String(item.session_host) : undefined,
      critical: /** @type {string[]} */ (item.critical),
      allowDuplicateNames: /** @type {string[]} */ (item.allow_duplicate_names ?? []),
      priority: /** @type {string[]} */ (item.priority),
    };
  }
  return banks;
}

export async function loadBankConfig() {
  const url = browserApi.runtime.getURL('cookie-export-banks.json');
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Bank-Konfiguration nicht ladbar (${response.status})`);
  }
  return parseBankConfig(await response.json());
}
