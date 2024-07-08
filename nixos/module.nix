{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.oidc_pages;
  settingsFormat = pkgs.formats.json {};
  configurationFile = settingsFormat.generate "oidc_pages_config.json" cfg.settings;
in {
  options.services.oidc_pages = {
    enable = lib.mkEnableOption "OIDC Pages";

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = lib.types.attrsOf settingsFormat.type;

        options = {
          public_url = lib.mkOption {
            description = "URL that end users will use to access OIDC pages.";
            example = "https://pages.company.com";
            type = lib.types.str;
          };

          issuer_url = lib.mkOption {
            description = ''
              OIDC issuer URL for configuration discovery.

              Reference
              [Obtaining OpenID Provider Configuration Information](https://openid.net/specs/openid-connect-discovery-1_0.html#ProviderConfig)
              in the OIDC specification for more information.
            '';
            example = "https://keycloak.company.com/realms/company";
            type = lib.types.str;
          };

          client_id = lib.mkOption {
            description = ''
              OIDC client ID.

              This must match the client ID configured in your OIDC server.
            '';
            example = "pages";
            type = lib.types.str;
          };

          bind_addrs = lib.mkOption {
            default = ["127.0.0.1:8000"];
            description = "Addresses to serve OIDC pages on.";
            type = lib.types.listOf lib.types.str;
          };

          log_level = lib.mkOption {
            default = "warn";
            description = "Logging level.";
            type = lib.types.enum ["off" "error" "warn" "info" "debug" "trace"];
          };

          pages_path = lib.mkOption {
            description = "Path to directory containing documents to serve.";
            type = lib.types.path;
          };

          title = lib.mkOption {
            default = "OIDC Pages";
            description = "Instance title";
            example = "Company Pages";
            type = lib.types.str;
          };

          assets_path = lib.mkOption {
            description = "Path to static assets.";
            type = lib.types.path;
            default = "${pkgs.oidc_pages}/share/oidc_pages/assets";
          };
        };
      };
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      description = ''
        Environment file as defined in {manpage}`systemd.exec(5)`.

        OIDC pages uses the following environment variables for passing secrets:

        * `OIDC_PAGES_CLIENT_SECRET`: OIDC client secret provided by your OIDC provider

        Example contents:

        ```
        OIDC_PAGES_CLIENT_SECRET=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
        ```
      '';
      example = ["/run/keys/oidc_pages.env"];
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.oidc_pages = {
      wantedBy = ["multi-user.target"];

      description = cfg.settings.title;

      serviceConfig = {
        Type = "idle";
        KillSignal = "SIGINT";
        ExecStart = "${pkgs.oidc_pages}/bin/oidc_pages ${configurationFile}";
        Restart = "on-failure";
        RestartSec = 10;
        EnvironmentFile = cfg.environmentFiles;

        # hardening
        DynamicUser = true;
        DevicePolicy = "closed";
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        DeviceAllow = "";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateMounts = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        BindReadOnlyPaths = [cfg.settings.pages_path];
        MemoryDenyWriteExecute = true;
        LockPersonality = true;
        RemoveIPC = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        ProtectProc = "invisible";
        ProtectHostname = true;
        ProcSubset = "pid";
        UMask = "0077";
      };
    };
  };

  meta.maintainers = pkgs.oidc_pages.meta.maintainers;
}
