// TPIX Wallet — หน้าสแกน QR ธีม Obsidian (ตาม A-Scan.dc.html)
//
// เป็น part ของ qr_scanner_screen.dart โดยตั้งใจ: ใช้ตัวควบคุมกล้อง / จังหวะแอปสลับ /
// กันสแกนซ้ำ / ข้อความกล้องเปิดไม่ได้ ชุดเดิมร่วมกัน — ธีมอื่นใช้หน้าเดิมทุกอย่าง
//
// ที่ต่างจาก mock โดยตั้งใจ:
//   - ไม่มีปุ่ม "เลือกรูปจากคลัง" — แอปยังไม่มีตัวเลือกรูป (image_picker) และสแกนเนอร์เดิมไม่รองรับ
//   - สแกนเจอแล้วส่งค่าให้ผู้เรียกตามเดิม (หน้าแรกพาไปหน้าส่งที่เติมที่อยู่ให้) แทนแผ่นจ่ายใน mock
//     — QR ของกระเป๋ามีแค่ที่อยู่ ไม่มีจำนวน และการยืนยัน PIN/ตรวจยอด/ตรวจสัญญาอยู่ที่หน้าส่งที่เดียว
//
// Developed by Xman Studio

part of 'qr_scanner_screen.dart';

extension _ObsidianScanner on _QRScannerScreenState {
  Widget _buildObsidian(LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final locked = _lock != null;
    final payMode = widget.onShowMyQr != null;
    final title = locked
        ? l.t('obs.scan.found')
        : l.t(payMode ? 'scanSheet.pay' : (widget.titleKey ?? 'send.scanQR'));
    final preview = QRScannerScreen.debugPreviewBuilder;

    return Scaffold(
      backgroundColor: const Color(0xFF050608),
      body: LayoutBuilder(builder: (context, box) {
        _viewSize = box.biggest;
        final window = ScanGeometry.windowFor(box.biggest);
        return Stack(
          fit: StackFit.expand,
          children: [
            // ── ภาพกล้อง ──
            if (preview != null)
              preview(context, _onDetect)
            else
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                fit: BoxFit.cover,
                errorBuilder: (context, error) => _obsError(context, error, l),
              ),

            // ── ม่านมืด + กรอบเล็ง ──
            ScanViewfinder(lock: _lock),

            // ── หัว: ปิด · หัวข้อ · ไฟฉาย ──
            Positioned(
              left: 20,
              right: 20,
              top: math.max(52.0, topInset + 8),
              child: ObsidianTopBar(
                leading: ObsidianTopButton(
                  tint: const Color(0x1AFFFFFF),
                  onTap: () => Navigator.maybePop(context),
                  semanticLabel: l.t('obs.sr.close'),
                  child: const ObsidianGlyphIcon(ObsidianGlyph.close, strokeWidth: 2.2),
                ),
                center: Semantics(
                  header: true,
                  liveRegion: locked,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: st.ui(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: ObsidianColors.text,
                      shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 10, offset: Offset(0, 2))],
                    ),
                  ),
                ),
                trailing: _obsTorch(l),
              ),
            ),

            // ── คำใบ้ใต้ช่องเล็ง (กะพริบช้า ๆ) ──
            if (!locked)
              Positioned(
                left: 24,
                right: 24,
                top: window.bottom + 28,
                child: IgnorePointer(
                  child: ObsidianLoop(
                    period: const Duration(milliseconds: 1200),
                    reverse: true,
                    restValue: 1,
                    builder: (context, t, child) => Opacity(opacity: 0.55 + 0.45 * t, child: child),
                    child: Text(
                      l.t('obs.scan.hint'),
                      textAlign: TextAlign.center,
                      style: st.ui(fontSize: 14, color: const Color(0xFFE9EAEE)),
                    ),
                  ),
                ),
              ),

            // ── แท็บ สแกนจ่าย / QR รับเงิน (เฉพาะสแกนจ่ายจากหน้าแรก) ──
            if (payMode && !locked)
              Positioned(
                left: 20,
                right: 20,
                bottom: 30 + bottomInset,
                child: _obsModeTabs(l, st),
              ),
          ],
        );
      }),
    );
  }

  /// ปุ่มไฟฉาย — ซ่อนถ้าเครื่องไม่มีไฟฉาย (เหมือนหน้าเดิม)
  Widget _obsTorch(LocaleProvider l) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _controller,
      builder: (_, state, _) {
        if (state.torchState == TorchState.unavailable) return const SizedBox.shrink();
        final on = state.torchState == TorchState.on;
        return Semantics(
          toggled: on,
          child: ObsidianTopButton(
            tint: on ? const Color(0x59FDE68A) : const Color(0x1AFFFFFF),
            onTap: () => _controller.toggleTorch().ignore(),
            semanticLabel: l.t('scan.torch'),
            child: ObsidianGlyphIcon(
              ObsidianGlyph.flash,
              color: on ? const Color(0xFFFDE68A) : ObsidianColors.text,
            ),
          ),
        );
      },
    );
  }

  Widget _obsModeTabs(LocaleProvider l, ObsidianStyle st) {
    Widget tab({required String asset, required String label, required bool selected, VoidCallback? onTap}) {
      final body = SizedBox(
        height: 50,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon3D(asset, size: 30),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: st.ui(
                  fontSize: 14.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? const Color(0xFF0A0B0F) : ObsidianColors.chrome,
                ),
              ),
            ),
          ],
        ),
      );
      return Semantics(
        selected: selected,
        button: !selected,
        child: selected
            ? CustomPaint(
                painter: const ObsidianSurfacePainter(ObsidianSurface(
                  radius: 16,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFF7F8FA), Color(0xFFD9DCE3)],
                  ),
                )),
                child: body,
              )
            : ObsidianPressable(onTap: onTap, child: body),
      );
    }

    return ObsidianPanel(
      blur: 18,
      padding: const EdgeInsets.all(4),
      surface: const ObsidianSurface(
        radius: 20,
        color: Color(0xC70C0E14), // rgba(12,14,20,.78)
        topHighlight: Color(0x1AFFFFFF),
        shadows: [CssShadow(0, 18, 34, -14, Color(0xF2000000))],
      ),
      child: Row(
        children: [
          Expanded(child: tab(asset: ObsidianIcons.scan, label: l.t('scanSheet.pay'), selected: true)),
          Expanded(
            child: tab(
              asset: ObsidianIcons.receive,
              label: l.t('obs.scan.myQr'),
              selected: false,
              onTap: widget.onShowMyQr,
            ),
          ),
        ],
      ),
    );
  }

  /// กล้องเปิดไม่ได้ — บอกสาเหตุเป็นภาษาคน (ข้อความ/ปุ่มลองใหม่ชุดเดิม)
  Widget _obsError(BuildContext context, MobileScannerException error, LocaleProvider l) {
    final st = ObsidianStyle.of(context);
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;
    final (title, hint) = denied
        ? (l.t('scan.noPermission'), l.t('scan.noPermissionHint'))
        : unsupported
            ? (l.t('scan.unsupported'), l.t('scan.unsupportedHint'))
            : (l.t('scan.cameraError'), l.t('scan.cameraErrorHint'));

    return ColoredBox(
      color: const Color(0xFF050608),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon3D(denied ? ObsidianIcons.lock : ObsidianIcons.scan, size: 72, dimmed: true),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: st.ui(fontSize: 18, fontWeight: FontWeight.w600, color: ObsidianColors.text),
              ),
              const SizedBox(height: 10),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: st.ui(fontSize: 14, height: 1.5, color: ObsidianColors.textSec),
              ),
              if (!unsupported) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  child: ObsidianButton.secondary(
                    label: l.t('scan.retry'),
                    onPressed: () async {
                      await _controller.stop();
                      await _controller.start();
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
