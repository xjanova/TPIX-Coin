/// TPIX Wallet — รายการโปรด (สมุดที่อยู่)
///
/// รวมส่วนติดต่อผู้ใช้ของสมุดที่อยู่ไว้ที่เดียว: แผ่นเลือก, กล่องบันทึกชื่อ,
/// และแถวชิปทางลัด เพื่อให้หน้าอื่น (โอน/สวอป/บริดจ์) หยิบไปใช้ซ้ำได้
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';
import '../core/themes/tokens.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../models/contact.dart';
import '../services/db_service.dart';

/// สีวงกลมย่อชื่อ — เลือกจากที่อยู่ให้คนเดิมได้สีเดิมทุกครั้ง
Color contactColor(String address) {
  const palette = [
    Color(0xFF06B6D4),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFF00C853),
    Color(0xFFEC4899),
    Color(0xFF3B82F6),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
  ];
  var hash = 0;
  for (final unit in address.toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  return palette[hash % palette.length];
}

/// วงกลมตัวอักษรแรกของชื่อ
class ContactAvatar extends StatelessWidget {
  final Contact contact;
  final double size;

  const ContactAvatar({super.key, required this.contact, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final color = contactColor(contact.address);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.28)!, color],
        ),
      ),
      child: Text(
        contact.initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// แผ่นเลือกรายการโปรด
// ─────────────────────────────────────────────────────────────

/// เปิดแผ่นเลือกรายการโปรด — คืนรายการที่ผู้ใช้เลือก (null = ปิดไปเฉยๆ)
Future<Contact?> showContactPicker(BuildContext context) {
  return showModalBottomSheet<Contact>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _ContactPickerSheet(),
  );
}

class _ContactPickerSheet extends StatefulWidget {
  const _ContactPickerSheet();

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  List<Contact> _all = const [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DbService.getContacts();
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  List<Contact> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all
        .where((c) =>
            c.name.toLowerCase().contains(q) || c.address.contains(q))
        .toList();
  }

  Future<void> _edit(Contact contact) async {
    final saved = await showSaveContactDialog(
      context,
      address: contact.address,
      existing: contact,
    );
    if (saved != null) await _load();
  }

  Future<void> _delete(Contact contact) async {
    final l = context.read<LocaleProvider>();
    final c = AppColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.lg)),
        title: Text(l.t('contacts.deleteTitle'),
            style: TextStyle(color: c.text, fontSize: 17)),
        content: Text(
          l.t('contacts.deleteBody').replaceAll('{name}', contact.name),
          style: TextStyle(color: c.textSec, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.t('send.cancel'),
                style: TextStyle(color: c.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.t('contacts.delete'),
                style: const TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (contact.id != null) await DbService.deleteContact(contact.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final c = AppColors.of(context);
    final items = _visible;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(TpixRadius.sheet)),
          border: Border.all(color: c.glassBorder, width: 1.2),
        ),
        child: Column(
          children: [
            const SizedBox(height: TpixGap.md),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: c.textMuted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: TpixGap.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.star_rounded, color: c.brandWarm, size: 22),
                  const SizedBox(width: TpixGap.sm),
                  Text(
                    l.t('contacts.title'),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: c.text),
                  ),
                  const Spacer(),
                  if (_all.isNotEmpty)
                    Text('${_all.length}',
                        style: TextStyle(fontSize: 13, color: c.textMuted)),
                ],
              ),
            ),
            const SizedBox(height: TpixGap.md),

            // ช่องค้นหา — โผล่เมื่อมีรายการเยอะพอที่จะหายาก
            if (_all.length > 5)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(color: c.text, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l.t('contacts.search'),
                    hintStyle: TextStyle(color: c.textMuted, fontSize: 14),
                    prefixIcon:
                        Icon(Icons.search, color: c.textMuted, size: 20),
                    filled: true,
                    fillColor: c.glassColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TpixRadius.md),
                      borderSide: BorderSide(color: c.glassBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TpixRadius.md),
                      borderSide: BorderSide(color: c.glassBorder),
                    ),
                  ),
                ),
              ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? _buildEmpty(l, c)
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: TpixGap.xs),
                          itemBuilder: (_, i) =>
                              _buildTile(items[i], l, c),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(Contact contact, LocaleProvider l, AppColors c) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(TpixRadius.md),
        onTap: () => Navigator.pop(context, contact),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              ContactAvatar(contact: contact),
              const SizedBox(width: TpixGap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.text),
                    ),
                    const SizedBox(height: TpixGap.hair),
                    Text(
                      contact.shortAddress,
                      style: TextStyle(
                          fontSize: 12,
                          color: c.textMuted,
                          fontFamily: 'monospace'),
                    ),
                    if (contact.note != null &&
                        contact.note!.trim().isNotEmpty) ...[
                      const SizedBox(height: TpixGap.hair),
                      Text(
                        contact.note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: c.textSec),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: c.textMuted, size: 20),
                color: c.card,
                onSelected: (v) =>
                    v == 'edit' ? _edit(contact) : _delete(contact),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18, color: c.textSec),
                        const SizedBox(width: TpixGap.md),
                        Text(l.t('contacts.edit'),
                            style: TextStyle(color: c.text)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline,
                            size: 18, color: AppTheme.danger),
                        const SizedBox(width: TpixGap.md),
                        Text(l.t('contacts.delete'),
                            style: const TextStyle(color: AppTheme.danger)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(LocaleProvider l, AppColors c) {
    final searching = _query.trim().isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(searching ? Icons.search_off_rounded : Icons.star_border_rounded,
                size: 52, color: c.textMuted),
            const SizedBox(height: TpixGap.lg),
            Text(
              l.t(searching ? 'contacts.noMatch' : 'contacts.empty'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
            ),
            if (!searching) ...[
              const SizedBox(height: TpixGap.sm),
              Text(
                l.t('contacts.emptyHint'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.textMuted, height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// กล่องบันทึกชื่อ
// ─────────────────────────────────────────────────────────────

/// เปิดกล่องตั้งชื่อให้ที่อยู่ — คืนรายการที่บันทึกแล้ว (null = ยกเลิก)
Future<Contact?> showSaveContactDialog(
  BuildContext context, {
  required String address,
  Contact? existing,
}) {
  return showDialog<Contact>(
    context: context,
    builder: (_) => _SaveContactDialog(address: address, existing: existing),
  );
}

class _SaveContactDialog extends StatefulWidget {
  final String address;
  final Contact? existing;

  const _SaveContactDialog({required this.address, this.existing});

  @override
  State<_SaveContactDialog> createState() => _SaveContactDialogState();
}

class _SaveContactDialogState extends State<_SaveContactDialog> {
  // ตัวควบคุมช่องกรอกต้องถูกสร้างใน State ไม่ใช่ใน builder ของ dialog
  // ไม่งั้นค่าจะรีเซ็ตทุกครั้งที่ rebuild และไม่มีใคร dispose ให้
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return; // กันกดรัว
    final l = context.read<LocaleProvider>();
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l.t('contacts.nameRequired'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final note = _note.text.trim();
    final contact = Contact(
      id: widget.existing?.id,
      address: widget.address.toLowerCase(),
      name: name,
      note: note.isEmpty ? null : note,
      usedCount: widget.existing?.usedCount ?? 0,
      lastUsedAt: widget.existing?.lastUsedAt,
      createdAt: widget.existing?.createdAt ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    try {
      final id = await DbService.saveContact(contact);
      if (!mounted) return;
      Navigator.pop(context, contact.copyWith(id: id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l.t('contacts.saveFailed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final c = AppColors.of(context);
    final short = widget.address.length > 16
        ? '${widget.address.substring(0, 10)}…${widget.address.substring(widget.address.length - 6)}'
        : widget.address;

    return AlertDialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.lg)),
      title: Text(
        l.t(widget.existing == null ? 'contacts.saveTitle' : 'contacts.editTitle'),
        style: TextStyle(color: c.text, fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TpixRadius.sm),
              color: c.glassColor,
              border: Border.all(color: c.glassBorder),
            ),
            child: Text(
              short,
              style: TextStyle(
                  fontSize: 13, color: c.textSec, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: TpixGap.lg),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            style: TextStyle(color: c.text),
            decoration: InputDecoration(
              counterText: '',
              labelText: l.t('contacts.nameLabel'),
              labelStyle: TextStyle(color: c.textMuted),
              hintText: l.t('contacts.nameHint'),
              hintStyle: TextStyle(color: c.textMuted.withValues(alpha: 0.5)),
              filled: true,
              fillColor: c.glassColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(TpixRadius.md),
                borderSide: BorderSide(color: c.glassBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(TpixRadius.md),
                borderSide: BorderSide(color: c.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(TpixRadius.md),
                borderSide: BorderSide(color: c.brandPrimary),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: TpixGap.md),
          TextField(
            controller: _note,
            maxLength: 60,
            style: TextStyle(color: c.text, fontSize: 14),
            decoration: InputDecoration(
              counterText: '',
              labelText: l.t('contacts.noteLabel'),
              labelStyle: TextStyle(color: c.textMuted),
              filled: true,
              fillColor: c.glassColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(TpixRadius.md),
                borderSide: BorderSide(color: c.glassBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(TpixRadius.md),
                borderSide: BorderSide(color: c.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(TpixRadius.md),
                borderSide: BorderSide(color: c.brandPrimary),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: TpixGap.md),
            Text(_error!,
                style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l.t('send.cancel'), style: TextStyle(color: c.textMuted)),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: c.brandPrimary),
          child: Text(
            l.t('contacts.save'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
