// src-tauri/src/lib.rs
use tauri::Manager;
use std::sync::{Arc, Mutex}; // Added Arc

// Declare your modules
pub mod config_handler;
pub mod rfid_handler;
pub mod adam_handler;
pub mod soap_services_handler;
pub mod rest_services_handler;
pub mod print_handler;

#[derive(Clone, serde::Serialize)]
struct EventPayload {
  message: String,
  data: Option<serde_json::Value>,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Initialize logging here if not done in main.rs, or ensure it's only called once.
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    log::info!("Starting Checkpoint Manager Tauri application (Rust Backend v2 - from lib.rs)...");

    let initial_config = config_handler::AppConfig::default();
    let rfid_manager = rfid_handler::RFIDManager::new(); // This is an instance of RFIDManager

    // The state managed should be the Arc<Mutex<RFIDManager>>
    // RFIDManagerState is the type alias for Arc<Mutex<RFIDManager>>
    let rfid_manager_state: rfid_handler::RFIDManagerState = Arc::new(Mutex::new(rfid_manager));

    tauri::Builder::default()
        // Register all plugins
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_shell::init())

        // Manage application state
        .manage(config_handler::AppConfigState(Mutex::new(initial_config)))
        .manage(rfid_manager_state) // Manage the Arc<Mutex<RFIDManager>>
        .setup(|app| {
            log::info!("Tauri setup hook initiated from lib.rs.");
            let handle = app.handle();

            // Initialize config state by loading from file or using defaults
            // The get_app_settings command also updates the state.
            let config_state_manager: tauri::State<config_handler::AppConfigState> = app.state();
            match config_handler::get_app_settings(handle.clone(), config_state_manager) {
                Ok(loaded_cfg) => {
                    log::info!("Config loaded/initialized successfully during setup: {:?}", loaded_cfg);
                }
                Err(e) => {
                    log::error!("Failed to get/initialize config during setup, defaults will be used: {}", e);
                }
            }

            #[cfg(debug_assertions)]
            {
                match app.get_webview_window("main") {
                    Some(window) => {
                        log::debug!("Opening devtools for main window.");
                        window.open_devtools();
                    },
                    None => {
                        log::error!("Could not get main window to open devtools.");
                    }
                }
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            config_handler::get_app_settings,
            config_handler::save_app_settings,
            rfid_handler::initialize_rfid_reader_command,
            rfid_handler::start_rfid_detection_command,
            rfid_handler::stop_rfid_detection_command, // Keep this
            rfid_handler::rfid_payment_command,
            rfid_handler::get_rfid_status_command,   // Keep this
            soap_services_handler::validate_rfid_card_command,
            soap_services_handler::send_gate_in_command,
            soap_services_handler::send_truck_in_command,
            print_handler::print_payment_slip_command,
            print_handler::print_cms_command,
            adam_handler::control_adam_portal_command,
            adam_handler::get_adam_button_status_command, // Ensure this is registered if it exists
            process_gatepass_qr_command
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application from lib.rs");
}

#[tauri::command]
async fn process_gatepass_qr_command(qr_data: String) -> Result<String, String> {
    log::info!("Backend (lib.rs): Received GatePass QR for validation: {}", qr_data);
    if qr_data.to_uppercase().contains("INVALID") || qr_data.len() < 4 {
        log::warn!("GatePass QR validation failed: {}", qr_data);
        Err(format!("Invalid GatePass format or content: {}", qr_data))
    } else {
        log::info!("GatePass QR {} validated successfully (simulated).", qr_data);
        Ok(format!("GatePass {} accepted and processed.", qr_data))
    }
}