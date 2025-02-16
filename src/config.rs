use std::{
    ffi::OsString,
    fs::{self, File},
    io::BufReader,
    path::PathBuf,
    str::FromStr,
};

use anyhow::Context;
use openidconnect::{ClientId, ClientSecret, IssuerUrl};
use serde::Deserialize;
use url::Url;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ConfigFile {
    public_url: Url,
    issuer_url: IssuerUrl,
    client_id: ClientId,
    client_secret_file_path: Option<String>,
    log_level: String,
    pages_path: PathBuf,
    title: String,
    assets_path: PathBuf,
    additional_scopes: Vec<openidconnect::Scope>,
    roles_path: Vec<String>,
}

#[derive(Clone)]
pub struct Config {
    pub public_url: Url,
    pub issuer_url: IssuerUrl,
    pub client_id: ClientId,
    pub client_secret: ClientSecret,
    pub pages_path: PathBuf,
    pub title: String,
    pub assets_path: PathBuf,
    pub additional_scopes: Vec<openidconnect::Scope>,
    pub roles_path: Vec<String>,
}

impl Config {
    pub fn from_args_os() -> anyhow::Result<Config> {
        let config_file_path: OsString = match std::env::args_os().nth(1) {
            Some(x) => x,
            None => {
                eprintln!(
                    "usage: {} [config-file.json]",
                    std::env::args_os()
                        .next()
                        .unwrap_or_else(|| OsString::from("???"))
                        .to_string_lossy()
                );
                std::process::exit(1);
            }
        };

        let file: File = File::open(&config_file_path).with_context(|| {
            format!(
                "Failed to open config file {}",
                config_file_path.to_string_lossy()
            )
        })?;
        let reader: BufReader<File> = BufReader::new(file);
        let config: ConfigFile =
            serde_json::from_reader(reader).context("Failed to deserialize config file")?;

        let level: log::LevelFilter =
            log::LevelFilter::from_str(&config.log_level).with_context(|| {
                format!(
                    "Invalid log_level in configuration file {}",
                    config_file_path.to_string_lossy()
                )
            })?;

        if level != log::LevelFilter::Off {
            systemd_journal_logger::JournalLog::new()
                .context("Failed to create logger")?
                .install()
                .context("Failed to install logger")?;
            log::set_max_level(level);
        }

        log::debug!("Hello world");

        let client_secret_str: String = if let Some(client_secret_file_path) =
            config.client_secret_file_path
        {
            fs::read_to_string(&client_secret_file_path).with_context(|| {
                format!("Failed to read client secret from '{client_secret_file_path}'")
            })?
        } else {
            const CLIENT_SECRET_ENV_VAR: &str = "OIDC_PAGES_CLIENT_SECRET";

            std::env::var(CLIENT_SECRET_ENV_VAR).with_context(|| {
                    format!(
                        "Failed to read client secret from environment variable '{CLIENT_SECRET_ENV_VAR}'"
                    )
                })?
        };

        let client_secret: ClientSecret = ClientSecret::new(client_secret_str);

        Ok(Config {
            public_url: config.public_url,
            issuer_url: config.issuer_url,
            client_id: config.client_id,
            client_secret,
            pages_path: config.pages_path,
            title: config.title,
            assets_path: config.assets_path,
            additional_scopes: config.additional_scopes,
            roles_path: config.roles_path,
        })
    }
}
