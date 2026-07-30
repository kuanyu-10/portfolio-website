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

// Premium motion and reading progress
(() => {
    "use strict";

    const progress = document.querySelector(".scroll-progress span");
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let progressTicking = false;

    function updateProgress() {
        const scrollable = Math.max(document.documentElement.scrollHeight - window.innerHeight, 1);
        const ratio = Math.min(Math.max(window.scrollY / scrollable, 0), 1);
        if (progress) progress.style.transform = `scaleX(${ratio})`;
        progressTicking = false;
    }

    function requestProgressUpdate() {
        if (progressTicking) return;
        progressTicking = true;
        window.requestAnimationFrame(updateProgress);
    }

    window.addEventListener("scroll", requestProgressUpdate, { passive: true });
    window.addEventListener("resize", requestProgressUpdate);
    updateProgress();

    const targets = [...document.querySelectorAll(".home-main > .section")];
    if (reducedMotion || !("IntersectionObserver" in window)) {
        targets.forEach(target => target.classList.add("is-visible"));
        return;
    }

    document.documentElement.classList.add("reveal-enabled");
    targets.forEach(target => target.classList.add("reveal-target"));
    const observer = new IntersectionObserver(entries => {
        entries.forEach(entry => {
            if (!entry.isIntersecting) return;
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
        });
    }, { threshold: 0.08, rootMargin: "0px 0px -48px" });
    targets.forEach(target => observer.observe(target));
})();
// Accessible award certificate lightbox
(() => {
    "use strict";

    const dialog = document.getElementById("award-lightbox");
    const image = dialog?.querySelector("figure img");
    const caption = document.getElementById("award-lightbox-caption");
    const closeButton = dialog?.querySelector(".award-lightbox-close");
    const triggers = [...document.querySelectorAll(".award-lightbox-trigger")];
    if (!dialog || !image || !caption || !closeButton || !triggers.length) return;

    let activeTrigger = null;

    function languageSuffix() {
        const language = document.documentElement.dataset.language || "en";
        return language.charAt(0).toUpperCase() + language.slice(1);
    }

    function updateContent(trigger) {
        const sourceImage = trigger.querySelector("img");
        image.src = trigger.dataset.lightboxSrc || sourceImage?.src || "";
        image.alt = sourceImage?.alt || "";
        caption.textContent = trigger.dataset[`caption${languageSuffix()}`] || "";
    }

    function openLightbox(trigger) {
        activeTrigger = trigger;
        updateContent(trigger);
        dialog.showModal();
        document.body.classList.add("lightbox-open");
        closeButton.focus();
    }

    function closeLightbox() {
        if (dialog.open) dialog.close();
    }

    triggers.forEach(trigger => trigger.addEventListener("click", () => openLightbox(trigger)));
    closeButton.addEventListener("click", closeLightbox);
    dialog.addEventListener("click", event => {
        if (event.target === dialog) closeLightbox();
    });
    dialog.addEventListener("close", () => {
        document.body.classList.remove("lightbox-open");
        image.removeAttribute("src");
        activeTrigger?.focus();
        activeTrigger = null;
    });
    window.addEventListener("portfolio:languagechange", () => {
        if (activeTrigger && dialog.open) updateContent(activeTrigger);
    });
})();
// Case study section navigation
(() => {
    "use strict";

    const index = document.querySelector(".case-index");
    if (!index) return;

    const links = [...index.querySelectorAll('a[href^="#"]')];
    const sections = links
        .map(link => document.querySelector(link.getAttribute("href")))
        .filter(Boolean);
    let ticking = false;

    function update() {
        const marker = Math.min(window.innerHeight * 0.32, 230);
        let current = sections[0]?.id;
        sections.forEach(section => {
            if (section.getBoundingClientRect().top <= marker) current = section.id;
        });
        links.forEach(link => {
            const active = link.getAttribute("href") === `#${current}`;
            if (active) link.setAttribute("aria-current", "true");
            else link.removeAttribute("aria-current");
        });
        ticking = false;
    }

    function requestUpdate() {
        if (ticking) return;
        ticking = true;
        window.requestAnimationFrame(update);
    }

    window.addEventListener("scroll", requestUpdate, { passive: true });
    window.addEventListener("resize", requestUpdate);
    update();
})();