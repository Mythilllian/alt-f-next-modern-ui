/* Alt-F file browser. Lists one folder level at a time and loads sub-folders when opened. */
(function () {
  'use strict';
  var box = document.getElementById('fb');
  if (!box) return;

  var ROOT = box.getAttribute('data-root');
  var LIST = box.getAttribute('data-list');
  var GET = box.getAttribute('data-get');
  var cache = {};
  var current = ROOT;
  var sortKey = 'name';
  var filter = '';
  var PREVIEW = /\.(jpe?g|png|gif|webp|pdf|txt|mp3|m4a|mp4|m4v|webm)$/i;

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function enc(s) { return encodeURIComponent(s); }

  function join(dir, name) { return (dir === '/' ? '' : dir) + '/' + name; }

  function fmtSize(n) {
    var u = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
    return (i === 0 ? n : n.toFixed(n < 10 ? 1 : 0)) + ' ' + u[i];
  }

  function fmtDate(s) {
    var m = /^(\d+)-(\d+)-(\d+) (\d+):(\d+)/.exec(s);
    if (!m) return s;
    var d = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]);
    try {
      return d.toLocaleString(undefined, { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
    } catch (e) { return s; }
  }

  /* fetch one folder; cb(errorMessage, data) */
  function load(path, cb) {
    if (cache[path]) { cb(null, cache[path]); return; }
    fetch(LIST + '?p=' + enc(path), { credentials: 'same-origin', headers: { 'X-Requested-With': 'fetch' } })
      .then(function (r) {
        if (r.status === 401) { window.location.reload(); return null; }
        return r.json().then(function (j) { return { ok: r.ok, j: j }; });
      })
      .then(function (res) {
        if (!res) return;
        if (!res.ok) { cb(res.j.error || 'Something went wrong.'); return; }
        cache[path] = res.j;
        cb(null, res.j);
      })
      .catch(function () {
        cb("Couldn't reach the NAS. Check your network connection and try again.");
      });
  }

  function sorted(entries, all) {
    var list = entries.filter(function (e) {
      return all || !filter || e.n.toLowerCase().indexOf(filter) !== -1;
    });
    list.sort(function (a, b) {
      if (a.t !== b.t) return a.t === 'd' ? -1 : 1;
      if (sortKey === 'size' && a.s !== b.s) return b.s - a.s;
      if (sortKey === 'date' && a.m !== b.m) return a.m < b.m ? 1 : -1;
      return a.n.localeCompare(b.n, undefined, { numeric: true, sensitivity: 'base' });
    });
    return list;
  }

  function message(text, retry) {
    var p = el('div', 'empty');
    p.appendChild(el('p', '', text));
    if (retry) {
      var b = el('button', 'btn', 'Try again');
      b.type = 'button';
      b.addEventListener('click', retry);
      p.appendChild(b);
    }
    return p;
  }

  /* wide screens get a tree: folders can be opened in place. Phones get a plain list. */
  var wide = !!(window.matchMedia && window.matchMedia('(min-width: 48rem)').matches);

  function toggle(li, tg, full) {
    var sub = li.querySelector('ul.files');
    if (sub) {
      li.removeChild(sub);
      tg.setAttribute('aria-expanded', 'false');
      tg.textContent = '▸';
      return;
    }
    sub = el('ul', 'files');
    var wait = el('li');
    wait.appendChild(message('Loading…'));
    sub.appendChild(wait);
    li.appendChild(sub);
    tg.setAttribute('aria-expanded', 'true');
    tg.textContent = '▾';
    load(full, function (err, data) {
      sub.textContent = '';
      var item = el('li');
      if (err) { item.appendChild(message(err)); sub.appendChild(item); return; }
      if (!data.entries.length) { item.appendChild(message('This folder is empty.')); sub.appendChild(item); return; }
      sorted(data.entries, true).forEach(function (e) { sub.appendChild(row(full, e)); });
    });
  }

  function row(dir, e) {
    var li = el('li');
    var r = el('div', 'row');
    var head = el('div', 'head');
    var full = join(dir, e.n);
    var name;
    r.appendChild(head);
    if (e.t === 'd') {
      if (wide) {
        var tg = el('button', 'tog', '▸');
        tg.type = 'button';
        tg.setAttribute('aria-expanded', 'false');
        tg.setAttribute('aria-label', 'Show what is inside ' + e.n);
        tg.addEventListener('click', function () { toggle(li, tg, full); });
        head.appendChild(tg);
      }
      name = el('button', 'name');
      name.type = 'button';
      name.appendChild(el('span', 'ico', '📁'));
      name.appendChild(el('span', '', e.n));
      name.addEventListener('click', function () { open(full); });
      head.appendChild(name);
      r.appendChild(el('span', 'meta', ''));
    } else {
      name = el('a', 'name');
      name.href = GET + '?p=' + enc(full);
      name.appendChild(el('span', 'ico', '📄'));
      name.appendChild(el('span', '', e.n));
      head.appendChild(name);
      r.appendChild(el('span', 'meta', fmtSize(e.s)));
    }
    r.appendChild(el('span', 'meta date', fmtDate(e.m)));
    li.appendChild(r);
    if (e.t !== 'd' && PREVIEW.test(e.n)) {
      var v = el('a', 'meta', 'Open in browser');
      v.href = GET + '?p=' + enc(full) + '&inline=1';
      v.target = '_blank';
      v.rel = 'noopener';
      r.insertBefore(v, r.lastChild);
    }
    return li;
  }

  function crumbs(path) {
    var nav = el('nav');
    nav.setAttribute('aria-label', 'You are here');
    var ol = el('ol', 'crumbs');
    var parts = path.slice(ROOT.length).split('/').filter(Boolean);
    var acc = ROOT;
    var first = el('li');
    if (parts.length) {
      var a0 = el('a', '', 'All disks');
      a0.href = '#' + enc(ROOT);
      first.appendChild(a0);
    } else {
      first.appendChild(el('span', '', 'All disks'));
    }
    ol.appendChild(first);
    parts.forEach(function (seg, i) {
      acc = join(acc, seg);
      var li = el('li');
      if (i === parts.length - 1) {
        var s = el('span', '', seg);
        s.setAttribute('aria-current', 'page');
        li.appendChild(s);
      } else {
        var a = el('a', '', seg);
        a.href = '#' + enc(acc);
        li.appendChild(a);
      }
      ol.appendChild(li);
    });
    nav.appendChild(ol);
    return nav;
  }

  function tools() {
    var t = el('div', 'tools');
    var f = el('div', 'field');
    var lab = el('label', 'sr', 'Filter this folder');
    lab.setAttribute('for', 'fb-filter');
    var inp = el('input');
    inp.type = 'search';
    inp.id = 'fb-filter';
    inp.placeholder = 'Filter by name';
    inp.value = filter;
    inp.addEventListener('input', function () {
      filter = inp.value.toLowerCase();
      renderList();
    });
    f.appendChild(lab);
    f.appendChild(inp);
    var s = el('select');
    s.setAttribute('aria-label', 'Sort by');
    [['name', 'Sort by name'], ['size', 'Sort by size'], ['date', 'Sort by date']].forEach(function (o) {
      var op = el('option', '', o[1]);
      op.value = o[0];
      if (o[0] === sortKey) op.selected = true;
      s.appendChild(op);
    });
    s.addEventListener('change', function () { sortKey = s.value; renderList(); });
    t.appendChild(f);
    t.appendChild(s);
    return t;
  }

  var listBox = null;

  function renderList() {
    if (!listBox) return;
    var data = cache[current];
    listBox.textContent = '';
    if (!data) return;
    var rows = sorted(data.entries);
    if (!data.entries.length) {
      listBox.appendChild(message(current === ROOT
        ? 'No disks found. Plug in a drive and refresh.'
        : 'This folder is empty.', current === ROOT ? function () { cache = {}; open(current); } : null));
      return;
    }
    if (!rows.length) {
      listBox.appendChild(message('Nothing here matches "' + filter + '".'));
      return;
    }
    var ul = el('ul', 'files');
    rows.forEach(function (e) { ul.appendChild(row(current, e)); });
    listBox.appendChild(ul);
    if (data.truncated) {
      listBox.appendChild(el('p', 'notice', 'This folder is large, so only the first items are shown. Use the filter to narrow it down.'));
    }
  }

  function render(path) {
    current = path;
    box.textContent = '';
    box.appendChild(crumbs(path));
    var card = el('div', 'card');
    card.appendChild(tools());
    listBox = el('div');
    listBox.setAttribute('aria-live', 'polite');
    listBox.appendChild(message('Loading…'));
    card.appendChild(listBox);
    box.appendChild(card);
    load(path, function (err) {
      if (path !== current) return;
      if (err) {
        listBox.textContent = '';
        listBox.appendChild(message(err, function () { open(path); }));
        return;
      }
      renderList();
    });
  }

  function open(path) {
    var h = '#' + enc(path);
    if (window.location.hash === h) render(path);
    else window.location.hash = h;
  }

  function fromHash() {
    var h = window.location.hash.slice(1);
    var p = ROOT;
    try { if (h) p = decodeURIComponent(h); } catch (e) { p = ROOT; }
    if (p !== ROOT && p.indexOf(ROOT + '/') !== 0) p = ROOT;
    render(p);
  }

  window.addEventListener('hashchange', fromHash);
  fromHash();
}());
