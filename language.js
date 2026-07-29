(() => {
    "use strict";

    const STORAGE_KEY = "portfolio-language";
    const SUPPORTED = new Set(["zh", "en", "ja"]);
    const HTML_LANG = { zh: "zh-Hant", en: "en", ja: "ja" };
    const ui = {
        ja: { label: "表示言語", auto: "自動", detected: "自動判定" },
        zh: { label: "顯示語言", auto: "自動", detected: "自動偵測" },
        en: { label: "Display language", auto: "Auto", detected: "Auto detected" }
    };
    let detectedLanguage = null;

    function getStoredLanguage() {
        try {
            const value = localStorage.getItem(STORAGE_KEY);
            return SUPPORTED.has(value) ? value : null;
        } catch { return null; }
    }

    function saveLanguage(language) {
        try {
            if (SUPPORTED.has(language)) localStorage.setItem(STORAGE_KEY, language);
            else localStorage.removeItem(STORAGE_KEY);
        } catch { /* Switching still works when storage is unavailable. */ }
    }

    function browserLanguage() {
        const languages = (navigator.languages?.length ? navigator.languages : [navigator.language || "en"])
            .map(value => value.toLowerCase());
        if (languages.some(value => value.startsWith("zh"))) return "zh";
        if (languages.some(value => value.startsWith("ja"))) return "ja";
        return "en";
    }

    function automaticLanguage() {
        try {
            const zone = Intl.DateTimeFormat().resolvedOptions().timeZone || "";
            if (["Asia/Taipei", "Asia/Hong_Kong", "Asia/Macau", "Asia/Shanghai", "Asia/Chongqing", "Asia/Urumqi"].includes(zone)) return "zh";
            if (zone === "Asia/Tokyo") return "ja";
            if (zone) return "en";
        } catch { /* Fall through when timezone detection is unavailable. */ }
        return browserLanguage();
    }

    function localizedAttribute(element, prefix, language) {
        return element.getAttribute(`data-${prefix}-${language}`);
    }

    function render(language) {
        const active = SUPPORTED.has(language) ? language : "en";
        document.documentElement.lang = HTML_LANG[active];
        document.documentElement.dataset.language = active;

        document.querySelectorAll("[data-ja][data-zh][data-en]").forEach(element => {
            element.textContent = element.getAttribute(`data-${active}`) || "";
        });
        document.querySelectorAll("[data-alt-ja][data-alt-zh][data-alt-en]").forEach(element => {
            element.alt = localizedAttribute(element, "alt", active) || "";
        });
        document.querySelectorAll("[data-aria-ja][data-aria-zh][data-aria-en]").forEach(element => {
            element.setAttribute("aria-label", localizedAttribute(element, "aria", active) || "");
        });

        const body = document.body;
        const suffix = active[0].toUpperCase() + active.slice(1);
        const title = body.dataset[`title${suffix}`];
        const descriptionText = body.dataset[`description${suffix}`];
        if (title) document.title = title;
        const description = document.querySelector('meta[name="description"]');
        if (description && descriptionText) description.content = descriptionText;

        const select = document.getElementById("language-select");
        const label = document.querySelector('label[for="language-select"]');
        if (select) {
            const automatic = select.value === "auto";
            const autoLanguage = detectedLanguage || active;
            const names = { zh: "中文", en: "English", ja: "日本語" };
            select.setAttribute("aria-label", ui[active].label);
            select.title = automatic ? `${ui[active].detected}: ${names[autoLanguage]}` : ui[active].label;
            select.options[0].textContent = automatic ? `${ui[active].auto} · ${names[autoLanguage]}` : ui[active].auto;
            select.options[1].textContent = "中文";
            select.options[2].textContent = "English";
            select.options[3].textContent = "日本語";
        }
        if (label) label.textContent = ui[active].label;
        window.dispatchEvent(new CustomEvent("portfolio:languagechange", { detail: { language: active } }));
    }

    function applyAutomaticLanguage() {
        detectedLanguage = automaticLanguage();
        render(detectedLanguage);
    }

    document.addEventListener("DOMContentLoaded", () => {
        const select = document.getElementById("language-select");
        const saved = getStoredLanguage();
        if (select) select.value = saved || "auto";
        if (saved) render(saved); else applyAutomaticLanguage();
        select?.addEventListener("change", () => {
            saveLanguage(select.value);
            if (select.value === "auto") applyAutomaticLanguage();
            else {
                detectedLanguage = null;
                render(select.value);
            }
        });
    });
})();