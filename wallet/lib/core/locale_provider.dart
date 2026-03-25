import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const String _key = 'app_locale';
  String _locale = 'th';

  String get locale => _locale;
  bool get isThai => _locale == 'th';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _locale = prefs.getString(_key) ?? 'th';
    notifyListeners();
  }

  Future<void> setLocale(String locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale);
    notifyListeners();
  }

  Future<void> toggle() async {
    await setLocale(_locale == 'th' ? 'en' : 'th');
  }

  String t(String key) => _translations[_locale]?[key] ?? _translations['en']?[key] ?? key;

  static const Map<String, Map<String, String>> _translations = {
    'th': {
      // Splash
      'splash.byXman': 'by Xman Studio',

      // Onboarding
      'onboarding.subtitle': 'กระเป๋าเงินสำหรับ TPIX Chain\nปลอดภัย ไม่มีค่าแก๊ส เร็ว 2 วินาที',
      'onboarding.createWallet': 'สร้างกระเป๋าใหม่',
      'onboarding.createWalletSub': 'Create New Wallet',
      'onboarding.importWallet': 'นำเข้ากระเป๋า',
      'onboarding.importWalletSub': 'Import Existing Wallet',

      // Home
      'home.copied': 'คัดลอกที่อยู่แล้ว!',
      'home.balance': 'ยอดคงเหลือ',
      'home.send': 'ส่ง',
      'home.sendSub': 'Send',
      'home.receive': 'รับ',
      'home.receiveSub': 'Receive',
      'home.history': 'ประวัติ',
      'home.historySub': 'History',
      'home.swap': 'แลก',
      'home.swapSub': 'Swap',
      'home.blockTime': 'Block Time',
      'home.blockTimeVal': '2 วินาที',
      'home.gasFee': 'Gas Fee',
      'home.gasFeeVal': 'ฟรี!',
      'home.consensus': 'Consensus',
      'home.links': 'ลิงก์',
      'home.settings': 'ตั้งค่า',
      'home.language': 'ภาษา',
      'home.recentTx': 'ธุรกรรมล่าสุด',
      'home.viewAll': 'ดูทั้งหมด',

      // Import
      'import.title': 'นำเข้ากระเป๋า',
      'import.subtitle': 'Import Wallet',
      'import.hintMnemonic': 'ใส่ 12 คำ คั่นด้วยช่องว่าง...',
      'import.hintKey': 'ใส่ Private Key (0x...)...',
      'import.button': 'นำเข้า',
      'import.scanQR': 'สแกน QR Code',
      'import.scanHint': 'วาง QR Code ในกรอบ',

      // Send
      'send.title': 'ส่ง TPIX',
      'send.subtitle': 'Send TPIX — Zero Gas Fee',
      'send.toAddress': 'ที่อยู่ผู้รับ',
      'send.invalidAddress': 'ที่อยู่ไม่ถูกต้อง',
      'send.invalidAmount': 'จำนวนไม่ถูกต้อง',
      'send.amount': 'จำนวน',
      'send.balance': 'ยอดคงเหลือ: ',
      'send.gasFee': 'Gas Fee: ',
      'send.gasFreeVal': 'ฟรี! (0 TPIX)',
      'send.sending': 'กำลังส่ง...',
      'send.button': 'ส่ง TPIX',
      'send.success': 'ส่งสำเร็จ!',
      'send.confirmed': 'Transaction Confirmed',
      'send.goBack': 'กลับหน้าหลัก',
      'send.scanQR': 'สแกน QR Code',
      'send.scanHint': 'วาง QR Code ที่อยู่ผู้รับในกรอบ',

      // Receive
      'receive.title': 'รับ TPIX',
      'receive.subtitle': 'Receive TPIX',
      'receive.copied': 'คัดลอกที่อยู่แล้ว!',
      'receive.copy': 'คัดลอก',
      'receive.warning': 'ส่งเฉพาะ TPIX (Chain ID: 4289) มาที่อยู่นี้เท่านั้น',

      // Backup
      'backup.title': 'สำรองกระเป๋า',
      'backup.subtitle': 'Backup Seed Phrase',
      'backup.warning': 'จดบันทึก 12 คำนี้ไว้ในที่ปลอดภัย ห้ามแชร์ให้ใครเด็ดขาด!',
      'backup.copied': 'คัดลอกแล้ว!',
      'backup.copy': 'คัดลอก',
      'backup.continue': 'สำรองแล้ว ดำเนินการต่อ',

      // PIN
      'pin.setup': 'ตั้ง PIN 6 หลัก',
      'pin.setupSub': 'Set a 6-digit PIN',
      'pin.confirm': 'ยืนยัน PIN',
      'pin.confirmSub': 'Confirm your PIN',
      'pin.unlock': 'ใส่ PIN เพื่อเข้าใช้',
      'pin.unlockSub': 'Enter your PIN to unlock',
      'pin.wrong': 'PIN ไม่ถูกต้อง',

      // Transaction History
      'tx.title': 'ประวัติธุรกรรม',
      'tx.subtitle': 'Transaction History',
      'tx.empty': 'ยังไม่มีธุรกรรม',
      'tx.emptyHint': 'ส่งหรือรับ TPIX เพื่อเริ่มบันทึก',
      'tx.scan': 'สแกนบล็อกเชน',
      'tx.scanning': 'กำลังสแกน...',
      'tx.detail': 'รายละเอียดธุรกรรม',
      'tx.hash': 'TX Hash',
      'tx.from': 'จาก',
      'tx.to': 'ถึง',
      'tx.amount': 'จำนวน',
      'tx.status': 'สถานะ',
      'tx.block': 'บล็อก',
      'tx.copyHash': 'คัดลอก TX Hash',
      'tx.hashCopied': 'คัดลอก TX Hash แล้ว!',

      // Identity / Recovery
      'identity.title': 'การปกป้องตัวตน',
      'identity.subtitle': 'Living Identity Recovery',
      'identity.securityLevel': 'ระดับความปลอดภัย',
      'identity.level0': 'ไม่มีการป้องกัน',
      'identity.level1': 'พื้นฐาน',
      'identity.level2': 'ปานกลาง',
      'identity.level3': 'สูงสุด',
      'identity.questions': 'คำถามกันลืม',
      'identity.questionsDesc': 'ตั้งคำถาม 3 ข้อที่คุณเท่านั้นรู้คำตอบ',
      'identity.questionsHint': 'เลือกคำถามที่คำตอบไม่เปลี่ยนตามเวลา',
      'identity.questionLabel': 'คำถามที่',
      'identity.questionPlaceholder': 'พิมพ์คำถาม...',
      'identity.answerPlaceholder': 'คำตอบ...',
      'identity.needQuestions': 'ต้องตอบครบ 3 คำถาม',
      'identity.questionsSaved': 'บันทึกคำถามกันลืมแล้ว!',
      'identity.location': 'พิกัดที่อยู่ประจำ',
      'identity.locationDesc': 'ลงทะเบียนสถานที่สำหรับกู้คืน (สูงสุด 3 จุด)',
      'identity.locationHint': 'ไปที่สถานที่จริง (บ้าน, ที่ทำงาน) แล้วลงทะเบียน\nเก็บเฉพาะ hash ไม่เก็บพิกัดจริง',
      'identity.locationLabel': 'ชื่อสถานที่ (เช่น บ้าน, ที่ทำงาน)',
      'identity.needLabel': 'กรุณาใส่ชื่อสถานที่',
      'identity.locationSaved': 'ลงทะเบียนสถานที่แล้ว!',
      'identity.registerHere': 'ลงทะเบียนตำแหน่งปัจจุบัน',
      'identity.recoveryPin': 'Recovery PIN',
      'identity.recoveryPinDesc': 'PIN สำรอง 6-8 หลัก (ใช้แทน GPS)',
      'identity.recoveryPinHint': 'ใช้เมื่อ GPS ไม่พร้อม หรืออยู่ต่างสถานที่',
      'identity.confirmPin': 'ยืนยัน PIN',
      'identity.pinTooShort': 'PIN ต้องมีอย่างน้อย 6 หลัก',
      'identity.pinMismatch': 'PIN ไม่ตรงกัน',
      'identity.pinSaved': 'บันทึก Recovery PIN แล้ว!',
      'identity.save': 'บันทึก',
      'identity.testRecovery': 'ทดสอบการกู้คืน',
      'identity.testRecoveryDesc': 'ทดสอบว่าคุณสามารถกู้คืนกระเป๋าได้จริง\nจะตรวจคำถาม + ตำแหน่ง GPS',
      'identity.startTest': 'เริ่มทดสอบ',
      'identity.verify': 'ยืนยันตัวตน',
      'identity.recoveryPinOptional': 'Recovery PIN (ถ้า GPS ไม่พร้อม)',
      'identity.testSuccess': 'ผ่าน! คุณสามารถกู้คืนกระเป๋าได้',
      'identity.testFailed': 'ไม่ผ่าน กรุณาตรวจสอบคำตอบและตำแหน่ง',

      // Wallet Management
      'wallets.title': 'กระเป๋าเงิน',
      'wallets.active': 'ใช้งาน',
      'wallets.switch': 'สลับ',
      'wallets.rename': 'เปลี่ยนชื่อ',
      'wallets.delete': 'ลบ',
      'wallets.newName': 'ชื่อใหม่',
      'wallets.cancel': 'ยกเลิก',
      'wallets.save': 'บันทึก',
      'wallets.created': 'สร้างกระเป๋าใหม่แล้ว!',
      'wallets.deleteConfirm': 'ลบกระเป๋า?',
      'wallets.deleteMsg': 'กระเป๋านี้จะถูกลบถาวร กรุณาสำรองก่อนลบ',
    },
    'en': {
      // Splash
      'splash.byXman': 'by Xman Studio',

      // Onboarding
      'onboarding.subtitle': 'Wallet for TPIX Chain\nSecure. Zero Gas Fee. 2-Second Blocks.',
      'onboarding.createWallet': 'Create New Wallet',
      'onboarding.createWalletSub': 'Generate a fresh wallet',
      'onboarding.importWallet': 'Import Wallet',
      'onboarding.importWalletSub': 'Use seed phrase or private key',

      // Home
      'home.copied': 'Address copied!',
      'home.balance': 'Balance',
      'home.send': 'Send',
      'home.sendSub': 'Transfer',
      'home.receive': 'Receive',
      'home.receiveSub': 'Deposit',
      'home.history': 'History',
      'home.historySub': 'Records',
      'home.swap': 'Swap',
      'home.swapSub': 'Exchange',
      'home.blockTime': 'Block Time',
      'home.blockTimeVal': '2 Seconds',
      'home.gasFee': 'Gas Fee',
      'home.gasFeeVal': 'Free!',
      'home.consensus': 'Consensus',
      'home.links': 'Links',
      'home.settings': 'Settings',
      'home.language': 'Language',
      'home.recentTx': 'Recent Transactions',
      'home.viewAll': 'View All',

      // Import
      'import.title': 'Import Wallet',
      'import.subtitle': 'Restore your wallet',
      'import.hintMnemonic': 'Enter 12 words separated by spaces...',
      'import.hintKey': 'Enter Private Key (0x...)...',
      'import.button': 'Import',
      'import.scanQR': 'Scan QR Code',
      'import.scanHint': 'Place QR Code in frame',

      // Send
      'send.title': 'Send TPIX',
      'send.subtitle': 'Send TPIX — Zero Gas Fee',
      'send.toAddress': 'Recipient Address',
      'send.invalidAddress': 'Invalid address',
      'send.invalidAmount': 'Invalid amount',
      'send.amount': 'Amount',
      'send.balance': 'Balance: ',
      'send.gasFee': 'Gas Fee: ',
      'send.gasFreeVal': 'Free! (0 TPIX)',
      'send.sending': 'Sending...',
      'send.button': 'Send TPIX',
      'send.success': 'Sent Successfully!',
      'send.confirmed': 'Transaction Confirmed',
      'send.goBack': 'Back to Home',
      'send.scanQR': 'Scan QR Code',
      'send.scanHint': 'Place recipient QR Code in frame',

      // Receive
      'receive.title': 'Receive TPIX',
      'receive.subtitle': 'Your wallet address',
      'receive.copied': 'Address copied!',
      'receive.copy': 'Copy',
      'receive.warning': 'Only send TPIX (Chain ID: 4289) to this address',

      // Backup
      'backup.title': 'Backup Wallet',
      'backup.subtitle': 'Save your seed phrase',
      'backup.warning': 'Write down these 12 words in a safe place. Never share them!',
      'backup.copied': 'Copied!',
      'backup.copy': 'Copy',
      'backup.continue': 'I\'ve backed up, continue',

      // PIN
      'pin.setup': 'Set 6-Digit PIN',
      'pin.setupSub': 'Create a secure PIN',
      'pin.confirm': 'Confirm PIN',
      'pin.confirmSub': 'Enter your PIN again',
      'pin.unlock': 'Enter PIN to Unlock',
      'pin.unlockSub': 'Authenticate to continue',
      'pin.wrong': 'Incorrect PIN',

      // Transaction History
      'tx.title': 'Transaction History',
      'tx.subtitle': 'All transactions',
      'tx.empty': 'No transactions yet',
      'tx.emptyHint': 'Send or receive TPIX to start recording',
      'tx.scan': 'Scan Blockchain',
      'tx.scanning': 'Scanning...',
      'tx.detail': 'Transaction Detail',
      'tx.hash': 'TX Hash',
      'tx.from': 'From',
      'tx.to': 'To',
      'tx.amount': 'Amount',
      'tx.status': 'Status',
      'tx.block': 'Block',
      'tx.copyHash': 'Copy TX Hash',
      'tx.hashCopied': 'TX Hash copied!',

      // Identity / Recovery
      'identity.title': 'Identity Protection',
      'identity.subtitle': 'Living Identity Recovery',
      'identity.securityLevel': 'Security Level',
      'identity.level0': 'No protection',
      'identity.level1': 'Basic',
      'identity.level2': 'Medium',
      'identity.level3': 'Maximum',
      'identity.questions': 'Security Questions',
      'identity.questionsDesc': 'Set 3 questions only you know the answers to',
      'identity.questionsHint': 'Choose questions with answers that don\'t change over time',
      'identity.questionLabel': 'Question',
      'identity.questionPlaceholder': 'Type your question...',
      'identity.answerPlaceholder': 'Answer...',
      'identity.needQuestions': 'All 3 questions required',
      'identity.questionsSaved': 'Security questions saved!',
      'identity.location': 'Trusted Location',
      'identity.locationDesc': 'Register locations for recovery (up to 3)',
      'identity.locationHint': 'Go to the actual location (home, office) and register.\nOnly stores hash — never your exact coordinates.',
      'identity.locationLabel': 'Location name (e.g. Home, Office)',
      'identity.needLabel': 'Please enter a location name',
      'identity.locationSaved': 'Location registered!',
      'identity.registerHere': 'Register Current Location',
      'identity.recoveryPin': 'Recovery PIN',
      'identity.recoveryPinDesc': 'Backup 6-8 digit PIN (replaces GPS)',
      'identity.recoveryPinHint': 'Use when GPS is unavailable or at a different location',
      'identity.confirmPin': 'Confirm PIN',
      'identity.pinTooShort': 'PIN must be at least 6 digits',
      'identity.pinMismatch': 'PINs do not match',
      'identity.pinSaved': 'Recovery PIN saved!',
      'identity.save': 'Save',
      'identity.testRecovery': 'Test Recovery',
      'identity.testRecoveryDesc': 'Verify you can actually recover your wallet.\nChecks questions + GPS location.',
      'identity.startTest': 'Start Test',
      'identity.verify': 'Verify Identity',
      'identity.recoveryPinOptional': 'Recovery PIN (if GPS unavailable)',
      'identity.testSuccess': 'Passed! You can recover your wallet.',
      'identity.testFailed': 'Failed. Check your answers and location.',

      // Wallet Management
      'wallets.title': 'Wallets',
      'wallets.active': 'Active',
      'wallets.switch': 'Switch',
      'wallets.rename': 'Rename',
      'wallets.delete': 'Delete',
      'wallets.newName': 'New name',
      'wallets.cancel': 'Cancel',
      'wallets.save': 'Save',
      'wallets.created': 'New wallet created!',
      'wallets.deleteConfirm': 'Delete wallet?',
      'wallets.deleteMsg': 'This wallet will be permanently removed. Please backup first.',
    },
  };
}
