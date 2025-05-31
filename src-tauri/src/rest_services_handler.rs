use reqwest::Client as ReqwestClient;
use serde::Deserialize;
use crate::config_handler::{AppConfigState, AppConfig}; // Import AppConfig
use tauri::State;
use crate::rfid_handler::PaymentResultDetails; // Ensure this path is correct

#[derive(serde::Serialize, Debug)]
pub struct SaveOutPaymentInfoPayload {
    #[serde(rename = "trId")] pub tr_id: i32,
    pub cardnumber: Option<String>,
    pub deduct_amount: i32,
    pub card_remain_balance: i32,
    pub cardtype: Option<String>,
    pub midreader: Option<String>,
    pub tidreader: Option<String>,
    pub transcounter: Option<String>,
    pub transactiondata: Option<String>,
    pub deduct_status: Option<String>,
    pub stid: Option<String>,
    #[serde(rename = "gateId")] pub gate_id: Option<String>,
    pub mode: Option<String>,
    #[serde(rename = "datePayment")] pub date_payment: Option<String>,
}

#[derive(Deserialize, Debug)]
pub struct CaCMToolCommonResponse {
    #[serde(rename = "Status")] pub status: Option<String>, // Case sensitive
    #[serde(rename = "Message")] pub message: Option<String>,
}

#[tauri::command]
pub async fn save_payment_to_cacm_tool_command(
    config_state: State<'_, AppConfigState>,
    payment_details: PaymentResultDetails, // Comes from rfid_handler after successful payment
    original_transaction_id: i32, // The autogate transaction ID, not payment system's
    stid_tag_number: String,
) -> Result<CaCMToolCommonResponse, String> {
    let config = config_state.0.lock().unwrap().clone(); // Clone to use after lock is dropped
    
    let client = ReqwestClient::new();
    let endpoint = "/api/TransactionDetail"; 
    let url = format!("{}{}", config.cacm_tool_url.trim_end_matches('/'), endpoint);

    let payload = SaveOutPaymentInfoPayload {
        tr_id: original_transaction_id,
        cardnumber: Some(payment_details.card_no),
        deduct_amount: payment_details.amount_paid as i32,
        card_remain_balance: payment_details.balance_after as i32,
        cardtype: Some("N/A".to_string()), // Or from payment_details if available
        midreader: Some("READER_MID_SIM".to_string()), // Placeholder
        tidreader: Some("READER_TID_SIM".to_string()), // Placeholder
        transcounter: Some("N/A".to_string()),       // Placeholder
        transactiondata: Some(payment_details.transaction_id), // This is likely the payment system's TX ID
        deduct_status: Some(if payment_details.success { "00".to_string() } else { "02".to_string() }),
        stid: Some(stid_tag_number),
        gate_id: Some(config.gate_name.clone()),
        mode: Some("AUTOGATE_V2".to_string()), // Or specific gate mode
        date_payment: Some(payment_details.timestamp),
    };

    log::debug!("REST: Calling CaCMTool SavePayment. URL: {}, Payload: {:?}", url, payload);

    match client.post(&url).json(&payload).send().await {
        Ok(response) => {
            let status_code = response.status();
            if status_code.is_success() {
                response.json::<CaCMToolCommonResponse>().await
                    .map_err(|e| format!("REST: Failed to parse CaCMTool JSON response: {}", e))
            } else {
                let err_text = response.text().await.unwrap_or_else(|_| "Unknown API error content".to_string());
                log::error!("REST: CaCMTool API request failed (status {}): {}", status_code, err_text);
                Err(format!("CaCMTool API request failed (status {}): {}", status_code, err_text))
            }
        }
        Err(e) => {
            log::error!("REST: Failed to send request to CaCMTool: {}", e);
            Err(format!("Failed to send request to CaCMTool: {}", e))
        }
    }
}