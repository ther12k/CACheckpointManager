import { useState, useEffect, useRef } from "react";
// For Tauri v2, core contains invoke. If you are on v1, it's from /tauri
import { invoke } from "@tauri-apps/api/core"; // Verify this path for your Tauri version
import { listen, UnlistenFn } from "@tauri-apps/api/event";

// Shadcn/UI components
import { Button } from "@/components/ui/button";
import { Card, CardHeader, CardTitle, CardContent, CardFooter } from "@/components/ui/card"; // Added CardContent
import { Input } from "@/components/ui/input";
import { Progress } from "@/components/ui/progress";

// --- Icon Components ---
const RFIDIcon = () => <img src="@/assets/rfid-icon-white.svg" alt="RFID" className="w-12 h-12 md:w-16 md:h-16 mb-4" />;
const QRIcon = () => <img src="@/assets/qr-icon-white.svg" alt="QR" className="w-16 h-16 md:w-20 md:h-20 mb-3" />;
const CheckmarkIcon = () => <img src="@/assets/checkmark-white.svg" alt="Success" className="w-6 h-6 md:w-8 md:h-8 text-white" />;

// --- Types and States ---
const APP_STATE = {
  DETECTING_RFID: 'DETECTING_RFID',
  VALIDATING_RFID: 'VALIDATING_RFID',
  AWAITING_PAYMENT: 'AWAITING_PAYMENT',
  PROCESSING_PAYMENT: 'PROCESSING_PAYMENT',
  PAYMENT_SUCCESS_AWAIT_QR: 'PAYMENT_SUCCESS_AWAIT_QR',
  AWAITING_NEXT_QR: 'AWAITING_NEXT_QR',
  PROCESSING_FINAL: 'PROCESSING_FINAL',
  ERROR: 'ERROR',
} as const;

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
}

interface PaymentResultDetails {
  success: boolean; 
  message: string; 
  transaction_id: string;
  card_no: string; 
  amount_paid: number; 
  balance_after: number; 
  timestamp: string;
}

interface CMSDataItem {
  daily_seq?: string; 
  cntr_number?: string;
  truck_police_num?: string; 
  truck_in_time?: string;
}

interface CGSTReceiveResult {
  status: boolean; 
  result?: string; 
  transaction_id_str?: string;
  result_cms?: CMSDataItem[];
}

interface EventPayload<T = string> {
  message: T;
  data?: any;
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

  // Timers - Fixed typing
  const rfidProgressTimerRef = useRef<NodeJS.Timeout | null>(null);
  const gatepassCountdownTimerRef = useRef<NodeJS.Timeout | null>(null);
  const nextGatepassCountdownTimerRef = useRef<NodeJS.Timeout | null>(null);
  const qrInputTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  const updateStatus = (text: string, isError: boolean = false) => {
    setStatusBarText(text);
    setIsErrorStatus(isError);
  };

  const clearAllTimers = () => {
    if (rfidProgressTimerRef.current) clearTimeout(rfidProgressTimerRef.current);
    if (gatepassCountdownTimerRef.current) clearTimeout(gatepassCountdownTimerRef.current);
    if (nextGatepassCountdownTimerRef.current) clearTimeout(nextGatepassCountdownTimerRef.current);
    if (qrInputTimeoutRef.current) clearTimeout(qrInputTimeoutRef.current);
  };

  const resetAppState = () => {
    console.log("Resetting app state");
    clearAllTimers();
    setRfidData(null);
    setScannedGatePasses([]);
    setQrInputValue("");
    setCurrentScreen(APP_STATE.DETECTING_RFID);
    updateStatus("Detecting RFID...");
    invoke('start_rfid_detection_command').catch(e => console.error("Error restarting RFID detection:", e));
  };
  
  // Initial settings load and RFID listener setup
  useEffect(() => {
    let unlistenRfid: Promise<UnlistenFn> | null = null;

    async function setup() {
      try {
        const settings: AppSettings = await invoke('get_app_settings');
        setGateName(settings.gate_name || "Unknown Gate"); // << If this fails, gateName remains "Loading..." or becomes "Gate Error"
        setPaymentAmount(settings.emoney_deduct_price || 17000);
        console.log("App settings loaded:", settings);
        
        updateStatus("Initializing RFID Reader...");
        await invoke('initialize_rfid_reader_command');
        await invoke('start_rfid_detection_command');
        // Only update status if still in an initial state, to prevent overriding later messages
        if (currentScreen === APP_STATE.DETECTING_RFID || currentScreen === APP_STATE.VALIDATING_RFID) {
          updateStatus("Scanning for RFID tag...");
        }

        unlistenRfid = listen<EventPayload>('rfid_card_tapped', (event) => { // Make sure EventPayload matches Rust
          console.log("Frontend received rfid_card_tapped:", event.payload.message);
          handleRfidTap(event.payload.message); // Pass the actual message string
        });

      } catch (e: any) {
        console.error("Failed to load app settings or init RFID:", e);
        setGateName("Gate Error"); // << THIS IS LIKELY WHERE "Gate Error" COMES FROM
        updateStatus(`Error initializing: ${e.toString()}`, true);
        setCurrentScreen(APP_STATE.ERROR); // Good to show an error screen
      }
    }
    
    setup();
    
    return () => { // Cleanup function
      if (unlistenRfid) {
        unlistenRfid.then(f => f()).catch(console.error); // Ensure unlistenRfid is not null before calling .then
      }
      clearAllTimers();
    };
  }, []); // Empty dependency array is correct for running once on mount

  const handleRfidTap = async (cardRawData: string) => {
    if (currentScreen === APP_STATE.DETECTING_RFID) {
      setCurrentScreen(APP_STATE.VALIDATING_RFID);
      updateStatus(`Card: ${cardRawData}. Validating...`);
      try {
        const validationResult: { status: boolean; message?: string } = await invoke('validate_rfid_card_command', { cardData: cardRawData });
        if (validationResult.status) {
          const parts = cardRawData.split('_');
          const newRfidData = { raw: cardRawData, main: parts[1] || cardRawData, sub: parts[2] || "" };
          setRfidData(newRfidData);
          updateStatus(`RFID Validated: ${newRfidData.main}. Proceed to payment.`);
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
  };

  const handlePaymentConfirm = async () => {
    if (!rfidData || currentScreen !== APP_STATE.AWAITING_PAYMENT) return;

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
        setTimeout(() => {
          if (qrInputRef.current) qrInputRef.current.focus();
        }, 100);
      } else {
        updateStatus(`Payment Failed: ${paymentResult.message || 'Unknown error'}. Try again or contact support.`, true);
        setCurrentScreen(APP_STATE.AWAITING_PAYMENT);
      }
    } catch (e: any) {
      updateStatus(`Payment Error: ${e.toString()}. Try again or contact support.`, true);
      console.error("Payment error:", e);
      setCurrentScreen(APP_STATE.AWAITING_PAYMENT);
    }
  };

  const handleQrInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = e.target.value;
    setQrInputValue(newValue);

    if (qrInputTimeoutRef.current) clearTimeout(qrInputTimeoutRef.current);
    qrInputTimeoutRef.current = setTimeout(async () => {
      const capturedQr = newValue.trim().replace(/(\r\n|\n|\r)/gm, "");
      
      if (capturedQr && (currentScreen === APP_STATE.PAYMENT_SUCCESS_AWAIT_QR || currentScreen === APP_STATE.AWAITING_NEXT_QR)) {
        console.log("QR Value to process:", capturedQr);
        if (qrInputRef.current) {
          qrInputRef.current.value = "";
          setQrInputValue("");
        }

        updateStatus(`GatePass ${capturedQr} scanned. Validating...`);
        try {
          const validationMsg: string = await invoke('process_gatepass_qr_command', { qrData: capturedQr });
          setScannedGatePasses(prev => [...prev, { code: capturedQr, valid: true, details: validationMsg }]);
          setCurrentScreen(APP_STATE.AWAITING_NEXT_QR);
          updateStatus(`GatePass ${capturedQr} OK. Scan next or proceed.`);
          setTimeout(() => {
            if (qrInputRef.current) qrInputRef.current.focus();
          }, 100);
        } catch (e: any) {
          updateStatus(`Invalid GatePass ${capturedQr}: ${e.toString()}. Try again.`, true);
          setScannedGatePasses(prev => [...prev, { code: capturedQr, valid: false, error: e.toString() }]);
          setTimeout(() => {
            if (qrInputRef.current) qrInputRef.current.focus();
          }, 100);
        }
      }
    }, 250);
  };

  const handleProceedWithGatePasses = async () => {
    const validGatePasses = scannedGatePasses.filter(gp => gp.valid);
    if (validGatePasses.length === 0) {
      updateStatus("No valid GatePasses scanned to proceed.", true);
      return;
    }
    
    setCurrentScreen(APP_STATE.PROCESSING_FINAL);
    try {
      const gateInData = {
        transaction_id_str: String(Date.now()),
        rfid_info: rfidData,
        gate_passes: validGatePasses.map(gp => gp.code),
        gate_name: gateName
      };
      
      setFinalProgress(20);
      setFinalProgressMsg("Sending GateIn to SOAP service...");
      const gateInResult: CGSTReceiveResult = await invoke('send_gate_in_command', { data: gateInData });

      if (gateInResult.status && gateInResult.result_cms && gateInResult.result_cms.length > 0) {
        setFinalProgress(50);
        setFinalProgressMsg("GateIn successful. Printing CMS...");
        const cmsPrintPayload = {
          transaction_id: gateInResult.transaction_id_str || "N/A_CMS",
          cms_items: gateInResult.result_cms,
          gate_name: gateName,
          tag_number: rfidData?.main,
          tractor_number: rfidData?.sub
        };
        await invoke('print_cms_command', { cmsData: cmsPrintPayload });
        
        setFinalProgress(75);
        setFinalProgressMsg("CMS Printed. Sending TruckIn confirmation...");
        await invoke('send_truck_in_command', { transactionIdStr: gateInResult.transaction_id_str || "N/A_TRUCKIN" });
        
        setFinalProgress(90);
        setFinalProgressMsg("Transaction complete! Opening portal.");
        await invoke('control_adam_portal_command', { action: "open" });
        setFinalProgress(100);
        setFinalProgressMsg("Portal opened. Thank you!");
        
        setTimeout(resetAppState, 4000);
      } else {
        throw new Error(gateInResult.result || "GateIn processing failed at backend.");
      }
    } catch (e: any) {
      console.error("Final processing error:", e);
      updateStatus(`Final processing error: ${e.toString()}`, true);
      setCurrentScreen(APP_STATE.ERROR);
    }
  };

  // Countdown timer effects
  useEffect(() => {
    if (currentScreen === APP_STATE.PAYMENT_SUCCESS_AWAIT_QR) {
      let countdown = 10;
      const updateCountdown = () => {
        const el = document.getElementById('gatepass-countdown');
        if (el) el.textContent = String(countdown);
      };
      
      updateCountdown();
      gatepassCountdownTimerRef.current = setInterval(() => {
        countdown--;
        updateCountdown();
        if (countdown <= 0) {
          if (gatepassCountdownTimerRef.current) clearInterval(gatepassCountdownTimerRef.current);
          if (currentScreen === APP_STATE.PAYMENT_SUCCESS_AWAIT_QR) {
            updateStatus("Gatepass scan timeout. Resetting.", true);
            setTimeout(resetAppState, 1500);
          }
        }
      }, 1000);
    }
    
    return () => {
      if (gatepassCountdownTimerRef.current) clearInterval(gatepassCountdownTimerRef.current);
    };
  }, [currentScreen]);

  useEffect(() => {
    if (currentScreen === APP_STATE.AWAITING_NEXT_QR) {
      let countdown = 10;
      const updateCountdown = () => {
        const el = document.getElementById('next-gatepass-countdown');
        if (el) el.textContent = String(countdown);
      };

      updateCountdown();
      nextGatepassCountdownTimerRef.current = setInterval(() => {
        countdown--;
        updateCountdown();
        if (countdown <= 0) {
          if (nextGatepassCountdownTimerRef.current) clearInterval(nextGatepassCountdownTimerRef.current);
          if (currentScreen === APP_STATE.AWAITING_NEXT_QR) {
            handleProceedWithGatePasses();
          }
        }
      }, 1000);
    }
    
    return () => {
      if (nextGatepassCountdownTimerRef.current) clearInterval(nextGatepassCountdownTimerRef.current);
    };
  }, [currentScreen, scannedGatePasses]);

  // RFIDInfoDisplay component
  const RFIDInfoDisplay = ({ rfidData }: { rfidData: RFIDData | null }) => (
    <div className="rfid-info-display bg-green-600/80 text-white p-4 rounded-lg mb-6 w-full max-w-md mx-auto flex items-center justify-between shadow-md">
      <div className="flex items-center">
        <img src="/assets/rfid-icon-white.svg" alt="RFID" className="w-10 h-10 mr-4" />
        <div>
          <span className="block font-bold text-xl">{rfidData?.main || "N/A"}</span>
          <span className="block text-base opacity-90">{rfidData?.sub || "N/A"}</span>
        </div>
      </div>
      {rfidData && <CheckmarkIcon />}
    </div>
  );

  const renderCurrentView = () => {
    switch (currentScreen) {
      case APP_STATE.DETECTING_RFID:
      case APP_STATE.VALIDATING_RFID:
        return (
          <div className="view-container detecting-rfid-view flex flex-col items-center justify-center min-h-[60vh] text-white text-center">
            <RFIDIcon />
            <h1 className="text-4xl font-bold mb-4">
              {currentScreen === APP_STATE.VALIDATING_RFID ? "Validating RFID..." : "Detecting RFID..."}
            </h1>
            <p className="text-lg mb-6">Please hold your vehicle tag near the RFID reader.</p>
            <Progress 
              value={currentScreen === APP_STATE.VALIDATING_RFID ? 50 : (rfidData ? 100 : 20)}
              className="w-4/5 h-3 my-6 bg-white/30"
            />
            <p className="scan-status-text text-base">{statusBarText}</p>
          </div>
        );
        
      case APP_STATE.AWAITING_PAYMENT:
      case APP_STATE.PROCESSING_PAYMENT:
        return (
          <div className="view-container payment-view flex flex-col items-center justify-center min-h-[60vh]">
            <Card className="w-full max-w-md bg-white/20 border-white/30 text-white shadow-xl">
              <CardHeader>
                <CardTitle className="text-3xl font-semibold text-center">Payment Required</CardTitle>
              </CardHeader>
              <CardContent className="space-y-5 pt-6">
                {rfidData && <RFIDInfoDisplay rfidData={rfidData} />}
                <p className="text-xl text-center">
                  Amount: <span className="font-bold">{paymentAmount.toLocaleString('id-ID', { style: 'currency', currency: 'IDR' })}</span>
                </p>
                <p className="text-lg min-h-[2em] text-center">
                  {currentScreen === APP_STATE.PROCESSING_PAYMENT ? "Processing payment... Please wait." : "Click button below to confirm payment."}
                </p>
              </CardContent>
              <CardFooter>
                <Button 
                  onClick={handlePaymentConfirm} 
                  disabled={currentScreen === APP_STATE.PROCESSING_PAYMENT}
                  className="w-full bg-white text-green-700 hover:bg-gray-200 text-lg py-6 font-semibold"
                >
                  {currentScreen === APP_STATE.PROCESSING_PAYMENT ? "Processing..." : "Confirm Payment"}
                </Button>
              </CardFooter>
            </Card>
          </div>
        );
        
      case APP_STATE.PAYMENT_SUCCESS_AWAIT_QR:
        return (
          <div className="view-container scan-gatepass-view flex flex-col items-center justify-center min-h-[60vh] text-white">
            {rfidData && <RFIDInfoDisplay rfidData={rfidData} />}
            <Card className="w-full max-w-md bg-white/20 border-white/30 text-white shadow-xl">
              <CardHeader className="items-center pt-6">
                <QRIcon />
                <CardTitle className="text-3xl mt-2">Scan Gatepass</CardTitle>
              </CardHeader>
              <CardContent className="pt-4 text-center">
                <div className="qr-placeholder my-6 w-32 h-32 mx-auto border-2 border-dashed border-white/50 rounded-lg flex items-center justify-center">
                  <div className="text-white/70">QR Scanner</div>
                </div>
                <p className="text-sm opacity-80">QR data will be captured automatically.</p>
              </CardContent>
            </Card>
            <p className="scan-status-text mt-6 text-lg text-center">
              Waiting for Gatepass scan... <span id="gatepass-countdown" className="font-bold">10</span>s
            </p>
          </div>
        );
        
      case APP_STATE.AWAITING_NEXT_QR:
        return (
          <div className="view-container scan-next-gatepass-view flex flex-col items-center justify-center min-h-[60vh] text-white">
            {rfidData && <RFIDInfoDisplay rfidData={rfidData} />}
            
            <Card className="w-full max-w-md bg-purple-800/50 border-purple-400/50 text-white mb-4 shadow-lg">
              <CardHeader className="pb-2 pt-4">
                <CardTitle className="flex items-center justify-center text-xl">
                  <QRIcon />
                  Last: {scannedGatePasses.length > 0 ? scannedGatePasses[scannedGatePasses.length-1].code : 'N/A'}
                </CardTitle>
              </CardHeader>
              <CardContent className="max-h-20 overflow-y-auto text-xs px-4 pb-3">
                {scannedGatePasses.map((gp, index) => (
                  <div key={index} className={`py-0.5 ${gp.valid ? 'text-green-300' : 'text-red-300'}`}>
                    {gp.code} - {gp.valid ? (gp.details || 'OK') : (gp.error || 'Invalid')}
                  </div>
                ))}
              </CardContent>
            </Card>
            
            <Card className="w-full max-w-md bg-white/20 border-white/30 text-white shadow-xl">
              <CardHeader className="items-center pt-6">
                <QRIcon />
                <CardTitle className="text-3xl mt-2">Scan Next Gatepass</CardTitle>
              </CardHeader>
              <CardContent className="pt-4 text-center">
                <div className="qr-placeholder my-6 w-32 h-32 mx-auto border-2 border-dashed border-white/50 rounded-lg flex items-center justify-center">
                  <div className="text-white/70">QR Scanner</div>
                </div>
                <p className="text-sm opacity-80">QR data will be captured automatically.</p>
              </CardContent>
            </Card>
            
            <Button 
              onClick={handleProceedWithGatePasses} 
              className="mt-5 text-4xl bg-green-600 hover:bg-green-700 text-white px-8 py-4"
            >
              ➔
            </Button>
            <p className="scan-status-text mt-3 text-base text-center">
              Auto-proceed in <span id="next-gatepass-countdown" className="font-bold">10</span>s or scan next
            </p>
          </div>
        );
        
      case APP_STATE.PROCESSING_FINAL:
        return (
          <div className="view-container processing-view flex flex-col items-center justify-center min-h-[60vh] text-white">
            <h2 className="text-3xl font-bold mb-6">Processing Transaction</h2>
            <Progress 
              value={finalProgress} 
              className="w-4/5 h-4 my-6 bg-gray-600"
            />
            <p className="text-xl mt-4 text-center">{finalProgressMsg}</p>
          </div>
        );
        
      case APP_STATE.ERROR:
        return (
          <div className="view-container error-view flex flex-col items-center justify-center min-h-[60vh] text-white">
            <h2 className="text-3xl font-bold text-red-400 mb-4">Operation Failed</h2>
            <p className="text-lg mb-6 text-center">{statusBarText}</p>
            <Button 
              onClick={resetAppState} 
              className="bg-yellow-500 hover:bg-yellow-600 text-black font-semibold py-3 px-6 text-lg"
            >
              Try Again
            </Button>
          </div>
        );
        
      default:
        return (
          <div className="view-container flex flex-col items-center justify-center min-h-[60vh] text-white">
            <h1>Unknown Application State</h1>
          </div>
        );
    }
  };

  return (
    <div className="app-container min-h-screen bg-gradient-to-br from-blue-900 to-purple-900 flex flex-col">
      <header className="flex items-center justify-between p-4 bg-black/20">
        <img src="/assets/app_logo.png" alt="Logo" className="h-10 md:h-12" />
        <div className="text-xl md:text-2xl text-white font-semibold">{gateName}</div>
      </header>
      
      <main className="flex-grow overflow-hidden">
        {renderCurrentView()}
      </main>
      
      <footer className="mt-auto pt-4 pb-2">
        <div className={`text-center text-sm px-4 ${isErrorStatus ? 'text-red-300' : 'text-gray-200'}`}>
          {statusBarText}
        </div>
        <Input 
          ref={qrInputRef} 
          type="text" 
          value={qrInputValue}
          onChange={handleQrInputChange}
          className="fixed -left-full w-px h-px opacity-0 pointer-events-none"
          autoComplete="off"
        />
      </footer>
    </div>
  );
}

export default App;