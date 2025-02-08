# OIDC Pages

OIDC Pages is a static HTML document server that integrates OpenID Connect (OIDC) for authentication and per-document authorization (permissions).
OIDC Pages is designed to work seamlessly with documentation tools such as Sphinx, Doxygen, and mdbook, and can be used with any static HTML content.

## Screenshots

![OIDC Pages index](/screenshots/index.png?raw=true "OIDC Pages index")

## Features

- Works with keycloak or kanidm
- Respects system dark / light settings
- NixOS module provided
- Supports dynamically uploaded documents
- Secure by default

### Limitations

- Likely incompatible out-of-the-box with other OIDC providers
- Sessions are stored in-memory and erased on restart
- Not intended for serving untrusted content

### Adapting to other OIDC providers

1. The OIDC specification doesn't define a type for the access token.
   Your OIDC provider must use a JSON web token which is the de-facto standard.
2. The OIDC specification doesn't provide a standard way to read roles.
   The JSON path to the roles is set with `roles_path` in the configuration.
   This typically requires getting your hands dirty and reading the responses
   of your OIDC provider with a working application.

### Planned features

These features may or may not happen.

- Public pages
- Persistent user sessions
- Refresh tokens
- API for uploading pages over https
- [Pretty error pages](https://docs.rs/tower-http/0.6.2/tower_http/services/struct.ServeDir.html#method.not_found_service)
- Serving pages from subdomains instead of paths
- Pictorial preview of pages

## Security

Please report vulnerabilities to my git committer email.

## Technology

- Language: [rust](https://www.rust-lang.org)
- Asynchronous runtime: [tokio](https://tokio.rs)
- Web framework: [axum](https://github.com/tokio-rs/axum)
- Session management: [tower-sessions](https://github.com/maxcountryman/tower-sessions)
- Templating engine: [askama](https://github.com/djc/askama)
- OpenID Connect library: [openidconnect-rs](https://github.com/ramosbugs/openidconnect-rs)
- Favicon provided by [Flowbite](https://flowbite.com/icons)

## Configuration

This is designed to work with [NixOS], but should work on any Linux OS with
systemd.

You need to bring a reverse proxy for TLS, I suggest [nginx].

### Keycloak configuration

- Create and enable an OpenID Connect client in your realm
  - Root URL: `https://pages.company.com`
  - Home URL: `https://pages.company.com`
  - Valid redirect URIs: `https://pages.company.com/callback`
  - Client authentication: `On`
  - Authorization: `Off`
  - Authentication flow: `Standard flow` (all others disabled)
- Create roles for the newly created client
  - The `admin` role can view all pages
  - All other roles grant permissions to pages in a directory matching the role name
- Create a dedicated audience mapper for the newly created client
  - Navigate to **Clients** -> `<client_id>` -> **Client scopes**
    -> `<client_id>-dedicated` -> **Configure a new mapper** -> **Audience**
  - Name: `aud-mapper-<client_id>`
  - Included Client Audience: `<client_id>`
  - Add to ID token: `On`
  - Add to access token: `On`
  - Add to lightweight access token: `Off`
  - Add to token introspection: `On`

### Kanidm configuration

Create the OAuth2 client:

```bash
kanidm system oauth2 create pages "pages.domain.name" https://pages.domain.name
kanidm system oauth2 update-scope-map pages oidc_pages_users email openid profile groups
kanidm system oauth2 get pages
kanidm system oauth2 show-basic-secret pages
<SECRET>
```

Create permission groups:

```bash
kanidm group create 'oidc_pages_users'
kanidm group create 'oidc_pages_pagename'
```

Setup the claim-map:

```bash
kanidm system oauth2 update-claim-map-join 'pages' 'pages_role' array
kanidm system oauth2 update-claim-map 'pages' 'pages_role' 'oidc_pages_pagename' 'pagename'
```

Add users to the groups:

```bash
kanidm person update myusername --legalname "Personal Name" --mail "user@example.com"
kanidm group add-members 'oidc_pages_users' 'myusername'
kanidm group add-members 'oidc_pages_pagename' 'myusername'
```

### NixOS configuration

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
    # give nginx access to oidc_pages.socket
    socketUser = config.services.nginx.user;
    settings = {
      public_url = "https://${pagesDomain}";
      client_id = "pages";
      pages_path = "/var/www/pages";
      log_level = "info";
      # provider specific:
      # - keycloak: "https://sso.company.com/realms/company"
      # - kanidm: "https://sso.company.com/oauth2/openid/${client_id}"
      issuer_url = "";
      # provider specific:
      # - keycloak: ["roles"]
      # - kanidm: []
      additional_scopes = [];
      # provider specific:
      # - keycloak: ["resource_access" client_id "roles"]
      # - kanidm: ["pages_roles"]
      roles_path = [];
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
