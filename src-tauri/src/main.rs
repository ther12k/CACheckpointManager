// src-tauri/src/main.rs
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

// No need for these here if lib.rs handles everything:
// mod config_handler;
// mod rfid_handler;
// use config_handler::AppConfigState;
// use rfid_handler::{RFIDManagerState, RFIDManager};
// use std::sync::{Arc, Mutex};

fn main() {
    // Initialize logging once, preferably at the very start of the app.
    // If lib.rs also does this, ensure it's only done once.
    // For simplicity, let lib.rs handle it if it's already doing so.
    // env_logger::init(); // Consider moving this to lib.rs if it's not already there or ensure only one call

    // Call the run function from your lib.rs
    // Assumes your crate name in Cargo.toml is "cacheckpointmanager"
    cacheckpointmanager::run();
}