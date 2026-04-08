/* ============================================================
   Juriba App Readiness Docs — Sidebar Navigation
   ============================================================ */
(function () {
  "use strict";

  /* ---------- Navigation Structure ------------------------- */
  var NAV = [
    { title: "Home",                   href: "index.html" },
    { title: "Getting Started",        href: "getting-started.html" },
    { title: "Connection & Security",  href: "connection-security.html" },
    {
      title: "Cmdlet Reference",
      children: [
        { title: "Instance Configuration", href: "cmdlets-instance-config.html" },
        { title: "Applications",           href: "cmdlets-applications.html" },
        { title: "Upload & Create",        href: "cmdlets-upload-create.html" },
        { title: "Knowledge Base",         href: "cmdlets-knowledge-base.html" },
        { title: "Packages",              href: "cmdlets-packages.html" },
        { title: "Testing",               href: "cmdlets-testing.html" },
        { title: "Quality Review",         href: "cmdlets-quality-review.html" },
        { title: "Publishing",             href: "cmdlets-publishing.html" },
        { title: "Generic Integration",    href: "cmdlets-generic-integration.html" }
      ]
    },
    { title: "Workflows",             href: "workflows.html" },
    { title: "Examples Guide",         href: "examples.html" },
    { title: "Quick Reference",        href: "reference-quick.html" }
  ];

  /* ---------- Helpers -------------------------------------- */
  function currentPage() {
    var path = window.location.pathname;
    var parts = path.replace(/\\/g, "/").split("/");
    return parts[parts.length - 1] || "index.html";
  }

  function el(tag, attrs, children) {
    var node = document.createElement(tag);
    if (attrs) {
      Object.keys(attrs).forEach(function (k) {
        if (k === "className") { node.className = attrs[k]; }
        else if (k === "textContent") { node.textContent = attrs[k]; }
        else { node.setAttribute(k, attrs[k]); }
      });
    }
    if (children) {
      children.forEach(function (c) { if (c) node.appendChild(c); });
    }
    return node;
  }

  /* ---------- Build Sidebar -------------------------------- */
  function buildSidebar() {
    var page = currentPage();

    // Sidebar container
    var sidebar = el("nav", { className: "sidebar", id: "sidebar" });

    // Header
    var header = el("div", { className: "sidebar-header" });
    var logoLink = el("a", { className: "logo-text", href: "index.html", textContent: "Juriba App Readiness" });
    var sub = el("span", { className: "logo-sub", textContent: "PowerShell Module Docs" });
    header.appendChild(logoLink);
    header.appendChild(sub);
    sidebar.appendChild(header);

    // Nav list
    var navWrap = el("div", { className: "sidebar-nav" });
    var rootUl = el("ul");

    NAV.forEach(function (item) {
      var li = el("li");

      if (item.children) {
        // Expandable group
        var isChildActive = item.children.some(function (c) { return c.href === page; });

        li.className = "nav-group" + (isChildActive ? " expanded" : "");

        var btn = el("button", { className: "nav-group-toggle", textContent: item.title });
        btn.addEventListener("click", function () {
          li.classList.toggle("expanded");
        });
        li.appendChild(btn);

        var subUl = el("ul", { className: "nav-group-items" });
        item.children.forEach(function (child) {
          var subLi = el("li");
          var a = el("a", { href: child.href, textContent: child.title });
          if (child.href === page) { a.className = "active"; }
          subLi.appendChild(a);
          subUl.appendChild(subLi);
        });
        li.appendChild(subUl);
      } else {
        // Simple link
        var a = el("a", { href: item.href, textContent: item.title });
        if (item.href === page) { a.className = "active"; }
        li.appendChild(a);
      }

      rootUl.appendChild(li);
    });

    navWrap.appendChild(rootUl);
    sidebar.appendChild(navWrap);

    return sidebar;
  }

  /* ---------- Hamburger & Overlay -------------------------- */
  function buildHamburger() {
    var btn = el("button", { className: "hamburger", id: "hamburger" });
    btn.innerHTML = "&#9776;";
    btn.setAttribute("aria-label", "Toggle navigation");
    return btn;
  }

  function buildOverlay() {
    return el("div", { className: "sidebar-overlay", id: "sidebar-overlay" });
  }

  function bindMobileToggle() {
    var hamburger = document.getElementById("hamburger");
    var sidebar   = document.getElementById("sidebar");
    var overlay   = document.getElementById("sidebar-overlay");

    if (!hamburger || !sidebar || !overlay) return;

    function open()  { sidebar.classList.add("open"); overlay.classList.add("visible"); }
    function close() { sidebar.classList.remove("open"); overlay.classList.remove("visible"); }

    hamburger.addEventListener("click", function () {
      sidebar.classList.contains("open") ? close() : open();
    });

    overlay.addEventListener("click", close);

    // Close on Escape
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") close();
    });
  }

  /* ---------- Init ----------------------------------------- */
  function init() {
    var body = document.body;

    // Insert hamburger, overlay, and sidebar at the start of body
    var frag = document.createDocumentFragment();
    frag.appendChild(buildHamburger());
    frag.appendChild(buildOverlay());
    frag.appendChild(buildSidebar());
    body.insertBefore(frag, body.firstChild);

    // Ensure the main content wrapper exists
    // (Pages should have a <div class="main"> wrapping their content.)
    bindMobileToggle();
  }

  // Run on DOMContentLoaded
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
