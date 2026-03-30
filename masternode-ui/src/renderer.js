/**
 * TPIX Master Node — Renderer (Vue 3 + i18n)
 * Bilingual Thai/English, glass-morphism dark theme
 * Developed by Xman Studio
 */

const { createApp, ref, reactive, computed, onMounted, onUnmounted, watch, nextTick } = Vue;

// ─── Translations ───────────────────────────────────────────

const LANG = {
    en: {
        switchLang: 'Switch to Thai',
        tabs: {
            dashboard: 'Dashboard',
            setup: 'Run a Node',
            wallet: 'Wallet',
            network: 'Network',
            explorer: 'Explorer',
            masternodes: 'Masternodes',
            links: 'Links',
            logs: 'Logs',
            settings: 'Settings',
            about: 'About',
        },
        dash: {
            nodeStatus: 'Node Status',
            blockHeight: 'Block Height',
            blockAge: 'Block Age',
            validators: 'Validators',
            peers: 'Peers',
            uptime: 'Uptime',
            chainHealthy: 'Chain is Healthy',
            chainHealthyDesc: 'Blocks are being produced every 2 seconds.',
            chainStopped: 'Chain Stopped!',
            chainStoppedDesc: 'Block production has stopped. Validators may be offline. More master nodes needed!',
            startNode: 'Start Node',
            stopNode: 'Stop Node',
            refresh: 'Refresh',
            memory: 'Memory',
            blockProduction: 'Block Production',
            live: 'LIVE',
        },
        setup: {
            steps: ['Choose Tier', 'Wallet', 'Configure & Run'],
            chooseTierDesc: 'Choose a node tier based on how much TPIX you want to stake. Higher tiers earn more rewards and help secure the network.',
            estimatedReward: 'Estimated Rewards',
            month: 'month',
            year: 'year',
            canAfford: 'Sufficient balance',
            cantAfford: 'Insufficient balance',
            next: 'Next',
            back: 'Back',
            walletDesc: 'Connect or create a wallet to register your node on TPIX Chain.',
            configDesc: 'Review your configuration and start running your master node!',
            tier: 'Tier',
            stake: 'Stake Required',
            reward: 'APY',
            launchNode: 'Launch Node',
            rewardInfo: 'Reward Distribution (3 Years)',
            totalEmission: 'Total Emission',
            total: 'Total',
            rewardNote: 'Rewards are distributed proportionally based on your stake and uptime. Validators earn the highest share. Pool: 1.4 Billion TPIX over 3 years (ending 2028).',
        },
        wallet: {
            setupTitle: 'Set Up Your Wallet',
            setupDesc: 'Create a new wallet or import an existing one to start running your master node.',
            create: 'Create New Wallet',
            import: 'Import Private Key',
            importDesc: 'Paste your private key (0x + 64 hex characters)',
            saveKeyTitle: 'Save Your Private Key!',
            saveKeyDesc: 'This is shown only once. Back it up securely. Anyone with this key controls your funds.',
            show: 'Show',
            hide: 'Hide',
            copy: 'Copy',
            exportKey: 'Export Key',
            clickCopy: 'click to copy',
            neverShare: 'Never share your private key with anyone!',
        },
        net: {
            production: 'Block Production',
            active: 'Active',
            stopped: 'Stopped',
            validatorsTitle: 'Active Validators',
            noValidators: 'No validator data available',
            ibftRequires: 'IBFT2 requires',
            ibftOnline: 'validators online for consensus.',
            faultTolerance: 'Fault tolerance',
            nodesFail: 'nodes can fail.',
            whyRunTitle: 'Why Run a Master Node?',
            whyRunReasons: [
                'Earn TPIX rewards from 1.4 Billion reward pool',
                'Help secure and decentralize the TPIX Chain',
                'More nodes = more stable network (fewer outages)',
                'Support the TPIX ecosystem and community',
                'Earn 4-20% APY depending on node tier',
            ],
        },
        logs: { empty: 'No logs yet. Start the node to see activity.' },
        settings: {
            nodeName: 'Node Name',
            tier: 'Node Tier',
            rpcUrl: 'RPC URL',
            p2pPort: 'P2P Port',
            maxPeers: 'Max Peers',
            save: 'Save Settings',
            openDir: 'Open Data Directory',
        },
        about: {
            description: 'About',
            descText: 'TPIX Master Node is a desktop application for running validator nodes on the TPIX Chain. It helps secure and decentralize the network while earning TPIX rewards.',
            developer: 'Developer',
            studio: 'Studio',
            license: 'License',
            version: 'Version',
            download: 'Download',
            downloadDesc: 'Get the latest version of TPIX Master Node and other TPIX apps.',
            downloadBtn: 'Go to TPIX Downloads',
            updateTitle: 'Auto Update',
            currentVersion: 'Current Version',
            checking: 'Checking for updates...',
            newVersion: 'New version available:',
            downloadUpdate: 'Download Update',
            readyInstall: 'Update Ready!',
            readyInstallDesc: 'The update has been downloaded. Restart to apply.',
            installRestart: 'Install & Restart',
            upToDate: 'You are up to date',
            checkNow: 'Check Now',
        },
        multiWallet: {
            walletSlot: 'Wallet',
            ofMax: 'of 128',
            addWallet: 'Add Wallet',
            rename: 'Rename',
            deleteWallet: 'Delete',
            switchWallet: 'Switch Wallet',
            walletList: 'Wallet List',
            active: 'Active',
            confirmDelete: 'Are you sure you want to delete this wallet? Enter password to confirm.',
            noWallets: 'No wallets yet. Create or import one.',
            walletName: 'Wallet Name',
        },
        send: {
            title: 'Send TPIX',
            recipient: 'Recipient Address',
            amount: 'Amount',
            password: 'Password',
            estimatedFee: 'Estimated Fee',
            confirmSend: 'Confirm Send',
            sending: 'Sending...',
            txSent: 'Transaction Sent!',
            txHash: 'Transaction Hash',
            invalidAddress: 'Invalid address',
            invalidAmount: 'Invalid amount',
            passwordRequired: 'Password is required',
            close: 'Close',
        },
        receive: {
            title: 'Receive TPIX',
            scanQr: 'Scan QR code to send TPIX to this address',
            copyAddress: 'Copy Address',
            copied: 'Copied!',
        },
        history: {
            title: 'Transaction History',
            sent: 'Sent',
            received: 'Received',
            pending: 'Pending',
            confirmed: 'Confirmed',
            failed: 'Failed',
            noTx: 'No transactions yet',
            loadMore: 'Load More',
            from: 'From',
            to: 'To',
            amount: 'Amount',
            fee: 'Fee',
            date: 'Date',
            hash: 'Tx Hash',
            page: 'Page',
        },
        stakingRewards: {
            title: 'Staking Rewards',
            totalRewards: 'Total Rewards',
            checkRewards: 'Check Rewards',
            noRewards: 'No rewards yet',
            epoch: 'Epoch',
            amount: 'Amount',
            date: 'Date',
        },
        identity: {
            title: 'Living Identity',
            securityLevel: 'Security Level',
            setupQuestions: 'Set Security Questions',
            setupRecoveryKey: 'Set Recovery Key',
            questionsSet: 'Security Questions Set',
            recoveryKeySet: 'Recovery Key Set',
            question: 'Question',
            answer: 'Answer',
            questionPlaceholder: 'Enter your personal question...',
            answerPlaceholder: 'Enter your answer...',
            saveQuestions: 'Save Security Questions',
            recoveryKeyLabel: 'Recovery PIN (6-8 digits)',
            recoveryHint: 'Hint (optional)',
            saveRecoveryKey: 'Save Recovery Key',
            // GPS
            gpsTitle: 'GPS Location Proof',
            gpsDesc: 'Register trusted locations. Only hashed grid stored — never your exact coordinates.',
            gpsRegister: 'Register Current Location',
            gpsLabel: 'Location name',
            gpsLabelPlaceholder: 'e.g. Home, Office...',
            gpsRegistered: 'locations registered',
            gpsNone: 'No locations registered',
            gpsRemove: 'Remove',
            gpsRegistering: 'Getting GPS...',
            gpsPrivacy: 'Privacy: coordinates are rounded to ~111m grid then SHA-256 hashed. No one can see your exact location.',
            gpsNoSupport: 'GPS not available on this device. Use the mobile wallet for location registration.',
            gpsVerified: 'Location verified',
            gpsNotVerified: 'Location not matched',
            mnemonicTitle: 'Recovery Seed Phrase',
            mnemonicDesc: 'Write down these 12 words in order. This is the ONLY way to recover ALL your HD wallets.',
            mnemonicWarning: 'Never share your seed phrase! Anyone with these words can steal all your wallets.',
            showMnemonic: 'Show Seed Phrase',
            hideMnemonic: 'Hide Seed Phrase',
            recoverWallet: 'Recover from Seed',
            recoverDesc: 'Enter your 12-word seed phrase to recover all HD wallets',
            recoverBtn: 'Recover Wallets',
            recovering: 'Recovering...',
            recovered: 'wallets recovered!',
            none: 'None',
            basic: 'Basic',
            standard: 'Standard',
            strong: 'Strong',
            viewSeed: 'View Seed Phrase',
            levels: {
                0: 'No identity protection',
                1: 'Basic protection',
                2: 'Standard protection',
                3: 'Strong protection',
            },
        },
        qrScanner: {
            scanTitle: 'Scan QR Code',
            scanning: 'Point camera at QR code...',
            noCamera: 'Camera access denied or not available',
            scanBtn: 'Scan QR',
            stopScan: 'Stop',
        },
        explorer: {
            title: 'Block Explorer',
            latestBlocks: 'Latest Blocks',
            blockDetail: 'Block Detail',
            txDetail: 'Transaction Detail',
            blockNumber: 'Block',
            timestamp: 'Time',
            txCount: 'Transactions',
            validator: 'Validator',
            gasUsed: 'Gas Used',
            hash: 'Hash',
            parentHash: 'Parent Hash',
            from: 'From',
            to: 'To',
            value: 'Value',
            status: 'Status',
            success: 'Success',
            failed: 'Failed',
            loading: 'Loading...',
            noBlocks: 'No blocks found',
            searchPlaceholder: 'Block number or Tx hash...',
            search: 'Search',
            back: 'Back',
            viewTx: 'View Transaction',
        },
        staking: {
            stakingActive: 'Staking Active',
            stakingStopped: 'Not Staking',
            tier: 'Tier',
            stakeAmount: 'Staked',
            rewardWallet: 'Reward Wallet',
            totalRewards: 'Total Rewards Earned',
            uptime: 'Total Uptime',
            registeredAt: 'Registered',
            insufficientBalance: 'Insufficient balance. Required:',
            validating: 'Checking balance...',
            balanceOk: 'Balance sufficient',
            stakingRequired: 'You must stake TPIX to run a node',
            myNode: 'My Node',
        },
        masternodeMap: {
            title: 'Masternode Network',
            totalNodes: 'Total Nodes',
            countries: 'Countries',
            types: 'Node Types',
            light: 'Light',
            sentinel: 'Sentinel',
            guardian: 'Guardian',
            validator: 'Validator',
            location: 'Location',
            mapTitle: 'Global Network Map',
            zoomAll: 'World View',
            nodeReport: 'Node Report',
            allTypes: 'All Types',
            allCountries: 'All Countries',
            wallet: 'Wallet',
            status: 'Status',
            rewards: 'Rewards',
            checkRewards: 'Check Rewards',
            rewardDetail: 'Reward Detail',
            totalRewardsLabel: 'Total Rewards',
            blocksProduced: 'Blocks Produced',
            rewardHistory: 'Reward History',
            liveNode: 'LIVE',
            demoNode: 'DEMO',
        },
        status: { stopped: 'Stopped', starting: 'Starting...', running: 'Running', syncing: 'Syncing', error: 'Error' },
    },
    th: {
        switchLang: 'Switch to English',
        tabs: {
            dashboard: 'แดชบอร์ด',
            setup: 'ตั้งค่าโหนด',
            wallet: 'กระเป๋าเงิน',
            network: 'เครือข่าย',
            explorer: 'สำรวจบล็อก',
            masternodes: 'มาสเตอร์โหนด',
            links: 'ลิงก์',
            logs: 'บันทึก',
            settings: 'ตั้งค่า',
            about: 'เกี่ยวกับ',
        },
        dash: {
            nodeStatus: 'สถานะโหนด',
            blockHeight: 'ความสูงบล็อก',
            blockAge: 'อายุบล็อก',
            validators: 'ผู้ตรวจสอบ',
            peers: 'เพียร์',
            uptime: 'เวลาออนไลน์',
            chainHealthy: 'เชนทำงานปกติ',
            chainHealthyDesc: 'กำลังผลิตบล็อกทุก 2 วินาที',
            chainStopped: 'เชนหยุดทำงาน!',
            chainStoppedDesc: 'การผลิตบล็อกหยุดแล้ว ผู้ตรวจสอบอาจออฟไลน์ ต้องการ master node เพิ่ม!',
            startNode: 'เริ่มโหนด',
            stopNode: 'หยุดโหนด',
            refresh: 'รีเฟรช',
            memory: 'หน่วยความจำ',
            blockProduction: 'การผลิตบล็อก',
            live: 'สด',
        },
        setup: {
            steps: ['เลือกระดับ', 'กระเป๋าเงิน', 'ตั้งค่า & เริ่มรัน'],
            chooseTierDesc: 'เลือกระดับโหนดตามจำนวน TPIX ที่ต้องการ stake ระดับสูงกว่าจะได้รับรางวัลมากกว่าและช่วยเพิ่มความปลอดภัยของเครือข่าย',
            estimatedReward: 'รางวัลโดยประมาณ',
            month: 'เดือน',
            year: 'ปี',
            canAfford: 'ยอดเพียงพอ',
            cantAfford: 'ยอดไม่เพียงพอ',
            next: 'ถัดไป',
            back: 'ย้อนกลับ',
            walletDesc: 'เชื่อมต่อหรือสร้างกระเป๋าเงินเพื่อลงทะเบียนโหนดบน TPIX Chain',
            configDesc: 'ตรวจสอบการตั้งค่าและเริ่มรัน master node ของคุณ!',
            tier: 'ระดับ',
            stake: 'ต้อง Stake',
            reward: 'ผลตอบแทน',
            launchNode: 'เริ่มรันโหนด',
            rewardInfo: 'การแจกรางวัล (3 ปี)',
            totalEmission: 'จำนวนที่ปล่อย',
            total: 'รวม',
            rewardNote: 'รางวัลจะแจกตามสัดส่วนของ stake และ uptime ของคุณ Validator ได้ส่วนแบ่งมากที่สุด พูลรวม: 1,400 ล้าน TPIX ตลอด 3 ปี (สิ้นสุด 2028)',
        },
        wallet: {
            setupTitle: 'ตั้งค่ากระเป๋าเงิน',
            setupDesc: 'สร้างกระเป๋าใหม่หรือนำเข้ากระเป๋าที่มีอยู่เพื่อเริ่มรัน master node',
            create: 'สร้างกระเป๋าใหม่',
            import: 'นำเข้า Private Key',
            importDesc: 'วาง private key ของคุณ (0x + 64 ตัวอักษร hex)',
            saveKeyTitle: 'บันทึก Private Key ของคุณ!',
            saveKeyDesc: 'จะแสดงเพียงครั้งเดียว สำรองไว้อย่างปลอดภัย ใครก็ตามที่มี key นี้จะควบคุมเงินของคุณได้',
            show: 'แสดง',
            hide: 'ซ่อน',
            copy: 'คัดลอก',
            exportKey: 'ส่งออก Key',
            clickCopy: 'คลิกเพื่อคัดลอก',
            neverShare: 'อย่าแชร์ private key ของคุณกับใครเด็ดขาด!',
        },
        net: {
            production: 'การผลิตบล็อก',
            active: 'ทำงาน',
            stopped: 'หยุด',
            validatorsTitle: 'ผู้ตรวจสอบที่ใช้งาน',
            noValidators: 'ไม่มีข้อมูลผู้ตรวจสอบ',
            ibftRequires: 'IBFT2 ต้องการ',
            ibftOnline: 'ผู้ตรวจสอบออนไลน์เพื่อ consensus',
            faultTolerance: 'ทนทานต่อความผิดพลาด',
            nodesFail: 'โหนดที่ล่มได้',
            whyRunTitle: 'ทำไมต้องรัน Master Node?',
            whyRunReasons: [
                'รับรางวัล TPIX จากพูล 1,400 ล้าน TPIX',
                'ช่วยรักษาความปลอดภัยและกระจายอำนาจ TPIX Chain',
                'ยิ่งมี node มาก = เครือข่ายยิ่งเสถียร (ล่มน้อยลง)',
                'สนับสนุนระบบนิเวศและชุมชน TPIX',
                'รับผลตอบแทน 4-20% APY ตามระดับโหนด',
            ],
        },
        logs: { empty: 'ยังไม่มีบันทึก เริ่มโหนดเพื่อดูกิจกรรม' },
        settings: {
            nodeName: 'ชื่อโหนด',
            tier: 'ระดับโหนด',
            rpcUrl: 'RPC URL',
            p2pPort: 'พอร์ต P2P',
            maxPeers: 'เพียร์สูงสุด',
            save: 'บันทึกการตั้งค่า',
            openDir: 'เปิดโฟลเดอร์ข้อมูล',
        },
        about: {
            description: 'เกี่ยวกับ',
            descText: 'TPIX Master Node คือแอปพลิเคชันเดสก์ท็อปสำหรับรัน validator node บน TPIX Chain ช่วยรักษาความปลอดภัยและกระจายอำนาจของเครือข่าย พร้อมรับรางวัล TPIX',
            developer: 'ผู้พัฒนา',
            studio: 'สตูดิโอ',
            license: 'ใบอนุญาต',
            version: 'เวอร์ชัน',
            download: 'ดาวน์โหลด',
            downloadDesc: 'ดาวน์โหลด TPIX Master Node เวอร์ชันล่าสุดและแอปอื่นๆ ของ TPIX',
            downloadBtn: 'ไปหน้าดาวน์โหลด TPIX',
            updateTitle: 'อัปเดตอัตโนมัติ',
            currentVersion: 'เวอร์ชันปัจจุบัน',
            checking: 'กำลังตรวจสอบอัปเดต...',
            newVersion: 'มีเวอร์ชันใหม่:',
            downloadUpdate: 'ดาวน์โหลดอัปเดต',
            readyInstall: 'พร้อมติดตั้ง!',
            readyInstallDesc: 'ดาวน์โหลดอัปเดตเสร็จแล้ว รีสตาร์ทเพื่อติดตั้ง',
            installRestart: 'ติดตั้ง & รีสตาร์ท',
            upToDate: 'เป็นเวอร์ชันล่าสุดแล้ว',
            checkNow: 'ตรวจสอบตอนนี้',
        },
        multiWallet: {
            walletSlot: 'กระเป๋า',
            ofMax: 'จาก 128',
            addWallet: 'เพิ่มกระเป๋า',
            rename: 'เปลี่ยนชื่อ',
            deleteWallet: 'ลบ',
            switchWallet: 'สลับกระเป๋า',
            walletList: 'รายการกระเป๋า',
            active: 'ใช้งานอยู่',
            confirmDelete: 'คุณแน่ใจหรือไม่ว่าต้องการลบกระเป๋านี้? ใส่รหัสผ่านเพื่อยืนยัน',
            noWallets: 'ยังไม่มีกระเป๋า สร้างหรือนำเข้ากระเป๋าใหม่',
            walletName: 'ชื่อกระเป๋า',
        },
        send: {
            title: 'ส่ง TPIX',
            recipient: 'ที่อยู่ผู้รับ',
            amount: 'จำนวน',
            password: 'รหัสผ่าน',
            estimatedFee: 'ค่าธรรมเนียมโดยประมาณ',
            confirmSend: 'ยืนยันการส่ง',
            sending: 'กำลังส่ง...',
            txSent: 'ส่งธุรกรรมสำเร็จ!',
            txHash: 'แฮชธุรกรรม',
            invalidAddress: 'ที่อยู่ไม่ถูกต้อง',
            invalidAmount: 'จำนวนไม่ถูกต้อง',
            passwordRequired: 'กรุณาใส่รหัสผ่าน',
            close: 'ปิด',
        },
        receive: {
            title: 'รับ TPIX',
            scanQr: 'สแกน QR code เพื่อส่ง TPIX มายังที่อยู่นี้',
            copyAddress: 'คัดลอกที่อยู่',
            copied: 'คัดลอกแล้ว!',
        },
        history: {
            title: 'ประวัติธุรกรรม',
            sent: 'ส่ง',
            received: 'รับ',
            pending: 'รอดำเนินการ',
            confirmed: 'ยืนยันแล้ว',
            failed: 'ล้มเหลว',
            noTx: 'ยังไม่มีธุรกรรม',
            loadMore: 'โหลดเพิ่ม',
            from: 'จาก',
            to: 'ถึง',
            amount: 'จำนวน',
            fee: 'ค่าธรรมเนียม',
            date: 'วันที่',
            hash: 'แฮชธุรกรรม',
            page: 'หน้า',
        },
        stakingRewards: {
            title: 'รางวัล Staking',
            totalRewards: 'รางวัลรวม',
            checkRewards: 'ตรวจสอบรางวัล',
            noRewards: 'ยังไม่มีรางวัล',
            epoch: 'Epoch',
            amount: 'จำนวน',
            date: 'วันที่',
        },
        identity: {
            title: 'ตัวตนมีชีวิต',
            securityLevel: 'ระดับความปลอดภัย',
            setupQuestions: 'ตั้งคำถามกันลืม',
            setupRecoveryKey: 'ตั้งรหัสกู้คืน',
            questionsSet: 'ตั้งคำถามกันลืมแล้ว',
            recoveryKeySet: 'ตั้งรหัสกู้คืนแล้ว',
            question: 'คำถาม',
            answer: 'คำตอบ',
            questionPlaceholder: 'ตั้งคำถามส่วนตัวของคุณ...',
            answerPlaceholder: 'ใส่คำตอบ...',
            saveQuestions: 'บันทึกคำถามกันลืม',
            recoveryKeyLabel: 'PIN กู้คืน (6-8 หลัก)',
            recoveryHint: 'คำใบ้ (ไม่บังคับ)',
            saveRecoveryKey: 'บันทึกรหัสกู้คืน',
            // GPS
            gpsTitle: 'พิสูจน์ตำแหน่ง GPS',
            gpsDesc: 'ลงทะเบียนสถานที่ที่ไว้ใจได้ เก็บเฉพาะ hash — ไม่เก็บพิกัดจริงของคุณ',
            gpsRegister: 'ลงทะเบียนตำแหน่งปัจจุบัน',
            gpsLabel: 'ชื่อสถานที่',
            gpsLabelPlaceholder: 'เช่น บ้าน, ที่ทำงาน...',
            gpsRegistered: 'สถานที่ลงทะเบียนแล้ว',
            gpsNone: 'ยังไม่มีสถานที่ลงทะเบียน',
            gpsRemove: 'ลบ',
            gpsRegistering: 'กำลังรับ GPS...',
            gpsPrivacy: 'ความเป็นส่วนตัว: พิกัดถูกปัดเป็นตาราง ~111m แล้ว SHA-256 hash ไม่มีใครเห็นพิกัดจริงของคุณ',
            gpsNoSupport: 'GPS ไม่พร้อมใช้งานบนอุปกรณ์นี้ ใช้กระเป๋ามือถือเพื่อลงทะเบียนตำแหน่ง',
            gpsVerified: 'ยืนยันตำแหน่งสำเร็จ',
            gpsNotVerified: 'ตำแหน่งไม่ตรงกัน',
            mnemonicTitle: 'คำลับกู้คืน (Seed Phrase)',
            mnemonicDesc: 'จดคำ 12 คำนี้ตามลำดับ นี่คือวิธีเดียวในการกู้คืนกระเป๋า HD ทั้งหมด',
            mnemonicWarning: 'ห้ามแชร์ seed phrase! ใครมีคำเหล่านี้สามารถขโมยกระเป๋าทั้งหมดได้',
            showMnemonic: 'แสดง Seed Phrase',
            hideMnemonic: 'ซ่อน Seed Phrase',
            recoverWallet: 'กู้คืนจาก Seed',
            recoverDesc: 'ใส่ seed phrase 12 คำเพื่อกู้คืนกระเป๋า HD ทั้งหมด',
            recoverBtn: 'กู้คืนกระเป๋า',
            recovering: 'กำลังกู้คืน...',
            recovered: 'กระเป๋าที่กู้คืนได้!',
            none: 'ไม่มี',
            basic: 'พื้นฐาน',
            standard: 'มาตรฐาน',
            strong: 'แข็งแกร่ง',
            viewSeed: 'ดู Seed Phrase',
            levels: {
                0: 'ยังไม่มีการป้องกันตัวตน',
                1: 'การป้องกันพื้นฐาน',
                2: 'การป้องกันมาตรฐาน',
                3: 'การป้องกันแข็งแกร่ง',
            },
        },
        qrScanner: {
            scanTitle: 'สแกน QR Code',
            scanning: 'ชี้กล้องไปที่ QR code...',
            noCamera: 'ไม่สามารถเข้าถึงกล้องได้',
            scanBtn: 'สแกน QR',
            stopScan: 'หยุด',
        },
        explorer: {
            title: 'สำรวจบล็อก',
            latestBlocks: 'บล็อกล่าสุด',
            blockDetail: 'รายละเอียดบล็อก',
            txDetail: 'รายละเอียดธุรกรรม',
            blockNumber: 'บล็อก',
            timestamp: 'เวลา',
            txCount: 'ธุรกรรม',
            validator: 'ผู้ตรวจสอบ',
            gasUsed: 'Gas ที่ใช้',
            hash: 'แฮช',
            parentHash: 'แฮชพ่อ',
            from: 'จาก',
            to: 'ถึง',
            value: 'จำนวน',
            status: 'สถานะ',
            success: 'สำเร็จ',
            failed: 'ล้มเหลว',
            loading: 'กำลังโหลด...',
            noBlocks: 'ไม่พบบล็อก',
            searchPlaceholder: 'เลขบล็อกหรือ Tx hash...',
            search: 'ค้นหา',
            back: 'กลับ',
            viewTx: 'ดูธุรกรรม',
        },
        staking: {
            stakingActive: 'กำลัง Stake',
            stakingStopped: 'ยังไม่ได้ Stake',
            tier: 'ระดับ',
            stakeAmount: 'จำนวนที่ Stake',
            rewardWallet: 'กระเป๋ารับรางวัล',
            totalRewards: 'รางวัลที่ได้รับทั้งหมด',
            uptime: 'เวลาออนไลน์รวม',
            registeredAt: 'ลงทะเบียนเมื่อ',
            insufficientBalance: 'ยอดเงินไม่เพียงพอ ต้องการ:',
            validating: 'กำลังตรวจสอบยอดเงิน...',
            balanceOk: 'ยอดเงินเพียงพอ',
            stakingRequired: 'ต้อง Stake TPIX เพื่อรันโหนด',
            myNode: 'โหนดของฉัน',
        },
        masternodeMap: {
            title: 'เครือข่ายมาสเตอร์โหนด',
            totalNodes: 'โหนดทั้งหมด',
            countries: 'ประเทศ',
            types: 'ประเภทโหนด',
            light: 'ไลท์',
            sentinel: 'เซนติเนล',
            guardian: 'การ์เดียน',
            validator: 'วาลิเดเตอร์',
            location: 'ตำแหน่ง',
            mapTitle: 'แผนที่เครือข่ายโลก',
            zoomAll: 'มุมมองโลก',
            nodeReport: 'รายงานโหนด',
            allTypes: 'ทุกประเภท',
            allCountries: 'ทุกประเทศ',
            wallet: 'กระเป๋า',
            status: 'สถานะ',
            rewards: 'รางวัล',
            checkRewards: 'ตรวจรางวัล',
            rewardDetail: 'รายละเอียดรางวัล',
            totalRewardsLabel: 'รางวัลทั้งหมด',
            blocksProduced: 'บล็อกที่ผลิต',
            rewardHistory: 'ประวัติรางวัล',
            liveNode: 'สด',
            demoNode: 'เดโม',
        },
        status: { stopped: 'หยุด', starting: 'กำลังเริ่ม...', running: 'ทำงาน', syncing: 'กำลังซิงค์', error: 'ข้อผิดพลาด' },
    },
};

// ─── App ────────────────────────────────────────────────────

const app = createApp({
    setup() {
        const appVersion = ref('...');
        const lang = ref(localStorage.getItem('tpix-lang') || 'th');
        const i18n = computed(() => LANG[lang.value]);
        const activeTab = ref('dashboard');
        const setupStep = ref(0);

        const tabs = [
            { id: 'dashboard', icon: '&#9661;' },
            { id: 'setup',     icon: '&#9881;' },
            { id: 'wallet',    icon: '&#128176;' },
            { id: 'network',   icon: '&#127760;' },
            { id: 'explorer',  icon: '&#128270;' },
            { id: 'masternodes', icon: '&#127758;' },
            { id: 'links',     icon: '&#128279;' },
            { id: 'logs',      icon: '&#128196;' },
            { id: 'settings',  icon: '&#9881;' },
            { id: 'about',     icon: '&#8505;' },
        ];

        function toggleLang() {
            lang.value = lang.value === 'th' ? 'en' : 'th';
            localStorage.setItem('tpix-lang', lang.value);
        }

        // ─── Tiers ────────────────────────────────
        const tiers = computed(() => [
            {
                id: 'light', name: 'Light Node', stake: 10000,
                apy: '4-6% APY',
                monthlyReward: Math.round(10000 * 0.05 / 12),
                yearlyReward: Math.round(10000 * 0.05),
                features: lang.value === 'th'
                    ? ['Stake ต่ำสุด', 'ล็อค 7 วัน', 'ไม่มีค่าปรับ', 'ไม่จำกัดจำนวน']
                    : ['Lowest stake', '7-day lock', 'No slashing', 'Unlimited nodes'],
            },
            {
                id: 'sentinel', name: 'Sentinel Node', stake: 100000,
                apy: '7-9% APY',
                monthlyReward: Math.round(100000 * 0.08 / 12),
                yearlyReward: Math.round(100000 * 0.08),
                features: lang.value === 'th'
                    ? ['ผลตอบแทนปานกลาง', 'ล็อค 30 วัน', 'ค่าปรับ 5%', 'สูงสุด 500 โหนด']
                    : ['Medium rewards', '30-day lock', '5% slashing', 'Max 500 nodes'],
            },
            {
                id: 'guardian', name: 'Guardian Node', stake: 1000000,
                apy: '10-12% APY',
                monthlyReward: Math.round(1000000 * 0.11 / 12),
                yearlyReward: Math.round(1000000 * 0.11),
                features: lang.value === 'th'
                    ? ['ผลตอบแทนสูง', 'ล็อค 90 วัน', 'ค่าปรับ 10%', 'สูงสุด 100 โหนด']
                    : ['High rewards', '90-day lock', '10% slashing', 'Max 100 nodes'],
            },
            {
                id: 'validator', name: 'Validator Node', stake: 10000000,
                apy: '15-20% APY',
                monthlyReward: Math.round(10000000 * 0.175 / 12),
                yearlyReward: Math.round(10000000 * 0.175),
                features: lang.value === 'th'
                    ? ['ผลตอบแทนสูงสุด', 'ล็อค 180 วัน', 'ค่าปรับ 15%', 'สูงสุด 21 โหนด', 'IBFT2 Block Sealer', 'สิทธิ์โหวต Governance', 'ต้อง KYC บริษัท']
                    : ['Highest rewards', '180-day lock', '15% slashing', 'Max 21 nodes', 'IBFT2 Block Sealer', 'Governance voting', 'Company KYC required'],
            },
        ]);

        const selectedTier = computed(() => tiers.value.find(t => t.id === config.tier));

        // ─── Links ────────────────────────────────
        const linkGroups = computed(() => [
            {
                title: lang.value === 'th' ? 'เว็บไซต์หลัก' : 'Main Websites',
                links: [
                    { icon: '🌐', name: 'TPIX Trade', desc: lang.value === 'th' ? 'แพลตฟอร์มเทรด DEX' : 'DEX Trading Platform', url: 'https://tpix.online' },
                    { icon: '🔍', name: 'Block Explorer', desc: lang.value === 'th' ? 'ดูธุรกรรมบน TPIX Chain' : 'View TPIX Chain transactions', url: 'https://explorer.tpix.online' },
                    { icon: '⬇️', name: 'TPIX Download', desc: lang.value === 'th' ? 'ดาวน์โหลดแอปทั้งหมด' : 'Download all TPIX apps', url: 'https://tpix.online/download' },
                    { icon: '💻', name: 'Xman Studio', desc: lang.value === 'th' ? 'ผู้พัฒนา' : 'Developer', url: 'https://xman4289.com' },
                ],
            },
            {
                title: lang.value === 'th' ? 'เอกสาร' : 'Documentation',
                links: [
                    { icon: '📃', name: 'Whitepaper', desc: lang.value === 'th' ? 'เอกสาร Whitepaper ของ TPIX' : 'TPIX Whitepaper document', url: 'https://tpix.online/whitepaper' },
                    { icon: '📚', name: 'API Docs', desc: lang.value === 'th' ? 'เอกสาร API สำหรับนักพัฒนา' : 'API documentation for developers', url: 'https://tpix.online/api-docs' },
                    { icon: '💻', name: 'GitHub', desc: lang.value === 'th' ? 'ซอร์สโค้ดโอเพนซอร์ส' : 'Open source code', url: 'https://github.com/xjanova/TPIX-Coin'},
                ],
            },
            {
                title: lang.value === 'th' ? 'โซเชียล & ชุมชน' : 'Social & Community',
                links: [
                    { icon: '💬', name: 'Telegram', desc: 'TPIX Community', url: 'https://t.me/tpixtrade' },
                    { icon: '🐦', name: 'Twitter / X', desc: '@TPIXTrade', url: 'https://x.com/TPIXTrade' },
                    { icon: '🎬', name: 'YouTube', desc: 'TPIX Channel', url: 'https://youtube.com/@tpixtrade' },
                    { icon: '💬', name: 'Discord', desc: 'TPIX Discord', url: 'https://discord.gg/tpix' },
                    { icon: '📷', name: 'Facebook', desc: 'TPIX Trade', url: 'https://facebook.com/tpixtrade' },
                ],
            },
            {
                title: lang.value === 'th' ? 'เครื่องมือ Blockchain' : 'Blockchain Tools',
                links: [
                    { icon: '⛓️', name: 'TPIX RPC', desc: 'https://rpc.tpix.online', url: 'https://rpc.tpix.online' },
                    { icon: '💰', name: 'Token Factory', desc: lang.value === 'th' ? 'สร้างเหรียญบน TPIX Chain' : 'Create tokens on TPIX Chain', url: 'https://tpix.online/token-factory' },
                    { icon: '🌱', name: 'Carbon Credits', desc: lang.value === 'th' ? 'ระบบ Carbon Credit' : 'Carbon Credit system', url: 'https://tpix.online/carbon-credit' },
                    { icon: '🔗', name: 'Bridge', desc: 'BSC ↔ TPIX Chain', url: 'https://tpix.online/bridge' },
                ],
            },
        ]);

        // ─── Node State ───────────────────────────
        const nodeStatus = ref('stopped');
        const nodeUptime = ref(0);
        const network = ref({
            blockNumber: 0, blockAge: -1, isProducing: false,
            peerCount: 0, chainId: 4289, validators: [], validatorCount: 0,
        });
        const metrics = ref(null);
        const logs = ref([]);

        // ─── Block Animation State ───────────────
        const liveBlocks = ref([]);
        let blockAnimInterval = null;
        let blockAnimId = 0;
        let lastAnimBlockNum = 0;

        function pushLiveBlock() {
            const bn = network.value.blockNumber;
            if (bn <= 0) return;
            // Sync with real block number, then increment locally between RPC refreshes
            if (lastAnimBlockNum === 0 || bn > lastAnimBlockNum) {
                lastAnimBlockNum = bn;
            } else {
                lastAnimBlockNum++;
            }
            const now = Date.now();
            blockAnimId++;
            liveBlocks.value.push({
                id: blockAnimId,
                number: lastAnimBlockNum,
                time: now,
                txCount: Math.floor(Math.random() * 5),
                hash: '0x' + Array.from({ length: 8 }, () => Math.floor(Math.random() * 16).toString(16)).join(''),
            });
            // Keep only last 20 blocks in the animation strip
            if (liveBlocks.value.length > 20) liveBlocks.value.shift();
        }

        function startBlockAnim() {
            if (blockAnimInterval) return;
            pushLiveBlock();
            blockAnimInterval = setInterval(pushLiveBlock, 2000);
        }

        function stopBlockAnim() {
            if (blockAnimInterval) { clearInterval(blockAnimInterval); blockAnimInterval = null; }
        }
        const config = reactive({
            nodeName: '', tier: 'light', walletAddress: '', rewardWallet: '',
            rpcUrl: 'https://rpc.tpix.online', p2pPort: 30303, maxPeers: 50,
        });

        // ─── Wallet State ─────────────────────────
        const walletAddress = ref(null);
        const walletBalance = ref('0');
        const walletLoading = ref(false);
        const newWalletData = ref(null);
        const showPrivateKey = ref(false);
        const showImportModal = ref(false);
        const importKeyInput = ref('');
        const importError = ref('');
        const exportedKey = ref(null);

        // ─── Password Prompt Modal ─────────────────
        const showPasswordModal = ref(false);
        const passwordModalTitle = ref('');
        const passwordModalInput = ref('');
        const passwordModalError = ref('');
        let passwordModalResolve = null;

        function askPassword(title) {
            return new Promise((resolve) => {
                passwordModalTitle.value = title || (lang.value === 'th' ? 'ใส่รหัสผ่าน' : 'Enter password');
                passwordModalInput.value = '';
                passwordModalError.value = '';
                passwordModalResolve = resolve;
                showPasswordModal.value = true;
                nextTick(() => {
                    const el = document.querySelector('.modal-overlay input[type="password"]');
                    if (el) el.focus();
                });
            });
        }
        function confirmPasswordModal() {
            showPasswordModal.value = false;
            if (passwordModalResolve) passwordModalResolve(passwordModalInput.value);
            passwordModalResolve = null;
            passwordModalInput.value = '';
        }
        function cancelPasswordModal() {
            showPasswordModal.value = false;
            if (passwordModalResolve) passwordModalResolve(null);
            passwordModalResolve = null;
            passwordModalInput.value = '';
        }

        // ─── Multi-Wallet State ──────────────────
        const wallets = ref([]);
        const walletCount = ref(0);
        const activeWallet = ref(null);
        const walletBalances = ref({});
        const showSendModal = ref(false);
        const showReceiveModal = ref(false);
        const showWalletList = ref(false);
        const sendForm = reactive({ toAddress: '', amount: '', password: '', sending: false, error: '', txHash: '' });
        const gasEstimate = ref(null);
        const qrCodeData = ref(null);
        const transactions = ref([]);
        const txPage = ref(1);
        const txTotal = ref(0);
        const rewards = ref({ rewards: [], total: 0 });
        const walletNameEdit = ref(null);
        const walletNameInput = ref('');

        // ─── QR Scanner State ──────────────────
        const showQRScanner = ref(false);
        const qrScanError = ref('');
        let qrVideoStream = null;
        let qrScanInterval = null;

        // ─── Identity State ────────────────────
        const identityStatus = ref(null);
        const showIdentitySetup = ref(false);
        const showSecurityQuestions = ref(false);
        const showRecoveryKeySetup = ref(false);
        const showMnemonicModal = ref(false);
        const showRecoverModal = ref(false);
        const showMnemonic = ref(false);
        const mnemonicWords = ref('');
        const recoverMnemonicInput = ref('');
        const recoverPassword = ref('');
        const recoverResult = ref(null);
        const recoverLoading = ref(false);
        const securityQuestionsForm = ref([
            { question: '', answer: '' },
            { question: '', answer: '' },
            { question: '', answer: '' },
            { question: '', answer: '' },
            { question: '', answer: '' },
        ]);
        const recoveryKeyForm = reactive({ pin: '', hint: '' });
        const identitySaving = ref(false);
        // GPS state
        const showGPSSetup = ref(false);
        const gpsLabel = ref('');
        const gpsRegistering = ref(false);
        const gpsError = ref('');

        // ─── Explorer State ──────────────────────
        const explorerBlocks = ref([]);
        const explorerBlock = ref(null);
        const explorerTx = ref(null);
        const explorerLoading = ref(false);
        const explorerSearch = ref('');
        const explorerView = ref('list'); // 'list', 'block', 'tx'

        // ─── Masternode Map State ────────────────
        const masternodeData = ref([]);
        const masternodeStats = ref({ total: 0, countries: 0, byType: { light: 0, sentinel: 0, guardian: 0, validator: 0 } });
        const mnFilterType = ref('all');
        const mnFilterCountry = ref('all');
        const selectedNodeReward = ref(null);
        let leafletMap = null;
        let leafletMarkers = [];

        const masternodeCountries = computed(() => {
            const map = {};
            masternodeData.value.forEach(n => {
                if (!map[n.country]) map[n.country] = { code: n.country, name: n.countryName, flag: n.flag };
            });
            return Object.values(map).sort((a, b) => a.name.localeCompare(b.name));
        });

        const filteredMasternodes = computed(() => {
            return masternodeData.value.filter(n => {
                if (mnFilterType.value !== 'all' && n.type !== mnFilterType.value) return false;
                if (mnFilterCountry.value !== 'all' && n.country !== mnFilterCountry.value) return false;
                return true;
            });
        });

        // ─── Staking State ───────────────────────────
        const stakingInfo = ref(null);      // Active staking record
        const stakingValidation = ref(null); // Balance validation result
        const stakingLoading = ref(false);
        const stakingError = ref('');

        // ─── Update State ─────────────────────────
        const updateStatus = ref({
            checking: false, updateAvailable: false, updateDownloaded: false,
            updateInfo: null, downloadProgress: null, error: null,
        });

        const statusLabel = computed(() => i18n.value.status[nodeStatus.value] || nodeStatus.value);

        // ─── Intervals ────────────────────────────
        let networkInterval, metricsInterval, uptimeInterval;

        // ─── Actions ──────────────────────────────
        async function startNode() {
            if (nodeStatus.value === 'starting') return;
            const cfg = { ...config };
            if (walletAddress.value) cfg.walletAddress = walletAddress.value;
            nodeStatus.value = 'starting';
            const result = await window.tpix.node.start(cfg);
            if (!result.success) {
                nodeStatus.value = 'error';
                logs.value.push({ time: new Date().toISOString(), level: 'error', message: result.error });
            }
        }
        let stoppingNode = false;
        async function stopNode() {
            if (stoppingNode) return;
            stoppingNode = true;
            try {
                await window.tpix.node.stop();
                await stopStaking();
                nodeStatus.value = 'stopped';
                nodeUptime.value = 0;
            } finally { stoppingNode = false; }
        }
        async function launchNode() {
            stakingError.value = '';

            // Register staking first
            const registered = await registerStaking();
            if (!registered) return;

            activeTab.value = 'dashboard';
            startNode();
        }
        async function refreshNetwork() {
            try {
                const stats = await window.tpix.rpc.getNetworkStats();
                if (stats) network.value = stats;
            } catch {}
        }
        async function refreshMetrics() {
            try { const m = await window.tpix.system.getMetrics(); if (m) metrics.value = m; } catch {}
        }

        // ─── Wallet ───────────────────────────────
        async function loadWallet() {
            try {
                const exists = await window.tpix.wallet.exists();
                if (exists) {
                    walletAddress.value = await window.tpix.wallet.getAddress();
                    await refreshBalance();
                }
                await loadWallets();
                await loadIdentityStatus();
            } catch {}
        }
        async function createWallet() {
            const password = await askPassword(lang.value === 'th' ? 'ใส่รหัสผ่านสำหรับกระเป๋า' : 'Set a password for your wallet');
            if (password === null) return;
            walletLoading.value = true;
            try {
                const result = await window.tpix.wallet.create(password);
                if (result.success) {
                    newWalletData.value = result.data;
                    if (result.data.mnemonic) {
                        mnemonicWords.value = result.data.mnemonic;
                        showMnemonicModal.value = true;
                    }
                    walletAddress.value = result.data.address;
                    config.walletAddress = result.data.address;
                    saveSettings();
                    await loadWallets();
                    await loadIdentityStatus();
                    // Auto-clear private key from memory after 60 seconds
                    setTimeout(() => {
                        if (newWalletData.value && newWalletData.value.privateKey) {
                            newWalletData.value = { ...newWalletData.value, privateKey: null };
                        }
                    }, 60000);
                } else {
                    alert(result.error || 'Failed to create wallet');
                }
            } finally { walletLoading.value = false; }
        }
        async function importWallet() {
            importError.value = '';
            try {
                const result = await window.tpix.wallet.import(importKeyInput.value.trim());
                if (result.success) {
                    walletAddress.value = result.data.address;
                    config.walletAddress = result.data.address;
                    showImportModal.value = false;
                    importKeyInput.value = '';
                    saveSettings();
                    await refreshBalance();
                    await loadWallets();
                } else { importError.value = result.error || 'Import failed'; }
            } catch (e) { importError.value = e.message; }
        }
        async function refreshBalance() {
            try { walletBalance.value = await window.tpix.wallet.getBalance(); } catch { walletBalance.value = '0'; }
        }
        async function showExportKey() {
            const password = await askPassword(lang.value === 'th' ? 'ใส่รหัสผ่านเพื่อดู Private Key' : 'Enter password to export Private Key');
            if (password === null) return;
            try {
                const result = await window.tpix.wallet.exportKey(undefined, password);
                if (result && result.success) {
                    exportedKey.value = result.key;
                    // Auto-clear after 30 seconds
                    setTimeout(() => { exportedKey.value = null; }, 30000);
                } else {
                    alert(result?.error || 'Wrong password');
                }
            } catch (e) { alert(e.message); }
        }

        // ─── Multi-Wallet Functions ──────────────
        async function loadWallets() {
            try {
                const list = await window.tpix.wallet.listWallets();
                if (Array.isArray(list)) wallets.value = list;
                walletCount.value = await window.tpix.wallet.getWalletCount();
                const active = await window.tpix.wallet.getActiveWallet();
                if (active) {
                    activeWallet.value = active;
                    walletAddress.value = active.address;
                }
                const balances = await window.tpix.wallet.getBalances();
                if (balances) walletBalances.value = balances;
            } catch {}
        }

        async function switchWallet(id) {
            try {
                const result = await window.tpix.wallet.switchWallet(id);
                if (result && result.success) {
                    await loadWallets();
                    await refreshBalance();
                    await loadTransactions(1);
                }
            } catch {}
        }

        async function addNewWallet() {
            const password = await askPassword(lang.value === 'th' ? 'ใส่รหัสผ่านสำหรับกระเป๋าใหม่' : 'Set a password for new wallet');
            if (password === null) return;
            walletLoading.value = true;
            try {
                const result = await window.tpix.wallet.create(password);
                if (result.success) {
                    newWalletData.value = result.data;
                    await loadWallets();
                    await refreshBalance();
                } else {
                    alert(result.error || 'Failed to create wallet');
                }
            } finally { walletLoading.value = false; }
        }

        function startRenameWallet(wallet) {
            walletNameEdit.value = wallet.id;
            walletNameInput.value = wallet.name || '';
        }

        async function confirmRenameWallet(id) {
            try {
                await window.tpix.wallet.renameWallet(id, walletNameInput.value.trim());
                walletNameEdit.value = null;
                walletNameInput.value = '';
                await loadWallets();
            } catch {}
        }

        async function deleteWalletConfirm(id) {
            const password = await askPassword(i18n.value.multiWallet.confirmDelete);
            if (password === null) return; // User cancelled
            // Empty password is valid (default for wallets created without password)
            try {
                const result = await window.tpix.wallet.deleteWallet(id, password);
                if (result && result.success) {
                    await loadWallets();
                    await refreshBalance();
                } else if (result && result.error) {
                    alert(result.error);
                }
            } catch (e) {
                alert(e.message || 'Delete failed');
            }
        }

        // ─── Send / Receive ──────────────────────
        function openSendModal() {
            sendForm.toAddress = '';
            sendForm.amount = '';
            sendForm.password = '';
            sendForm.sending = false;
            sendForm.error = '';
            sendForm.txHash = '';
            gasEstimate.value = null;
            showSendModal.value = true;
        }

        let gasEstimateTimer = null;
        async function estimateGasFee() {
            if (gasEstimateTimer) clearTimeout(gasEstimateTimer);
            gasEstimateTimer = setTimeout(async () => {
                if (!sendForm.toAddress || !sendForm.amount) { gasEstimate.value = null; return; }
                try {
                    const result = await window.tpix.wallet.estimateGas(sendForm.toAddress, sendForm.amount);
                    if (result && result.success) gasEstimate.value = result.data;
                } catch { gasEstimate.value = null; }
            }, 500);
        }

        async function confirmSend() {
            if (sendForm.sending) return;
            sendForm.error = '';
            if (!sendForm.toAddress || !sendForm.toAddress.startsWith('0x') || sendForm.toAddress.length !== 42) {
                sendForm.error = i18n.value.send.invalidAddress; return;
            }
            const amount = parseFloat(sendForm.amount);
            if (isNaN(amount) || amount <= 0) {
                sendForm.error = i18n.value.send.invalidAmount; return;
            }
            // Password can be empty (wallets created without password)
            // Only validate that password field is not undefined/null
            if (sendForm.password === undefined || sendForm.password === null) {
                sendForm.password = '';
            }
            sendForm.sending = true;
            try {
                const result = await window.tpix.wallet.sendTransaction(sendForm.toAddress, sendForm.amount, sendForm.password);
                if (result && result.success) {
                    sendForm.txHash = result.data.txHash;
                    await refreshBalance();
                    await loadTransactions(1);
                } else {
                    sendForm.error = (result && result.error) || 'Transaction failed';
                }
            } catch (e) {
                sendForm.error = e.message || 'Transaction failed';
            } finally {
                sendForm.sending = false;
            }
        }

        async function openReceiveModal() {
            showReceiveModal.value = true;
            qrCodeData.value = null;
            try {
                const walletId = activeWallet.value ? activeWallet.value.id : undefined;
                const data = await window.tpix.wallet.getQRCode(walletId);
                qrCodeData.value = data;
            } catch {}
        }

        // ─── Transaction History ─────────────────
        async function loadTransactions(page, append = false) {
            if (page !== undefined) txPage.value = page;
            try {
                const walletId = activeWallet.value ? activeWallet.value.id : undefined;
                const result = await window.tpix.wallet.getTransactions(walletId, txPage.value, 20);
                if (result) {
                    if (append && txPage.value > 1) {
                        // Append new results to existing list (Load More)
                        const existingHashes = new Set(transactions.value.map(t => t.tx_hash));
                        const newTxs = (result.transactions || []).filter(t => !existingHashes.has(t.tx_hash));
                        transactions.value = [...transactions.value, ...newTxs];
                    } else {
                        transactions.value = result.transactions || [];
                    }
                    txTotal.value = result.total || 0;
                }
            } catch {}
        }

        // ─── Rewards ─────────────────────────────
        async function loadRewards() {
            try {
                const walletId = activeWallet.value ? activeWallet.value.id : undefined;
                const result = await window.tpix.wallet.getRewards(walletId);
                if (result) rewards.value = result;
                // Also load staking info
                await loadStakingInfo();
            } catch {}
        }

        // ─── QR Scanner ───────────────────────
        async function startQRScan() {
            showQRScanner.value = true;
            qrScanError.value = '';

            try {
                const stream = await navigator.mediaDevices.getUserMedia({
                    video: { facingMode: 'environment', width: { ideal: 640 }, height: { ideal: 480 } }
                });
                qrVideoStream = stream;

                // Wait for Vue to flush DOM update then find video element
                await Vue.nextTick();
                await new Promise(r => setTimeout(r, 50));
                const video = document.getElementById('qr-video');
                if (!video) { stopQRScan(); return; }

                video.srcObject = stream;
                await video.play();

                const canvas = document.createElement('canvas');
                const ctx = canvas.getContext('2d', { willReadFrequently: true });

                qrScanInterval = setInterval(() => {
                    if (video.readyState !== video.HAVE_ENOUGH_DATA) return;
                    canvas.width = video.videoWidth;
                    canvas.height = video.videoHeight;
                    ctx.drawImage(video, 0, 0);
                    const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);

                    if (typeof jsQR !== 'undefined') {
                        const code = jsQR(imageData.data, canvas.width, canvas.height, { inversionAttempts: 'dontInvert' });
                        if (code && code.data) {
                            handleQRResult(code.data);
                            stopQRScan();
                        }
                    }
                }, 200);
            } catch (err) {
                qrScanError.value = i18n.value.qrScanner.noCamera;
                console.error('[QR] Camera error:', err);
            }
        }

        function stopQRScan() {
            if (qrScanInterval) { clearInterval(qrScanInterval); qrScanInterval = null; }
            if (qrVideoStream) {
                qrVideoStream.getTracks().forEach(t => t.stop());
                qrVideoStream = null;
            }
            showQRScanner.value = false;
        }

        function handleQRResult(data) {
            // Parse ethereum: URI or plain address
            // Format: ethereum:0x1234...@4289 or just 0x1234...
            let address = data;
            if (data.startsWith('ethereum:')) {
                address = data.replace('ethereum:', '').split('@')[0].split('?')[0].split('/')[0];
            }
            if (/^0x[0-9a-fA-F]{40}$/.test(address)) {
                sendForm.toAddress = address;
                estimateGasFee();
            }
        }

        // ─── Identity (Living Wallet) ─────────
        async function loadIdentityStatus() {
            try {
                const walletId = activeWallet.value ? activeWallet.value.id : undefined;
                const status = await window.tpix.identity.getStatus(walletId);
                if (status) identityStatus.value = status;
            } catch {}
        }

        async function saveSecurityQuestions() {
            const walletId = activeWallet.value?.id;
            if (!walletId) return;

            const valid = securityQuestionsForm.value.filter(q => q.question.trim() && q.answer.trim());
            if (valid.length < 3) {
                alert(lang.value === 'th' ? 'ต้องตั้งคำถามอย่างน้อย 3 ข้อ' : 'At least 3 questions required');
                return;
            }

            identitySaving.value = true;
            try {
                const result = await window.tpix.identity.setSecurityQuestions(walletId, valid);
                if (result.success) {
                    showSecurityQuestions.value = false;
                    await loadIdentityStatus();
                } else {
                    alert(result.error || 'Failed');
                }
            } catch (e) {
                alert(e.message);
            } finally {
                identitySaving.value = false;
            }
        }

        async function saveRecoveryKey() {
            const walletId = activeWallet.value?.id;
            if (!walletId) return;

            if (!/^\d{6,8}$/.test(recoveryKeyForm.pin)) {
                alert(lang.value === 'th' ? 'PIN ต้องเป็นตัวเลข 6-8 หลัก' : 'PIN must be 6-8 digits');
                return;
            }

            identitySaving.value = true;
            try {
                const result = await window.tpix.identity.setRecoveryKey(walletId, recoveryKeyForm.pin, recoveryKeyForm.hint);
                if (result.success) {
                    showRecoveryKeySetup.value = false;
                    recoveryKeyForm.pin = '';
                    recoveryKeyForm.hint = '';
                    await loadIdentityStatus();
                } else {
                    alert(result.error || 'Failed');
                }
            } catch (e) {
                alert(e.message);
            } finally {
                identitySaving.value = false;
            }
        }

        // ─── GPS Location ────────────────────
        async function registerGPSLocation() {
            const walletId = activeWallet.value?.id;
            if (!walletId) return;
            const label = gpsLabel.value.trim();
            if (!label) {
                gpsError.value = lang.value === 'th' ? 'กรุณาใส่ชื่อสถานที่' : 'Location name is required';
                return;
            }
            if (gpsRegistering.value) return; // double-tap guard
            gpsRegistering.value = true;
            gpsError.value = '';
            try {
                // Get GPS from browser Geolocation API
                const position = await new Promise((resolve, reject) => {
                    if (!navigator.geolocation) {
                        reject(new Error(i18n.value.identity.gpsNoSupport));
                        return;
                    }
                    navigator.geolocation.getCurrentPosition(resolve, reject, {
                        enableHighAccuracy: true,
                        timeout: 15000,
                        maximumAge: 0,
                    });
                });

                const result = await window.tpix.identity.registerGPS(
                    walletId, label, position.coords.latitude, position.coords.longitude
                );
                if (result.success) {
                    gpsLabel.value = '';
                    await loadIdentityStatus();
                } else {
                    gpsError.value = result.error || 'Failed';
                }
            } catch (e) {
                if (e.code === 1) {
                    gpsError.value = lang.value === 'th' ? 'การเข้าถึงตำแหน่งถูกปฏิเสธ' : 'Location access denied';
                } else if (e.code === 2) {
                    gpsError.value = lang.value === 'th' ? 'ไม่สามารถรับตำแหน่งได้' : 'Position unavailable';
                } else if (e.code === 3) {
                    gpsError.value = lang.value === 'th' ? 'หมดเวลารับ GPS' : 'GPS timeout';
                } else {
                    gpsError.value = e.message || 'GPS error';
                }
            } finally {
                gpsRegistering.value = false;
            }
        }

        async function removeGPSLocation(locationId) {
            const walletId = activeWallet.value?.id;
            if (!walletId) return;
            const msg = lang.value === 'th' ? 'ลบสถานที่นี้?' : 'Remove this location?';
            if (!confirm(msg)) return;
            try {
                await window.tpix.identity.removeGPS(walletId, locationId);
                await loadIdentityStatus();
            } catch {}
        }

        async function viewMnemonic() {
            const password = await askPassword(lang.value === 'th' ? 'ใส่รหัสผ่านเพื่อดู Seed Phrase' : 'Enter password to view Seed Phrase');
            if (password === null) return;
            try {
                const result = await window.tpix.wallet.getMnemonic(password);
                if (result.success && result.mnemonic) {
                    mnemonicWords.value = result.mnemonic;
                    showMnemonicModal.value = true;
                } else {
                    alert(result.error || 'Wrong password');
                }
            } catch (e) {
                alert(e.message);
            }
        }

        async function recoverFromSeed() {
            if (!recoverMnemonicInput.value.trim()) return;
            recoverLoading.value = true;
            recoverResult.value = null;
            try {
                const result = await window.tpix.wallet.recoverFromMnemonic(
                    recoverMnemonicInput.value.trim(),
                    recoverPassword.value
                );
                if (result.success) {
                    recoverResult.value = result.data;
                    await loadWallets();
                    await refreshBalance();
                } else {
                    alert(result.error || 'Recovery failed');
                }
            } catch (e) {
                alert(e.message);
            } finally {
                recoverLoading.value = false;
            }
        }

        // ─── Explorer ────────────────────────────
        async function loadLatestBlocks() {
            explorerLoading.value = true;
            try {
                const result = await window.tpix.explorer.getLatestBlocks(20);
                if (result.success) explorerBlocks.value = result.data;
            } catch {} finally { explorerLoading.value = false; }
        }

        async function viewBlock(blockNum) {
            explorerLoading.value = true;
            explorerView.value = 'block';
            try {
                const result = await window.tpix.explorer.getBlock(blockNum);
                if (result.success) explorerBlock.value = result.data;
            } catch {} finally { explorerLoading.value = false; }
        }

        function goToBlock(blockNum) {
            // Animation increments locally between RPC refreshes (every 2s, matching chain).
            // These blocks likely exist on chain. Pass number directly — viewBlock handles
            // not-found gracefully (explorerBlock stays null → empty state shown).
            if (blockNum <= 0) return;
            activeTab.value = 'explorer';
            viewBlock(blockNum);
        }

        async function viewTx(txHash) {
            explorerLoading.value = true;
            explorerView.value = 'tx';
            try {
                const result = await window.tpix.explorer.getTx(txHash);
                if (result.success) explorerTx.value = result.data;
            } catch {} finally { explorerLoading.value = false; }
        }

        async function explorerSearchAction() {
            const q = explorerSearch.value.trim();
            if (!q) return;
            if (q.startsWith('0x') && q.length === 66) {
                await viewTx(q);
            } else {
                const num = parseInt(q);
                if (!isNaN(num)) await viewBlock(num);
            }
        }

        function explorerBack() {
            explorerView.value = 'list';
            explorerBlock.value = null;
            explorerTx.value = null;
        }

        function formatBlockTime(hex) {
            if (!hex) return '';
            const ts = parseInt(hex, 16) * 1000;
            return new Date(ts).toLocaleString();
        }

        function hexToNum(hex) {
            if (!hex) return 0;
            return parseInt(hex, 16);
        }

        function hexToTpix(hex) {
            if (!hex || hex === '0x0') return '0';
            try {
                const wei = BigInt(hex);
                const whole = wei / BigInt(1e18);
                const frac = wei % BigInt(1e18);
                if (frac === 0n) return whole.toString();
                const fracStr = frac.toString().padStart(18, '0').slice(0, 6).replace(/0+$/, '');
                return whole + (fracStr ? '.' + fracStr : '');
            } catch { return '0'; }
        }

        // ─── Masternode Map ──────────────────────
        function loadMasternodes() {
            const flag = (code) => String.fromCodePoint(...[...code.toUpperCase()].map(c => 0x1F1E6 + c.charCodeAt(0) - 65));
            let nodes = [
                { id: 1, type: 'validator', addr: '0x742d35Cc6634C0532925a3b844Bc9e7595f2bD4e', country: 'TH', countryName: 'Thailand', lat: 13.75, lng: 100.5, city: 'Bangkok', ip: '203.150.45.12', online: true, totalRewards: '45,200', rewards: [
                    { block: 1250000, amount: '8.5', time: '2026-03-25 14:30' }, { block: 1249800, amount: '8.5', time: '2026-03-25 14:20' }, { block: 1249600, amount: '8.5', time: '2026-03-25 14:10' },
                ]},
                { id: 2, type: 'guardian', addr: '0x8Ba1f109551bD432803012645Hac136c9b7c31A5', country: 'TH', countryName: 'Thailand', lat: 18.79, lng: 98.98, city: 'Chiang Mai', ip: '203.150.78.34', online: true, totalRewards: '10,230', rewards: [
                    { block: 1250001, amount: '2.5', time: '2026-03-25 14:30' }, { block: 1249801, amount: '2.5', time: '2026-03-25 14:20' },
                ]},
                { id: 3, type: 'guardian', addr: '0x1aF5b3E2A31c4e7FBc65A32Da0F7e53c9712E4eB', country: 'SG', countryName: 'Singapore', lat: 1.35, lng: 103.82, city: 'Singapore', ip: '128.199.142.78', online: true, totalRewards: '11,800', rewards: [
                    { block: 1250002, amount: '2.5', time: '2026-03-25 14:30' },
                ]},
                { id: 4, type: 'sentinel', addr: '0x3cD2fC9d5dBe97BAc69f4e7d76D2fA5E3a1E5b7A', country: 'JP', countryName: 'Japan', lat: 35.68, lng: 139.69, city: 'Tokyo', ip: '45.76.198.45', online: true, totalRewards: '5,120', rewards: [
                    { block: 1249500, amount: '1.2', time: '2026-03-25 13:50' },
                ]},
                { id: 5, type: 'sentinel', addr: '0x9eF8A2D3c45b67E8f901d2C34B56a78E9f0123BC', country: 'KR', countryName: 'South Korea', lat: 37.57, lng: 126.98, city: 'Seoul', ip: '121.170.56.89', online: true, totalRewards: '4,890', rewards: [
                    { block: 1249000, amount: '1.2', time: '2026-03-25 13:00' },
                ]},
                { id: 6, type: 'sentinel', addr: '0x5bA3D7e8f901C23d45E67F89a01b2C34D56E78Fe', country: 'US', countryName: 'United States', lat: 37.77, lng: -122.42, city: 'San Francisco', ip: '104.238.167.12', online: true, totalRewards: '4,560', rewards: []},
                { id: 7, type: 'light', addr: '0x2dC4E5f6A7b8C9d0E1F2a3B4c5D6e7F8a9B0C1De', country: 'DE', countryName: 'Germany', lat: 52.52, lng: 13.41, city: 'Berlin', ip: '195.201.45.167', online: true, totalRewards: '1,230', rewards: []},
                { id: 8, type: 'light', addr: '0x6fE1a2B3c4D5e6F7a8B9c0D1e2F3a4B5c6D7e8Ab', country: 'GB', countryName: 'United Kingdom', lat: 51.51, lng: -0.13, city: 'London', ip: '51.158.98.201', online: false, totalRewards: '980', rewards: []},
                { id: 9, type: 'light', addr: '0x4aB7c8D9e0F1a2B3c4D5e6F7a8B9c0D1e2F312Cd', country: 'AU', countryName: 'Australia', lat: -33.87, lng: 151.21, city: 'Sydney', ip: '103.16.128.45', online: true, totalRewards: '1,100', rewards: []},
                { id: 10, type: 'guardian', addr: '0x7cE9a0B1c2D3e4F5a6B7c8D9e0F1a2B3c4D556Fg', country: 'TH', countryName: 'Thailand', lat: 7.88, lng: 98.39, city: 'Phuket', ip: '203.150.92.56', online: true, totalRewards: '9,750', rewards: [
                    { block: 1250003, amount: '2.5', time: '2026-03-25 14:30' },
                ]},
                { id: 11, type: 'light', addr: '0x8dA2b3C4d5E6f7A8b9C0d1E2f3A4b5C6d7E834Hi', country: 'VN', countryName: 'Vietnam', lat: 10.82, lng: 106.63, city: 'Ho Chi Minh', ip: '113.190.45.78', online: true, totalRewards: '890', rewards: []},
                { id: 12, type: 'sentinel', addr: '0x1bC5d6E7f8A9b0C1d2E3f4A5b6C7d8E9f0A178Jk', country: 'MY', countryName: 'Malaysia', lat: 3.14, lng: 101.69, city: 'Kuala Lumpur', ip: '175.143.67.89', online: true, totalRewards: '3,450', rewards: []},
                { id: 13, type: 'light', addr: '0x3eD8f9A0b1C2d3E4f5A6b7C8d9E0f1A2b3C490Lm', country: 'IN', countryName: 'India', lat: 19.08, lng: 72.88, city: 'Mumbai', ip: '49.36.145.23', online: false, totalRewards: '670', rewards: []},
                { id: 14, type: 'sentinel', addr: '0x5fA1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6E723No', country: 'CA', countryName: 'Canada', lat: 43.65, lng: -79.38, city: 'Toronto', ip: '198.55.100.34', online: true, totalRewards: '4,120', rewards: []},
                { id: 15, type: 'light', addr: '0x9gB4c5D6e7F8a9B0c1D2e3F4a5B6c7D8e9F056Pq', country: 'BR', countryName: 'Brazil', lat: -23.55, lng: -46.63, city: 'Sao Paulo', ip: '187.45.223.67', online: true, totalRewards: '540', rewards: []},
            ].map(n => ({ ...n, flag: flag(n.country), isDemo: true }));

            // Add user's own node if staking is active
            if (stakingInfo.value && stakingInfo.value.status === 'active') {
                const s = stakingInfo.value;
                const myNode = {
                    id: 999,
                    type: s.tier,
                    addr: s.wallet_address,
                    country: 'TH',
                    countryName: 'Thailand',
                    lat: 13.75 + (Math.random() - 0.5) * 0.1,
                    lng: 100.5 + (Math.random() - 0.5) * 0.1,
                    city: 'My Node',
                    ip: '127.0.0.1',
                    online: nodeStatus.value === 'running' || nodeStatus.value === 'syncing',
                    totalRewards: rewards.value.total ? String(rewards.value.total) : '0',
                    rewards: (rewards.value.rewards || []).slice(0, 5).map(r => ({
                        block: r.block_number,
                        amount: (Number(r.amount) / 1e18).toFixed(4),
                        time: new Date(r.timestamp * 1000).toLocaleString(),
                    })),
                    isMyNode: true,
                    isDemo: false,
                    flag: flag('TH'),
                };
                // Remove duplicate if exists
                nodes = nodes.filter(n => n.id !== 999);
                nodes.unshift(myNode);
            }

            masternodeData.value = nodes;

            const byType = { light: 0, sentinel: 0, guardian: 0, validator: 0 };
            const countrySet = new Set();
            nodes.forEach(n => { byType[n.type]++; countrySet.add(n.country); });
            masternodeStats.value = { total: nodes.length, countries: countrySet.size, byType };
        }

        function initLeafletMap() {
            // v-if destroys the DOM — use nextTick + setTimeout to ensure
            // the container is fully rendered and sized before Leaflet init
            Vue.nextTick(() => {
                setTimeout(() => {
                    const container = document.getElementById('leaflet-map');
                    if (!container || leafletMap) return;

                    // Dark theme map
                    leafletMap = L.map('leaflet-map', {
                        center: [20, 100],
                        zoom: 3,
                        minZoom: 2,
                        maxZoom: 15,
                        zoomControl: true,
                        attributionControl: false,
                    });

                    // Dark tile layer (free, no API key)
                    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
                        subdomains: 'abcd',
                        maxZoom: 19,
                    }).addTo(leafletMap);

                    // Add attribution manually
                    L.control.attribution({ prefix: false }).addAttribution('&copy; <a href="https://carto.com/">CARTO</a> &copy; <a href="https://osm.org/">OSM</a>').addTo(leafletMap);

                    // Force recalculate container size after v-if re-render
                    leafletMap.invalidateSize();

                    addMapMarkers();
                }, 100);
            });
        }

        function addMapMarkers() {
            if (!leafletMap) return;

            // Clear existing markers
            leafletMarkers.forEach(m => leafletMap.removeLayer(m));
            leafletMarkers = [];

            const typeColors = { validator: '#00e676', guardian: '#f59e0b', sentinel: '#a855f7', light: '#06b6d4' };
            const typeSizes = { validator: 12, guardian: 11, sentinel: 10, light: 8 };

            masternodeData.value.forEach(node => {
                const color = typeColors[node.type] || '#06b6d4';
                const size = typeSizes[node.type] || 8;

                const icon = L.divIcon({
                    className: 'mn-map-marker',
                    html: '<div style="width:' + size + 'px;height:' + size + 'px;background:' + color + ';border-radius:50%;box-shadow:0 0 ' + (size * 2) + 'px ' + color + ', 0 0 ' + (size * 4) + 'px ' + color + '40;border:2px solid ' + color + '80;"></div>',
                    iconSize: [size + 4, size + 4],
                    iconAnchor: [(size + 4) / 2, (size + 4) / 2],
                });

                const marker = L.marker([node.lat, node.lng], { icon }).addTo(leafletMap);

                // Popup with node info
                const statusDot = node.online ? '<span style="color:#00e676">&#9679;</span>' : '<span style="color:#ff1744">&#9679;</span>';
                const statusText = node.online ? 'Online' : 'Offline';
                const demoBadge = node.isDemo
                    ? '<span style="background:rgba(245,158,11,0.2);color:#f59e0b;padding:1px 6px;border-radius:8px;font-size:9px;font-weight:700;letter-spacing:0.5px;margin-left:4px">DEMO</span>'
                    : '<span style="background:rgba(0,230,118,0.2);color:#00e676;padding:1px 6px;border-radius:8px;font-size:9px;font-weight:700;letter-spacing:0.5px;margin-left:4px">LIVE</span>';
                marker.bindPopup(
                    '<div style="font-family:monospace;font-size:12px;min-width:220px;color:#e2e8f0;background:#0a0f1e;padding:8px;border-radius:8px;border:1px solid rgba(6,182,212,0.3)">' +
                    '<div style="font-size:18px;text-align:center">' + node.flag + '</div>' +
                    '<div style="font-weight:600;color:#06b6d4;margin:4px 0">' + node.city + ', ' + node.countryName + '</div>' +
                    '<div><span style="background:' + color + '20;color:' + color + ';padding:1px 6px;border-radius:8px;font-size:10px;font-weight:600">' + node.type.toUpperCase() + '</span> ' + demoBadge + ' ' + statusDot + ' ' + statusText + '</div>' +
                    '<hr style="border:none;border-top:1px solid rgba(6,182,212,0.15);margin:6px 0">' +
                    '<div style="font-size:10px;color:#94a3b8">Wallet</div>' +
                    '<div style="font-size:11px;word-break:break-all">' + node.addr + '</div>' +
                    '<div style="font-size:10px;color:#94a3b8;margin-top:4px">IP: ' + node.ip + '</div>' +
                    '<div style="color:#06b6d4;margin-top:4px;font-weight:600">Rewards: ' + node.totalRewards + ' TPIX</div>' +
                    '</div>',
                    { className: 'mn-popup', maxWidth: 300 }
                );

                leafletMarkers.push(marker);
            });
        }

        function mapZoomAll() {
            if (leafletMap) leafletMap.setView([20, 100], 2);
        }

        function mapFocusNode(node) {
            if (leafletMap) {
                leafletMap.setView([node.lat, node.lng], 10);
                // Open popup for this node
                const marker = leafletMarkers.find((m, i) => masternodeData.value[i]?.id === node.id);
                if (marker) marker.openPopup();
            }
        }

        function checkNodeRewards(node) {
            selectedNodeReward.value = { ...node };
        }

        // ─── Format Helpers ──────────────────────
        function formatTpix(weiString) {
            if (!weiString) return '0';
            try {
                const wei = BigInt(weiString);
                if (wei === 0n) return '0';
                // BigInt division for precision
                const whole = wei / BigInt(1e18);
                const frac = wei % BigInt(1e18);
                if (frac === 0n) return whole.toLocaleString();
                // Format with up to 6 decimal places
                const fracStr = frac.toString().padStart(18, '0').slice(0, 6).replace(/0+$/, '');
                if (!fracStr) return whole.toLocaleString();
                return whole.toLocaleString() + '.' + fracStr;
            } catch { return '0'; }
        }

        // ─── Staking Functions ────────────────────
        async function validateStakeBalance() {
            if (!walletAddress.value || !config.tier) return;
            stakingValidation.value = null;
            stakingError.value = '';
            try {
                const result = await window.tpix.staking.validateBalance(walletAddress.value, config.tier);
                stakingValidation.value = result;
                return result;
            } catch (err) {
                stakingError.value = err.message;
                return null;
            }
        }

        async function loadStakingInfo() {
            try {
                const active = await window.tpix.staking.getActive();
                stakingInfo.value = active;
            } catch {}
        }

        async function registerStaking() {
            if (stakingLoading.value) return;
            stakingError.value = '';
            stakingLoading.value = true;
            try {
                // Validate balance first
                const validation = await validateStakeBalance();
                if (!validation || !validation.valid) {
                    stakingError.value = validation?.error ||
                        (lang.value === 'th'
                            ? `ยอดเงินไม่เพียงพอ ต้องการ ${validation?.requiredTpix?.toLocaleString() || '?'} TPIX`
                            : `Insufficient balance. Required: ${validation?.requiredTpix?.toLocaleString() || '?'} TPIX`);
                    return false;
                }

                // Get wallet info
                const active = activeWallet.value;
                if (!active) {
                    stakingError.value = lang.value === 'th' ? 'ไม่มีกระเป๋าที่เลือก' : 'No active wallet';
                    return false;
                }

                // Calculate stake in wei
                const tierStakes = { light: 10000, sentinel: 100000, guardian: 1000000, validator: 10000000 };
                const stakeAmount = BigInt(tierStakes[config.tier] || 10000) * BigInt('1000000000000000000');

                const result = await window.tpix.staking.register({
                    walletId: active.id,
                    walletAddress: active.address,
                    rewardWallet: config.rewardWallet || active.address,
                    tier: config.tier,
                    stakeAmount: stakeAmount.toString(),
                    nodeName: config.nodeName,
                });

                if (result.success) {
                    await loadStakingInfo();
                    return true;
                } else {
                    stakingError.value = result.error;
                    return false;
                }
            } catch (err) {
                stakingError.value = err.message;
                return false;
            } finally {
                stakingLoading.value = false;
            }
        }

        async function stopStaking() {
            try {
                await window.tpix.staking.stop();
                stakingInfo.value = null;
            } catch {}
        }

        // ─── Settings ─────────────────────────────
        async function loadConfig() {
            try { const c = await window.tpix.node.getConfig(); if (c) Object.assign(config, c); } catch {}
        }
        async function saveSettings() { await window.tpix.node.saveConfig({ ...config }); }
        function openDataDir() { window.tpix.system.openDataDir(); }

        // ─── Update Actions ───────────────────────
        async function checkUpdate() {
            try { const r = await window.tpix.update.check(); if (r?.data) updateStatus.value = r.data; } catch {}
        }
        async function downloadUpdate() {
            try { await window.tpix.update.download(); } catch {}
        }
        function installUpdate() {
            try { window.tpix.update.install(); } catch {}
        }

        // ─── Links ────────────────────────────────
        function openLink(key) {
            const map = {
                explorer: 'https://explorer.tpix.online',
                explorerAddr: `https://explorer.tpix.online/address/${walletAddress.value}`,
                download: 'https://tpix.online/download',
                xmanstudio: 'https://xman4289.com',
            };
            const url = map[key] || key;
            window.tpix.system.openExternal(url);
        }

        // ─── Logs ─────────────────────────────────
        async function loadLogs() {
            try { const l = await window.tpix.node.getLogs(200); if (l) logs.value = l; } catch {}
        }

        // ─── Helpers ──────────────────────────────
        function formatNumber(n) { return n ? n.toLocaleString() : '0'; }
        function formatDuration(s) {
            if (!s || s < 0) return 'N/A';
            if (s < 60) return s + 's';
            if (s < 3600) return Math.floor(s / 60) + 'm ' + (s % 60) + 's';
            return Math.floor(s / 3600) + 'h ' + Math.floor((s % 3600) / 60) + 'm';
        }
        function formatMB(mb) { return mb >= 1024 ? (mb / 1024).toFixed(1) + ' GB' : (mb || 0) + ' MB'; }
        function formatLogTime(iso) { try { return new Date(iso).toLocaleTimeString('en-US', { hour12: false }); } catch { return ''; } }
        function copyToClipboard(t) { if (t) navigator.clipboard.writeText(t).catch(() => {}); }
        function formatBytes(b) { if (!b) return '0 B'; if (b < 1024) return b + ' B'; if (b < 1048576) return (b/1024).toFixed(1) + ' KB'; return (b/1048576).toFixed(1) + ' MB'; }
        function shortAddr(a) { return a ? a.slice(0, 8) + '...' + a.slice(-6) : ''; }
        function minimize() { window.tpix.window.minimize(); }
        function maximize() { window.tpix.window.maximize(); }
        function closeWindow() { window.tpix.window.close(); }

        // ─── Lifecycle ────────────────────────────
        onMounted(async () => {
            // Fetch version dynamically from main process
            try { appVersion.value = await window.tpix.update.getVersion(); } catch { appVersion.value = '?'; }

            await loadConfig();
            await loadWallet(); // loadWallet already calls loadWallets inside
            await loadTransactions(1);
            await refreshNetwork();
            await refreshMetrics();
            await loadLogs();
            try { const s = await window.tpix.node.status(); if (s) { nodeStatus.value = s.status; nodeUptime.value = s.uptime || 0; } } catch {}
            networkInterval = setInterval(refreshNetwork, 15000);
            startBlockAnim();
            metricsInterval = setInterval(refreshMetrics, 5000);
            uptimeInterval = setInterval(() => { if (nodeStatus.value === 'running' || nodeStatus.value === 'syncing') nodeUptime.value++; }, 1000);
            window.tpix.node.onStatusUpdate(d => { if (d.status) nodeStatus.value = d.status; if (d.network) network.value = d.network; });
            window.tpix.node.onLog(e => { logs.value.push(e); if (logs.value.length > 500) logs.value.shift(); });
            window.tpix.node.onMetrics(m => { metrics.value = m; });
            // Update events
            if (window.tpix.update) {
                window.tpix.update.onStatus(s => { updateStatus.value = s; });
                window.tpix.update.onProgress(p => { updateStatus.value = { ...updateStatus.value, downloadProgress: p }; });
                try { const s = await window.tpix.update.getStatus(); if (s) updateStatus.value = s; } catch {}
            }
            loadMasternodes();
            await loadStakingInfo();
            // Listen for reward accrual events
            window.tpix.node.onRewardAccrued(async (reward) => {
                // Reload rewards when a new reward is accrued
                await loadRewards();
            });
        });
        onUnmounted(() => {
            clearInterval(networkInterval); clearInterval(metricsInterval); clearInterval(uptimeInterval);
            stopBlockAnim();
            if (gasEstimateTimer) clearTimeout(gasEstimateTimer);
            stopQRScan();
            if (leafletMap) { try { leafletMap.remove(); } catch {} leafletMap = null; leafletMarkers = []; }
        });

        // Auto-scroll block stream to newest block
        // Watch the last block id (not length) so scroll works even when array is full (shift+push)
        watch(() => liveBlocks.value.length ? liveBlocks.value[liveBlocks.value.length - 1].id : 0, () => {
            Vue.nextTick(() => {
                const track = document.querySelector('.block-stream-track');
                if (track) track.scrollLeft = track.scrollWidth;
            });
        });

        // Validate balance when setup step or tier changes
        watch(() => [activeTab.value, setupStep.value, config.tier], ([tab, step]) => {
            if (tab === 'setup' && step === 0 && walletAddress.value) {
                validateStakeBalance();
            }
        });

        watch(activeTab, (tab) => {
            if (tab === 'explorer' && explorerBlocks.value.length === 0) loadLatestBlocks();
            if (tab === 'masternodes') {
                loadMasternodes();
                // v-if destroys the DOM when switching away, so the old leafletMap
                // instance is attached to a detached element. Destroy and recreate.
                if (leafletMap) {
                    try { leafletMap.remove(); } catch {}
                    leafletMap = null;
                    leafletMarkers = [];
                }
                initLeafletMap();
            }
        });

        return {
            appVersion, lang, i18n, toggleLang,
            activeTab, tabs, setupStep,
            tiers, selectedTier, linkGroups,
            nodeStatus, statusLabel, nodeUptime,
            network, metrics, logs, config, liveBlocks,
            walletAddress, walletBalance, walletLoading,
            newWalletData, showPrivateKey, showImportModal, importKeyInput, importError, exportedKey,
            // Password prompt modal
            showPasswordModal, passwordModalTitle, passwordModalInput, passwordModalError,
            confirmPasswordModal, cancelPasswordModal,
            // Multi-wallet state
            wallets, walletCount, activeWallet, walletBalances,
            showSendModal, showReceiveModal, showWalletList,
            sendForm, gasEstimate, qrCodeData,
            transactions, txPage, txTotal,
            rewards, walletNameEdit, walletNameInput,
            // QR Scanner
            showQRScanner, qrScanError, startQRScan, stopQRScan,
            // Identity
            identityStatus, showIdentitySetup, showSecurityQuestions, showRecoveryKeySetup,
            showMnemonicModal, showRecoverModal, showMnemonic, mnemonicWords,
            recoverMnemonicInput, recoverPassword, recoverResult, recoverLoading,
            securityQuestionsForm, recoveryKeyForm, identitySaving,
            showGPSSetup, gpsLabel, gpsRegistering, gpsError,
            loadIdentityStatus, saveSecurityQuestions, saveRecoveryKey,
            registerGPSLocation, removeGPSLocation,
            viewMnemonic, recoverFromSeed,
            // Actions
            startNode, stopNode, launchNode, refreshNetwork, refreshMetrics,
            loadWallet, createWallet, importWallet, refreshBalance, showExportKey,
            // Multi-wallet actions
            loadWallets, switchWallet, addNewWallet,
            startRenameWallet, confirmRenameWallet, deleteWalletConfirm,
            openSendModal, estimateGasFee, confirmSend,
            openReceiveModal, loadTransactions, loadRewards,
            formatTpix,
            // Explorer
            explorerBlocks, explorerBlock, explorerTx, explorerLoading, explorerSearch, explorerView,
            loadLatestBlocks, viewBlock, viewTx, explorerSearchAction, explorerBack, goToBlock,
            formatBlockTime, hexToNum, hexToTpix,
            // Masternodes
            masternodeData, masternodeStats, loadMasternodes,
            masternodeCountries, filteredMasternodes,
            mnFilterType, mnFilterCountry, selectedNodeReward,
            mapZoomAll, mapFocusNode, checkNodeRewards,
            // Staking
            stakingInfo, stakingValidation, stakingLoading, stakingError,
            validateStakeBalance, loadStakingInfo, registerStaking, stopStaking,
            // Settings & utils
            loadConfig, saveSettings, openDataDir, openLink, loadLogs,
            formatNumber, formatDuration, formatMB, formatLogTime,
            updateStatus, checkUpdate, downloadUpdate, installUpdate,
            copyToClipboard, shortAddr, formatBytes, minimize, maximize, closeWindow,
        };
    },
});

app.mount('#app');
