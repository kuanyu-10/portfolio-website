(() => {
    "use strict";

    const toggle = document.querySelector(".menu-toggle");
    const menu = document.getElementById("nav-menu");
    if (!toggle || !menu) return;

    const labels = {
        ja: { open: "メニューを開く", close: "メニューを閉じる" },
        zh: { open: "開啟選單", close: "關閉選單" },
        en: { open: "Open menu", close: "Close menu" }
    };

    function activeLanguage() {
        const language = document.documentElement.lang.toLowerCase().split("-")[0];
        return labels[language] ? language : "en";
    }

    function setMenu(open) {
        menu.classList.toggle("is-open", open);
        toggle.setAttribute("aria-expanded", String(open));
        toggle.setAttribute("aria-label", labels[activeLanguage()][open ? "close" : "open"]);
    }

    toggle.addEventListener("click", () => setMenu(toggle.getAttribute("aria-expanded") !== "true"));
    menu.addEventListener("click", event => {
        if (event.target.closest("a")) setMenu(false);
    });
    document.addEventListener("keydown", event => {
        if (event.key === "Escape" && toggle.getAttribute("aria-expanded") === "true") {
            setMenu(false);
            toggle.focus();
        }
    });
    window.addEventListener("resize", () => {
        if (window.innerWidth > 820) setMenu(false);
    });
    new MutationObserver(() => setMenu(toggle.getAttribute("aria-expanded") === "true")).observe(document.documentElement, { attributes: true, attributeFilter: ["lang"] });
    setMenu(false);

    const nav = document.querySelector(".site-nav");
    const links = [...menu.querySelectorAll('a[href^="#"]')];
    const sections = links.map(link => document.querySelector(link.getAttribute("href"))).filter(Boolean);
    let scrollTicking = false;

    function updateNavigationState() {
        nav?.classList.toggle("is-scrolled", window.scrollY > 20);
        const marker = Math.min(window.innerHeight * 0.34, 240);
        let current = sections[0]?.id;
        sections.forEach(section => {
            if (section.getBoundingClientRect().top <= marker) current = section.id;
        });
        links.forEach(link => {
            const active = link.getAttribute("href") === `#${current}`;
            if (active) link.setAttribute("aria-current", "page");
            else link.removeAttribute("aria-current");
        });
        scrollTicking = false;
    }

    function requestNavigationUpdate() {
        if (scrollTicking) return;
        scrollTicking = true;
        window.requestAnimationFrame(updateNavigationState);
    }

    window.addEventListener("scroll", requestNavigationUpdate, { passive: true });
    window.addEventListener("resize", requestNavigationUpdate);
    updateNavigationState();
})();
