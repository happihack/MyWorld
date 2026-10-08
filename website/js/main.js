// My World in a Box — website: the navigation bar, things fading in as they come
// into view, and the gallery's lightbox. No libraries.

(() => {
  // The navigation bar turns solid once the page is scrolled.
  const nav = document.querySelector(".nav");
  const onScroll = () => nav.classList.toggle("is-solid", window.scrollY > 40);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  // Fade in as they come into view.
  const reveal = document.querySelectorAll(".feature, .pillar, .arc__steps li, .screens__row figure, .shot, .section__head");
  if ("IntersectionObserver" in window) {
    const seen = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-in");
          seen.unobserve(entry.target);
        }
      }
    }, { rootMargin: "0px 0px -8% 0px" });
    reveal.forEach((el, i) => {
      el.classList.add("reveal");
      el.style.transitionDelay = `${(i % 4) * 70}ms`;
      seen.observe(el);
    });
  }

  // The gallery's lightbox: click to enlarge; arrows, Escape, swipe.
  const box = document.querySelector(".lightbox");
  const big = box.querySelector("img");
  const shots = [...document.querySelectorAll(".shot")];
  let at = 0;
  const show = (i) => {
    at = (i + shots.length) % shots.length;
    big.src = shots[at].dataset.full;
    big.alt = shots[at].querySelector("img").alt;
  };
  const open = (i) => { show(i); box.hidden = false; document.body.style.overflow = "hidden"; };
  const close = () => { box.hidden = true; document.body.style.overflow = ""; };
  shots.forEach((shot, i) => shot.addEventListener("click", () => open(i)));
  box.querySelector(".lightbox__close").addEventListener("click", close);
  box.querySelector(".lightbox__nav--prev").addEventListener("click", (e) => { e.stopPropagation(); show(at - 1); });
  box.querySelector(".lightbox__nav--next").addEventListener("click", (e) => { e.stopPropagation(); show(at + 1); });
  box.addEventListener("click", (e) => { if (e.target === box) close(); });
  document.addEventListener("keydown", (e) => {
    if (box.hidden) return;
    if (e.key === "Escape") close();
    if (e.key === "ArrowLeft") show(at - 1);
    if (e.key === "ArrowRight") show(at + 1);
  });
  let startX = null;
  box.addEventListener("touchstart", (e) => { startX = e.touches[0].clientX; }, { passive: true });
  box.addEventListener("touchend", (e) => {
    if (startX === null) return;
    const dx = e.changedTouches[0].clientX - startX;
    if (Math.abs(dx) > 40) show(at + (dx < 0 ? 1 : -1));
    startX = null;
  });

  // This year in the footer.
  const year = document.querySelector("[data-year]");
  if (year) year.textContent = new Date().getFullYear();
})();
