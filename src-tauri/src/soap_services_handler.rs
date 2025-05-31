// src-tauri/src/soap_services.rs
use reqwest;
use serde::{Deserialize, Serialize};
use crate::config_handler::AppConfigState;
use tauri::State;
use base64::{Engine as _, engine::general_purpose};

// ... (CGSMessageResult, CMSData, CGSTReceiveResult remain the same) ...
#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct CGSMessageResult {
    #[serde(rename = "Status")]
    pub status: bool,
    #[serde(rename = "Message")]
    pub message: Option<String>,
    #[serde(rename = "InnerMessage")]
    pub inner_message: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, Clone, Default)]
pub struct CMSData {
    #[serde(rename = "dailySeq")] pub daily_seq: Option<String>,
    #[serde(rename = "laneNum")] pub lane_num: Option<String>,
    #[serde(rename = "terminalId")] pub terminal_id: Option<String>,
    #[serde(rename = "resultStatus")] pub result_status: Option<String>,
    #[serde(rename = "resultMessage")] pub result_message: Option<String>,
    #[serde(rename = "cntrNumber")] pub cntr_number: Option<String>,
    #[serde(rename = "cntrIsocode")] pub cntr_isocode: Option<String>,
    #[serde(rename = "cntrStatus")] pub cntr_status: Option<String>,
    #[serde(rename = "cntrGrossWeight")] pub cntr_gross_weight: Option<String>,
    #[serde(rename = "cntrNettWeight")] pub cntr_nett_weight: Option<String>,
    #[serde(rename = "cntrAxle")] pub cntr_axle: Option<String>,
    #[serde(rename = "cntrSeal")] pub cntr_seal: Option<String>,
    #[serde(rename = "truckId")] pub truck_id: Option<String>,
    #[serde(rename = "truckPoliceNum")] pub truck_police_num: Option<String>,
    #[serde(rename = "truckInTime")] pub truck_in_time: Option<String>,
    pub ei: Option<String>,
    pub autohold: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct CGSTReceiveResult {
    pub status: bool,
    pub result: Option<String>,
    pub transaction_id_str: Option<String>,
    #[serde(rename = "resultCMS")]
    pub result_cms: Option<Vec<CMSData>>,
}


#[derive(Serialize, Deserialize, Debug)] // Added Deserialize here
pub struct GateInCommandData {
    pub transaction_id_str: String,
    // Ensure RfidDataCacheForEvent also derives Deserialize if it's not just for events
    pub rfid_info: Option<super::rfid_handler::RfidDataCacheForEvent>,
    pub gate_passes: Vec<String>,
    pub gate_name: String,
}

async fn post_soap_request(url: &str, soap_action: &str, body: String) -> Result<String, String> {
    let client = reqwest::Client::new();
    log::trace!("SOAP Request to: {}, Action: {}", url, soap_action);
    log::trace!("SOAP Body: {}", body);
    let response = client.post(url)
        .header("Content-Type", "text/xml; charset=utf-8")
        .header("SOAPAction", soap_action)
        .body(body)
        .send().await
        .map_err(|e| e.to_string())?;
    let status = response.status();
    let response_text = response.text().await.map_err(|e| e.to_string())?;
    log::trace!("SOAP Response Status: {}", status);
    log::trace!("SOAP Response Body (first 500 chars): {}", response_text.chars().take(500).collect::<String>());
    if status.is_success() {
        Ok(response_text)
    } else {
        Err(format!("SOAP request failed with status {}: {}", status, response_text))
    }
}

fn get_auth_header_xml(gate_name: &str) -> String {
    let username = general_purpose::STANDARD.encode(gate_name);
    let password = general_purpose::STANDARD.encode(format!("{}PWD", gate_name));
    format!(r#"<AuthHeader xmlns="http://halotec-indonesia.com/"><UserName>{}</UserName><Password>{}</Password></AuthHeader>"#, username, password)
}

#[tauri::command]
pub async fn validate_rfid_card_command(config_state: State<'_, AppConfigState>, card_data: String) -> Result<CGSMessageResult, String> {
    let config = config_state.0.lock().unwrap().clone();
    let parts: Vec<&str> = card_data.split('_').collect();
    let proximity_id = parts.get(0).unwrap_or(&"").to_string();
    let tid_from_card = parts.get(1).unwrap_or(&card_data.as_str()).to_string();
    log::info!("SOAP: Validating RFID: Prox={}, TID={}, Gate={}", proximity_id, tid_from_card, config.gate_name);
    let auth_header_xml = get_auth_header_xml(&config.gate_name);
    let soap_body = format!(r#"<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Header>{auth_header_xml}</soap:Header><soap:Body><CheckTIDStatus xmlns="http://halotec-indonesia.com/"><tid>{tid_from_card}</tid><gateId>{gate_id}</gateId><proximityId>{proximity_id}</proximityId></CheckTIDStatus></soap:Body></soap:Envelope>"#, auth_header_xml=auth_header_xml, tid_from_card=tid_from_card, gate_id=config.gate_name, proximity_id=proximity_id);
    match post_soap_request(&config.cgs_gateway_url, "http://halotec-indonesia.com/CheckTIDStatus", soap_body).await {
        Ok(response_xml) => {
            // Simplified parsing, ideally use an XML parser
            if response_xml.contains("<Status>true</Status>") || response_xml.contains("<Status>True</Status>") {
                let msg = response_xml.split("<Message>").nth(1).and_then(|s| s.split("</Message>").next()).unwrap_or("Validated").to_string();
                Ok(CGSMessageResult { status: true, message: Some(msg), inner_message: None })
            } else {
                let err_msg = response_xml.split("<Message>").nth(1).and_then(|s| s.split("</Message>").next()).unwrap_or("Validation Failed").to_string();
                log::warn!("RFID Validation SOAP response indicates failure: {}", err_msg);
                Err(err_msg) // Return the error message from the SOAP service
            }
        }
        Err(e) => {
            log::error!("SOAP request error for CheckTIDStatus: {}", e);
            Err(format!("SOAP request error: {}", e))
        },
    }
}

#[tauri::command]
pub async fn send_gate_in_command(config_state: State<'_, AppConfigState>, data: GateInCommandData) -> Result<CGSTReceiveResult, String> {
    let config = config_state.0.lock().unwrap().clone();
    log::info!("SOAP: GateIn TX: {}, GPs: {:?}, Gate: {}", data.transaction_id_str, data.gate_passes, data.gate_name);
    let auth_header_xml = get_auth_header_xml(&config.gate_name);
    let tar_xml_elements: String = data.gate_passes.iter().map(|tar| format!("<string>{}</string>", tar)).collect();
    let rfid_tag_num = data.rfid_info.as_ref().map_or_else(String::new, |ri| ri.main.clone()); // Example: use main as TagNum
    let soap_body = format!(
        r#"<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
            <soap:Header>{auth_header_xml}</soap:Header>
            <soap:Body>
                <TruckInOut xmlns="http://halotec-indonesia.com/">
                    <TRANSACTIONID>{transaction_id}</TRANSACTIONID>
                    <TAGNUM>{rfid_tag_num}</TAGNUM>
                    <TARList>{tar_list}</TARList>
                    <INOUT>IN</INOUT>
                    <GATEID>{gate_id}</GATEID>
                </TruckInOut>
            </soap:Body>
        </soap:Envelope>"#,
        auth_header_xml = auth_header_xml,
        transaction_id = data.transaction_id_str,
        rfid_tag_num = rfid_tag_num,
        tar_list = tar_xml_elements,
        gate_id = data.gate_name
    );
    match post_soap_request(&config.cgs_gateway_url, "http://halotec-indonesia.com/TruckInOut", soap_body).await {
        Ok(response_xml) => {
            // More robust parsing needed here
            if response_xml.contains("<status>true</status>") && (response_xml.contains("<result>OK</result>") || response_xml.contains("<result>Ok</result>")) {
                let cms_items = Some(vec![CMSData { 
                    daily_seq: Some("CMS_SIM_001".to_string()), 
                    cntr_number: data.gate_passes.get(0).cloned(), 
                    truck_police_num: data.rfid_info.map(|r| r.sub), 
                    truck_in_time: Some(chrono::Local::now().to_rfc3339()), 
                    ..Default::default() 
                }]);
                Ok(CGSTReceiveResult { status: true, result: Some("OK".to_string()), transaction_id_str: Some(data.transaction_id_str), result_cms: cms_items })
            } else {
                let err_msg = response_xml.split("<result>").nth(1).and_then(|s| s.split("</result>").next()).unwrap_or("GateIn Failed").to_string();
                log::warn!("GateIn SOAP response indicates failure: {}", err_msg);
                Err(err_msg)
            }
        }
        Err(e) => {
            log::error!("SOAP request error for TruckInOut: {}", e);
            Err(format!("SOAP request error: {}", e))
        },
    }
}

#[tauri::command]
pub async fn send_truck_in_command(config_state: State<'_, AppConfigState>, transaction_id_str: String) -> Result<String, String> {
    let config = config_state.0.lock().unwrap().clone();
    log::info!("SOAP: TruckIn confirm TX ID: {}", transaction_id_str);
    let auth_header_xml = get_auth_header_xml(&config.gate_name);
    let soap_body = format!(
        r#"<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
            <soap:Header>{auth_header_xml}</soap:Header>
            <soap:Body>
                <Message6TAR xmlns="http://halotec-indonesia.com/">
                    <transactionId>{transaction_id}</transactionId>
                    <tar>{tar}</tar>
                    <updateams>true</updateams>
                    <datetime>{datetime}</datetime>
                </Message6TAR>
            </soap:Body>
        </soap:Envelope>"#,
        auth_header_xml = auth_header_xml,
        transaction_id = transaction_id_str,
        tar = "FINAL_DUMMY_TAR", // Or actual TAR if available
        datetime = chrono::Utc::now().format("%Y%m%d%H%M%S")
    );
    match post_soap_request(&config.cgs_gateway_url, "http://halotec-indonesia.com/Message6TAR", soap_body).await {
        Ok(response_xml) => {
             // More robust parsing needed here
            if response_xml.contains("OK") || response_xml.contains("<Status>S</Status>") || response_xml.contains("<Message6TARResult>OK</Message6TARResult>") {
                Ok("TruckIn successful.".to_string())
            } else {
                let err_msg = response_xml.split("<Message6TARResult>").nth(1).and_then(|s|s.split("</Message6TARResult>").next()).unwrap_or(&response_xml).to_string();
                log::warn!("TruckIn SOAP response indicates failure: {}", err_msg);
                Err(err_msg)
            }
        }
        Err(e) => {
            log::error!("SOAP request error for Message6TAR: {}", e);
            Err(format!("SOAP request error: {}", e))
        },
    }
}