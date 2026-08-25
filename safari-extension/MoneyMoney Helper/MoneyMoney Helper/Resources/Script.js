function show(enabled, useSettingsInsteadOfPreferences) {
    if (useSettingsInsteadOfPreferences) {
        setText("state-on", "MoneyMoney Helper’s extension is currently on. You can turn it off in the Extensions section of Safari Settings.");
        setText("state-off", "MoneyMoney Helper’s extension is currently off. You can turn it on in the Extensions section of Safari Settings.");
        setText("state-unknown", "You can turn on MoneyMoney Helper’s extension in the Extensions section of Safari Settings. On macOS 27, enable the extension there — do not open “Edit Websites”.");
        setText("open-preferences", "Quit and Open Safari Settings…");
    }

    if (typeof enabled === "boolean") {
        document.body.classList.toggle("state-on", enabled);
        document.body.classList.toggle("state-off", !enabled);
    } else {
        document.body.classList.remove("state-on");
        document.body.classList.remove("state-off");
    }
}

function setText(className, text) {
    document.getElementsByClassName(className)[0].innerText = text;
}

function openPreferences() {
    webkit.messageHandlers.controller.postMessage("open-preferences");
}

document.querySelector("button.open-preferences").addEventListener("click", openPreferences);
