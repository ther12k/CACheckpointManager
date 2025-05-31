use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::Manager;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct AppConfig {
    pub cgs_gateway_url: String,
    pub device_gateway_url: String,
    pub cacm_tool_url: String,
    pub gate_name: String,
    pub gate_type: i32, // 0 for IN, 1 for OUT
    pub emoney_reader_port: String,
    pub emoney_baud_rate: u32,
    pub emoney_init_key: String,
    pub emoney_deduct_price: f64,
    pub adam_portal_ip: String,
    pub adam_portal_port: u16,
    pub adam_button_ip: String,
    pub adam_button_port: u16,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            cgs_gateway_url: "https://cusmod-ca.multiterminal.co.id/cgsin02/services/services.asmx".to_string(),
            device_gateway_url: "https://cusmod-ca.multiterminal.co.id/DeviceGateway/DeviceGatewayService.asmx".to_string(),
            cacm_tool_url: "http://cacmtool.halotec.my.id".to_string(),
            gate_name: "GATE_A01".to_string(),
            gate_type: 0, // IN
            emoney_reader_port: if cfg!(windows) { 
                "COM1".to_string() 
            } else { 
                "/dev/ttyUSB0".to_string() 
            },
            emoney_baud_rate: 38400,
            emoney_init_key: "FE45DF39F44A4866AD7153136E051B0A".to_string(),
            emoney_deduct_price: 17000.0,
            adam_portal_ip: "10.0.0.10".to_string(),
            adam_portal_port: 502,
            adam_button_ip: "10.0.0.11".to_string(),
            adam_button_port: 502,
        }
    }
}

pub struct AppConfigState(pub Mutex<AppConfig>);

fn get_config_path(app_handle: &tauri::AppHandle) -> Result<PathBuf, Box<dyn std::error::Error>> {
    // Use the new Tauri 2.0 API
    let config_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| format!("Failed to get app data directory: {}", e))?;
    
    if !config_dir.exists() {
        fs::create_dir_all(&config_dir)?;
    }
    
    Ok(config_dir.join("app_settings.json"))
}

#[tauri::command]
pub fn get_app_settings(
    app_handle: tauri::AppHandle, 
    state: tauri::State<'_, AppConfigState>
) -> Result<AppConfig, String> {
    let path = get_config_path(&app_handle)
        .map_err(|e| format!("Failed to get config path: {}", e))?;
    
    if path.exists() {
        log::info!("Loading settings from: {:?}", path);
        let content = fs::read_to_string(&path)
            .map_err(|e| format!("Failed to read settings file: {}", e))?;
        
        match serde_json::from_str(&content) {
            Ok(loaded_config) => {
                let mut app_config_state = state.0.lock()
                    .map_err(|e| format!("Failed to lock config state: {}", e))?;
                *app_config_state = loaded_config;
                Ok(app_config_state.clone())
            }
            Err(e) => {
                log::error!("Failed to parse settings JSON, using default from state: {}", e);
                let app_config_state = state.0.lock()
                    .map_err(|e| format!("Failed to lock config state: {}", e))?;
                Ok(app_config_state.clone())
            }
        }
    } else {
        log::info!("Settings file not found at {:?}, returning default from state.", path);
        let app_config_state = state.0.lock()
            .map_err(|e| format!("Failed to lock config state: {}", e))?;
        
        // Optionally save the default config here if it doesn't exist
        let default_config = app_config_state.clone();
        drop(app_config_state); // Release the lock before calling save
        
        // Save default config for next time
        match save_app_settings(app_handle, default_config.clone(), state) {
            Ok(_) => log::info!("Default config saved successfully"),
            Err(e) => log::warn!("Failed to save default config: {}", e),
        }
        
        Ok(default_config)
    }
}

#[tauri::command]
pub fn save_app_settings(
    app_handle: tauri::AppHandle, 
    settings: AppConfig, 
    state: tauri::State<'_, AppConfigState>
) -> Result<(), String> {
    let path = get_config_path(&app_handle)
        .map_err(|e| format!("Failed to get config path: {}", e))?;
    
    log::info!("Saving settings to: {:?}", path);
    
    let content = serde_json::to_string_pretty(&settings)
        .map_err(|e| format!("Failed to serialize settings: {}", e))?;
    
    fs::write(&path, content)
        .map_err(|e| format!("Failed to write settings file: {}", e))?;
    
    // Update the state
    let mut app_config_state = state.0.lock()
        .map_err(|e| format!("Failed to lock config state: {}", e))?;
    *app_config_state = settings;
    
    log::info!("Settings saved successfully");
    Ok(())
}

// Helper function to initialize the config state
pub fn initialize_config_state(app_handle: &tauri::AppHandle) -> AppConfigState {
    let default_config = AppConfig::default();
    
    // Try to load existing config
    let config_path = match get_config_path(app_handle) {
        Ok(path) => path,
        Err(e) => {
            log::error!("Failed to get config path during initialization: {}", e);
            return AppConfigState(Mutex::new(default_config));
        }
    };
    
    if config_path.exists() {
        match fs::read_to_string(&config_path) {
            Ok(content) => {
                match serde_json::from_str::<AppConfig>(&content) {
                    Ok(loaded_config) => {
                        log::info!("Loaded existing config from: {:?}", config_path);
                        return AppConfigState(Mutex::new(loaded_config));
                    }
                    Err(e) => {
                        log::error!("Failed to parse existing config: {}", e);
                    }
                }
            }
            Err(e) => {
                log::error!("Failed to read existing config: {}", e);
            }
        }
    }
    
    log::info!("Using default config");
    AppConfigState(Mutex::new(default_config))
}