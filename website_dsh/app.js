/* 一读 · One Read — 官网交互（简洁版）
   进度细线、导航高亮、渐入、打字机、封面倾斜、标注点、
   四刊卡片、FAQ、实机录屏的可见即播。 */
(function () {
  'use strict';

  const $ = (s, c) => (c || document).querySelector(s);
  const $$ = (s, c) => Array.from((c || document).querySelectorAll(s));
  const finePointer = window.matchMedia('(pointer: fine)').matches;
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  if (!reducedMotion) document.documentElement.classList.add('motion-on');

  /* ── 页眉与进度细线 ── */
  const header = $('#site-header');
  const ribbonFill = $('#ribbon-fill');
  let ticking = false;
  let docMax = 0;
  const measure = () => { docMax = Math.max(0, document.documentElement.scrollHeight - innerHeight); };
  const onScroll = () => {
    const p = docMax > 0 ? Math.min(1, Math.max(0, scrollY / docMax)) : 0;
    ribbonFill.style.transform = 'scaleX(' + p.toFixed(4) + ')';
    header.classList.toggle('scrolled', scrollY > 8);
  };
  measure();
  window.addEventListener('resize', measure, { passive: true });
  window.addEventListener('load', measure);
  document.addEventListener('scroll', () => {
    if (!ticking) { ticking = true; requestAnimationFrame(() => { onScroll(); ticking = false; }); }
  }, { passive: true });
  onScroll();

  /* ── 导航高亮 ── */
  const navSections = $$('section[data-nav]');
  const navLinks = $$('#nav-links a[data-nav]');
  const spy = new IntersectionObserver((entries) => {
    entries.forEach((en) => {
      if (en.isIntersecting) {
        navLinks.forEach((a) => a.classList.toggle('active', a.dataset.nav === en.target.dataset.nav));
      }
    });
  }, { rootMargin: '-38% 0px -52% 0px' });
  navSections.forEach((s) => spy.observe(s));

  /* ── 滚动渐入 ── */
  const groups = new Map();
  $$('.reveal').forEach((el) => {
    const parent = el.parentElement;
    if (!groups.has(parent)) groups.set(parent, 0);
    el.style.setProperty('--stagger', Math.min(groups.get(parent) * 45, 220) + 'ms');
    groups.set(parent, groups.get(parent) + 1);
  });
  const revealer = new IntersectionObserver((entries) => {
    entries.forEach((en) => { if (en.isIntersecting) { en.target.classList.add('visible'); revealer.unobserve(en.target); } });
  }, { rootMargin: '0px 0px 6% 0px', threshold: 0.01 });
  $$('.reveal').forEach((el) => revealer.observe(el));

  /* ── 打字机 ── */
  const typedEl = $('#cover-typed');
  if (typedEl) {
    const phrases = ['Read a little.', 'See a little more.', 'Keep every word.'];
    if (reducedMotion) { typedEl.textContent = phrases.join(' · '); }
    else {
      let pi = 0, ci = 0, deleting = false;
      const caret = document.createElement('span');
      caret.className = 'caret';
      typedEl.append(caret);
      const tick = () => {
        const phrase = phrases[pi];
        if (!deleting) {
          ci++;
          typedEl.firstChild.textContent = phrase.slice(0, ci);
          if (ci === phrase.length) { deleting = true; setTimeout(tick, 2200); return; }
          setTimeout(tick, 55 + Math.random() * 60);
        } else {
          ci--;
          typedEl.firstChild.textContent = phrase.slice(0, ci);
          if (ci === 0) { deleting = false; pi = (pi + 1) % phrases.length; setTimeout(tick, 420); return; }
          setTimeout(tick, 26);
        }
      };
      typedEl.prepend(document.createTextNode(''));
      setTimeout(tick, 900);
    }
  }

  /* ── 封面书架倾斜（rAF 节流，移动中关闭过渡避免拖拽感） ── */
  const plateFrame = $('.plate-frame');
  if (plateFrame && finePointer && !reducedMotion) {
    const plate = $('#cover-plate');
    let raf = null, ex = 0, ey = 0;
    const render = () => {
      raf = null;
      const r = plate.getBoundingClientRect();
      const px = (ex - r.left) / r.width;
      const py = (ey - r.top) / r.height;
      const ry = (px - 0.5) * 7;
      const rx = (0.5 - py) * 5;
      plateFrame.style.transform = 'rotateY(' + ry.toFixed(2) + 'deg) rotateX(' + rx.toFixed(2) + 'deg)';
    };
    plate.addEventListener('pointermove', (e) => {
      ex = e.clientX; ey = e.clientY;
      plateFrame.style.transition = 'none';
      if (!raf) raf = requestAnimationFrame(render);
    }, { passive: true });
    plate.addEventListener('pointerleave', () => {
      if (raf) { cancelAnimationFrame(raf); raf = null; }
      plateFrame.style.transition = '';
      plateFrame.style.transform = '';
    });
  }

  /* ── 主界面标注点 ── */
  $$('.pin').forEach((pin) => {
    pin.addEventListener('click', (e) => {
      e.stopPropagation();
      const open = pin.getAttribute('aria-expanded') === 'true';
      $$('.pin').forEach((p) => p.setAttribute('aria-expanded', 'false'));
      pin.setAttribute('aria-expanded', String(!open));
    });
  });
  document.addEventListener('click', () => $$('.pin').forEach((p) => p.setAttribute('aria-expanded', 'false')));

  /* ── 四刊卡片：翻页 ── */
  const magCards = $$('.mag-card');
  const closeMag = (card, focusBack) => {
    if (!card.classList.contains('is-open')) return;
    card.classList.remove('is-open');
    $('.mag-open', card).setAttribute('aria-expanded', 'false');
    $('.mag-back', card).inert = true;
    if (focusBack) $('.mag-open', card).focus({ preventScroll: true });
  };
  magCards.forEach((card) => {
    const openBtn = $('.mag-open', card);
    const back = $('.mag-back', card);
    const closeBtn = $('.mag-close', card);
    openBtn.addEventListener('click', () => {
      magCards.forEach((c) => { if (c !== card) closeMag(c, false); });
      const open = !card.classList.contains('is-open');
      card.classList.toggle('is-open', open);
      openBtn.setAttribute('aria-expanded', String(open));
      back.inert = !open;
      if (open) requestAnimationFrame(() => closeBtn.focus({ preventScroll: true }));
    });
    closeBtn.addEventListener('click', () => closeMag(card, true));
    card.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') closeMag(card, true);
    });
  });

  /* ── 页码标记 ── */
  const pageMarker = $('#page-marker');
  const pageNum = $('#page-marker-num');
  if (pageMarker && pageNum) {
    const coverSection = $('#cover');
    if (coverSection) {
      new IntersectionObserver(([en]) => {
        pageMarker.classList.toggle('is-on', !en.isIntersecting);
      }, { rootMargin: '0px 0px -8% 0px' }).observe(coverSection);
    }
    const pageSpy = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        if (!en.isIntersecting) return;
        const n = en.target.dataset.page;
        if (pageNum.textContent === n) return;
        pageNum.textContent = n;
        pageNum.classList.remove('roll');
        void pageNum.offsetWidth;
        pageNum.classList.add('roll');
      });
    }, { rootMargin: '-42% 0px -52% 0px' });
    $$('section[data-page]').forEach((s) => pageSpy.observe(s));
  }

  /* ── FAQ：同组只展开一个 ── */
  const faq = $('.faq');
  if (faq) {
    faq.addEventListener('toggle', (e) => {
      if (e.target.open) $$('details[open]', faq).forEach((d) => { if (d !== e.target) d.open = false; });
    }, true);
  }

  /* ══════════ 下载菜单与平台配置 ══════════ */
  /* 上线新平台时，只需在此处把 status 改为 'ready' 并填写 href，
     页面上的 [data-platform] 元素会自动获得链接与状态样式。
     同时把对应行的「即将推出」文案改为版本号即可。 */
  const PLATFORMS = {
    macos:   { status: 'ready', href: 'https://github.com/Yahoo-npu/OneRead/releases/latest', tag: 'v1.0.0 ↓', cta: '下载 v1.0.0' },
    windows: { status: 'soon', tag: '即将推出' },
    android: { status: 'soon', tag: '即将推出' }
  };

  $$('[data-platform]').forEach((el) => {
    const cfg = PLATFORMS[el.dataset.platform];
    if (!cfg) return;
    const ready = cfg.status === 'ready' && !!cfg.href;
    el.classList.toggle('is-ready', ready);
    el.classList.toggle('is-soon', !ready);

    const tag = el.querySelector('.platform-tag');
    if (tag && cfg.tag) tag.textContent = cfg.tag;

    const btn = el.querySelector('.platform-btn');
    if (btn) {
      if (ready) {
        btn.href = cfg.href;
        btn.innerHTML = (cfg.cta || '下载') + ' <span aria-hidden="true">↓</span>';
      } else {
        btn.removeAttribute('href');
      }
    }

    if (el.matches('a')) {
      if (ready) { el.href = cfg.href; el.removeAttribute('aria-disabled'); }
      else { el.removeAttribute('href'); el.setAttribute('aria-disabled', 'true'); }
    }
  });

  const downloadToggle = $('#download-toggle');
  const platformPanel = $('#platform-panel');
  if (downloadToggle && platformPanel) {
    const closePanel = () => {
      platformPanel.hidden = true;
      downloadToggle.setAttribute('aria-expanded', 'false');
    };
    downloadToggle.addEventListener('click', (e) => {
      e.stopPropagation();
      const open = !platformPanel.hidden;
      platformPanel.hidden = open;
      downloadToggle.setAttribute('aria-expanded', String(!open));
    });
    document.addEventListener('click', (e) => {
      if (!platformPanel.hidden && !e.target.closest('.download-nav')) closePanel();
    });
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && !platformPanel.hidden) { closePanel(); downloadToggle.focus(); }
    });
    platformPanel.addEventListener('click', (e) => {
      if (e.target.closest('a')) closePanel();
    });
  }

  /* ══════════ 实机录屏：可见即播，滚出即停 ══════════ */
  const videos = $$('.demo-figure video');
  if (videos.length) {
    let userWantsPlay = false;
    const ratios = new WeakMap();
    const shouldPlay = () => !reducedMotion || userWantsPlay;

    /* 锚点平滑滚动：自定义缓动（比原生更可控），滚动期间暂停视频 */
    let suppress = false;
    let glideRaf = null;
    const easeInOutCubic = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
    const headerOffset = () => (innerWidth <= 600 ? 76 : 90);
    const glideEnd = () => {
      if (!suppress) return;
      suppress = false;
      syncPlayback();
    };
    const cancelGlide = () => {
      if (!glideRaf) return;
      cancelAnimationFrame(glideRaf);
      glideRaf = null;
      glideEnd();
    };
    window.addEventListener('wheel', cancelGlide, { passive: true });
    window.addEventListener('touchstart', cancelGlide, { passive: true });

    /* 抵达时在区块顶部画一道页边线 */
    let arriveTimer = null;
    const announceArrival = (target) => {
      const section = target.closest('section[data-page]');
      $$('.arrive').forEach((el) => el.classList.remove('arrive'));
      if (!section) return;
      void section.offsetWidth;
      section.classList.add('arrive');
      clearTimeout(arriveTimer);
      arriveTimer = setTimeout(() => section.classList.remove('arrive'), 1400);
    };

    document.addEventListener('click', (e) => {
      const link = e.target.closest('a[href^="#"]');
      if (!link) return;
      const id = link.getAttribute('href');
      if (!id || id.length < 2) return;
      const target = document.querySelector(id);
      if (!target) return;
      e.preventDefault();
      const y = Math.max(0, target.getBoundingClientRect().top + scrollY - headerOffset());
      history.pushState(null, '', id);
      if (reducedMotion) { scrollTo(0, y); return; }

      suppress = true;
      videos.forEach((v) => v.pause());
      cancelGlide();
      const startY = scrollY;
      const dist = y - startY;
      const dur = Math.min(950, Math.max(420, Math.abs(dist) * 0.42));
      const t0 = performance.now();
      const step = (now) => {
        const p = Math.min(1, (now - t0) / dur);
        scrollTo(0, startY + dist * easeInOutCubic(p));
        if (p < 1) glideRaf = requestAnimationFrame(step);
        else { glideRaf = null; glideEnd(); announceArrival(target); }
      };
      glideRaf = requestAnimationFrame(step);
    });

    /* 只播放「最可见」的一段视频，避免多段同时解码导致滚动掉帧 */
    const syncPlayback = () => {
      if (suppress) { videos.forEach((v) => v.pause()); return; }
      let best = null, bestRatio = 0;
      videos.forEach((v) => {
        const r = ratios.get(v) || 0;
        if (r > bestRatio) { bestRatio = r; best = v; }
      });
      videos.forEach((v) => { if (v !== best) v.pause(); });
      if (!best) return;
      if (bestRatio < 0.2 || !shouldPlay()) { best.pause(); return; }
      if (bestRatio >= 0.55 && best.paused) best.play().catch(() => {});
    };

    const observer = new IntersectionObserver((entries) => {
      entries.forEach((en) => ratios.set(en.target, en.intersectionRatio));
      syncPlayback();
    }, { threshold: [0, 0.2, 0.4, 0.55, 0.75, 1] });
    videos.forEach((v) => { v.loop = true; observer.observe(v); });

    document.addEventListener('visibilitychange', () => {
      if (document.hidden) videos.forEach((v) => v.pause());
      else syncPlayback();
    });

    /* 播放状态反馈：正在播放的那一段「实机演示」状态点亮红点 */
    document.addEventListener('play', (e) => {
      const demo = e.target.closest && e.target.closest('.demo');
      if (demo) demo.classList.add('is-live');
    }, true);
    document.addEventListener('pause', (e) => {
      const demo = e.target.closest && e.target.closest('.demo');
      if (demo) demo.classList.remove('is-live');
    }, true);

    /* 减少动态效果：默认不自动播放，点击海报播放 */
    if (reducedMotion) {
      videos.forEach((v) => {
        const hint = document.createElement('button');
        hint.className = 'play-hint';
        hint.type = 'button';
        hint.innerHTML = '<span>▶ 播放演示</span>';
        v.parentElement.append(hint);
        hint.addEventListener('click', () => {
          userWantsPlay = true;
          hint.remove();
          v.play().catch(() => {});
        });
      });
    }
  }
})();
