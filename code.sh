#!/bin/bash

PROJECT_NAME_INPUT="CACheckpointManager"
FRONTEND_TEMPLATE="react-ts" # Essential for this setup

echo "---------------------------------------------------------------------"
echo "Tauri v2 Project Setup: React + TypeScript + Shadcn/UI + Tailwind v4"
echo "---------------------------------------------------------------------"
echo
echo "This script will guide you. It uses 'pnpm create tauri-app'."
echo "You WILL be prompted by the Tauri CLI and later by the Shadcn/UI CLI."
echo

# 1. Create Tauri project with React-TS template
read -p "Enter project name (default: $PROJECT_NAME_INPUT): " USER_PROJECT_NAME
PROJECT_NAME=${USER_PROJECT_NAME:-$PROJECT_NAME_INPUT}

echo
echo "Attempting to create Tauri project '$PROJECT_NAME' with template '$FRONTEND_TEMPLATE' using pnpm..."
echo "Please follow ALL interactive prompts from 'pnpm create tauri-app'."
echo "-> When asked for 'App name', use: $PROJECT_NAME"
echo "-> When asked for 'Window title', use: Checkpoint Manager"
echo "-> When asked to 'Choose your UI template', select: $FRONTEND_TEMPLATE"
echo "-> When asked for 'package manager', select: pnpm"
echo

if pnpm create tauri-app; then
    echo -e "\nSUCCESS: Tauri project scaffolding initiated with pnpm.\n"
else
    echo -e "\n---------------------------------------------------------------------"
    echo "ERROR: 'pnpm create tauri-app' failed or was cancelled."
    echo "Ensure Node.js, pnpm, Rust, and Tauri v2 prerequisites are installed."
    echo "Prerequisites: https://v2.tauri.app/start/prerequisites/"
    echo "---------------------------------------------------------------------"
    exit 1
fi

echo "IMPORTANT: 'pnpm create tauri-app' likely created a new directory for your project."
echo "Please enter the exact name of the directory that was just created (usually '$PROJECT_NAME')."
read -p "Enter the project directory name: " ACTUAL_PROJECT_DIR

if [ -z "$ACTUAL_PROJECT_DIR" ]; then
    echo "No project directory name entered. Exiting."
    exit 1
fi
if [ ! -d "$ACTUAL_PROJECT_DIR" ]; then
    echo "ERROR: Directory '$ACTUAL_PROJECT_DIR' not found. Exiting."
    exit 1
fi

cd "$ACTUAL_PROJECT_DIR" || { echo "ERROR: Failed to cd into '$ACTUAL_PROJECT_DIR'."; exit 1; }
echo "Changed directory to $(pwd)"
echo

if [ ! -d "src-tauri" ]; then
    echo "ERROR: 'src-tauri' directory not found. Initialization incomplete. Exiting."
    exit 1
fi

# 2. Install Tailwind CSS v4 and its Vite plugin
echo "Installing Tailwind CSS v4 and related packages..."
pnpm add -D tailwindcss postcss autoprefixer @tailwindcss/vite

# 3. Create Tailwind and PostCSS config files
echo "Creating Tailwind CSS and PostCSS configuration files..."

cat > tailwind.config.js << 'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}", // Ensure this covers your React files
  ],
  theme: {
    extend: {
      // You can extend your theme here later if needed
      colors: {
        // Example custom colors inspired by screenshots
        'brand-purple-dark': '#4A00E0',
        'brand-purple-light': '#8E2DE2',
        'rfid-orange-dark': '#FF6B6B',
        'rfid-orange-light': '#FFB147',
        'gatepass-blue-dark': '#4778FF',
        'gatepass-blue-light': '#47C6FF',
        'nextpass-purple-dark': '#6D32A5',
        'nextpass-purple-light': '#9354E8',
        'payment-green-dark': '#56AB2F',
        'payment-green-light': '#A8E063',
        'rfid-info-bg': 'rgba(126, 217, 87, 0.85)',
        'rfid-info-text': '#0A3600',
      },
      fontFamily: {
        sans: ['Roboto', 'Segoe UI', 'Helvetica Neue', 'Arial', 'sans-serif'],
      },
    },
  },
  plugins: [
    // require('@tailwindcss/forms'), // If you need form styling enhancements
    // require('@tailwindcss/typography'), // If you need prose styling
  ],
}
EOF

cat > postcss.config.js << 'EOF'
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
EOF

# 4. Update main CSS file (path depends on React template, usually src/index.css or src/App.css)
# Assuming create-tauri-app with react-ts creates src/index.css or you create it.
CSS_FILE_PATH="src/index.css" # Default for Vite React templates
if [ ! -f "$CSS_FILE_PATH" ] && [ -f "src/App.css" ]; then
    CSS_FILE_PATH="src/App.css"
elif [ ! -f "$CSS_FILE_PATH" ] && [ -f "src/style.css" ]; then # Vanilla template might use this
    CSS_FILE_PATH="src/style.css"
fi

echo "Adding Tailwind directives to $CSS_FILE_PATH..."
if [ -f "$CSS_FILE_PATH" ]; then
    # Prepend Tailwind directives
    echo -e "@tailwind base;\n@tailwind components;\n@tailwind utilities;\n\n$(cat $CSS_FILE_PATH)" > "$CSS_FILE_PATH"
else
    echo "@tailwind base;" > "$CSS_FILE_PATH"
    echo "@tailwind components;" >> "$CSS_FILE_PATH"
    echo "@tailwind utilities;" >> "$CSS_FILE_PATH"
    echo "Created $CSS_FILE_PATH with Tailwind directives."
fi
echo "Make sure to import '$CSS_FILE_PATH' in your 'src/main.tsx'."

# 5. Update vite.config.ts to include Tailwind CSS Vite plugin
echo "Updating vite.config.ts for Tailwind CSS..."
# This is a bit tricky as we need to import and add the plugin.
# We'll create a new vite.config.ts with the plugin.
# The user might need to merge if their existing vite.config.ts is complex.
VITE_CONFIG_PATH="vite.config.ts" # create-tauri-app usually creates this

cat > $VITE_CONFIG_PATH << 'EOF'
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite"; // Import Tailwind CSS Vite plugin

// @ts-expect-error process is a nodejs global
const host = process.env.TAURI_DEV_HOST;

// https://vitejs.dev/config/
export default defineConfig(async () => ({
  plugins: [
    react(),
    tailwindcss(), // Add Tailwind CSS Vite plugin
  ],

  // Vite options tailored for Tauri development and only applied in `tauri dev` or `tauri build`
  //
  // 1. prevent vite from obscuring rust errors
  clearScreen: false,
  // 2. tauri expects a fixed port, fail if that port is not available
  server: {
    port: 1420,
    strictPort: true,
    host: host || false,
    hmr: host
      ? {
          protocol: "ws",
          host,
          port: 1421,
        }
      : undefined,
    watch: {
      // 3. tell vite to ignore watching `src-tauri`
      ignored: ["**/src-tauri/**"],
    },
  },
}));
EOF
echo "Vite configuration updated. Please review $VITE_CONFIG_PATH if you had custom Vite settings."

# 6. Initialize Shadcn/UI
echo ""
echo "---------------------------------------------------------------------"
echo "Now, we will initialize Shadcn/UI using its CLI."
echo "This step is INTERACTIVE. Please answer the prompts."
echo "Recommended answers for this project:"
echo "  - Would you like to use TypeScript? (y/N): y (if not already set)"
echo "  - Which style would you like to use? › Default"
echo "  - Which color would you like to use as base color? › Slate"
echo "  - Where is your global CSS file? › (Path to your main CSS, e.g., src/index.css or src/App.css)"
echo "  - Would you like to use CSS variables for colors? (y/N): y"
echo "  - Where is your tailwind.config.js located? › tailwind.config.js"
echo "  - Configure import alias for components: › @/components"
echo "  - Configure import alias for utils: › @/lib/utils"
echo "  - Are you using React Server Components? (y/N): N"
echo "  - Write configuration to components.json. Proceed? (Y/n): Y"
echo "---------------------------------------------------------------------"
echo "Running Shadcn/UI init..."
if pnpm dlx shadcn-ui@latest init; then
    echo -e "\nSUCCESS: Shadcn/UI initialized.\n"
else
    echo -e "\nWARNING: Shadcn/UI initialization might have failed or was cancelled. You can try running 'pnpm dlx shadcn-ui@latest init' manually later.\n"
fi

# 7. Install some example Shadcn/UI components
echo "Installing example Shadcn/UI components (Button, Card, Input, Progress)..."
pnpm dlx shadcn-ui@latest add button card input progress
echo

# --- Frontend React Component Placeholders ---
echo "Creating placeholder React components (src/App.tsx, src/views/*)..."
# Overwrite/Create src/App.tsx
cat > src/App.tsx << 'EOF'
import { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/tauri";
import { listen } from "@tauri-apps/api/event";
import './App.css'; // Or your global CSS file like index.css if different

// Shadcn/UI components (assuming you've added them)
import { Button } from "@/components/ui/button";
import { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Progress } from "@/components/ui/progress";

// Placeholder icons - replace with actual SVGs or a library
const RFIDIcon = () => <img src="./assets/rfid-icon-white.svg" alt="RFID" className="w-16 h-16 mb-4" />;
const QRIcon = () => <img src="./assets/qr-icon-white.svg" alt="QR" className="w-20 h-20 mb-3" />;
const CheckmarkIcon = () => <img src="./assets/checkmark-white.svg" alt="Success" className="w-8 h-8 text-white" />;


const APP_STATE = {
  DETECTING_RFID: 'DETECTING_RFID',
  VALIDATING_RFID: 'VALIDATING_RFID',
  AWAITING_PAYMENT: 'AWAITING_PAYMENT',
  PROCESSING_PAYMENT: 'PROCESSING_PAYMENT',
  PAYMENT_SUCCESS_AWAIT_QR: 'PAYMENT_SUCCESS_AWAIT_QR',
  AWAITING_NEXT_QR: 'AWAITING_NEXT_QR',
  PROCESSING_FINAL: 'PROCESSING_FINAL',
  ERROR: 'ERROR',
} as const; // Use 'as const' for stricter type checking on states

type AppScreenState = typeof APP_STATE[keyof typeof APP_STATE];

interface RFIDData {
  raw: string;
  main: string;
  sub: string;
}
interface GatePass {
  code: string;
  valid: boolean;
  details?: string;
  error?: string;
}
interface AppSettings {
    gate_name?: string;
    emoney_deduct_price?: number;
    // Add other settings you expect
}
interface PaymentResultDetails { // From rfid_handler.rs
    success: boolean;
    message: string;
    transaction_id: string;
    card_no: string;
    amount_paid: number;
    balance_after: number;
    timestamp: string;
}
interface CGSTReceiveResult { // From soap_services.rs
    status: boolean;
    result?: string;
    transaction_id_str?: string;
    result_cms?: CMSDataItem[];
}
interface CMSDataItem { // From soap_services.rs CMSData
    daily_seq?: string;
    cntr_number?: string;
    truck_police_num?: string;
    truck_in_time?: string;
}


function App() {
  const [currentScreen, setCurrentScreen] = useState<AppScreenState>(APP_STATE.DETECTING_RFID);
  const [gateName, setGateName] = useState("Loading...");
  const [statusBarText, setStatusBarText] = useState("Initializing...");
  const [isErrorStatus, setIsErrorStatus] = useState(false);
  const [rfidData, setRfidData] = useState<RFIDData | null>(null);
  const [paymentAmount, setPaymentAmount] = useState(0);
  const [scannedGatePasses, setScannedGatePasses] = useState<GatePass[]>([]);
  const [qrInputValue, setQrInputValue] = useState("");
  const qrInputRef = useRef<HTMLInputElement>(null);
  const [finalProgress, setFinalProgress] = useState(0);
  const [finalProgressMsg, setFinalProgressMsg] = useState("");

  const updateStatus = (text: string, isError: boolean = false) => {
    setStatusBarText(text);
    setIsErrorStatus(isError);
  };

  useEffect(() => {
    async function fetchSettingsAndInit() {
      try {
        const settings: AppSettings = await invoke('get_app_settings');
        setGateName(settings.gate_name || "Unknown Gate");
        setPaymentAmount(settings.emoney_deduct_price || 17000);
        console.log("App settings loaded:", settings);
        
        updateStatus("Initializing RFID Reader...");
        await invoke('initialize_rfid_reader_command');
        await invoke('start_rfid_detection_command'); // Start polling
        if (currentScreen === APP_STATE.DETECTING_RFID || currentScreen === APP_STATE.VALIDATING_RFID) { // Only if still in initial states
          updateStatus("Scanning for RFID tag...");
        }
      } catch (e: any) {
        console.error("Failed to load app settings or init RFID:", e);
        setGateName("Gate Error");
        updateStatus(`Error initializing: ${e.toString()}`, true);
        setCurrentScreen(APP_STATE.ERROR);
      }
    }
    fetchSettingsAndInit();

    const unlistenRfid = listen<string>('rfid_card_tapped', async (event) => {
      console.log("Frontend received rfid_card_tapped:", event.payload);
      const cardRawData = event.payload;
      
      if (currentScreen === APP_STATE.DETECTING_RFID) {
        setCurrentScreen(APP_STATE.VALIDATING_RFID);
        updateStatus(`Card: ${cardRawData}. Validating...`);
        try {
          const validationResult: { status: boolean; message?: string } = await invoke('validate_rfid_card_command', { cardData: cardRawData });
          if (validationResult.status) {
            const parts = cardRawData.split('_');
            const newRfidData = { raw: cardRawData, main: parts[1] || "N/A", sub: parts[2] || "N/A" };
            setRfidData(newRfidData);
            updateStatus(`RFID Validated: ${newRfidData.main}. Proceeding to payment.`);
            setCurrentScreen(APP_STATE.AWAITING_PAYMENT);
          } else {
            updateStatus(`RFID Validation Failed: ${validationResult.message || 'Unknown error'}. Tap card again.`, true);
            setCurrentScreen(APP_STATE.DETECTING_RFID);
          }
        } catch (e: any) {
          updateStatus(`Error validating RFID: ${e.toString()}. Tap card again.`, true);
          console.error("RFID validation error:", e);
          setCurrentScreen(APP_STATE.DETECTING_RFID);
        }
      }
    });
    return () => { unlistenRfid.then(f => f()); };
  }, []); // Run once on mount


  const handlePaymentConfirm = async () => {
    if (!rfidData) return;
    setCurrentScreen(APP_STATE.PROCESSING_PAYMENT);
    updateStatus("Processing payment...");
    try {
        const paymentResult: PaymentResultDetails = await invoke('rfid_payment_command', {
            cardData: rfidData.raw,
            amount: paymentAmount
        });
        if (paymentResult.success) {
            updateStatus("Payment successful. Printing slip...");
            await invoke('print_payment_slip_command', { slipDetails: paymentResult });
            setCurrentScreen(APP_STATE.PAYMENT_SUCCESS_AWAIT_QR);
            updateStatus("Payment slip printed. Scan GatePass QR Code.");
        } else {
            updateStatus(`Payment Failed: ${paymentResult.message || 'Unknown error'}. Try again or contact support.`, true);
            setCurrentScreen(APP_STATE.AWAITING_PAYMENT); // Allow retry
        }
    } catch (e: any) {
        updateStatus(`Payment Error: ${e.toString()}. Try again or contact support.`, true);
        console.error("Payment error:", e);
        setCurrentScreen(APP_STATE.AWAITING_PAYMENT);
    }
  };
  
  let qrInputTimeout: NodeJS.Timeout | null = null;
  const handleQrInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = e.target.value;
    setQrInputValue(newValue); // For controlled input if needed

    if (qrInputTimeout) clearTimeout(qrInputTimeout);
    qrInputTimeout = setTimeout(async () => {
      const capturedQr = newValue.trim(); // Use the latest value from state or directly
      if (capturedQr && (currentScreen === APP_STATE.PAYMENT_SUCCESS_AWAIT_QR || currentScreen === APP_STATE.AWAITING_NEXT_QR)) {
        console.log("QR Value to process:", capturedQr);
        setQrInputValue(""); // Clear input
        if (qrInputRef.current) qrInputRef.current.value = ""; // Also clear the actual input field

        updateStatus(`GatePass ${capturedQr} scanned. Validating...`);
        try {
          const validationMsg: string = await invoke('process_gatepass_qr_command', { qrData: capturedQr });
          setScannedGatePasses(prev => [...prev, { code: capturedQr, valid: true, details: validationMsg }]);
          setCurrentScreen(APP_STATE.AWAITING_NEXT_QR);
          updateStatus(`GatePass ${capturedQr} OK. Scan next or proceed.`);
        } catch (e: any) {
          updateStatus(`Invalid GatePass ${capturedQr}: ${e.toString()}. Try again.`, true);
          setScannedGatePasses(prev => [...prev, { code: capturedQr, valid: false, error: e.toString() }]);
        }
      }
    }, 200); // Adjust timeout as needed for scanner speed
  };

  const handleProceedWithGatePasses = async () => {
    if (scannedGatePasses.filter(gp => gp.valid).length === 0) {
        updateStatus("No valid GatePasses scanned to proceed.", true);
        return;
    }
    setCurrentScreen(APP_STATE.PROCESSING_FINAL);
    try {
        const gateInData = {
            transaction_id_str: String(Date.now()), 
            rfid_info: rfidData,
            gate_passes: scannedGatePasses.filter(gp => gp.valid).map(gp => gp.code),
            gate_name: gateName
        };
        updateFinalProcessingProgress(20, "Sending GateIn to SOAP service...");
        const gateInResult: CGSTReceiveResult = await invoke('send_gate_in_command', { data: gateInData });

        if (gateInResult.status && gateInResult.result_cms && gateInResult.result_cms.length > 0) {
            updateFinalProcessingProgress(50, "GateIn successful. Printing CMS...");
            const cmsPrintPayload = { 
                transaction_id: gateInResult.transaction_id_str || "N/A_CMS", 
                cms_items: gateInResult.result_cms, 
                gate_name: gateName, 
                tag_number: rfidData?.main, 
                tractor_number: rfidData?.sub 
            };
            await invoke('print_cms_command', { cmsData: cmsPrintPayload });
            
            updateFinalProcessingProgress(75, "CMS Printed. Sending TruckIn confirmation...");
            await invoke('send_truck_in_command', { transactionIdStr: gateInResult.transaction_id_str || "N/A_TRUCKIN" });
            
            updateFinalProcessingProgress(90, "Transaction complete! Opening portal.");
            await invoke('control_adam_portal_command', { action: "open" });
            updateFinalProcessingProgress(100, "Portal opened. Thank you!");
        } else {
            throw new Error(gateInResult.result || "GateIn processing failed at backend.");
        }
        setTimeout(resetAppState, 4000); 
    } catch (e: any) {
        console.error("Final processing error:", e);
        updateStatus(`Final processing error: ${e.toString()}`, true);
        setCurrentScreen(APP_STATE.ERROR);
    }
  };

  const resetAppState = () => {
    setRfidData(null);
    setScannedGatePasses([]);
    setCurrentScreen(APP_STATE.DETECTING_RFID);
    updateStatus("Detecting RFID...");
    invoke('start_rfid_detection_command'); // Re-start polling if necessary
  };


  const renderCurrentView = () => {
    switch (currentScreen) {
      case APP_STATE.DETECTING_RFID:
      case APP_STATE.VALIDATING_RFID: // Show same UI for validating
        return (
          <div className="view-container detecting-rfid-view">
            <RFIDIcon />
            <h1>{currentScreen === APP_STATE.VALIDATING_RFID ? "Validating RFID..." : "Detecting RFID..."}</h1>
            <p>Please hold your vehicle tag near the RFID reader.</p>
            <Progress value={currentScreen === APP_STATE.VALIDATING_RFID ? 50 : 20} className="w-4/5 h-3 my-6 bg-white/40" indicatorClassName="bg-white" />
            <p className="scan-status-text">{statusBarText}</p>
          </div>
        );
      case APP_STATE.AWAITING_PAYMENT:
      case APP_STATE.PROCESSING_PAYMENT:
        return (
          <div className="view-container payment-view">
            <Card className="w-full max-w-md bg-white/10 border-white/20 text-white">
              <CardHeader>
                <CardTitle className="text-2xl">Payment Required</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                {rfidData && (
                    <div className="rfid-info-display bg-payment-green-dark/80 text-white p-3 rounded-md">
                        <RFIDIcon />
                        <div>
                            <span className="rfid-main">{rfidData.main}</span>
                            <span className="rfid-sub">{rfidData.sub}</span>
                        </div>
                        <CheckmarkIcon />
                    </div>
                )}
                <p className="text-xl">Amount: <span className="font-bold">{paymentAmount.toLocaleString('id-ID', { style: 'currency', currency: 'IDR' })}</span></p>
                <p id="payment-status-message" className="text-lg">
                    {currentScreen === APP_STATE.PROCESSING_PAYMENT ? "Processing payment... Please wait." : "Please tap card again to confirm payment."}
                </p>
              </CardContent>
              <CardFooter>
                <Button 
                    onClick={handlePaymentConfirm} 
                    disabled={currentScreen === APP_STATE.PROCESSING_PAYMENT}
                    className="w-full bg-white text-payment-green-dark hover:bg-gray-200 text-lg py-3"
                >
                  {currentScreen === APP_STATE.PROCESSING_PAYMENT ? "Processing..." : "Confirm Payment (Tap Card)"}
                </Button>
              </CardFooter>
            </Card>
          </div>
        );
      case APP_STATE.PAYMENT_SUCCESS_AWAIT_QR:
        return (
          <div className="view-container scan-gatepass-view">
            {rfidData && <RFIDInfoDisplay rfidData={rfidData} />}
             <Card className="w-full max-w-md bg-white/10 border-white/20 text-white">
                <CardHeader className="items-center"> <QRIcon /> <CardTitle>Scan Gatepass</CardTitle> </CardHeader>
                <CardContent>
                    <div className="qr-placeholder my-4"><div className="qr-frame"></div></div>
                    <Input 
                        ref={qrInputRef}
                        type="text" 
                        value={qrInputValue} 
                        onChange={handleQrInputChange} 
                        placeholder="QR Data will appear here" 
                        className="text-center bg-transparent border-white/30 focus:ring-white/50"
                        autoFocus
                    />
                </CardContent>
             </Card>
            <p className="scan-status-text mt-4" id="gatepass-scan-progress">Waiting for Gatepass scan...</p>
          </div>
        );
      case APP_STATE.AWAITING_NEXT_QR:
        return (
          <div className="view-container scan-next-gatepass-view">
            {rfidData && <RFIDInfoDisplay rfidData={rfidData} />}
            <Card className="w-full max-w-md bg-white/10 border-white/20 text-white mb-4">
                <CardHeader>
                    <CardTitle className="flex items-center justify-center"><img src="./assets/qr-icon-white.svg" alt="QR" className="status-icon-small mr-2 filter-none" /> Last: {scannedGatePasses.length > 0 ? scannedGatePasses[scannedGatePasses.length-1].code : 'N/A'}</CardTitle>
                </CardHeader>
                <CardContent className="max-h-24 overflow-y-auto text-sm">
                    {scannedGatePasses.map((gp, index) => (
                        <div key={index} className={gp.valid ? 'text-green-300' : 'text-red-300'}>
                            {gp.code} - {gp.valid ? (gp.details || 'OK') : (gp.error || 'Invalid')}
                        </div>
                    ))}
                </CardContent>
            </Card>
            <Card className="w-full max-w-md bg-white/10 border-white/20 text-white items-center">
                <CardHeader className="items-center"><QRIcon /><CardTitle>Scan Next Gatepass</CardTitle></CardHeader>
                <CardContent>
                    <div className="qr-placeholder my-4"><div className="qr-frame"></div></div>
                    <Input 
                        ref={qrInputRef}
                        type="text" 
                        value={qrInputValue} 
                        onChange={handleQrInputChange} 
                        placeholder="Next QR Data" 
                        className="text-center bg-transparent border-white/30"
                        autoFocus
                    />
                </CardContent>
            </Card>
            <Button onClick={handleProceedWithGatePasses} className="proceed-btn mt-4">→</Button>
            <p className="scan-status-text mt-2" id="auto-proceed-status">Or scan next gatepass</p>
          </div>
        );
      case APP_STATE.PROCESSING_FINAL:
         return (
            <div className="view-container processing-view">
                <h2 className="text-3xl font-bold mb-6">Processing Transaction</h2>
                <Progress value={finalProgress} className="w-4/5 h-4 my-6 bg-gray-700" indicatorClassName="bg-green-500" />
                <p id="final-processing-status" className="text-xl mt-4">{finalProgressMsg}</p>
            </div>
        );
      case APP_STATE.ERROR:
        return (
            <div className="view-container error-view">
                <h2 className="text-3xl font-bold text-red-400 mb-4">Operation Failed</h2>
                <p className="text-lg mb-6">{statusBarText}</p>
                <Button onClick={resetAppState} className="bg-yellow-500 hover:bg-yellow-600 text-black font-semibold py-3 px-6">
                    Try Again
                </Button>
            </div>
        );
      default:
        return <div className="view-container"><h1>Unknown State</h1></div>;
    }
  };

  // RFIDInfoDisplay component for reuse
  const RFIDInfoDisplay = ({ rfidData }: { rfidData: RFIDData | null }) => (
    <div className="rfid-info-display bg-rfid-info-bg text-rfid-info-text p-3 rounded-lg mb-5 w-full max-w-sm mx-auto">
      <img src="./assets/rfid-icon-white.svg" alt="RFID" className="w-8 h-8 mr-3 filter-none" /> {/* Assuming this icon is colored and doesn't need inversion */}
      <div>
        <span className="block font-bold text-lg">{rfidData?.main || "N/A"}</span>
        <span className="block text-sm">{rfidData?.sub || "N/A"}</span>
      </div>
      {rfidData && <CheckmarkIcon />}
    </div>
  );


  return (
    <div className="app-container">
      <header>
        <img src="./assets/app_logo.png" alt="Logo" id="app-logo" />
        <div id="gate-info">{gateName}</div>
      </header>
      <main id="main-content">
        {renderCurrentView()}
      </main>
      <footer>
        <div id="status-bar" className={isErrorStatus ? 'text-red-400' : 'text-gray-300'}>
          {statusBarText}
        </div>
        {/* Hidden input for global QR capture */}
        <Input 
            ref={qrInputRef} 
            type="text" 
            id="global-qr-catcher" 
            onInput={handleQrInputChange} // Use onInput for rapid char-by-char
            className="absolute -left-full w-px h-px opacity-0" // Visually hidden but focusable
        />
      </footer>
    </div>
  );
}

export default App;
EOF

# Update src/main.tsx to import App.css or index.css
# (The exact import depends on what `create-tauri-app --template react-ts` generates)
MAIN_TSX_PATH="src/main.tsx"
if [ -f "$CSS_FILE_PATH" ] && [ -f "$MAIN_TSX_PATH" ]; then
    # Check if CSS import already exists
    if ! grep -q "$CSS_FILE_PATH" "$MAIN_TSX_PATH"; then
        # Prepend import statement
        echo "Importing CSS into $MAIN_TSX_PATH..."
        echo -e "import './${CSS_FILE_PATH#src/}';\n$(cat $MAIN_TSX_PATH)" > "$MAIN_TSX_PATH"
    fi
else
    echo "Warning: $MAIN_TSX_PATH or $CSS_FILE_PATH not found. Manual CSS import might be needed in your main React/TS file."
fi


# # --- Backend Files (src-tauri/src/) ---
# echo "Creating/Overwriting Rust backend files in src-tauri/src/..."
# # For main.rs, config_handler.rs, rfid_handler.rs, adam_handler.rs, soap_services.rs, rest_services.rs, print_handler.rs
# # **COPY THE FULL CONTENT FROM THE PREVIOUS SHELL SCRIPT'S OUTPUT FOR THESE FILES HERE**
# # Example for one file (repeat for all .rs files mentioned above):
# # cat > src-tauri/src/main.rs << 'EOF'
# # // Paste the full content of main.rs from the previous script output here
# # EOF
# # ... and so on for all other .rs files
# # For brevity in this script, I'm assuming you'll copy them manually or adapt the previous script's cat commands.
# # **This is a critical step: The backend logic needs to be in place.**
# # Make sure the `config_handler.rs` file is created as its `AppConfigState` is used by `main.rs`

# echo "Placeholder: Ensure Rust backend files (main.rs, config_handler.rs, etc.) are copied into src-tauri/src/ from the previous script version."
# echo "For example, copy the content of 'main.rs_previous_backup' into 'src-tauri/src/main.rs' etc."


# # --- Update src-tauri/Cargo.toml ---
# echo "Updating src-tauri/Cargo.toml (manual review and merge of dependencies is CRITICAL)..."
# # Append dependencies. User MUST manually merge these with existing ones from `create-tauri-app`.
# echo "" >> src-tauri/Cargo.toml
# echo "# === Dependencies to MANUALLY MERGE into your [dependencies] section of src-tauri/Cargo.toml ===" >> src-tauri/Cargo.toml
# echo "# === Remove duplicates and ensure features are correct for Tauri v2. ====" >> src-tauri/Cargo.toml
# echo "# serde_json = \"1.0\"" >> src-tauri/Cargo.toml
# echo "# serde = { version = \"1.0\", features = [\"derive\"] }" >> src-tauri/Cargo.toml
# echo "# tokio = { version = \"1\", features = [\"macros\", \"rt-multi-thread\", \"time\", \"sync\"] }" >> src-tauri/Cargo.toml
# echo "# serialport = \"4.2.2\" # Or a Tauri v2 compatible serial plugin e.g. tauri-plugin-serial" >> src-tauri/Cargo.toml
# echo "# tokio-modbus = \"0.8.0\" # Or your chosen Modbus crate" >> src-tauri/Cargo.toml
# echo "# reqwest = { version = \"0.12\", features = [\"json\"] } # Check latest reqwest for v0.12.x or current" >> src-tauri/Cargo.toml
# echo "# printpdf = \"0.6.1\" # Or genpdf, or another PDF/printing solution" >> src-tauri/Cargo.toml
# echo "# qrcodegen = \"1.8.0\"" >> src-tauri/Cargo.toml
# echo "# aes-gcm = \"0.10.3\"" >> src-tauri/Cargo.toml
# echo "# sha2 = \"0.10.8\"" >> src-tauri/Cargo.toml
# echo "# log = \"0.4\"" >> src-tauri/Cargo.toml
# echo "# env_logger = \"0.11.3\"" >> src-tauri/Cargo.toml
# echo "# anyhow = \"1.0\"" >> src-tauri/Cargo.toml
# echo "# thiserror = \"1.0\"" >> src-tauri/Cargo.toml
# echo "# base64 = \"0.22.1\"" >> src-tauri/Cargo.toml
# echo "# chrono = { version = \"0.4\", features = [\"serde\"] }" >> src-tauri/Cargo.toml
# echo "# tauri = { version = \"2.0.0-beta\", features = [\"plugin-shell\", \"plugin-dialog\", \"plugin-fs\"] } # Example Tauri v2 features" >> src-tauri/Cargo.toml
# echo "# If using tauri-plugin-serial for v2:" >> src-tauri/Cargo.toml
# echo "# tauri-plugin-serial = { git = \"https://github.com/tauri-apps/plugins-workspace\", branch = \"v2\", features=[\"protocol-asset\"]}" >> src-tauri/Cargo.toml
# echo "# =========================================================================" >> src-tauri/Cargo.toml
# echo
# echo "Make sure your main tauri dependency in src-tauri/Cargo.toml looks something like:"
# echo "tauri = { version = \"2.0.0-beta.18\", features = [\"devtools\"] } # Adjust version & features"
# echo "And add plugin features like:"
# echo "# tauri-plugin-shell = { git = \"https://github.com/tauri-apps/plugins-workspace\", branch = \"v2\" }"
# echo "# tauri-plugin-log = { git = \"https://github.com/tauri-apps/plugins-workspace\", branch = \"v2\", features = [\"colored\"] }"
# echo

# echo
# echo "---------------------------------------------------------------------"
# echo "Project '$ACTUAL_PROJECT_DIR' setup script finished."
# echo "---------------------------------------------------------------------"
# echo "Next steps:"
# echo "1. You are NOW IN: $(pwd)"
# echo "2. **CRITICAL**: Manually open 'src-tauri/Cargo.toml' in a text editor."
# echo "   Carefully add or merge the Rust dependencies listed at the end of the file"
# echo "   into the [dependencies] section. Ensure versions are compatible with Tauri v2."
# echo "3. **CRITICAL**: Copy the content of the Rust (.rs) files from the *previous* script's output"
# echo "   (or your saved versions) into the respective files in 'src-tauri/src/'."
# echo "   This script only created empty placeholders for them to avoid excessive length."
# echo "4. Install frontend dependencies using pnpm: pnpm install"
# echo "5. Ensure Tauri v2 prerequisites are installed on your Linux system:"
# echo "   https://v2.tauri.app/start/prerequisites/"
# echo "6. Review all generated files. The React components (App.tsx, views) are basic placeholders"
# echo "   and will need significant work to implement the full UI and state logic."
# echo "7. Run the development server: pnpm tauri dev"
# echo "---------------------------------------------------------------------"
