use assert_cmd::Command;
use std::io::Write;
use tempfile::NamedTempFile;

fn main_bin() -> Command {
    Command::cargo_bin(assert_cmd::crate_name!()).unwrap()
}

#[test]
fn no_config_file() {
    main_bin().assert().stderr(
        predicates::str::is_match("usage: \\S+oidc_pages \\[config-file\\.json\\]\n")
            .unwrap()
            .count(1),
    );
}

#[test]
fn bad_config_file() {
    let mut config_file: NamedTempFile = NamedTempFile::new().unwrap();
    config_file.write_all(&[0xFF]).unwrap();

    main_bin().args([config_file.path()]).assert().stderr(
        r#"Error: Failed to deserialize config file

Caused by:
    expected value at line 1 column 1
"#,
    );
}

#[test]
fn deny_unknown_fields() {
    let mut config_file: NamedTempFile = NamedTempFile::new().unwrap();
    config_file
        .write_all(
            r#"{
                "public_url": "https://pages.local",
                "issuer_url": "https://sso.local/realms/testrealm",
                "client_id": "pages",
                "pages_path": "/tmp",
                "log_level": "off",
                "title": "OIDC Pages",
                "assets_path": "assets",
                "some_extra_field": "hello world"
            }"#
            .as_bytes(),
        )
        .unwrap();

    main_bin()
        .args([config_file.path()])
        .assert()
        .stderr(predicates::str::starts_with(
            r#"Error: Failed to deserialize config file

Caused by:
    unknown field `some_extra_field`, expected one of"#,
        ));
}

const MOCK_CONFIG: &str = r#"{
    "public_url": "https://pages.local",
    "issuer_url": "https://sso.local/realms/testrealm",
    "client_id": "pages",
    "pages_path": "/tmp",
    "log_level": "off",
    "title": "OIDC Pages",
    "assets_path": "assets"
}"#;

#[test]
fn no_client_secret() {
    let mut config_file: NamedTempFile = NamedTempFile::new().unwrap();
    config_file.write_all(MOCK_CONFIG.as_bytes()).unwrap();

    main_bin().args([config_file.path()]).assert().stderr(
        r#"Error: Failed to read client secret from environment variable 'OIDC_PAGES_CLIENT_SECRET'

Caused by:
    environment variable not found
"#,
    );
}

#[test]
fn valid() {
    let mut config_file: NamedTempFile = NamedTempFile::new().unwrap();
    config_file.write_all(MOCK_CONFIG.as_bytes()).unwrap();

    main_bin()
        .args([config_file.path()])
        .env("OIDC_PAGES_CLIENT_SECRET", "AAA")
        .assert()
        .stderr(predicates::str::starts_with(
            "Error: Failed to discover OpenID provider",
        ));
}
