use anyhow::Context;
use openidconnect::reqwest;

pub fn http_client() -> anyhow::Result<reqwest::Client> {
    reqwest::ClientBuilder::new()
        // following redirects opens the client up to SSRF vulnerabilities
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .context("Failed to create HTTP client")
}

pub trait UnwrapInfallible {
    type Ok;
    fn unwrap_infallible(self) -> Self::Ok;
}

impl<T> UnwrapInfallible for Result<T, std::convert::Infallible> {
    type Ok = T;
    fn unwrap_infallible(self) -> T {
        self.unwrap()
    }
}

pub fn to_string_array(v: &Vec<serde_json::Value>) -> Option<Vec<String>> {
    let mut ret: Vec<String> = Vec::with_capacity(v.len());
    for val in v {
        let val_convert: String = val.as_str()?.to_string();
        ret.push(val_convert);
    }
    Some(ret)
}
