// src-tauri/src/print_handler.rs
use std::fs::File;
use std::io::Write;
// use tauri::PathResolver; // Can be removed if not used as a direct type annotation
use tauri_plugin_shell::ShellExt; // For app_handle.shell().open()
use tauri::Manager; // For app_handle.path()

// Ensure correct path to your PaymentResultDetails and CMSData structs
use crate::rfid_handler::PaymentResultDetails;
use crate::soap_services_handler::CMSData;

#[derive(serde::Serialize, serde::Deserialize, Debug)]
pub struct CmsSlipCommandPayload {
    pub transaction_id: String,
    #[serde(rename = "cmsItems")]
    pub cms_items: Option<Vec<CMSData>>,
    #[serde(rename = "gateName")]
    pub gate_name: String,
    #[serde(rename = "tagNumber")]
    pub tag_number: Option<String>,
    #[serde(rename = "tractorNumber")]
    pub tractor_number: Option<String>,
}

#[tauri::command]
pub async fn print_payment_slip_command(
    app_handle: tauri::AppHandle,
    slip_details: PaymentResultDetails
) -> Result<String, String> {
    log::info!("PRINT: Generating payment slip for TX: {}", slip_details.transaction_id);

    let content = format!(
        "-- PAYMENT SLIP --\n\
        Gate: {}\n\
        Transaction ID: {}\n\
        Card No: {}\n\
        Amount Paid: {:.2}\n\
        Balance After: {:.2}\n\
        Timestamp: {}\n\
        ------------------\n(Simulated Print)",
        slip_details.gate_name,
        slip_details.transaction_id,
        slip_details.card_no,
        slip_details.amount_paid,
        slip_details.balance_after,
        slip_details.timestamp
    );

    // Correct way to get temp_dir using AppHandle in Tauri v2
    let temp_dir_path = app_handle.path().temp_dir()
        .map_err(|_| "PRINT Error: Failed to get temp dir".to_string())?;
    let file_name = format!("payment_slip_{}.txt", slip_details.transaction_id);
    let file_path = temp_dir_path.join(file_name);

    let mut file = File::create(&file_path)
        .map_err(|e| format!("PRINT Error: Failed to create slip file: {}", e))?;
    file.write_all(content.as_bytes())
        .map_err(|e| format!("PRINT Error: Failed to write to slip file: {}",e))?;

    log::info!("PRINT: Payment slip generated at: {:?}", file_path);

    app_handle.shell().open(file_path.to_string_lossy().to_string(), None)
        .map_err(|e| format!("PRINT Error: Failed to open slip file: {}", e.to_string()))?;

    Ok(format!("Payment slip {} opened.", file_path.display()))
}

#[tauri::command]
pub async fn print_cms_command(
    app_handle: tauri::AppHandle,
    cms_data: CmsSlipCommandPayload
) -> Result<String, String> {
    log::info!("PRINT: Generating CMS slip for TX ID: {}", cms_data.transaction_id);
    let mut content = String::new();
    content.push_str("-- CMS SLIP --\n");
    content.push_str(&format!("Gate: {}\n", cms_data.gate_name));
    content.push_str(&format!("Transaction ID: {}\n", cms_data.transaction_id));
    content.push_str(&format!("Tag: {}, Tractor: {}\n",
        cms_data.tag_number.as_deref().unwrap_or("N/A"),
        cms_data.tractor_number.as_deref().unwrap_or("N/A")
    ));
    content.push_str("------------------\n");
    if let Some(items) = &cms_data.cms_items {
        for item in items {
            content.push_str(&format!(
                "Seq: {}, CN: {}, Police: {}, Time: {}\n",
                item.daily_seq.as_deref().unwrap_or("N/A"),
                item.cntr_number.as_deref().unwrap_or("N/A"),
                item.truck_police_num.as_deref().unwrap_or("N/A"),
                item.truck_in_time.as_deref().unwrap_or("N/A"),
            ));
        }
    } else {
        content.push_str("No CMS items found.\n");
    }
    content.push_str("------------------\n(Simulated Print)\n");

    // Correct way to get temp_dir using AppHandle in Tauri v2
    let temp_dir_path = app_handle.path().temp_dir()
        .map_err(|_| "PRINT Error: Failed to get temp dir".to_string())?;
    let file_name = format!("cms_slip_{}.txt", cms_data.transaction_id);
    let file_path = temp_dir_path.join(file_name);

    let mut file = File::create(&file_path)
        .map_err(|e| format!("PRINT Error: Failed to create CMS file: {}", e))?;
    file.write_all(content.as_bytes())
        .map_err(|e| format!("PRINT Error: Failed to write to CMS file: {}",e))?;

    log::info!("PRINT: CMS slip generated at: {:?}", file_path);

    app_handle.shell().open(file_path.to_string_lossy().to_string(), None)
        .map_err(|e| format!("PRINT Error: Failed to open CMS file: {}", e.to_string()))?;

    Ok(format!("CMS slip {} opened.", file_path.display()))
}