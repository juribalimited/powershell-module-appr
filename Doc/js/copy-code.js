/* ============================================================
   Juriba App Readiness Docs — Code Block Enhancements
   ============================================================ */
(function () {
  "use strict";

  /* ---------- Copy Button for Code Blocks ------------------ */
  function addCopyButtons() {
    var blocks = document.querySelectorAll("pre > code");

    blocks.forEach(function (codeEl) {
      var pre = codeEl.parentElement;
      if (!pre) return;

      // Wrap pre in a relative container if not already wrapped
      var wrapper = pre.parentElement;
      if (!wrapper || !wrapper.classList.contains("code-block-wrapper")) {
        wrapper = document.createElement("div");
        wrapper.className = "code-block-wrapper";
        pre.parentNode.insertBefore(wrapper, pre);
        wrapper.appendChild(pre);
      }

      // Create copy button
      var btn = document.createElement("button");
      btn.className = "copy-btn";
      btn.textContent = "Copy";
      btn.setAttribute("aria-label", "Copy code to clipboard");
      btn.type = "button";

      btn.addEventListener("click", function () {
        var text = codeEl.textContent || "";
        navigator.clipboard.writeText(text).then(function () {
          btn.textContent = "Copied!";
          btn.classList.add("copied");
          setTimeout(function () {
            btn.textContent = "Copy";
            btn.classList.remove("copied");
          }, 1500);
        }, function () {
          // Fallback for older browsers / insecure contexts
          fallbackCopy(text, btn);
        });
      });

      wrapper.appendChild(btn);
    });
  }

  /* Fallback copy using a temporary textarea */
  function fallbackCopy(text, btn) {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.left = "-9999px";
    document.body.appendChild(ta);
    ta.select();
    try {
      document.execCommand("copy");
      btn.textContent = "Copied!";
      btn.classList.add("copied");
      setTimeout(function () {
        btn.textContent = "Copy";
        btn.classList.remove("copied");
      }, 1500);
    } catch (e) {
      btn.textContent = "Failed";
      setTimeout(function () { btn.textContent = "Copy"; }, 1500);
    }
    document.body.removeChild(ta);
  }

  /* ---------- Smooth Details/Summary Toggle ----------------- */
  function enhanceDetails() {
    var allDetails = document.querySelectorAll("details");

    allDetails.forEach(function (det) {
      var summary = det.querySelector("summary");
      if (!summary) return;

      // Get the content elements (everything after summary)
      summary.addEventListener("click", function (e) {
        e.preventDefault();

        if (det.open) {
          // Closing: animate then remove open
          var content = det.querySelector(":scope > :not(summary)");
          if (content) {
            content.style.overflow = "hidden";
            content.style.maxHeight = content.scrollHeight + "px";
            // Force reflow
            content.offsetHeight; // eslint-disable-line no-unused-expressions
            content.style.transition = "max-height .25s ease, opacity .25s ease";
            content.style.maxHeight = "0";
            content.style.opacity = "0";
            content.addEventListener("transitionend", function handler() {
              content.removeEventListener("transitionend", handler);
              det.open = false;
              content.style.maxHeight = "";
              content.style.opacity = "";
              content.style.overflow = "";
              content.style.transition = "";
            });
          } else {
            det.open = false;
          }
        } else {
          // Opening: set open then animate in
          det.open = true;
          var content = det.querySelector(":scope > :not(summary)");
          if (content) {
            content.style.overflow = "hidden";
            content.style.maxHeight = "0";
            content.style.opacity = "0";
            // Force reflow
            content.offsetHeight; // eslint-disable-line no-unused-expressions
            content.style.transition = "max-height .3s ease, opacity .3s ease";
            content.style.maxHeight = content.scrollHeight + "px";
            content.style.opacity = "1";
            content.addEventListener("transitionend", function handler() {
              content.removeEventListener("transitionend", handler);
              content.style.maxHeight = "";
              content.style.overflow = "";
              content.style.transition = "";
            });
          }
        }
      });
    });
  }

  /* ---------- Init ----------------------------------------- */
  function init() {
    addCopyButtons();
    enhanceDetails();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
