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

pub fn to_string_array(v: &serde_json::Value) -> Option<Vec<String>> {
    let v_arr: &Vec<serde_json::Value> = v.as_array()?;

    let mut ret: Vec<String> = Vec::with_capacity(v_arr.len());
    for val in v_arr {
        let val_convert: String = val.as_str()?.to_string();
        ret.push(val_convert);
    }
    Some(ret)
}

pub fn page_title(index_html: &str) -> Option<String> {
    let document: scraper::Html = scraper::Html::parse_document(index_html);

    let title_selector: scraper::Selector =
        scraper::Selector::parse("title").expect("Failed to create selector");

    document
        .select(&title_selector)
        .next()
        .map(|ele| ele.inner_html())
}

pub fn value_at_path<I, A>(json: &serde_json::Value, path: I) -> Option<&serde_json::Value>
where
    I: IntoIterator<Item = A>,
    A: AsRef<str>,
{
    let mut current: &serde_json::Value = json;
    for key in path.into_iter() {
        match current {
            serde_json::Value::Object(object) => {
                current = object.get(key.as_ref())?;
            }
            _ => return None,
        }
    }
    Some(current)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_page_title() {
        assert_eq!(
            page_title("<title>Hello, World!</title>"),
            Some("Hello, World!".to_string())
        );
        assert_eq!(page_title("<title></title>"), Some("".to_string()));
        assert_eq!(
            page_title("<title>Title Missing Closing Tag"),
            Some("Title Missing Closing Tag".to_string())
        );
    }

    #[test]
    fn test_page_title_err() {
        assert_eq!(page_title(""), None);
    }

    #[test]
    fn test_value_at_path() {
        let json = serde_json::json!({
            "first": {
                "extra_key": "extra_value",
                "second": {
                    "third": 123,
                }
            }
        });

        // path exists
        let roles_path = ["first", "second", "third"];
        assert_eq!(value_at_path(&json, roles_path).unwrap(), 123);

        // path does not exist
        let roles_path = ["first", "third"];
        assert_eq!(value_at_path(&json, roles_path), None);

        // path exists, less deep
        let roles_path = ["first", "extra_key"];
        assert_eq!(value_at_path(&json, roles_path).unwrap(), "extra_value");

        // no path provided
        let empty_path: [&str; 0] = [];
        assert_eq!(value_at_path(&json, empty_path), Some(&json));
    }
}
