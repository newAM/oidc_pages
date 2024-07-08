mod config;
mod util;
mod views;

use std::{net::SocketAddr, path::PathBuf};

use anyhow::Context;
use axum::{routing::get, Router};
use config::Config;
use openidconnect::{core::CoreProviderMetadata, RedirectUrl};
use tokio::net::TcpListener;
use tower_http::services::ServeDir;
use tower_sessions::{
    cookie::{self, time::Duration, SameSite},
    Expiry, MemoryStore, SessionManagerLayer,
};
use url::Url;

pub type Client<
    HasAuthUrl = openidconnect::EndpointSet,
    HasDeviceAuthUrl = openidconnect::EndpointNotSet,
    HasIntrospectionUrl = openidconnect::EndpointNotSet,
    HasRevocationUrl = openidconnect::EndpointNotSet,
    HasTokenUrl = openidconnect::EndpointSet,
    HasUserInfoUrl = openidconnect::EndpointMaybeSet,
> = openidconnect::Client<
    openidconnect::EmptyAdditionalClaims,
    openidconnect::core::CoreAuthDisplay,
    openidconnect::core::CoreGenderClaim,
    openidconnect::core::CoreJweContentEncryptionAlgorithm,
    openidconnect::core::CoreJsonWebKey,
    openidconnect::core::CoreAuthPrompt,
    openidconnect::StandardErrorResponse<openidconnect::core::CoreErrorResponseType>,
    openidconnect::core::CoreTokenResponse,
    openidconnect::core::CoreTokenIntrospectionResponse,
    openidconnect::core::CoreRevocableToken,
    openidconnect::core::CoreRevocationErrorResponse,
    HasAuthUrl,
    HasDeviceAuthUrl,
    HasIntrospectionUrl,
    HasRevocationUrl,
    HasTokenUrl,
    HasUserInfoUrl,
>;

#[derive(Clone)]
pub struct State {
    client: Client,
    metadata: CoreProviderMetadata,
    pages_path: PathBuf,
    title: String,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let config: Config = Config::from_args_os()?;

    let http_client = util::http_client()?;

    let metadata: CoreProviderMetadata =
        CoreProviderMetadata::discover_async(config.issuer_url, &http_client)
            .await
            .context("Failed to discover OpenID provider")?;

    let token_url = metadata
        .token_endpoint()
        .context("OIDC provider did not provide token endpoint in discovery")?
        .clone();

    let redirect_url: Url = config
        .public_url
        .join("callback")
        .context("invalid public_url")?;
    let redirect_url = RedirectUrl::from_url(redirect_url);

    let client: Client = openidconnect::core::CoreClient::from_provider_metadata(
        metadata.clone(),
        config.client_id,
        Some(config.client_secret),
    )
    .set_redirect_uri(redirect_url)
    .set_token_uri(token_url);

    // session_key will need to be persistent if changing from a memory store
    // for persistent user sessions
    let session_key: cookie::Key =
        cookie::Key::try_generate().context("Failed to generate session key")?;
    let session_store = MemoryStore::default();
    let session_layer = SessionManagerLayer::new(session_store)
        .with_name("__Host-id")
        .with_http_only(true)
        .with_same_site(SameSite::Strict)
        .with_expiry(Expiry::OnInactivity(Duration::days(1)))
        .with_secure(true)
        .with_path("/")
        .with_private(session_key);

    let app: Router = Router::new()
        .route("/", get(views::index))
        .route("/login", get(views::login))
        .route("/logout", get(views::logout))
        .route("/callback", get(views::callback))
        .route("/robots.txt", get(views::robots_txt))
        .route("/p/:page_name/*page_path", get(views::pages))
        .nest_service("/assets", ServeDir::new(config.assets_path))
        .layer(session_layer)
        .with_state(State {
            client,
            metadata,
            pages_path: config.pages_path,
            title: config.title,
        });

    let bind_addrs: &[SocketAddr] = config.bind_addrs.as_ref();
    let listener: TcpListener = TcpListener::bind(bind_addrs)
        .await
        .context("Failed to bind")?;

    log::info!("Starting server");

    axum::serve(listener, app).await?;

    Ok(())
}
