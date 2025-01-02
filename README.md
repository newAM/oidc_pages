# OIDC Pages

OIDC pages serves static HTML documents with OIDC for authentication and
per-document authorization (permissions).

This is designed to be used with HTML generated from tools such as sphinx,
doxygen, or mdbook, but works with any static HTML.

## Screenshots

![OIDC Pages index](/screenshots/index.png?raw=true "OIDC Pages index")

## Features

* Integrates with Keycloak
* Respects system dark / light settings
* NixOS module provided
* Supports dynamically uploaded documents
* Secure by default

### Limitations

* Likely incompatible out-of-the-box with other OIDC providers
* Sessions are stored in-memory and will be erased on restart
* Not intended for serving untrusted content

### Adapting to Other OIDC Providers

There are two assumptions that make this keycloak-specific.

1. The OIDC specification does not define a type for the access token,
   keycloak uses a JSON web token which is the de-facto standard.
2. The OIDC specification does not provide a standard way to read roles.
   Roles are assumed to be under `resource_access` -> `<client_id>` -> `roles`.

Majority of OIDC providers use a JWT for the access token,
the only modifications necessary should be how to obtain roles.

### Planned Features

These features may or may not happen.

* Public pages
* Persistent user sessions
* Refresh tokens
* API for uploading pages over https
* [Pretty error pages](https://docs.rs/tower-http/0.5.2/tower_http/services/struct.ServeDir.html#method.not_found_service)
* Serving pages from subdomains instead of paths
* Pictorial preview of pages

## Security

Please report vulnerabilities to my git committer email.

## Technology

* Language: [rust](https://www.rust-lang.org)
* Asynchronous runtime: [tokio](https://tokio.rs)
* Web framework: [axum](https://github.com/tokio-rs/axum)
* Session management: [tower-sessions](https://github.com/maxcountryman/tower-sessions)
* Templating engine: [askama](https://github.com/djc/askama)
* OpenID Connect library: [openidconnect-rs](https://github.com/ramosbugs/openidconnect-rs)
* Favicon provided by [Flowbite](https://flowbite.com/icons)

## Usage

This is designed to be used with [NixOS], but should work on any Linux OS with
systemd.

You will need to bring a reverse proxy for TLS, I suggest [nginx].

### Keycloak Configuration

* Create and enable an OpenID Connect client in your realm
  * Root URL: `https://pages.company.com`
  * Home URL: `https://pages.company.com`
  * Valid redirect URIs: `https://pages.company.com/callback`
  * Client authentication: `On`
  * Authorization: `Off`
  * Authentication flow: `Standard flow` (all others disabled)
* Create roles for the newly created client
  * The `admin` role can view all pages
  * All other roles allow users to access pages with a directory of the same name
* Create a dedicated audience mapper the newly created client 
  * Navigate to **Clients** -> `<client_id>` -> **Client scopes**
    -> `<client_id>-dedicated` -> **Configure a new mapper** -> **Audience**
  * Name: `aud-mapper-<client_id>`
  * Included Client Audience: `<client_id>`
  * Add to ID token: `On`
  * Add to access token: `On`
  * Add to lightweight access token: `Off`
  * Add to token introspection: `On`

### NixOS Configuration

Reference `nixos/module.nix` for a complete list of options,
below is an example of my configuration.

```nix
{
  oidc_pages,
  config,
  ...
}: let
  pagesDomain = "pages.company.com";
in {
  # import the module, this adds the "services.oidc_pages" options
  imports = [oidc_pages.nixosModules.default];

  # add the overlay, this puts "oidc_pages" into "pkgs"
  nixpkgs.overlays = [oidc_pages.overlays.default];

  # use nix-sops to manage secrets declaratively
  # https://github.com/Mic92/sops-nix
  sops.secrets.oidc_pages.mode = "0400";

  # reference module for descriptions of configuration
  services.oidc_pages = {
    enable = true;
    environmentFiles = [config.sops.secrets.oidc_pages.path];
    settings = {
      public_url = "https://${pagesDomain}";
      issuer_url = "https://sso.company.com/realms/company";
      client_id = "pages";
      pages_path = "/var/www/pages";
      log_level = "info";
    };
  };

  # use NGINX as a reverse proxy to provide a TLS (https) interface
  networking.firewall.allowedTCPPorts = [443];
  services.nginx = {
    enable = true;
    virtualHosts."${pagesDomain}" = {
      onlySSL = true;
      locations."/".proxyPass = "http://unix:${config.services.oidc_pages.bindPath}";
    };
  };
}
```

[NixOS]: https://nixos.org
[nginx]: https://nginx.org
