/* Alt-F shared script. Everything here is optional: pages work without it. */
(function () {
  'use strict';
  var KEY = 'altf-theme';
  var root = document.documentElement;

  function store(get, val) {
    try {
      if (get) return window.localStorage.getItem(KEY);
      window.localStorage.setItem(KEY, val);
    } catch (e) { /* storage blocked: the theme just won't be remembered */ }
    return null;
  }

  function applyTheme(t) {
    if (t === 'light' || t === 'dark') root.setAttribute('data-theme', t);
    else root.removeAttribute('data-theme');
  }

  /* Auto / Light / Dark switch */
  var sel = document.getElementById('theme-select');
  if (sel) {
    var saved = store(true);
    sel.value = (saved === 'light' || saved === 'dark') ? saved : 'auto';
    sel.addEventListener('change', function () {
      store(false, sel.value);
      applyTheme(sel.value);
    });
  }

  /* collapsible navigation on small screens */
  var tg = document.getElementById('navtoggle');
  var nav = document.getElementById('nav');
  if (tg && nav) {
    tg.addEventListener('click', function () {
      var open = nav.classList.toggle('open');
      tg.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  }

  /* gentle confirmation before risky actions: <form data-confirm="Are you sure?"> */
  var dlg = null;
  function ask(msg, yes) {
    if (!window.HTMLDialogElement) {
      if (window.confirm(msg)) yes();
      return;
    }
    if (!dlg) {
      dlg = document.createElement('dialog');
      dlg.setAttribute('aria-labelledby', 'dlg-msg');
      dlg.innerHTML = '<p id="dlg-msg"></p><div class="actions">' +
        '<button type="button" class="btn" value="no">Go back</button>' +
        '<button type="button" class="btn primary" value="yes">Yes, continue</button></div>';
      document.body.appendChild(dlg);
    }
    dlg.querySelector('p').textContent = msg;
    var btns = dlg.querySelectorAll('button');
    btns[0].onclick = function () { dlg.close(); };
    btns[1].onclick = function () { dlg.close(); yes(); };
    dlg.showModal();
    btns[0].focus();
  }
  document.addEventListener('submit', function (ev) {
    var f = ev.target;
    var msg = f.getAttribute && f.getAttribute('data-confirm');
    if (!msg || f.getAttribute('data-ok')) return;
    ev.preventDefault();
    ask(msg, function () { f.setAttribute('data-ok', '1'); f.submit(); });
  });

  /* optional live refresh of status blocks: <div data-refresh="/cgi-bin/x.cgi?refresh=y"> */
  var auto = document.getElementById('autorefresh');
  var timer = null;
  function refreshAll() {
    var els = document.querySelectorAll('[data-refresh]');
    Array.prototype.forEach.call(els, function (el) {
      var x = new XMLHttpRequest();
      x.open('GET', el.getAttribute('data-refresh'));
      x.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
      x.onload = function () {
        if (x.status === 200) el.innerHTML = x.responseText;
        else if (x.status === 401) window.location.reload();
      };
      x.send();
    });
  }
  if (auto) {
    auto.addEventListener('change', function () {
      if (timer) { window.clearInterval(timer); timer = null; }
      if (auto.checked) { refreshAll(); timer = window.setInterval(refreshAll, 15000); }
    });
  }
}());
