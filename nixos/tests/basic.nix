{
  self,
  lib,
  pkgs,
}: let
  tmpDomain = "tmp.local";
  keycloakDomain = "keycloak.local";
  oidcPagesDomain = "pages.local";

  envFileName = "oidc_pages_test_env";
  envFileDir = "/nginx";
  envFilePath = "${envFileDir}/${envFileName}";

  oidcPagesInternalPort = 8080;
  oidcPagesFrontendUrl = "https://${oidcPagesDomain}";

  keycloakFrontendUrl = "https://${keycloakDomain}";
  keycloakInitialAdminPassword = "h4Iho\"JFn't2>iQIR9";
  keycloakAdminPasswordFile = pkgs.writeText "admin-password" "${keycloakInitialAdminPassword}";

  client = {
    clientId = "test-client";
    name = "test-client";
    redirectUris = ["urn:ietf:wg:oauth:2.0:oob" "${oidcPagesFrontendUrl}/callback"];
    webOrigins = [oidcPagesFrontendUrl];
    rootUrl = oidcPagesFrontendUrl;
    baseUrl = oidcPagesFrontendUrl;
  };

  user = {
    firstName = "Chuck";
    lastName = "Testa";
    username = "chuck.testa";
    email = "chuck.testa@example.com";
  };

  password = "password1234";

  realm = {
    enabled = true;
    realm = "test-realm";
    clients = [client];
    users = [
      (
        user
        // {
          enabled = true;
          credentials = [
            {
              type = "password";
              temporary = false;
              value = password;
            }
          ];
        }
      )
    ];
  };

  realmDataJson = pkgs.writeText "realm-data.json" (builtins.toJSON realm);

  roles = {
    name = "notes";
    composite = false;
  };

  rolesDataJson = pkgs.writeText "roles-data.json" (builtins.toJSON roles);
in
  pkgs.nixosTest {
    name = "basic";

    nodes = {
      keycloak = {
        pkgs,
        nodes,
        ...
      }: {
        networking.hosts = {
          "127.0.0.1" = [keycloakDomain tmpDomain];
          "${nodes.machine.networking.primaryIPAddress}" = [oidcPagesDomain];
        };

        # reference for certificate generation:
        # nixpkgs/nixos/tests/common/acme/server/README.md
        security.pki.certificateFiles = [
          ./ca.keycloak.local.cert.pem
          ./ca.pages.local.cert.pem
        ];

        networking.firewall.allowedTCPPorts = [80 443];

        # using nginx to transfer the client secret file from keycloak to the
        # OIDC pages VM
        services.nginx = {
          enable = true;
          virtualHosts.${tmpDomain} = {
            root = envFileDir;
            extraConfig = "autoindex on;";
          };
        };

        services.keycloak = {
          enable = true;
          settings.hostname = keycloakDomain;
          initialAdminPassword = keycloakInitialAdminPassword;
          sslCertificate = self + "/nixos/tests/${keycloakDomain}.cert.pem";
          sslCertificateKey = self + "/nixos/tests/${keycloakDomain}.key.pem";
          database = {
            type = "postgresql";
            username = "bogus";
            name = "also bogus";
            passwordFile = "${pkgs.writeText "dbPassword" ''wzf6\"vO"Cb\nP>p#6;c&o?eu=q'THE'''H''''E''}";
          };
        };

        environment.systemPackages = with pkgs; [
          jq
        ];
      };

      machine = {
        pkgs,
        nodes,
        ...
      }: let
        pagesInternalAddr = "127.0.0.1:${builtins.toString oidcPagesInternalPort}";
      in {
        imports = [self.nixosModules.default];
        nixpkgs.overlays = [self.overlays.default];
        services.oidc_pages = {
          enable = true;
          environmentFiles = [envFilePath];
          settings = {
            public_url = oidcPagesFrontendUrl;
            issuer_url = "${keycloakFrontendUrl}/realms/${realm.realm}";
            client_id = client.clientId;
            pages_path = ./pages;
            log_level = "info";
            bind_addrs = [pagesInternalAddr];
          };
        };

        # this is not required, but it makes the logs easier to read because
        # oidc_pages wont try to start before the other VM is ready
        systemd.services.oidc_pages.wantedBy = lib.mkForce [];

        networking.firewall.allowedTCPPorts = [443];
        services.nginx = {
          enable = true;
          virtualHosts."pages.local" = {
            onlySSL = true;
            locations."/".proxyPass = "http://${pagesInternalAddr}";
            sslCertificateKey = ./pages.local.key.pem;
            sslCertificate = ./pages.local.cert.pem;
          };
        };

        security.pki.certificateFiles = [
          ./ca.keycloak.local.cert.pem
          ./ca.pages.local.cert.pem
        ];

        networking.hosts = {
          "127.0.0.1" = [oidcPagesDomain];
          "${nodes.keycloak.networking.primaryIPAddress}" = [keycloakDomain tmpDomain];
        };

        environment.systemPackages = with pkgs; [
          html-tidy
          jq
          xmlstarlet
        ];
      };
    };

    testScript = ''
      import json

      start_all()
      keycloak.wait_for_unit("keycloak.service")
      keycloak.wait_for_open_port(443)
      keycloak.wait_until_succeeds("curl -sSf ${keycloakFrontendUrl}")

      # Get an admin interface access token
      keycloak.succeed("""
          curl -sSf -d 'client_id=admin-cli' \
               -d 'username=admin' \
               -d "password=$(<${keycloakAdminPasswordFile})" \
               -d 'grant_type=password' \
               '${keycloakFrontendUrl}/realms/master/protocol/openid-connect/token' \
               | jq -r '"Authorization: bearer " + .access_token' >admin_auth_header
      """)

      # Publish the realm, including a test OIDC client and user
      keycloak.succeed(
          "curl -sSf -H @admin_auth_header -X POST -H 'Content-Type: application/json' -d @${realmDataJson} '${keycloakFrontendUrl}/admin/realms/'"
      )

      # get client id
      client_data_resp: str = keycloak.succeed(
          "curl -sSf -H @admin_auth_header '${keycloakFrontendUrl}/admin/realms/${realm.realm}/clients?clientId=${client.name}'",
      )
      client_data: list = json.loads(client_data_resp)
      client_id: str = client_data[0]["id"]
      print(f"{client_id=}")

      # generate and save the client secret
      keycloak.succeed(
          f"curl -sSf -H @admin_auth_header -X POST '${keycloakFrontendUrl}/admin/realms/${realm.realm}/clients/{client_id}/client-secret' | jq -r .value >client_secret",
      )

      # get user id
      user_data_resp: str = keycloak.succeed(
          "curl -sSf -H @admin_auth_header '${keycloakFrontendUrl}/admin/realms/${realm.realm}/users?username=${user.username}'",
      )
      user_data: list = json.loads(user_data_resp)
      user_id: str = user_data[0]["id"]
      print(f"{user_id=}")

      # create a role for the OIDC client
      keycloak.succeed(
          f"curl -sSf -H @admin_auth_header -X POST -H 'Content-Type: application/json' -d @${rolesDataJson} '${keycloakFrontendUrl}/admin/realms/${realm.realm}/clients/{client_id}/roles'",
      )

      # get role id
      role_data_resp: str = keycloak.succeed(
          f"curl -sSf -H @admin_auth_header '${keycloakFrontendUrl}/admin/realms/${realm.realm}/clients/{client_id}/roles'",
      )
      role_data: list = json.loads(role_data_resp)
      role_id: str = role_data[0]["id"]
      print(f"{role_id=}")

      role_post = json.dumps([{"id": role_id, "name": "${roles.name}"}])

      # Assign the role to the user
      keycloak.succeed(
          f"curl -vvvv -sSf -H @admin_auth_header -X POST -H 'Content-Type: application/json' -d '{role_post}' '${keycloakFrontendUrl}/admin/realms/${realm.realm}/users/{user_id}/role-mappings/clients/{client_id}'"
      )

      # put the environment file into a path to be served by nginx
      keycloak.succeed(
          "mkdir -p ${envFileDir}",
          "chmod 777 -R ${envFileDir}",
          "echo -n OIDC_PAGES_CLIENT_SECRET= > ${envFilePath}",
          "cat client_secret >> ${envFilePath}",
          "cp client_secret ${envFileDir}",
      )

      # grab the client secret from keycloak
      machine.succeed(
          "mkdir -p ${envFileDir}",
          "chmod 777 -R ${envFileDir}",
      )
      machine.wait_until_succeeds("curl http://${tmpDomain}/${envFileName} -o ${envFilePath}")
      machine.succeed("curl http://${tmpDomain}/client_secret -o client_secret")
      print(machine.succeed("cat ${envFilePath}"))

      # restart the service now that a valid environment file containing the client
      # secret exists
      machine.systemctl("restart oidc_pages.service")
      machine.wait_for_unit("oidc_pages.service")

      # wait for the server to start
      machine.wait_for_open_port(${builtins.toString oidcPagesInternalPort})

      # check systemd logging works
      machine.succeed('journalctl -u oidc_pages.service --grep "Starting server"')

      authenticated: str = "You are signed in as"
      unauthenticated: str = "Login to view documents..."

      # check we are not authenticated
      machine.succeed(
          "curl -sSf ${oidcPagesFrontendUrl} -o index.html",
          f"grep -v '{authenticated}' index.html",
          f"grep '{unauthenticated}' index.html",
      )

      # check unauthenticated users cannot view pages
      machine.succeed(
          'curl -sS -o /dev/null -w "%{http_code}" ${oidcPagesFrontendUrl}/p/notes/index.html | grep -q "^404$"',
          'curl -sS -o /dev/null -w "%{http_code}" ${oidcPagesFrontendUrl}/p/top_secret/index.html | grep -q "^404$"',
      )

      # get login form URL
      sso_login_url: str = machine.succeed(
          'curl -sSf -c pages_cookies.txt -w %{redirect_url} ${oidcPagesFrontendUrl}/login',
      ).rstrip()
      print(f"{sso_login_url=}")

      # extract the login form from the redirect
      machine.succeed(
          f"curl -sSf -c sso_cookies.txt -o login_page.html '{sso_login_url}'",
          "tidy -asxml -q -m login_page.html || true",
          "xml sel -T -t -m \"_:html/_:body/_:div/_:div/_:div/_:div/_:div/_:div/_:form[@id='kc-form-login']\" -v @action login_page.html > form_post_url.txt",
      )
      form_post_url: str = machine.succeed("cat form_post_url.txt").rstrip()
      print(f"{form_post_url=}")

      # post the login form and get the callback
      post_login_redirect_url: str = machine.succeed(
          f"curl -sSf -b sso_cookies.txt -w %{{redirect_url}} -d 'username=${user.username}' -d 'password=${password}' -d 'credentialId=' '{form_post_url}'",
      ).rstrip()
      print(f"{post_login_redirect_url=}")

      # make the callback, check that authentication succeeded
      machine.succeed(
          f"curl -L -sSf -b pages_cookies.txt -o index.html '{post_login_redirect_url}'",
          f"grep '{authenticated}' index.html",
          f"grep -v '{unauthenticated}' index.html",
      )
      print(machine.succeed("cat index.html"))

      # check that we can only view the pages we are authorized for
      machine.succeed(
          'curl -sS -b pages_cookies.txt -o /dev/null -w "%{http_code}" ${oidcPagesFrontendUrl}/p/notes/index.html | grep -q "^200$"',
          'curl -sS -b pages_cookies.txt -o /dev/null -w "%{http_code}" ${oidcPagesFrontendUrl}/p/top_secret/index.html | grep -q "^404$"',
      )

      # basic directory traversal attack check
      machine.succeed(
          'curl -sS -b pages_cookies.txt -o /dev/null -w "%{http_code}" ${oidcPagesFrontendUrl}/p/notes/../../top_secret/index.html | grep -q "^404$"',
      )
    '';
  }
