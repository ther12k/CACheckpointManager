use std::time::Duration;
use tauri::{State, Manager, Emitter};
use tokio::sync::mpsc;
use crate::config_handler::AppConfigState;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, Ordering};
// use serialport; // Uncomment when implementing actual serial logic

#[derive(Clone, serde::Serialize, serde::Deserialize, Debug)] // Added Deserialize
pub struct RfidDataCacheForEvent {
    pub raw: String,
    pub main: String,
    pub sub: String,
}

#[derive(Clone, serde::Serialize, serde::Deserialize, Debug)] // <<< Ensure Deserialize is here
pub struct PaymentResultDetails {
    pub success: bool,
    pub message: String,
    pub transaction_id: String,
    pub card_no: String,
    pub amount_paid: f64,
    pub balance_after: f64,
    pub timestamp: String,
    pub gate_name: String, // <<< Ensure this field exists
}

#[derive(serde::Serialize)]
struct EventPayload {
    message: String,
    data: Option<String>,
}

// Thread-safe RFID reader implementation
pub struct RFIDReader {
    port_name: String,
    baud_rate: u32,
    // For actual implementation, use Arc<Mutex<Box<dyn serialport::SerialPort + Send>>>
    // This allows safe sharing between threads
}

impl RFIDReader {
    pub fn new(port_name: &str, baud_rate: u32) -> Self {
        RFIDReader {
            port_name: port_name.to_string(),
            baud_rate,
        }
    }

    pub fn init_port(&mut self) -> Result<(), String> {
        log::info!("RFID: Initializing port {} @ {} baud", self.port_name, self.baud_rate);
        
        // TODO: Implement actual serial port opening
        // let port = serialport::new(&self.port_name, self.baud_rate)
        //     .timeout(Duration::from_millis(1000))
        //     .open()
        //     .map_err(|e| format!("Failed to open port {}: {}", self.port_name, e))?;
        
        // Send initialization commands here
        // Example from C# EmoneyReaderHelper.Init():
        // - Send wake-up command
        // - Configure reader settings
        // - Verify communication
        
        log::info!("RFID: Port {} initialized successfully", self.port_name);
        Ok(())
    }

    pub fn poll_for_card(&mut self) -> Option<String> {
        // TODO: Implement actual card detection
        // Send command to check for card presence
        // Parse response and extract card UID/data
        // Return card data if present, None otherwise
        
        // For now, return None (no simulation in polling method)
        None
    }

    pub fn process_payment(&mut self, card_data_raw: &str, amount: f64) -> Result<PaymentResultDetails, String> {
        log::info!("Processing payment for card: {}, amount: ${:.2}", card_data_raw, amount);
        
        // TODO: Implement actual payment processing
        // 1. Validate card data
        // 2. Check current balance
        // 3. Process deduction
        // 4. Update card balance
        // 5. Return transaction details
        
        // Simulate processing time
        std::thread::sleep(Duration::from_millis(500));
        
        // Simulated successful payment
        Ok(PaymentResultDetails {
            success: true,
            message: "Payment processed successfully".to_string(),
            transaction_id: format!("TXN_{}", chrono::Utc::now().timestamp_millis()),
            card_no: self.extract_card_number(card_data_raw),
            amount_paid: amount,
            balance_after: 95000.0, // Simulated balance
            timestamp: chrono::Utc::now().to_rfc3339(),
            gate_name: "SIMULATED_GATE".to_string(), // Provide actual gate name if available
        })
    }

    fn extract_card_number(&self, raw_data: &str) -> String {
        // Extract meaningful card number from raw data
        // This depends on your card data format
        if let Some(card_part) = raw_data.split('_').nth(1) {
            card_part.replace("RFID_C", "").replace("_B", "")
        } else {
            "UNKNOWN".to_string()
        }
    }
}

// Improved manager with better thread safety
pub struct RFIDManager {
    reader: Arc<Mutex<Option<RFIDReader>>>,
    is_polling: Arc<AtomicBool>,
    card_event_sender: Arc<Mutex<Option<mpsc::Sender<String>>>>,
    polling_handle: Arc<Mutex<Option<tokio::task::JoinHandle<()>>>>,
}

impl RFIDManager {
    pub fn new() -> Self {
        RFIDManager {
            reader: Arc::new(Mutex::new(None)),
            is_polling: Arc::new(AtomicBool::new(false)),
            card_event_sender: Arc::new(Mutex::new(None)),
            polling_handle: Arc::new(Mutex::new(None)),
        }
    }

    pub fn is_polling(&self) -> bool {
        self.is_polling.load(Ordering::Acquire)
    }

    pub fn stop_polling(&self) -> Result<(), String> {
        if !self.is_polling() {
            return Ok(());
        }

        // Signal stop
        self.is_polling.store(false, Ordering::Release);
        
        // Close the sender to signal the event listener to stop
        if let Ok(mut sender_guard) = self.card_event_sender.lock() {
            *sender_guard = None;
        }

        // Wait for polling task to finish
        if let Ok(mut handle_guard) = self.polling_handle.lock() {
            if let Some(handle) = handle_guard.take() {
                handle.abort();
            }
        }

        log::info!("RFID polling stopped");
        Ok(())
    }
}

pub type RFIDManagerState = Arc<Mutex<RFIDManager>>;

#[tauri::command]
pub async fn initialize_rfid_reader_command(
    config_state: State<'_, AppConfigState>,
    rfid_manager_state: State<'_, RFIDManagerState>,
) -> Result<String, String> {
    let config = config_state.0.lock()
        .map_err(|_| "Failed to acquire config lock")?;
    
    let manager = rfid_manager_state.lock()
        .map_err(|_| "Failed to acquire manager lock")?;

    log::info!(
        "Initializing RFID reader - Port: {}, Baud: {}", 
        config.emoney_reader_port, config.emoney_baud_rate
    );

    let mut reader = RFIDReader::new(&config.emoney_reader_port, config.emoney_baud_rate);
    reader.init_port()?;

    // Store the initialized reader
    if let Ok(mut reader_guard) = manager.reader.lock() {
        *reader_guard = Some(reader);
    } else {
        return Err("Failed to store reader instance".to_string());
    }

    log::info!("RFID Reader initialized successfully");
    Ok("RFID Reader initialized and ready for use".to_string())
}

#[tauri::command]
pub async fn start_rfid_detection_command(
    app_handle: tauri::AppHandle,
    config_state: State<'_, AppConfigState>,
    rfid_manager_state: State<'_, RFIDManagerState>,
) -> Result<(), String> {
    let manager = rfid_manager_state.lock()
        .map_err(|_| "Failed to acquire manager lock")?;

    if manager.is_polling() {
        log::info!("RFID detection already running");
        return Ok(());
    }

    // Ensure reader is initialized
    {
        let reader_guard = manager.reader.lock()
            .map_err(|_| "Failed to acquire reader lock")?;
        if reader_guard.is_none() {
            return Err("RFID Reader not initialized. Call initialize_rfid_reader_command first.".to_string());
        }
    }

    let config = config_state.0.lock()
        .map_err(|_| "Failed to acquire config lock")?
        .clone();

    // Set up communication channel
    let (tx, mut rx) = mpsc::channel::<String>(32);
    
    // Store sender in manager
    if let Ok(mut sender_guard) = manager.card_event_sender.lock() {
        *sender_guard = Some(tx.clone());
    }

    // Set polling flag
    manager.is_polling.store(true, Ordering::Release);

    // Clone necessary data for tasks
    let reader_arc = Arc::clone(&manager.reader);
    let is_polling_arc = Arc::clone(&manager.is_polling);
    let app_handle_clone = app_handle.clone();

    // Spawn polling task
    let polling_handle = tokio::spawn(async move {
        log::info!("RFID polling task started");
        let poll_interval = Duration::from_millis(100); // Adjust as needed
        let mut sim_counter = 0u32; // For simulation

        while is_polling_arc.load(Ordering::Acquire) {
            // Simulate card detection (remove in production)
            sim_counter += 1;
            if sim_counter % 50 == 0 { // Every ~5 seconds
                let simulated_card = format!("SIM_CARD_{:04X}", sim_counter);
                log::debug!("Simulated card detected: {}", simulated_card);
                
                if tx.send(simulated_card).await.is_err() {
                    log::warn!("Failed to send card data - receiver may have been dropped");
                    break;
                }
            }

            // TODO: Replace simulation with actual polling
            // if let Ok(mut reader_guard) = reader_arc.lock() {
            //     if let Some(ref mut reader) = *reader_guard {
            //         if let Some(card_data) = reader.poll_for_card() {
            //             log::debug!("Card detected: {}", card_data);
            //             if tx.send(card_data).await.is_err() {
            //                 log::warn!("Failed to send card data");
            //                 break;
            //             }
            //         }
            //     }
            // }

            tokio::time::sleep(poll_interval).await;
        }

        log::info!("RFID polling task finished");
    });

    // Store polling handle
    if let Ok(mut handle_guard) = manager.polling_handle.lock() {
        *handle_guard = Some(polling_handle);
    }

    // Spawn event emission task
    tokio::spawn(async move {
        log::info!("RFID event listener started");
        
        while let Some(card_data) = rx.recv().await {
            log::info!("Card tapped: {}", card_data);
            
            let event_payload = EventPayload {
                message: card_data.clone(),
                data: Some(card_data),
            };

            if let Err(e) = app_handle_clone.emit("rfid_card_tapped", &event_payload) {
                log::error!("Failed to emit rfid_card_tapped event: {}", e);
            }
        }
        
        log::info!("RFID event listener finished");
    });

    log::info!("RFID detection started successfully");
    Ok(())
}

#[tauri::command]
pub async fn stop_rfid_detection_command(
    rfid_manager_state: State<'_, RFIDManagerState>,
) -> Result<(), String> {
    let manager = rfid_manager_state.lock()
        .map_err(|_| "Failed to acquire manager lock")?;
    
    manager.stop_polling()?;
    Ok(())
}

#[tauri::command]
pub async fn rfid_payment_command(
    rfid_manager_state: State<'_, RFIDManagerState>,
    card_data: String, 
    amount: f64
) -> Result<PaymentResultDetails, String> {
    let manager = rfid_manager_state.lock()
        .map_err(|_| "Failed to acquire manager lock")?;

    let mut reader_guard = manager.reader.lock()
        .map_err(|_| "Failed to acquire reader lock")?;

    match reader_guard.as_mut() {
        Some(reader) => {
            reader.process_payment(&card_data, amount)
        }
        None => {
            Err("RFID Reader not initialized. Call initialize_rfid_reader_command first.".to_string())
        }
    }
}

#[tauri::command]
pub async fn get_rfid_status_command(
    rfid_manager_state: State<'_, RFIDManagerState>,
) -> Result<serde_json::Value, String> {
    let manager = rfid_manager_state.lock()
        .map_err(|_| "Failed to acquire manager lock")?;

    let reader_initialized = {
        let reader_guard = manager.reader.lock()
            .map_err(|_| "Failed to acquire reader lock")?;
        reader_guard.is_some()
    };

    Ok(serde_json::json!({
        "initialized": reader_initialized,
        "polling": manager.is_polling(),
        "status": if reader_initialized { "ready" } else { "not_initialized" }
    }))
}