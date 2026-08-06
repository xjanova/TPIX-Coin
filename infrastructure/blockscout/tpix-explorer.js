/* ══════════════════════════════════════════════════════════════════════════════
 * tpix-explorer.js — ส่วนเสริมหน้า Blockscout ของ TPIX
 *
 * เสิร์ฟเป็นไฟล์จริงที่ /tpix-explorer.js แล้วให้ nginx แทรกแค่แท็ก <script>
 * ก่อน </head> — ต่างจากของเดิมที่ย่อ JS ทั้งก้อนไปฝังเป็นสตริงเดียวใน
 * sub_filter ของ nginx config ซึ่งทำให้:
 *   - แก้โค้ดทีต้องไปแก้ config ของเว็บเซิร์ฟเวอร์
 *   - มีสำเนา JS สองชุด (ในไฟล์ .html กับใน nginx conf) ที่เพี้ยนจากกันได้
 *   - เบราว์เซอร์แคชไม่ได้ ต้องโหลดใหม่ทุกหน้า
 *
 * ทำอะไร
 *   1. เปลี่ยนโลโก้ + ลบเครดิต Blockscout ออกจาก footer
 *   2. เพิ่มแถบการ์ด "กระเป๋าคลัง" บนหน้าแรก แยกจาก Top accounts
 *
 * ทำไมต้องดึงยอดจาก RPC เอง ไม่ใช้ API ของ Blockscout
 *   Blockscout ค้นพบ address จาก block/transaction เท่านั้น กระเป๋าที่ได้เงิน
 *   ตั้งแต่ genesis ไม่เคยมีธุรกรรม จึงไม่เคยถูก index → /api/v2/addresses/<addr>
 *   ตอบ 404 และหน้า Top accounts ก็ไม่มีมันอยู่ในรายการ
 *   ยอดจริงยังอ่านได้จาก eth_getBalance เสมอ จึงถามเชนตรง ๆ
 * ══════════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var RPC = 'https://rpc1.tpix.online';
  var LOGO = 'https://tpix.online/images/logotpixexplorer.webp';
  var TOTAL_SUPPLY = 7000000000;

  /* ที่อยู่มาจาก infrastructure/chain/alloc.env ซึ่งเป็นชุดเดียวกับที่ใช้สร้าง
   * genesis จริง — ชื่อบทบาทยึดตาม docs/WHITEPAPER.md §Distribution
   * (alloc.env ตั้งชื่อตัวแปรไม่ตรงกับไวท์เปเปอร์ 3 ใบ แต่ที่อยู่กับยอดตรงกันหมด) */
  var TREASURY = [
    { role: 'Master Node Rewards',      th: 'รางวัลมาสเตอร์โหนด',  addr: '0xf54c0deE404ec728a03b467cba7bBA171CC77dad', path: "m/44'/60'/0'/0/1" },
    { role: 'Ecosystem Development',    th: 'พัฒนาระบบนิเวศ',      addr: '0x6E176Bf5Aa39Fb4217E0ebd00E14B67aDfFaf440', path: "m/44'/60'/0'/0/2" },
    { role: 'Team & Advisors',          th: 'ทีมงานและที่ปรึกษา',  addr: '0x87e62D9e0C2aF15d634D3301Dd2D4DA57972052d', path: "m/44'/60'/0'/0/3" },
    { role: 'Token Sale',               th: 'ขายเหรียญ',           addr: '0x4BcC1844Ad9E8587f7005f092928a5D14C30F463', path: "m/44'/60'/0'/0/4" },
    { role: 'Liquidity & Market Making',th: 'สภาพคล่อง',           addr: '0x2644A740A06e0401D21F8B4A840400fFe8dB42A9', path: "m/44'/60'/0'/0/5" },
    { role: 'Community & Rewards',      th: 'ชุมชนและรางวัล',      addr: '0x6dECa2E185CF37e7c838fE5Ae6897aED025c9921', path: "m/44'/60'/0'/0/6" }
  ];

  /* ── utils ─────────────────────────────────────────────────────────────── */

  function rpc(method, params) {
    return fetch(RPC, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', method: method, params: params || [], id: 1 })
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (j.error) throw new Error(j.error.message);
      return j.result;
    });
  }

  /* ยอดเป็น wei ซึ่งเกิน Number.MAX_SAFE_INTEGER — ต้องหารด้วย BigInt
   * ไม่งั้น 1,400,000,000 TPIX จะเพี้ยนตั้งแต่หลักสิบ */
  function weiToTpix(hex) {
    try { return Number(BigInt(hex) / BigInt('1000000000000000000')); }
    catch (e) { return 0; }
  }

  function fmt(n) { return n.toLocaleString('en-US'); }
  function shortAddr(a) { return a.slice(0, 8) + '…' + a.slice(-6); }

  /* ── การ์ดกระเป๋าคลัง ──────────────────────────────────────────────────── */

  function styles() {
    if (document.getElementById('tpix-treasury-css')) return;
    var s = document.createElement('style');
    s.id = 'tpix-treasury-css';
    s.textContent = [
      '.tpix-treasury{margin:24px 0 8px}',
      '.tpix-treasury h2{font-size:1.05rem;font-weight:600;margin:0 0 4px;letter-spacing:.01em}',
      '.tpix-treasury .tpix-sub{font-size:.78rem;opacity:.6;margin:0 0 14px}',
      '.tpix-grid{display:grid;gap:12px;grid-template-columns:repeat(auto-fill,minmax(258px,1fr))}',
      '.tpix-card{border:1px solid rgba(128,145,170,.22);border-radius:12px;padding:14px 16px;',
      '  background:linear-gradient(160deg,rgba(6,182,212,.055),rgba(6,182,212,0) 62%);',
      '  transition:border-color .16s,transform .16s;text-decoration:none;display:block;color:inherit}',
      '.tpix-card:hover{border-color:rgba(6,182,212,.55);transform:translateY(-1px)}',
      '.tpix-role{font-size:.82rem;font-weight:600;margin-bottom:2px}',
      '.tpix-role-th{font-size:.72rem;opacity:.55;margin-bottom:9px}',
      '.tpix-amt{font-size:1.24rem;font-weight:700;font-variant-numeric:tabular-nums;line-height:1.15}',
      '.tpix-amt small{font-size:.62em;font-weight:600;opacity:.55;margin-left:4px}',
      '.tpix-pct{font-size:.72rem;opacity:.62;margin-top:3px}',
      '.tpix-addr{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.68rem;',
      '  opacity:.5;margin-top:9px;word-break:break-all}',
      '.tpix-bar{height:3px;border-radius:2px;background:rgba(128,145,170,.16);margin-top:10px;overflow:hidden}',
      '.tpix-bar i{display:block;height:100%;background:#06b6d4;border-radius:2px}',
      '.tpix-skel{opacity:.4}'
    ].join('');
    document.head.appendChild(s);
  }

  function buildCard(w) {
    var a = document.createElement('a');
    a.className = 'tpix-card';
    a.href = '/address/' + w.addr;
    a.title = w.path;
    a.innerHTML =
      '<div class="tpix-role">' + w.role + '</div>' +
      '<div class="tpix-role-th">' + w.th + '</div>' +
      '<div class="tpix-amt tpix-skel" data-amt>— <small>TPIX</small></div>' +
      '<div class="tpix-pct" data-pct>&nbsp;</div>' +
      '<div class="tpix-bar"><i style="width:0"></i></div>' +
      '<div class="tpix-addr">' + shortAddr(w.addr) + '</div>';
    return a;
  }

  function render() {
    if (document.querySelector('.tpix-treasury')) return;      // แทรกซ้ำไม่ได้
    var main = document.querySelector('main');
    if (!main) return;

    styles();
    var box = document.createElement('section');
    box.className = 'tpix-treasury';
    box.innerHTML =
      '<h2>กระเป๋าคลัง TPIX · Treasury Wallets</h2>' +
      '<p class="tpix-sub">จัดสรรตั้งแต่บล็อกกำเนิด ตรวจสอบได้บนเชนตลอดเวลา · ' +
      'ยอดอ่านสดจาก RPC ไม่ผ่านตัว index</p>' +
      '<div class="tpix-grid"></div>';
    var grid = box.querySelector('.tpix-grid');

    TREASURY.forEach(function (w) { grid.appendChild(buildCard(w)); });
    main.insertBefore(box, main.firstChild);

    TREASURY.forEach(function (w, i) {
      rpc('eth_getBalance', [w.addr, 'latest']).then(function (hex) {
        var t = weiToTpix(hex), pct = (t / TOTAL_SUPPLY) * 100;
        var card = grid.children[i];
        var amt = card.querySelector('[data-amt]');
        amt.classList.remove('tpix-skel');
        amt.innerHTML = fmt(t) + ' <small>TPIX</small>';
        card.querySelector('[data-pct]').textContent = pct.toFixed(2) + '% ของอุปทานทั้งหมด';
        card.querySelector('.tpix-bar i').style.width = Math.min(pct * 4, 100) + '%';
      }).catch(function () {
        var amt = grid.children[i].querySelector('[data-amt]');
        amt.classList.remove('tpix-skel');
        amt.textContent = 'อ่านยอดไม่ได้';
      });
    });
  }

  /* ── branding ──────────────────────────────────────────────────────────── */

  function branding() {
    document.querySelectorAll("header a[href='/'] img, nav a[href='/'] img").forEach(function (img) {
      if (img.src !== LOGO) { img.src = LOGO; img.style.height = '60px'; img.style.width = 'auto'; img.style.maxHeight = 'none'; }
    });
    document.querySelectorAll("header a[href='/'] svg, nav a[href='/'] svg").forEach(function (svg) {
      var img = document.createElement('img');
      img.src = LOGO; img.alt = 'TPIX Explorer'; img.style.height = '60px'; img.style.width = 'auto';
      svg.parentNode.replaceChild(img, svg);
    });
    document.querySelectorAll("a[href*='blockscout.com']").forEach(function (a) {
      if (a.closest('footer') || a.closest("[class*='footer']")) {
        a.href = 'https://xman4289.com';
        if (a.textContent.trim().toLowerCase().indexOf('blockscout') > -1) a.textContent = 'Xman Studio';
      }
    });
  }

  /* ── lifecycle ─────────────────────────────────────────────────────────── */

  function isHome() { return location.pathname === '/' || location.pathname === ''; }

  function apply() {
    branding();
    if (isHome()) render();
    else { var b = document.querySelector('.tpix-treasury'); if (b) b.remove(); }
  }

  function boot() {
    apply();
    /* Blockscout เป็น SPA — เปลี่ยนหน้าโดยไม่โหลดใหม่ MutationObserver จึงจำเป็น
     * แต่ต้อง throttle ไม่งั้นทุกครั้งที่ DOM ขยับจะยิง apply() รัวจน CPU พุ่ง */
    var pending = false;
    new MutationObserver(function () {
      if (pending) return;
      pending = true;
      setTimeout(function () { pending = false; apply(); }, 400);
    }).observe(document.body, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
