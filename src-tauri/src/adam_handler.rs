// src-tauri/src/adam_handler.rs
use crate::config_handler::AppConfigState;
use tauri::State;
use tokio_modbus::client::Context;
use tokio_modbus::prelude::*;

const PORTAL_OPEN_COIL_ADDRESS: u16 = 0x0000;
const PUSH_BUTTON_1_STATUS_REGISTER: u16 = 0x0000;

async fn connect_adam_tcp(ip: &str, port: u16) -> Result<Context, String> {
    let socket_addr_str = format!("{}:{}", ip, port);
    let socket_addr = socket_addr_str
        .parse()
        .map_err(|e| format!("Invalid ADAM device address '{}': {}", socket_addr_str, e))?;
    log::debug!("ADAM: Connecting to {}:{}", ip, port);
    tcp::connect(socket_addr)
        .await
        .map_err(|e| format!("ADAM: Modbus TCP connect error to {}: {}", socket_addr_str, e))
}

#[tauri::command]
pub async fn control_adam_portal_command(
    action: String,
    config_state: State<'_, AppConfigState>,
) -> Result<String, String> {
    let config = config_state.0.lock().unwrap().clone();
    let mut ctx = connect_adam_tcp(&config.adam_portal_ip, config.adam_portal_port).await?;

    match action.to_lowercase().as_str() {
        "open" => {
            log::info!("ADAM Portal: Sending OPEN command to {}:{}", config.adam_portal_ip, config.adam_portal_port);
            ctx.write_single_coil(PORTAL_OPEN_COIL_ADDRESS, true).await
                .map_err(|e| format!("ADAM: Failed to write 'open' coil (ON): {}", e))?;
            tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;
            ctx.write_single_coil(PORTAL_OPEN_COIL_ADDRESS, false).await
                .map_err(|e| format!("ADAM: Failed to write 'open' coil (OFF): {}", e))?;
            Ok(format!("ADAM Portal command '{}' sent.", action))
        }
        "close" => {
            log::info!("ADAM Portal: Sending CLOSE command (simulated) to {}:{}", config.adam_portal_ip, config.adam_portal_port);
            Ok(format!("ADAM Portal command '{}' sent (simulated).", action))
        }
        _ => Err(format!("Unknown ADAM portal action: {}", action)),
    }
}

#[tauri::command]
pub async fn get_adam_button_status_command(
    config_state: State<'_, AppConfigState>,
    button_id: u16,
) -> Result<bool, String> {
    let config = config_state.0.lock().unwrap().clone();
    let mut ctx = connect_adam_tcp(&config.adam_button_ip, config.adam_button_port).await?;
    let address_to_read = PUSH_BUTTON_1_STATUS_REGISTER + button_id;
    log::debug!("ADAM Button: Reading discrete input {} from {}:{}", address_to_read, config.adam_button_ip, config.adam_button_port);
    
    // Assuming read_discrete_inputs returns Result<Vec<bool>, ModbusError>
    // And not Result<Result<Vec<bool>, ExceptionCode>, ModbusError>
    // If it were nested, the error message was correct. Let's try the direct approach first.
    // If the error "method not found in Result<Vec<bool>, ExceptionCode>" persists,
    // it means read_discrete_inputs returns a nested Result like Result<Result<Vec<bool>, ModbusExceptionCode>, ModbusError>
    // For now, assuming it's Result<Vec<bool>, ModbusError>:
    match ctx.read_discrete_inputs(address_to_read, 1).await {
        Ok(Ok(status_vec)) => status_vec.get(0).copied().ok_or_else(|| "No data for button".to_string()),
        Ok(Err(e)) => Err(format!("ADAM Button Modbus exception: {:?}", e)),
        Err(e) => Err(format!("ADAM Button read error: {}", e)),
    }
}