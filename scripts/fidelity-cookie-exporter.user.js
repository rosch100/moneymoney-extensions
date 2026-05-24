// ==UserScript==
// @name         Fidelity Cookie Exporter for MoneyMoney - ALL COOKIES
// @namespace    http://tampermonkey.net/
// @version      2.0
// @description  Export ALL Fidelity session cookies for MoneyMoney - includes all bot-mgmt, session, XSRF tokens
// @author       You
// @match        https://*.fidelity.com/*
// @match        https://fidelity.com/*
// @match        https://digital.fidelity.com/*
// @match        https://login.fidelity.com/*
// @grant        GM_setClipboard
// @grant        GM_notification
// @grant        GM_addStyle
// @run-at       document-start
// ==/UserScript==

(function() {
    'use strict';

    console.log('[Fidelity Cookie Exporter v2.0] Starting on:', window.location.href);

    // ALL cookies needed - in priority order for MoneyMoney
    const ALL_COOKIES_PRIORITY = [
        // BOT MANAGEMENT (Critical for Akamai bypass)
        '_abck', 'bm_sz', 'bm_s', 'bm_sv', 'bm_so', 'bm_ss', 'bm_mi', 'bm_lso', 'ak_bmsc',
        // SESSION AUTH (Critical for login state)
        'ATC', 'ATT', 'ET', 'SESSION_SCTX', 'JSESSIONID',
        // FIDELITY CORE
        'FC', 'MC', 'PIT', 'RC', 'SC', 'RtAzC', 'RtEntC',
        // XSRF/CSRF (Critical for API access)
        'PORTSUM_XSRF-TOKEN', 'FVL-XSRF-TOKEN', 'ap180806-XSRF-TOKEN',
        'RB-XSRF-TOKEN', 'URB-XSRF-TOKEN',
        '_fvl_neo.csrf', 'ap180806_neo.csrf', 'portsum_.csrf',
        '_ap126216-pwe.csrf', 'RB_felix.csrf', 'URB_neo.csrf',
        '_brkg.ap122489.equitytradeticket.csrf', '_tradecontainer.csrf',
        // APP STATUS
        'AP171348_HEADER_APP_SERVICE_COOKIE',
        // VISITOR/ANALYTICS (needed for consistency)
        'cvi', 'analytics_id',
        // ADOBE (often required by Akamai)
        'mbox', 'mboxEdgeCluster',
        'AMCV_EDCF01AC512D2B770A490D4C%40AdobeOrg',
        'AMCVS_EDCF01AC512D2B770A490D4C%40AdobeOrg',
        // LOAD BALANCER
        'AWSALB', 'AWSALBCORS',
        // CONSENT
        'OptanonConsent',
        // DATA MGMT
        'dmt_g', 'dmt_t', 'dmt_s', 'dmt_a', 'dmt_p', 'dmt_x',
        // MISC SESSION
        'npt', 's_sess', 's_pers', 'at_check', '_cs_ex', '_ldvid', '_cs_c', '_dd_s'
    ];

    let panelCreated = false;

    function getAllCookies() {
        const cookies = {};
        const cookieString = document.cookie;
        if (!cookieString) return cookies;

        cookieString.split(';').forEach(cookie => {
            const parts = cookie.trim().split('=');
            if (parts.length >= 2) {
                const name = parts[0].trim();
                const value = parts.slice(1).join('=').trim();
                if (name) cookies[name] = value;
            }
        });
        return cookies;
    }

    function formatAllCookies(cookies) {
        const pairs = [];
        const added = new Set();

        // First: priority order
        ALL_COOKIES_PRIORITY.forEach(name => {
            if (cookies[name] && !added.has(name)) {
                pairs.push(name + '=' + cookies[name]);
                added.add(name);
            }
        });

        // Second: all remaining cookies
        for (const [name, value] of Object.entries(cookies)) {
            if (!added.has(name)) {
                pairs.push(name + '=' + value);
                added.add(name);
            }
        }

        return pairs.join(';');
    }

    function escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    function createPanel() {
        if (panelCreated) return;

        const existing = document.getElementById('mm-cookie-panel');
        if (existing) existing.remove();

        const container = document.createElement('div');
        container.id = 'mm-cookie-panel';

        // Toggle button (always visible)
        const toggle = document.createElement('button');
        toggle.id = 'mm-toggle';
        toggle.innerHTML = '🍪';
        toggle.title = 'Fidelity Cookie Exporter (Alt+C)';

        // Main panel (initially hidden)
        const panel = document.createElement('div');
        panel.id = 'mm-panel';
        panel.innerHTML = `
            <div id="mm-header">
                <span>Fidelity → MoneyMoney</span>
                <button id="mm-close">✕</button>
            </div>
            <div id="mm-status">Checking cookies...</div>
            <button id="mm-copy-all" class="mm-btn-primary">📋 COPY ALL COOKIES</button>
            <button id="mm-copy-debug" class="mm-btn-secondary">🔍 Show Debug</button>
            <div id="mm-debug-area" style="display:none;margin-top:10px;"></div>
        `;

        container.appendChild(toggle);
        container.appendChild(panel);

        // Styles
        const style = document.createElement('style');
        style.textContent = `
            #mm-toggle {
                position: fixed !important;
                top: 80px !important;
                right: 20px !important;
                z-index: 2147483647 !important;
                width: 50px !important;
                height: 50px !important;
                border-radius: 50% !important;
                background: #4CAF50 !important;
                color: white !important;
                border: 3px solid white !important;
                font-size: 24px !important;
                cursor: pointer !important;
                box-shadow: 0 4px 15px rgba(0,0,0,0.4) !important;
                display: flex !important;
                align-items: center !important;
                justify-content: center !important;
            }
            #mm-panel {
                position: fixed !important;
                top: 80px !important;
                right: 20px !important;
                z-index: 2147483646 !important;
                width: 320px !important;
                background: linear-gradient(135deg, #1a5f2a, #0d3d18) !important;
                border-radius: 12px !important;
                padding: 16px !important;
                color: white !important;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif !important;
                font-size: 13px !important;
                box-shadow: 0 8px 32px rgba(0,0,0,0.3) !important;
                display: none !important;
            }
            #mm-panel.visible { display: block !important; }
            #mm-header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 12px;
                padding-bottom: 12px;
                border-bottom: 1px solid rgba(255,255,255,0.2);
                font-weight: 600;
            }
            #mm-close {
                background: rgba(255,255,255,0.15);
                border: none;
                color: white;
                padding: 4px 8px;
                border-radius: 4px;
                cursor: pointer;
            }
            #mm-status {
                padding: 10px;
                border-radius: 6px;
                margin-bottom: 12px;
                font-size: 12px;
                background: rgba(0,0,0,0.2);
            }
            #mm-status.ok { background: rgba(76,175,80,0.3); border: 1px solid rgba(76,175,80,0.5); }
            #mm-status.warn { background: rgba(255,152,0,0.3); border: 1px solid rgba(255,152,0,0.5); }
            #mm-status.error { background: rgba(244,67,54,0.3); border: 1px solid rgba(244,67,54,0.5); }
            .mm-btn-primary, .mm-btn-secondary {
                width: 100%;
                padding: 12px;
                border-radius: 6px;
                border: none;
                cursor: pointer;
                font-size: 13px;
                margin-bottom: 8px;
                font-weight: 600;
            }
            .mm-btn-primary {
                background: #4CAF50 !important;
                color: white !important;
            }
            .mm-btn-secondary {
                background: rgba(255,255,255,0.15) !important;
                color: white !important;
            }
            .mm-btn-primary:hover, .mm-btn-secondary:hover {
                opacity: 0.9;
                transform: translateY(-1px);
            }
        `;

        document.head.appendChild(style);

        if (document.body) {
            document.body.appendChild(container);
        } else {
            setTimeout(() => {
                if (document.body) document.body.appendChild(container);
            }, 500);
            return;
        }

        panelCreated = true;

        // Event handlers
        const toggleBtn = document.getElementById('mm-toggle');
        const panelEl = document.getElementById('mm-panel');
        const closeBtn = document.getElementById('mm-close');
        const copyBtn = document.getElementById('mm-copy-all');
        const debugBtn = document.getElementById('mm-copy-debug');

        toggleBtn.onclick = () => {
            panelEl.classList.toggle('visible');
            toggleBtn.style.display = panelEl.classList.contains('visible') ? 'none' : 'flex';
            updateStatus();
        };

        closeBtn.onclick = () => {
            panelEl.classList.remove('visible');
            toggleBtn.style.display = 'flex';
        };

        copyBtn.onclick = () => copyAllCookies();
        debugBtn.onclick = () => toggleDebug();

        updateStatus();
    }

    function updateStatus() {
        const statusEl = document.getElementById('mm-status');
        if (!statusEl) return;

        const cookies = getAllCookies();
        const cookieCount = Object.keys(cookies).length;

        // Check critical cookies
        const hasBot = !!(cookies['_abck'] || cookies['bm_sz']);
        const hasSession = !!(cookies['ATC'] || cookies['ET'] || cookies['SESSION_SCTX']);
        const hasXSRF = !!(cookies['PORTSUM_XSRF-TOKEN'] || cookies['FVL-XSRF-TOKEN']);

        if (hasBot && hasSession && hasXSRF) {
            statusEl.className = 'ok';
            statusEl.innerHTML = `✓ <strong>Session active!</strong><br>${cookieCount} cookies ready`;
        } else if (hasBot || hasSession) {
            statusEl.className = 'warn';
            let missing = [];
            if (!hasBot) missing.push('bot cookies');
            if (!hasSession) missing.push('session');
            if (!hasXSRF) missing.push('XSRF tokens');
            statusEl.innerHTML = `⚠ <strong>Partial session</strong><br>Missing: ${missing.join(', ')}`;
        } else {
            statusEl.className = 'error';
            statusEl.innerHTML = `✗ <strong>Not logged in</strong><br>Login to Fidelity first!`;
        }
    }

    function copyAllCookies() {
        const cookies = getAllCookies();
        const formatted = formatAllCookies(cookies);
        const output = 'COOKIE:' + formatted;

        console.log('[Fidelity Exporter] Copying', Object.keys(cookies).length, 'cookies');

        // Copy
        const ta = document.createElement('textarea');
        ta.value = output;
        ta.style.cssText = 'position:fixed;left:-9999px;';
        document.body.appendChild(ta);
        ta.select();
        ta.setSelectionRange(0, 999999);

        let copied = false;
        try {
            copied = document.execCommand('copy');
        } catch (e) {
            console.error('Copy failed:', e);
        }
        document.body.removeChild(ta);

        if (typeof GM_setClipboard !== 'undefined') {
            try { GM_setClipboard(output); copied = true; } catch(e) {}
        }

        const statusEl = document.getElementById('mm-status');
        if (copied) {
            statusEl.className = 'ok';
            statusEl.innerHTML = `✓ <strong>${Object.keys(cookies).length} cookies copied!</strong><br>Paste as password in MoneyMoney NOW!`;

            if (typeof GM_notification !== 'undefined') {
                GM_notification({
                    title: 'Fidelity Cookie Exporter',
                    text: `${Object.keys(cookies).length} cookies copied! Use immediately.`,
                    timeout: 5000
                });
            }

            // Flash button
            const btn = document.getElementById('mm-copy-all');
            const orig = btn.innerHTML;
            btn.innerHTML = '✓ COPIED!';
            btn.style.background = '#2196F3';
            setTimeout(() => {
                btn.innerHTML = orig;
                btn.style.background = '#4CAF50';
            }, 2000);

            alert(`✅ ${Object.keys(cookies).length} cookies copied!\n\nIMPORTANT: Use IMMEDIATELY in MoneyMoney!\n\n1. Open MoneyMoney NOW\n2. Edit Fidelity account\n3. Paste as PASSWORD\n4. Click OK\n\n(Cookies expire quickly!)`);
        } else {
            alert('⚠️ Copy failed. Please manually copy from debug view.');
        }
    }

    function toggleDebug() {
        const debugArea = document.getElementById('mm-debug-area');
        if (!debugArea) return;

        if (debugArea.style.display === 'none') {
            const cookies = getAllCookies();
            const formatted = formatAllCookies(cookies);
            debugArea.innerHTML = `
                <textarea style="width:100%;height:150px;font-size:10px;font-family:monospace;" onclick="this.select()">${escapeHtml('COOKIE:' + formatted)}</textarea>
                <div style="margin-top:8px;font-size:11px;">
                    <strong>Critical cookies:</strong><br>
                    _abck: ${cookies['_abck'] ? '✓' : '✗'} |
                    bm_sz: ${cookies['bm_sz'] ? '✓' : '✗'} |
                    ATC: ${cookies['ATC'] ? '✓' : '✗'} |
                    ET: ${cookies['ET'] ? '✓' : '✗'} |
                    SESSION_SCTX: ${cookies['SESSION_SCTX'] ? '✓' : '✗'} |
                    PIT: ${cookies['PIT'] ? '✓' : '✗'} |
                    XSRF: ${cookies['PORTSUM_XSRF-TOKEN'] ? '✓' : '✗'}
                </div>
            `;
            debugArea.style.display = 'block';
        } else {
            debugArea.style.display = 'none';
        }
    }

    // Initialize
    function init() {
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', createPanel);
        } else {
            createPanel();
        }
    }

    init();

    // Re-create on SPA navigation
    let lastUrl = location.href;
    setInterval(() => {
        if (location.href !== lastUrl) {
            lastUrl = location.href;
            panelCreated = false;
            setTimeout(createPanel, 500);
        }
    }, 1000);

    // Keyboard shortcut
    document.addEventListener('keydown', (e) => {
        if (e.altKey && e.key === 'c') {
            e.preventDefault();
            const toggle = document.getElementById('mm-toggle');
            if (toggle) toggle.click();
        }
    });

    console.log('[Fidelity Exporter v2.0] Ready. Press Alt+C or click 🍪 button.');
})();
