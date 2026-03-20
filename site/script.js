document.querySelectorAll("[data-copy-target]").forEach((button) => {
  button.addEventListener("click", async () => {
    const selector = button.getAttribute("data-copy-target");
    const target = selector ? document.querySelector(selector) : null;
    if (!target) {
      return;
    }

    const text = target.textContent?.trim() ?? "";
    if (!text) {
      return;
    }

    try {
      await navigator.clipboard.writeText(text);
      const original = button.textContent;
      button.textContent = "Copied";
      window.setTimeout(() => {
        button.textContent = original;
      }, 1400);
    } catch {
      button.textContent = "Copy failed";
      window.setTimeout(() => {
        button.textContent = "Copy";
      }, 1400);
    }
  });
});
