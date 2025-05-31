
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

# # Update src/main.tsx to import App.css or index.css
# # (The exact import depends on what `create-tauri-app --template react-ts` generates)
# MAIN_TSX_PATH="src/main.tsx"
# if [ -f "$CSS_FILE_PATH" ] && [ -f "$MAIN_TSX_PATH" ]; then
#     # Check if CSS import already exists
#     if ! grep -q "$CSS_FILE_PATH" "$MAIN_TSX_PATH"; then
#         # Prepend import statement
#         echo "Importing CSS into $MAIN_TSX_PATH..."
#         echo -e "import './${CSS_FILE_PATH#src/}';\n$(cat $MAIN_TSX_PATH)" > "$MAIN_TSX_PATH"
#     fi
# else
#     echo "Warning: $MAIN_TSX_PATH or $CSS_FILE_PATH not found. Manual CSS import might be needed in your main React/TS file."
# fi
