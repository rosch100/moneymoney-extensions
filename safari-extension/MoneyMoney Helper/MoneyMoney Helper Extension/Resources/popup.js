import { browserApi, loadBankConfig } from './config.js';
import {
  buildHint,
  collectCookies,
  detectBank,
  exportBlockReason,
  formatCookieExport,
  missingCritical,
} from './cookie-export.js';

const titleEl = document.getElementById('title');
const statusEl = document.getElementById('status');
const copyBtn = document.getElementById('copy');
const hintEl = document.getElementById('hint');

const COPY_BUTTON_LABEL = 'Cookies kopieren';
const COPIED_BUTTON_LABEL = 'Kopiert';
const STATUS_COPIED = 'In Zwischenablage kopiert';

let currentExport = '';

function setStatus(text, level) {
  statusEl.textContent = text;
  statusEl.className = level || '';
}

function partialAccessHint(failedOrigins) {
  return `Teilweise kein Cookie-Zugriff: ${failedOrigins.join(', ')}`;
}

async function refresh(banks) {
  const tabs = await browserApi.tabs.query({ active: true, currentWindow: true });
  const tab = tabs[0];
  if (!tab?.url?.startsWith('http')) {
    setStatus('Kein Bank-Tab aktiv', 'error');
    hintEl.textContent = 'Bank-Website in diesem Tab öffnen.';
    copyBtn.disabled = true;
    return;
  }

  const host = new URL(tab.url).hostname.replace(/^www\./, '');

  const bank = detectBank(host, banks);
  if (!bank) {
    setStatus('Bank nicht erkannt', 'error');
    titleEl.textContent = 'MoneyMoney';
    hintEl.textContent = 'Unterstützt: Fidelity, Bank of America, MLP Versicherungen.';
    copyBtn.disabled = true;
    return;
  }

  titleEl.textContent = bank.label;
  const { cookies, failedOrigins } = await collectCookies(browserApi, bank);
  currentExport = formatCookieExport(cookies, bank);

  const missing = missingCritical(cookies, bank);
  hintEl.textContent = buildHint(bank, missing, host);
  const blockReason = exportBlockReason(cookies, missing, failedOrigins);

  if (blockReason === 'permission') {
    setStatus('Cookie-Zugriff fehlgeschlagen', 'error');
    hintEl.textContent =
      'Berechtigung für diese Bank-Seite fehlt oder wurde verweigert (Safari: Extension in der Toolbar erlauben).';
    copyBtn.disabled = true;
    return;
  }

  if (blockReason === 'empty') {
    setStatus('Nicht eingeloggt oder keine Cookies', 'error');
    copyBtn.disabled = true;
    return;
  }

  if (failedOrigins.length > 0) {
    hintEl.textContent = [hintEl.textContent, partialAccessHint(failedOrigins)]
      .filter(Boolean)
      .join(' ');
  }

  if (blockReason === 'missing') {
    setStatus(`Fehlt: ${missing.join(', ')}`, 'warn');
    copyBtn.disabled = true;
    return;
  }

  if (blockReason === 'partial') {
    setStatus('Cookie-Zugriff unvollständig', 'warn');
    copyBtn.disabled = true;
    return;
  }

  setStatus(`${cookies.length} Cookies bereit`, 'ok');
  copyBtn.disabled = false;
}

async function copyExport() {
  if (!currentExport) {
    return;
  }

  try {
    await navigator.clipboard.writeText(currentExport);
    setStatus(STATUS_COPIED, 'ok');
    copyBtn.textContent = COPIED_BUTTON_LABEL;
    setTimeout(() => {
      copyBtn.textContent = COPY_BUTTON_LABEL;
    }, 1500);
  } catch {
    setStatus('Zwischenablage nicht verfügbar', 'error');
  }
}

async function init() {
  copyBtn.addEventListener('click', copyExport);
  try {
    const banks = await loadBankConfig();
    await refresh(banks);
  } catch (error) {
    setStatus('Konfiguration fehlerhaft', 'error');
    hintEl.textContent = error instanceof Error ? error.message : String(error);
    copyBtn.disabled = true;
  }
}

init();
