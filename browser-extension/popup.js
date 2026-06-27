import { browserApi, loadBankConfig } from './config.js';
import {
  buildHint,
  collectCookies,
  detectBank,
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
  const cookies = await collectCookies(browserApi, bank);
  currentExport = formatCookieExport(cookies, bank);

  const missing = missingCritical(cookies, bank);
  hintEl.textContent = buildHint(bank, cookies, host);

  if (cookies.length === 0) {
    setStatus('Nicht eingeloggt oder keine Cookies', 'error');
    copyBtn.disabled = true;
    return;
  }

  if (missing.length === 0) {
    setStatus(`${cookies.length} Cookies bereit`, 'ok');
    copyBtn.disabled = false;
    return;
  }

  setStatus(`Fehlt: ${missing.join(', ')}`, 'warn');
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
