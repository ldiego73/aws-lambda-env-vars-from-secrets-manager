use std::{
    collections::HashMap,
    env,
    fs::{remove_file, File, OpenOptions},
    io::Write,
    path::Path,
};

use aws_config::{meta::region::RegionProviderChain, retry::RetryConfig};
use aws_sdk_secretsmanager as secret_manager;
use serde_json::Value;

const DEFAULT_REGION: &str = "us-east-1";
const MAX_ATTEMPTS: u32 = 3;

fn retrieve_secret_args() -> Vec<String> {
    env::args()
        .skip_while(|arg| arg != "--secrets")
        .nth(1)
        .or_else(|| Some("".to_string()))
        .unwrap()
        .split(',')
        .map(ToString::to_string)
        .collect::<Vec<_>>()
}

fn retrieve_path_args() -> String {
    let path = env::args()
        .skip_while(|arg| arg != "--path")
        .nth(1)
        .expect("[Secret] Missing '--path' flag or argument after it");

    path
}

fn retrieve_prefix_args() -> String {
    env::args()
        .skip_while(|arg| arg != "--prefix")
        .nth(1)
        .or_else(|| Some("".to_string()))
        .unwrap()
}

fn retrieve_transform_args() -> String {
    env::args()
        .skip_while(|arg| arg != "--transform")
        .nth(1)
        .or_else(|| Some("".to_string()))
        .unwrap()
}

fn create_file(path: &str) -> File {
    if Path::new(path).exists() {
        remove_file(path).expect("[Secret] Failed to remove file");
    }

    OpenOptions::new()
        .create(true)
        .write(true)
        .open(path)
        .unwrap()
}

async fn get_secret_client() -> secret_manager::Client {
    let retry_config = RetryConfig::standard().with_max_attempts(MAX_ATTEMPTS);
    let region_provider = RegionProviderChain::default_provider().or_else(DEFAULT_REGION);
    let config = aws_config::from_env()
        .region(region_provider)
        .retry_config(retry_config)
        .load()
        .await;

    secret_manager::Client::new(&config)
}

#[::tokio::main]
async fn main() {
    let secret_path = retrieve_path_args();
    let secret_prefix = retrieve_prefix_args();
    let secret_transform = retrieve_transform_args();
    let secret_values = retrieve_secret_args();
    let secret_client = get_secret_client().await;

    let mut secret_file = create_file(&secret_path);

    let mut secrets: HashMap<String, _, _> = HashMap::new();

    for secret_value in secret_values {
        let raw_secret = secret_client
            .get_secret_value()
            .secret_id(&secret_value)
            .send()
            .await;

        match raw_secret {
            Ok(response) => {
                if let Some(secret) = response.secret_string() {
                    match serde_json::from_str::<Value>(&secret) {
                        Ok(json) => {
                            secrets.extend(json.as_object().unwrap().clone());
                        }
                        Err(err) => {
                            println!("[Secret] Failed to parse secret {}: {}", secret_value, err);
                        }
                    }
                }
            }
            Err(err) => {
                println!(
                    "[Secret] Failed to retrieve secret {}: {}",
                    secret_value, err
                );
            }
        }
    }
    for (secret, value) in secrets.iter() {
        let prefix = match secret_prefix.as_str() {
            "" => "".to_string(),
            _ => format!("{}_", secret_prefix),
        };
        let new_secret = secret.replace('-', "_");
        let new_value = value.as_str().unwrap();

        let line: String = match secret_transform.as_str() {
            "lower" => format!(
                "export {}{}='{}'\n",
                prefix.to_lowercase(),
                new_secret.to_lowercase(),
                new_value
            ),
            "upper" => format!(
                "export {}{}='{}'\n",
                prefix.to_uppercase(),
                new_secret.to_uppercase(),
                new_value
            ),
            _ => format!("export {}{}='{}'\n", prefix, new_secret, new_value),
        };

        secret_file
            .write(line.as_bytes())
            .expect("[Secret] Failed to write to file");
    }
}
