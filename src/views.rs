use std::path::PathBuf;

use crate::{
    util::{self, to_string_array, UnwrapInfallible},
    State,
};
use anyhow::Context;
use askama::Template;
use axum::{
    extract::Query,
    http::StatusCode,
    response::{IntoResponse, Redirect},
};
use openidconnect::{OAuth2TokenResponse, TokenResponse};
use serde::{Deserialize, Serialize};
use subtle::ConstantTimeEq;
use tower::util::ServiceExt;
use tower_http::services::ServeFile;
use tower_sessions::Session;
use url::Url;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    email: String,
    roles: Vec<String>,
}

#[derive(PartialEq, Eq)]
pub struct Page {
    title: String,
    dir: String,
}

impl PartialOrd for Page {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Page {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.title.to_lowercase().cmp(&other.title.to_lowercase())
    }
}

#[derive(Template)]
#[template(path = "index.html")]
struct IndexTemplate {
    title: String,
    user: Option<User>,
    pages: Vec<Page>,
}

struct HtmlTemplate<T>(T);

impl<T> IntoResponse for HtmlTemplate<T>
where
    T: Template,
{
    fn into_response(self) -> axum::response::Response {
        match self.0.render() {
            Ok(html) => axum::response::Html(html).into_response(),
            Err(err) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to render template. Error: {err}"),
            )
                .into_response(),
        }
    }
}

const PKCE_VERIFIER_KEY: &str = "pkce_verifier";
const CSRF_TOKEN_KEY: &str = "csrf_token";
const NONCE_KEY: &str = "nonce";
const USER_KEY: &str = "user";

fn user_can_view_page(roles: &[String], page: &String) -> bool {
    roles.contains(&"admin".to_string()) || roles.contains(page)
}

async fn page_title(index: &PathBuf) -> anyhow::Result<String> {
    let index_html: String = tokio::fs::read_to_string(index)
        .await
        .with_context(|| format!("Failed to read {}", index.to_string_lossy()))?;

    let document = scraper::Html::parse_document(&index_html);

    let title_selector = scraper::Selector::parse("title")
        .ok()
        .with_context(|| format!("Failed to parse {}", index.to_string_lossy()))?;

    document
        .select(&title_selector)
        .next()
        .map(|ele| ele.inner_html())
        .with_context(|| format!("Failed to find title in {}", index.to_string_lossy()))
}

async fn list_pages(path: PathBuf, roles: &[String]) -> Vec<Page> {
    let mut ret: Vec<Page> = vec![];
    let mut dir_entries = match tokio::fs::read_dir(&path).await {
        Ok(de) => de,
        Err(e) => {
            log::error!(
                "Failed to list pages from {}: {}",
                path.to_string_lossy(),
                e
            );
            return ret;
        }
    };

    while let Ok(Some(entry)) = dir_entries.next_entry().await {
        if entry
            .file_type()
            .await
            .map(|ft| ft.is_dir())
            .unwrap_or(false)
        {
            if let Ok(page) = entry.file_name().into_string() {
                if user_can_view_page(roles, &page) {
                    let mut index: PathBuf = path.clone();
                    index.push(&page);
                    index.push("index.html");
                    match page_title(&index).await {
                        Ok(title) => ret.push(Page { dir: page, title }),
                        Err(e) => {
                            log::warn!("Failed to get page title: {e}");
                            ret.push(Page {
                                dir: page.clone(),
                                title: page,
                            })
                        }
                    }
                }
            } else {
                log::warn!("Encountered non-UTF-8 directory");
            }
        }
    }
    ret.sort();
    ret
}

pub async fn index(
    state: axum::extract::State<State>,
    session: Session,
) -> axum::response::Response {
    let user: Option<User> = match session.get(USER_KEY).await {
        Ok(u) => u,
        Err(e) => {
            session.clear().await;
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to load session: {e}"),
            )
                .into_response();
        }
    };
    let pages: Vec<Page> = match user.as_ref() {
        Some(user) => list_pages(state.pages_path.clone(), &user.roles).await,
        None => vec![],
    };
    let template: IndexTemplate = IndexTemplate {
        title: state.title.clone(),
        user,
        pages,
    };
    HtmlTemplate(template).into_response()
}

pub async fn pages(
    state: axum::extract::State<State>,
    session: Session,
    axum::extract::Path((page_name, page_path)): axum::extract::Path<(String, String)>,
    request: axum::extract::Request,
) -> axum::response::Response {
    let not_found: axum::response::Response = (StatusCode::NOT_FOUND, "Not found").into_response();

    let user: User = match session.get(USER_KEY).await {
        Ok(Some(user)) => user,
        Ok(None) => return not_found,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to load session: {e}"),
            )
                .into_response()
        }
    };

    if user_can_view_page(&user.roles, &page_name) {
        let mut path = state.pages_path.clone();
        path.push(page_name);
        path.push(page_path);

        if path.exists() {
            let service: ServeFile = ServeFile::new(path);
            service
                .oneshot(request)
                .await
                .unwrap_infallible()
                .into_response()
        } else {
            not_found
        }
    } else {
        not_found
    }
}

pub async fn login(
    state: axum::extract::State<State>,
    session: Session,
) -> axum::response::Response {
    let (pkce_challenge, pkce_verifier) = openidconnect::PkceCodeChallenge::new_random_sha256();

    let (auth_url, csrf_token, nonce) = state
        .client
        .authorize_url(
            openidconnect::core::CoreAuthenticationFlow::AuthorizationCode,
            openidconnect::CsrfToken::new_random,
            openidconnect::Nonce::new_random,
        )
        .add_scope(openidconnect::Scope::new("roles".to_string()))
        .set_pkce_challenge(pkce_challenge)
        .url();

    match tokio::try_join!(
        session.insert(PKCE_VERIFIER_KEY, pkce_verifier),
        session.insert(NONCE_KEY, nonce),
        session.insert(CSRF_TOKEN_KEY, csrf_token)
    ) {
        Ok(_) => Redirect::temporary(auth_url.as_str()).into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed store login session.  Error: {e}"),
        )
            .into_response(),
    }
}

pub async fn logout(session: Session) -> axum::response::Response {
    match session.delete().await {
        Ok(_) => Redirect::temporary("/").into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed to logout.  Error: {e}"),
        )
            .into_response(),
    }
}

#[derive(serde::Deserialize, serde::Serialize)]
pub struct CallbackParams {
    iss: Url,
    state: String,
    #[serde(flatten)]
    data: CallbackData,
}

#[derive(serde::Deserialize, serde::Serialize)]
#[serde(untagged)]
pub enum CallbackData {
    Err {
        error: String,
        error_description: String,
    },
    Code {
        code: String,
        session_state: String,
    },
}

async fn fallible_callback(
    state: axum::extract::State<State>,
    session: &mut Session,
    params: CallbackParams,
) -> anyhow::Result<axum::response::Response> {
    let (code, _session_state) = match params.data {
        CallbackData::Err {
            error,
            error_description,
        } => {
            let msg: String = format!(
                "OIDC server returned error '{error}' with description '{error_description}'"
            );
            log::warn!("{}", msg);
            return Ok((StatusCode::BAD_REQUEST, msg).into_response());
        }
        CallbackData::Code {
            code,
            session_state,
        } => (code, session_state),
    };

    let (pkce_verifier, nonce, csrf_token): (
        openidconnect::PkceCodeVerifier,
        openidconnect::Nonce,
        openidconnect::CsrfToken,
    ) = match tokio::try_join!(
        session.remove(PKCE_VERIFIER_KEY),
        session.remove(NONCE_KEY),
        session.remove(CSRF_TOKEN_KEY)
    ) {
        Ok((Some(pkce_verifier), Some(nonce), Some(csrf_token))) => {
            (pkce_verifier, nonce, csrf_token)
        }
        _ => {
            let msg: &str = "Failed to load login session";
            log::warn!("{}", msg);
            return Ok((StatusCode::BAD_REQUEST, msg).into_response());
        }
    };

    // verify CSRF token
    if !bool::from(
        csrf_token
            .secret()
            .as_bytes()
            .ct_eq(params.state.as_bytes()),
    ) {
        anyhow::bail!("CSRF token mismatch")
    }

    let http_client = util::http_client()?;

    // exchange code for an access token and ID token
    let token_response = state
        .client
        .exchange_code(openidconnect::AuthorizationCode::new(code))
        .set_pkce_verifier(pkce_verifier)
        .request_async(&http_client)
        .await
        .context("Access token request failed")?;

    // extract the ID token claims after verifying authenticity and nonce
    let id_token = token_response
        .id_token()
        .context("OIDC server did not return an ID token")?;
    let id_token_verifier = state.client.id_token_verifier();
    let claims = id_token
        .claims(&id_token_verifier, &nonce)
        .context("Failed to verify claims")?;

    // Verify the access token hash to ensure that the access token hasn't been substituted for
    // another user's.
    if let Some(expected_access_token_hash) = claims.access_token_hash() {
        let actual_access_token_hash = openidconnect::AccessTokenHash::from_token(
            token_response.access_token(),
            id_token
                .signing_alg()
                .context("Access token is unsigned or utilizes JSON Web Encryption (JWE)")?,
            id_token
                .signing_key(&id_token_verifier)
                .context("Access token has no signature or a corresponding key cannot be found")?,
        )
        .context("Failed to generate access token hash")?;

        if !bool::from(
            actual_access_token_hash
                .as_bytes()
                .ct_eq(expected_access_token_hash.as_bytes()),
        ) {
            anyhow::bail!("Access token mismatch")
        }
    }

    let jwt_hdr: jsonwebtoken::Header =
        jsonwebtoken::decode_header(token_response.access_token().secret())
            .context("Failed to decode access token")?;

    let kid: String = jwt_hdr.kid.context("Access token is missing kid field")?;

    let keys_get = http_client
        .get(state.metadata.jwks_uri().url().clone())
        .send()
        .await
        .context("Failed to requesting OIDC JWKs")?
        .text()
        .await
        .context("Failed to read OIDC JWKs")?;

    let jwkset: jsonwebtoken::jwk::JwkSet =
        serde_json::from_str(&keys_get).context("Failed to deserialize OIDC JWKs")?;

    let jwk = jwkset.find(&kid).context("Key ID missing in OIDC JWKs")?;

    if !jwk.is_supported() {
        anyhow::bail!("JWK uses unsupported algorithm")
    }

    let client_id: &str = state.client.client_id().as_str();

    let decoding_key = jsonwebtoken::DecodingKey::from_jwk(jwk)
        .context("Failed to extract decoding key from JWK")?;
    let validation = {
        let mut validation = jsonwebtoken::Validation::new(jwt_hdr.alg);
        validation.set_audience(&[client_id]);
        validation
    };
    let access_token: jsonwebtoken::TokenData<serde_json::Value> = jsonwebtoken::decode(
        token_response.access_token().secret(),
        &decoding_key,
        &validation,
    )
    .context("Failed to decode access token")?;

    let email: String = claims
        .email()
        .map(|email| email.as_str())
        .context("OIDC server did not provide email address")?
        .to_string();

    let roles: &Vec<serde_json::Value> = access_token
        .claims
        .get("resource_access")
        .and_then(|ra| ra.get(client_id))
        .and_then(|cid| cid.get("roles"))
        .context("roles not in access token")?
        .as_array()
        .context("roles in access token is not an array")?;
    let roles: Vec<String> =
        to_string_array(roles).context("roles in access token is not an array of strings")?;

    let user: User = User { email, roles };

    session
        .insert(USER_KEY, user.clone())
        .await
        .context("Failed to store user information")?;

    log::info!("Authenticated {user:?}");

    Ok(Redirect::temporary("/").into_response())
}

pub async fn callback(
    state: axum::extract::State<State>,
    mut session: Session,
    Query(params): Query<CallbackParams>,
) -> axum::response::Response {
    match fallible_callback(state, &mut session, params).await {
        Ok(resp) => {
            if resp.status().is_client_error() || resp.status().is_server_error() {
                session.clear().await;
            }
            resp
        }
        Err(e) => {
            session.clear().await;
            let msg: String = format!("Authentication error: {e:?}");
            log::warn!("{}", msg);
            (StatusCode::UNAUTHORIZED, msg).into_response()
        }
    }
}
