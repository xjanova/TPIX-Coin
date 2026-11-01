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
 *   1. ลบเครดิต Blockscout ออกจาก footer
 *      (โลโก้ไม่ทำที่นี่แล้ว — ตั้งผ่าน NEXT_PUBLIC_NETWORK_LOGO/_ICON ใน compose
 *       เหตุผลอยู่ที่ฟังก์ชัน branding() ด้านล่าง)
 *   2. เพิ่มแถบการ์ด "กระเป๋าคลัง" บนหน้าแรก แยกจาก Top accounts
 *   3. ปุ่ม + หลังชื่อเหรียญทุกแถวในหน้า /tokens กดแล้วสลับ/เพิ่มเชน TPIX
 *      ให้กระเป๋า แล้วเพิ่มเหรียญนั้นเข้ารายการ (wallet_watchAsset)
 *      Blockscout มีปุ่ม MetaMask แค่ในหน้ารายละเอียดเหรียญ หน้ารายการไม่มี
 *   4. แถบ "ลงทะเบียนอยู่บน" พร้อมโลโก้ทะเบียนเชนใน footer ทุกหน้า
 *      NEXT_PUBLIC_FOOTER_LINKS (tpix-footer-links.json) ใส่ได้แค่ลิงก์ตัวหนังสือ
 *   5. ป้าย ✓ Verified หลังชื่อเหรียญ (หน้า /tokens และหน้า /token/0x…)
 *      เมื่อสัญญายืนยันซอร์สแล้ว — กฎเดียวกับ TPIX Wallet
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
    if (!main || !hydrated(main)) return;

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

  /* ── ปุ่ม + เพิ่มเหรียญเข้ากระเป๋า (หน้า /tokens) ─────────────────────────── */

  var CHAIN = {
    chainId: '0x10c1',                                       // 4289
    chainName: 'TPIX Chain',
    nativeCurrency: { name: 'TPIX', symbol: 'TPIX', decimals: 18 },
    rpcUrls: [RPC],
    blockExplorerUrls: ['https://explorer.tpix.online'],
    iconUrls: ['https://tpix.online/images/tpix-logo-512.png']
  };
  var TOKEN_LINK = /^\/token\/(0x[0-9a-fA-F]{40})$/;
  var tokenCache = {};

  function watchStyles() {
    if (document.getElementById('tpix-watch-css')) return;
    var s = document.createElement('style');
    s.id = 'tpix-watch-css';
    s.textContent = [
      '.tpix-watch{flex:none;margin-left:8px;width:22px;height:22px;padding:0;border-radius:6px;',
      '  border:1px solid rgba(6,182,212,.45);background:rgba(6,182,212,.08);color:#06b6d4;',
      '  font:600 16px/1 system-ui,sans-serif;display:inline-flex;align-items:center;justify-content:center;',
      '  cursor:pointer;transition:background .15s,border-color .15s}',
      '.tpix-watch:hover{background:rgba(6,182,212,.2);border-color:#06b6d4}',
      '.tpix-watch:disabled{cursor:wait;opacity:.5}',
      '.tpix-toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);z-index:9999;',
      '  max-width:min(92vw,460px);padding:10px 16px;border-radius:10px;background:#1a202c;color:#e2e8f0;',
      '  border:1px solid rgba(128,145,170,.3);font-size:.85rem;line-height:1.45;box-shadow:0 8px 24px rgba(0,0,0,.35)}',
      '.tpix-toast.ok{border-color:rgba(0,230,118,.55)}',
      '.tpix-toast.err{border-color:rgba(239,68,68,.6)}',
      '.tpix-toast a{color:#06b6d4;margin-left:8px;text-decoration:underline}'
    ].join('');
    document.head.appendChild(s);
  }

  function toast(text, kind, links) {
    var old = document.querySelector('.tpix-toast');
    if (old) old.remove();
    var t = document.createElement('div');
    t.className = 'tpix-toast' + (kind ? ' ' + kind : '');
    t.setAttribute('role', 'status');
    t.textContent = text;                      // textContent — ข้อความ error จากกระเป๋าห้ามตีความเป็น HTML
    (links || []).forEach(function (link) {
      var a = document.createElement('a');
      a.href = link.href;
      a.target = '_blank';
      a.rel = 'noopener';
      a.textContent = link.text;
      t.appendChild(a);
    });
    document.body.appendChild(t);
    setTimeout(function () { t.remove(); }, links ? 12000 : 4500);
  }

  function isMobile() { return /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent || ''); }

  /* ไม่มีกระเป๋า → TPIX Wallet มาก่อน MetaMask เป็นทางเลือกที่สอง
   * TPIX Wallet มีแต่ Android: บน Android ส่งไฟล์ APK ล่าสุดเลย (tpix.online ชี้ไป release ล่าสุดเอง)
   * เครื่องอื่นพาไปหน้าดาวน์โหลด ซึ่งบอกว่าเป็นแอป Android */
  var TPIX_WALLET_APK = 'https://tpix.online/api/v1/app/chain-download?type=wallet';
  var TPIX_DOWNLOAD_PAGE = 'https://tpix.online/download';

  function noWallet() {
    var tpixWallet = /Android/i.test(navigator.userAgent || '')
      ? { href: TPIX_WALLET_APK, text: 'ดาวน์โหลด TPIX Wallet' }
      : { href: TPIX_DOWNLOAD_PAGE, text: 'TPIX Wallet' };
    var metamask = isMobile()
      ? { href: 'https://metamask.app.link/dapp/' + location.host + location.pathname, text: 'เปิดใน MetaMask' }
      : { href: 'https://metamask.io/download/', text: 'MetaMask' };
    toast('ไม่พบกระเป๋า ติดตั้ง TPIX Wallet ก่อน · No wallet found — get TPIX Wallet', 'err', [tpixWallet, metamask]);
  }

  /* ดึงจาก API ของ Blockscout เอง (same-origin) — symbol/decimals ต้องตรงกับสัญญา
   * ไม่งั้น MetaMask ปฏิเสธ หรือแสดงยอดผิดหลัก */
  function tokenInfo(addr) {
    var key = addr.toLowerCase();
    if (!tokenCache[key]) {
      tokenCache[key] = fetch('/api/v2/tokens/' + addr).then(function (r) {
        if (!r.ok) throw Object.assign(new Error('HTTP ' + r.status), { code: 'NO_META' });
        return r.json();
      }).then(function (t) {
        if (t.type !== 'ERC-20') throw Object.assign(new Error(String(t.type)), { code: 'NOT_ERC20' });
        var dec = parseInt(t.decimals, 10);
        if (!t.symbol || !(dec >= 0 && dec <= 36)) throw Object.assign(new Error('bad metadata'), { code: 'NO_META' });
        return {
          address: t.address_hash || t.address || addr,
          symbol: String(t.symbol).slice(0, 11),             // MetaMask รับ symbol ไม่เกิน 11 ตัว
          decimals: dec,
          image: t.icon_url || null
        };
      });
      tokenCache[key].catch(function () { delete tokenCache[key]; });   // พลาดแล้วให้กดใหม่ได้
    }
    return tokenCache[key];
  }

  /* wallet_watchAsset เพิ่มเหรียญให้ "เชนที่กระเป๋าเปิดอยู่" — ต้องอยู่บน 4289 ก่อน
   * ไม่งั้นเหรียญจะไปโผล่ในรายการของเชนอื่นแล้วยอดเป็น 0 */
  function ensureChain(eth) {
    return eth.request({ method: 'eth_chainId' }).then(function (id) {
      if (parseInt(id, 16) === 4289) return;
      return eth.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: CHAIN.chainId }] })
        .catch(function (e) {
          var code = e && (e.code || (e.data && e.data.originalError && e.data.originalError.code));
          if (code !== 4902 && !/unrecognized|not added|unknown chain/i.test((e && e.message) || '')) throw e;
          return eth.request({ method: 'wallet_addEthereumChain', params: [CHAIN] });
        });
    });
  }

  function walletMessage(e) {
    var code = e && e.code;
    if (code === 4001 || code === 'ACTION_REJECTED') return 'ยกเลิกในกระเป๋า · Request rejected';
    if (code === -32002) return 'มีคำขอค้างอยู่ เปิดกระเป๋าเพื่อยืนยัน · A request is already pending in your wallet';
    if (code === 'NOT_ERC20') return 'เพิ่มได้เฉพาะเหรียญ ERC-20 · Only ERC-20 tokens can be added';
    if (code === 'NO_META') return 'อ่านข้อมูลเหรียญไม่ได้ ลองใหม่อีกครั้ง · Could not load token details';
    var msg = ((e && e.message) || String(e)).slice(0, 140);
    return 'เพิ่มไม่สำเร็จ · Failed: ' + msg;
  }

  function onWatch(ev) {
    ev.preventDefault();
    ev.stopPropagation();
    var btn = ev.currentTarget;
    if (btn.disabled) return;
    /* อ่านที่อยู่ตอนกด ไม่ผูกไว้ตอนสร้างปุ่ม — React อาจใช้แถวเดิมแสดงเหรียญอื่น
     * (แถว skeleton ตอนโหลด, เปลี่ยนหน้า, กรอง) ปุ่มที่ติดอยู่จะได้ที่อยู่ใหม่เสมอ */
    var link = btn.parentElement && btn.parentElement.querySelector('a[href^="/token/0x"]');
    var m = link && TOKEN_LINK.exec(link.getAttribute('href') || '');
    if (!m) return;
    var eth = window.ethereum;
    if (!eth || typeof eth.request !== 'function') { noWallet(); return; }

    btn.disabled = true;
    tokenInfo(m[1]).then(function (t) {
      return ensureChain(eth).then(function () {
        var options = { address: t.address, symbol: t.symbol, decimals: t.decimals };
        if (t.image) options.image = t.image;
        return eth.request({ method: 'wallet_watchAsset', params: { type: 'ERC20', options: options } });
      }).then(function (added) {
        if (added === false) toast('ยกเลิกแล้ว · Cancelled');
        else toast('เพิ่ม ' + t.symbol + ' เข้ากระเป๋าแล้ว · Added to wallet', 'ok');
      });
    }).catch(function (e) {
      toast(walletMessage(e), 'err');
    }).then(function () {
      btn.disabled = false;
    });
  }

  function addWatchButtons() {
    var links = document.querySelectorAll('main a[href^="/token/0x"]');
    if (!links.length) return;
    watchStyles();
    links.forEach(function (a) {
      if (!TOKEN_LINK.test(a.getAttribute('href') || '')) return;
      var box = a.parentElement;
      if (!box || box.querySelector('.tpix-watch')) return;
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'tpix-watch';
      b.textContent = '+';
      b.title = 'เพิ่มเหรียญเข้ากระเป๋า · Add token to wallet';
      b.setAttribute('aria-label', 'Add token to wallet');
      b.addEventListener('click', onWatch);
      box.appendChild(b);                     // ต่อท้ายสุด — ไม่แทรกกลางลูกที่ React จัดการอยู่
    });
  }

  /* ── ป้าย Verified หลังชื่อเหรียญ (/tokens และหน้า /token/0x…) ─────────────── */

  /* กฎเดียวกับ TPIX Wallet (wallet/lib/services/explorer_token_service.dart):
   * GET /api/v2/addresses/<addr> ตอบ 200 และ is_verified=true · is_scam=false ·
   * is_contract=true · hash ตรงกับที่อยู่ — ขาดข้อใดหรือตรวจไม่ได้ = ไม่มีป้าย (fail closed)
   * ป้ายบอกแค่ว่าซอร์สตรงกับสัญญาบนเชน ไม่ได้รับรองว่าเหรียญปลอดภัย */
  var ADDR = /^0x[0-9a-fA-F]{40}$/;
  var TOKEN_PAGE = /^\/token\/(0x[0-9a-fA-F]{40})\/?$/;
  var VERIFY_TTL = 10 * 60 * 1000;          // ได้คำตอบชัด (ผ่าน/ไม่ผ่าน) เก็บ 10 นาที
  var VERIFY_RETRY = 60 * 1000;             // ตรวจไม่ได้ เก็บ 60 วินาทีแล้วค่อยถามใหม่
  var VERIFY_TIMEOUT = 8000;
  var VERIFY_MAX = 4;                       // ยิง API พร้อมกันไม่เกิน 4 — /tokens มีได้ 50 แถวต่อหน้า
  var VERIFY_TIP = 'ยืนยันซอร์สโค้ดแล้ว — ซอร์สโค้ดตรงกับสัญญาบนเชน (ไม่ได้รับรองว่าเหรียญปลอดภัย) · ' +
    'Verified source — code matches the on-chain contract (not a safety endorsement)';
  var verifyCache = {};                     // ที่อยู่ตัวเล็ก → { done, ok, until }
  var verifyQueue = [];
  var verifyActive = 0;

  function verifyStyles() {
    if (document.getElementById('tpix-verified-css')) return;
    var s = document.createElement('style');
    s.id = 'tpix-verified-css';
    s.textContent = [
      /* ค่าตั้งต้นคือธีมสว่าง — ธีมมืด Blockscout ใส่ body.chakra-ui-dark และ html[data-theme=dark] */
      '.tpix-verified{flex:none;display:inline-flex;align-items:center;gap:3px;vertical-align:middle;margin-left:6px;',
      '  height:20px;padding:0 6px;border-radius:10px;border:1px solid rgba(22,101,52,.4);background:rgba(22,163,74,.1);',
      '  color:#166534;font:600 11px/1 system-ui,sans-serif;white-space:nowrap;cursor:help;user-select:none}',
      '.tpix-verified svg{width:12px;height:12px;flex:none;display:block}',
      '.chakra-ui-dark .tpix-verified,[data-theme=dark] .tpix-verified{border-color:rgba(74,222,128,.45);',
      '  background:rgba(74,222,128,.12);color:#4ade80}',
      '.tpix-verified-lg{height:24px;padding:0 8px;border-radius:12px;font-size:12px;margin-left:10px}',
      '.tpix-verified-lg svg{width:14px;height:14px}',
      /* จอมือถือเหลือแต่ไอคอน — ชื่อเหรียญไม่ต้องถูกตัดสั้นลงเพราะป้าย */
      '@media (max-width:480px){.tpix-verified .tpix-verified-t{display:none}',
      '  .tpix-verified{padding:0 3px}.tpix-verified-lg{padding:0 4px}}'
    ].join('');
    document.head.appendChild(s);
  }

  /* true = ผ่าน · false = explorer ตอบชัดว่าไม่ผ่าน · null = ตรวจไม่ได้
   * 404 นับเป็นคำตอบชัด (explorer ไม่รู้จักที่อยู่นี้) ตรงกับฝั่งกระเป๋า
   * ฟิลด์หาย/ผิดชนิด/hash ไม่ตรง = ตรวจไม่ได้ ไม่ใช่ผ่าน */
  function verdict(addr, status, j) {
    if (status === 404) return false;
    if (status !== 200 || !j || typeof j !== 'object') return null;
    if (typeof j.hash !== 'string' || j.hash.toLowerCase() !== addr.toLowerCase()) return null;
    if (typeof j.is_verified !== 'boolean' || typeof j.is_scam !== 'boolean' ||
        typeof j.is_contract !== 'boolean') return null;
    return j.is_verified === true && j.is_scam === false && j.is_contract === true;
  }

  /* ไม่ reject เลย — ล่ม/429/หมดเวลา/JSON เสีย ได้ null ทั้งหมด
   * ไม่มี AbortController ก็ยังเลิกรอที่ 8 วินาที (คำขอค้างต่อแต่ไม่กินช่องคิว) */
  function fetchVerified(addr) {
    var ctl = typeof AbortController === 'function' ? new AbortController() : null;
    var timer;
    var late = new Promise(function (resolve) {
      timer = setTimeout(function () { if (ctl) ctl.abort(); resolve(null); }, VERIFY_TIMEOUT);
    });
    var req = Promise.resolve().then(function () {
      return fetch('/api/v2/addresses/' + addr, {
        headers: { Accept: 'application/json' },
        signal: ctl ? ctl.signal : undefined
      });
    }).then(function (r) {
      if (r.status !== 200) return verdict(addr, r.status, null);
      return r.json().then(function (j) { return verdict(addr, 200, j); });
    }).catch(function () { return null; });
    return Promise.race([req, late]).then(function (v) { clearTimeout(timer); return v; });
  }

  function verifyPump() {
    while (verifyActive < VERIFY_MAX && verifyQueue.length) verifyQueue.shift()();
  }

  function queued(job) {
    return new Promise(function (resolve) {
      verifyQueue.push(function () {
        verifyActive++;
        job().then(resolve, function () { resolve(null); }).then(function () {
          verifyActive--;
          verifyPump();
        });
      });
      verifyPump();
    });
  }

  /* อ่านผลจากแคชทันทีไม่รอ — ยังไม่เคยถามหรือหมดอายุจึงยิงขอ 1 ครั้งต่อที่อยู่
   * กำลังรออยู่ก็คืนผลเดิม React วาดแถวใหม่กี่รอบก็ไม่ยิงซ้ำ
   * ระหว่างถามซ้ำตอนหมดอายุใช้ผลเดิมไปก่อน ป้ายจะได้ไม่กะพริบ — ถ้าถามซ้ำแล้วพลาด ป้ายหาย */
  function isVerified(addr) {
    if (!ADDR.test(addr)) return false;
    var key = addr.toLowerCase(), e = verifyCache[key];
    if (e && (!e.done || Date.now() < e.until)) return e.ok;
    var next = verifyCache[key] = { done: false, ok: !!(e && e.ok), until: 0 };
    queued(function () { return fetchVerified(key); }).then(function (v) {
      next.done = true;
      next.ok = v === true;
      next.until = Date.now() + (v === null ? VERIFY_RETRY : VERIFY_TTL);
      badges();                               // วาดตามผลทันที ไม่ต้องรอ DOM ขยับ
    });
    return next.ok;
  }

  /* สร้างด้วย createElement/textContent ล้วน — ไม่มีข้อความจาก API ลงป้ายเลย */
  function verifiedBadge(key, big) {
    verifyStyles();
    var NS = 'http://www.w3.org/2000/svg';
    var s = document.createElement('span');
    s.className = 'tpix-verified' + (big ? ' tpix-verified-lg' : '');
    s.setAttribute('data-tpix-addr', key);
    s.setAttribute('role', 'img');
    s.setAttribute('aria-label', VERIFY_TIP);
    s.title = VERIFY_TIP;
    var svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('viewBox', '0 0 16 16');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');
    var p = document.createElementNS(NS, 'path');
    p.setAttribute('d', 'M3.5 8.5l3 3 6-7');
    p.setAttribute('fill', 'none');
    p.setAttribute('stroke', 'currentColor');
    p.setAttribute('stroke-width', '2.2');
    p.setAttribute('stroke-linecap', 'round');
    p.setAttribute('stroke-linejoin', 'round');
    svg.appendChild(p);
    var t = document.createElement('span');
    t.className = 'tpix-verified-t';
    t.textContent = 'Verified';
    s.appendChild(svg);
    s.appendChild(t);
    return s;
  }

  /* ป้ายจำที่อยู่ไว้ใน data-tpix-addr — ใส่ซ้ำไม่ได้ และแถวที่ React เอาไปแสดงเหรียญอื่น
   * ป้ายเก่าจะถูกถอดตามที่อยู่ ไม่ใช่ดูแค่ว่ามีป้ายแล้ว
   * วางต่อท้ายลูกของ React แต่ก่อนปุ่ม + ของเรา → ลิงก์ · ป้าย · ปุ่ม +
   * ป้ายไม่ใช่ <a> — onWatch ยังหาลิงก์เหรียญใน parentElement ของปุ่มเจอเหมือนเดิม */
  function placeBadge(box, key, ok, big) {
    var keep = null, btn = null;
    [].slice.call(box.children).forEach(function (c) {
      if (c.classList.contains('tpix-watch')) btn = c;
      if (!c.classList.contains('tpix-verified')) return;
      if (ok && !keep && c.getAttribute('data-tpix-addr') === key) keep = c;
      else c.remove();
    });
    if (ok && !keep) box.insertBefore(verifiedBadge(key, big), btn);
  }

  function listBadges() {
    document.querySelectorAll('main a[href^="/token/0x"]').forEach(function (a) {
      var m = TOKEN_LINK.exec(a.getAttribute('href') || '');
      if (!m || !a.parentElement) return;
      placeBadge(a.parentElement, m[1].toLowerCase(), isVerified(m[1]), false);
    });
  }

  /* แถวชื่อเหรียญคือ flex ตัวแรกเหนือ <h1> (โลโก้ · skeleton > h1) */
  function titleRow(h1) {
    for (var el = h1.parentElement, i = 0; el && i < 2; el = el.parentElement, i++) {
      if (/flex/.test(getComputedStyle(el).display)) return el;
    }
    return null;
  }

  /* ที่อยู่เอาจาก URL ไม่ใช่จากหัวเรื่อง — ถามได้ตั้งแต่ยังโหลดชื่อไม่เสร็จ
   * <h1> มาจาก SSR ต้องรอ hydrate ก่อนแตะ (ดู hydrated()) */
  function pageBadge() {
    var m = TOKEN_PAGE.exec(location.pathname);
    if (!m) return;
    var ok = isVerified(m[1]);
    var h1 = document.querySelector('main h1');
    var row = h1 && titleRow(h1);
    if (!row || !hydrated(row)) return;
    placeBadge(row, m[1].toLowerCase(), ok, true);
  }

  function badges() {
    var stale = '.tpix-verified';
    if (isTokens()) { listBadges(); stale = '.tpix-verified-lg'; }
    else if (isTokenPage()) { pageBadge(); stale = '.tpix-verified:not(.tpix-verified-lg)'; }
    document.querySelectorAll(stale).forEach(function (b) { b.remove(); });   // ค้างจากหน้าก่อน
  }

  /* ── ทะเบียนเชนใน footer ───────────────────────────────────────────────── */

  /* ใส่เฉพาะที่ตรวจแล้วว่ามีหน้า chain 4289 จริง (ethereum-lists/chains PR #8148)
   * chainid.network ไม่มีโลโก้ทางการ จึงใช้ป้ายชื่อ — ห้ามวาดโลโก้ปลอมขึ้นเอง
   * ไม่ลิงก์ไฟล์ต้นทางบน GitHub ตามกฎเดียวกับเว็บหลัก (หน้าผู้ใช้ไม่มีลิงก์ GitHub ของเรา)
   * โลโก้เสิร์ฟจาก explorer เอง (assets/ → /opt/tpix/www/assets/) ไม่ hotlink เว็บนอก
   * chainlist.svg ต้นทาง (chainlist.org/logo.svg) เขียน stopColor แบบ JSX ซึ่ง SVG ไม่รู้จัก
   * ไอคอนจึงออกดำแทนฟ้า — สำเนาของเราแก้เป็น stop-color แล้ว */
  var REGISTRIES = [
    { name: 'Chainlist', href: 'https://chainlist.org/chain/4289', logo: '/tpix-assets/chainlist.svg' },
    { name: 'chainid.network', href: 'https://chainid.network/chain/4289/' }
  ];
  var LINK_ICON = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" ' +
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>' +
    '<path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>';

  function registryStyles() {
    if (document.getElementById('tpix-reg-css')) return;
    var s = document.createElement('style');
    s.id = 'tpix-reg-css';
    s.textContent = [
      '.tpix-reg{margin-top:20px}',
      '.tpix-reg p{font-size:12px;line-height:1.5;opacity:.7;margin:0 0 8px}',
      '.tpix-reg-list{display:flex;flex-wrap:wrap;gap:8px}',
      /* พื้นขาวทั้งสองธีม — โลโก้ Chainlist เป็นตัวหนังสือสีเข้ม บนพื้นมืดจะมองไม่เห็น */
      '.tpix-reg a{display:inline-flex;align-items:center;gap:6px;height:32px;padding:0 10px;border-radius:8px;',
      '  background:rgba(255,255,255,.92);border:1px solid rgba(128,145,170,.35);color:#1a202c;',
      '  font:600 12px/1 system-ui,sans-serif;text-decoration:none;transition:background .15s,border-color .15s}',
      '.tpix-reg a:hover{background:#fff;border-color:#06b6d4}',
      '.tpix-reg img{height:16px;width:auto;display:block}'
    ].join('');
    document.head.appendChild(s);
  }

  function registryLink(r) {
    var a = document.createElement('a');
    a.href = r.href;
    a.target = '_blank';
    a.rel = 'noopener';
    a.title = 'TPIX Chain (4289) — ' + r.name;
    var label = function () { a.innerHTML = LINK_ICON; a.appendChild(document.createTextNode(r.name)); };
    if (!r.logo) { label(); return a; }
    var img = document.createElement('img');
    img.src = r.logo;
    img.alt = r.name;
    img.loading = 'lazy';
    img.onerror = label;                        // โหลดโลโก้ไม่ได้ ยังเหลือป้ายชื่อให้กด
    a.appendChild(img);
    return a;
  }

  /* React ติด __reactFiber$… ให้ node ตอน hydrate เสร็จ — ใช้บอกว่าแตะ DOM ได้แล้ว
   * สคริปต์นี้รันต่อจาก chunk ของ Next ทันที ซึ่งเร็วกว่าการ hydrate ถ้าแทรกของลง
   * HTML ที่มาจากเซิร์ฟก่อน React จะเจอ DOM ไม่ตรง (error #418/#423) แล้ววาดใหม่
   * ทั้งหน้า — เจอจริงตอนเพิ่มแถบนี้ v6 (2026-10-22) */
  function hydrated(el) {
    for (var k in el) if (k.indexOf('__reactFiber') === 0) return true;
    return false;
  }

  /* วางในคอลัมน์ซ้ายใต้ Copyright (footer > grid > คอลัมน์แรก) ต่อท้ายสุด
   * ไม่แทรกกลางลูกที่ React จัดการ — ถ้า React วาดใหม่จนหาย apply() รอบถัดไปจะใส่คืน */
  function registries() {
    var col = document.querySelector('footer > div > div:first-child');
    if (!col || !hydrated(col) || col.querySelector('.tpix-reg')) return;
    registryStyles();
    var box = document.createElement('div');
    box.className = 'tpix-reg';
    var p = document.createElement('p');
    p.textContent = 'TPIX Chain (ID 4289) ลงทะเบียนอยู่บน · Registered on';
    var list = document.createElement('div');
    list.className = 'tpix-reg-list';
    REGISTRIES.forEach(function (r) { list.appendChild(registryLink(r)); });
    box.appendChild(p);
    box.appendChild(list);
    col.appendChild(box);
  }

  /* ── branding ──────────────────────────────────────────────────────────── */

  /* ไม่ยุ่งกับโลโก้ที่นี่แล้ว — ปล่อยให้ NEXT_PUBLIC_NETWORK_LOGO/_ICON ทำงาน
   *
   * โค้ดเดิมยัดโลโก้แนวนอนลงทุก <img> ในแถบหัวแล้วบังคับ height:60px width:auto
   * ปัญหาคือแถบหัวมีสองช่องคนละแบบ: ช่องโลโก้แนวนอน กับช่องไอคอน**จัตุรัส** 30×30
   * ที่ overflow:hidden — พอโดนบังคับสูง 60px ในกล่อง 30px รูปจึงถูกบีบเหลือ 30×60
   * กลายเป็นโลโก้ผอมสูงผิดสัดส่วนจนอ่านไม่ออก (เจอจริง 2026-08-08)
   *
   * ตอนนี้ compose ตั้ง LOGO เป็นรูปแนวนอน และ ICON เป็น tpix-logo-512.png (จัตุรัส)
   * แยกกันถูกช่องแล้ว Blockscout จัดขนาดเองได้ถูกต้องกว่าการไปฝืนด้วย inline style */
  function branding() {
    document.querySelectorAll("a[href*='blockscout.com']").forEach(function (a) {
      if (a.closest('footer') || a.closest("[class*='footer']")) {
        a.href = 'https://xman4289.com';
        if (a.textContent.trim().toLowerCase().indexOf('blockscout') > -1) a.textContent = 'Xman Studio';
      }
    });
  }

  /* ── lifecycle ─────────────────────────────────────────────────────────── */

  function isHome() { return location.pathname === '/' || location.pathname === ''; }
  function isTokens() { return /^\/tokens\/?$/.test(location.pathname); }
  function isTokenPage() { return TOKEN_PAGE.test(location.pathname); }   // ?tab=… อยู่ใน search ไม่กระทบ

  function apply() {
    branding();
    registries();
    if (isHome()) render();
    else { var b = document.querySelector('.tpix-treasury'); if (b) b.remove(); }
    if (isTokens()) addWatchButtons();
    badges();                                 // หลังปุ่ม + — ป้ายแทรกก่อนปุ่มได้ทันที
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
    /* apply() แรกมักมาก่อน hydrate จึงข้าม (ดู hydrated()) และหน้าที่ hydrate แล้ว
     * DOM ไม่ขยับเลยจะไม่ปลุก observer — ลองซ้ำตามเวลาไว้ให้ footer ขึ้นแน่ */
    [1000, 2500, 6000].forEach(function (ms) { setTimeout(apply, ms); });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
