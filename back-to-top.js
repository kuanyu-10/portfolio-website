(() => {
    "use strict";

    const button = document.getElementById("back-to-top");
    if (!button) return;
    const value = button.querySelector(".back-to-top-value");

    const labels = {
        ja: "ページ上部へ戻る",
        zh: "返回頁面頂端",
        en: "Back to top"
    };
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    let ticking = false;

    function updateLabel() {
        const language = document.documentElement.lang.toLowerCase().split("-")[0];
        const label = labels[language] || labels.en;
        button.setAttribute("aria-label", label);
        button.title = label;
    }

    function updateVisibility() {
        const visible = window.scrollY > Math.min(560, window.innerHeight * 0.75);
        const scrollable = Math.max(document.documentElement.scrollHeight - window.innerHeight, 1);
        const progress = Math.min(Math.max(window.scrollY / scrollable, 0), 1);
        const percentage = `${Math.round(progress * 100)}%`;
        button.style.setProperty("--page-progress", percentage);
        if (value) value.textContent = percentage;
        button.classList.toggle("is-visible", visible);
        button.setAttribute("aria-hidden", String(!visible));
        button.tabIndex = visible ? 0 : -1;
        ticking = false;
    }

    function requestVisibilityUpdate() {
        if (ticking) return;
        ticking = true;
        window.requestAnimationFrame(updateVisibility);
    }

    button.addEventListener("click", () => {
        window.scrollTo({
            top: 0,
            behavior: reducedMotion.matches ? "auto" : "smooth"
        });
    });

    window.addEventListener("scroll", requestVisibilityUpdate, { passive: true });
    window.addEventListener("resize", requestVisibilityUpdate);

    new MutationObserver(updateLabel).observe(document.documentElement, {
        attributes: true,
        attributeFilter: ["lang"]
    });

    updateLabel();
    updateVisibility();
})();
