document.addEventListener("DOMContentLoaded", () => {
  // Theme Toggle with LocalStorage
  const themeToggleBtn = document.getElementById("themeToggle");
  const currentTheme =
    localStorage.getItem("theme") ||
    (window.matchMedia("(prefers-color-scheme: light)").matches
      ? "light"
      : "dark");

  document.documentElement.setAttribute("data-theme", currentTheme);
  updateThemeButtonText(currentTheme);

  if (themeToggleBtn) {
    themeToggleBtn.addEventListener("click", () => {
      const activeTheme = document.documentElement.getAttribute("data-theme");
      const newTheme = activeTheme === "light" ? "dark" : "light";
      document.documentElement.setAttribute("data-theme", newTheme);
      localStorage.setItem("theme", newTheme);
      updateThemeButtonText(newTheme);
    });
  }

  function updateThemeButtonText(theme) {
    if (themeToggleBtn) {
      themeToggleBtn.textContent =
        theme === "light" ? "Dark Theme" : "Light Theme";
    }
  }

  // Copy-to-Clipboard Buttons
  document.querySelectorAll(".copy-btn").forEach((button) => {
    button.addEventListener("click", () => {
      const codeBlock = button.closest(".code-block");
      const pre = codeBlock ? codeBlock.querySelector("pre") : null;
      if (!pre) return;

      const codeText = pre.innerText;
      navigator.clipboard
        .writeText(codeText)
        .then(() => {
          const originalText = button.textContent;
          button.textContent = "Copied!";
          button.classList.add("copied");
          setTimeout(() => {
            button.textContent = originalText;
            button.classList.remove("copied");
          }, 2000);
        })
        .catch((err) => {
          console.error("Failed to copy text: ", err);
        });
    });
  });

  // Tab Group Switching
  document.querySelectorAll(".tab-group").forEach((group) => {
    const buttons = group.querySelectorAll(".tab-btn");
    const contents = group.querySelectorAll(".tab-content");

    buttons.forEach((btn) => {
      btn.addEventListener("click", () => {
        const targetTab = btn.getAttribute("data-tab");

        buttons.forEach((b) => b.classList.remove("active"));
        contents.forEach((c) => c.classList.remove("active"));

        btn.classList.add("active");
        const activeContent = group.querySelector(`#${targetTab}`);
        if (activeContent) {
          activeContent.classList.add("active");
        }
      });
    });
  });

  // Accordion Expand/Collapse
  document.querySelectorAll(".accordion-header").forEach((header) => {
    header.addEventListener("click", () => {
      const item = header.parentElement;
      const isOpen = item.classList.contains("open");

      // Optional: Close siblings
      const parent = item.parentElement;
      if (parent) {
        parent.querySelectorAll(".accordion-item").forEach((sibling) => {
          sibling.classList.remove("open");
        });
      }

      if (!isOpen) {
        item.classList.add("open");
      }
    });
  });
});
