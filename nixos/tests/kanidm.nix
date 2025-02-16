{
  self,
  lib,
  pkgs,
}: let
  # reusing certificates from keycloak test
  kanidmDomain = "keycloak.local";
  oidcPagesDomain = "pages.local";

  oidcPagesFrontendUrl = "https://${oidcPagesDomain}";
  oidcPagesClientId = "oidc_pages";

  kanidmPort = 8443;
  kanidmFrontendUrl = "https://${kanidmDomain}:${toString kanidmPort}";
  kanidmUserPassword = "a8LRTUU7wgdwx5cKbbGa95JUxBEDJkYMHYybEu68dGSsgreF";
  kanidmUserEmail = "jane.doe@example.com";
  kanidmUsername = "testuser1";

  oidcPagesRoleMap = "pages_roles";

  pagesPath = "/tmp/pages";
in
  pkgs.nixosTest {
    name = "kanidm";

    nodes = {
      kanidm = {
        pkgs,
        nodes,
        ...
      }: {
        networking.hosts = {
          "127.0.0.1" = [kanidmDomain];
          "${nodes.machine.networking.primaryIPAddress}" = [oidcPagesDomain];
        };

        # for debug
        # nix run .#checks.x86_64-linux.kanidm.driverInteractive -L --log-lines 0
        # run start_all() in the python repl, login as root
        # virtualisation.forwardPorts = [
        #   {
        #     proto = "tcp";
        #     host.port = 8443;
        #     guest.port = kanidmPort;
        #   }
        # ];

        # reference for certificate generation:
        # nixpkgs/nixos/tests/common/acme/server/README.md
        security.pki.certificateFiles = [
          ./ca.keycloak.local.cert.pem
          ./ca.pages.local.cert.pem
        ];

        networking.firewall.allowedTCPPorts = [kanidmPort];

        services.kanidm = {
          package = pkgs.kanidmWithSecretProvisioning;
          enableServer = true;
          serverSettings = {
            bindaddress = "0.0.0.0:${toString kanidmPort}";
            domain = kanidmDomain;
            origin = kanidmFrontendUrl;
            tls_chain = ./keycloak.local.cert.pem;
            tls_key = ./keycloak.local.key.pem;
          };
          enableClient = true;
          clientSettings = {
            uri = kanidmFrontendUrl;
            verify_ca = true;
            verify_hostnames = true;
          };
          provision = let
            oidcPagesUserGroup = "oidc_pages_users";
            oidcPagesNotesGroup = "oidc_pages_notes";
          in {
            enable = true;
            systems.oauth2.${oidcPagesClientId} = {
              displayName = "OIDC Pages";
              public = true;
              enableLegacyCrypto = false;
              preferShortUsername = true;
              originUrl = "${oidcPagesFrontendUrl}/callback";
              originLanding = "${oidcPagesFrontendUrl}";
              scopeMaps.${oidcPagesUserGroup} = [
                "openid"
                "email"
                "profile"
              ];
              removeOrphanedClaimMaps = true;
              claimMaps.${oidcPagesRoleMap}.valuesByGroup.${oidcPagesNotesGroup} = [
                "notes"
              ];
            };
            persons.${kanidmUsername} = {
              displayName = "Test User";
              mailAddresses = [kanidmUserEmail];
            };
            groups = {
              "${oidcPagesUserGroup}".members = [kanidmUsername];
              "${oidcPagesNotesGroup}".members = [kanidmUsername];
            };
          };
        };

        environment.systemPackages = with pkgs; [
          ripgrep
        ];
      };

      machine = {
        config,
        pkgs,
        nodes,
        ...
      }: {
        imports = [self.nixosModules.default];
        nixpkgs.overlays = [self.overlays.default];
        services.oidc_pages = {
          enable = true;
          # give nginx access to oidc_pages.socket
          socketUser = config.services.nginx.user;
          settings = {
            public_url = oidcPagesFrontendUrl;
            issuer_url = "${kanidmFrontendUrl}/oauth2/openid/${oidcPagesClientId}";
            client_id = oidcPagesClientId;
            pages_path = pagesPath;
            log_level = "info";
            roles_path = [oidcPagesRoleMap];
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
            locations."/".proxyPass = "http://unix:${config.services.oidc_pages.bindPath}";
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
          "${nodes.kanidm.networking.primaryIPAddress}" = [kanidmDomain];
        };

        environment.systemPackages = with pkgs; [
          htmlq
        ];
      };
    };

    testScript = ''
      start_all()
      kanidm.wait_for_unit("kanidm.service")
      kanidm.wait_for_open_port(${toString kanidmPort})
      kanidm.wait_until_succeeds("curl -sSf ${kanidmFrontendUrl}")

      # set user password
      kanidm.succeed("KANIDM_RECOVER_ACCOUNT_PASSWORD=${kanidmUserPassword} kanidmd recover-account ${kanidmUsername} --from-environment")

      # create some pages
      page_content: str = "<p>Hello World from {name}</p>"
      notes_content: str = page_content.format(name="notes")
      top_secret_content: str = page_content.format(name="top_secret")
      machine.succeed(
          "mkdir -p ${pagesPath}/{notes,top_secret}",
          f"echo '{notes_content}' > ${pagesPath}/notes/index.html",
          f"echo '{top_secret_content}' > ${pagesPath}/top_secret/index.html",
      )

      machine.systemctl("restart oidc_pages.service")
      machine.wait_for_unit("oidc_pages.service")
      machine.wait_for_unit("oidc_pages.socket")

      # check systemd logging works
      machine.wait_until_succeeds('journalctl -u oidc_pages.service --grep "Starting server"')

      # check favicon exists
      machine.succeed("curl -sSf ${oidcPagesFrontendUrl}/assets/favicon.svg")

      authenticated: str = "You are signed in as"
      unauthenticated: str = "Login to view documents..."

      # check we are not authenticated
      index_html_pre_login: str = machine.succeed("curl -sSf ${oidcPagesFrontendUrl}")
      assert unauthenticated in index_html_pre_login
      assert authenticated not in index_html_pre_login

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
          "htmlq '#login' --attribute action --filename login_page.html --output username_form_post_url.txt",
      )
      username_form_post_url: str = "${kanidmFrontendUrl}" + machine.succeed("cat username_form_post_url.txt").rstrip()
      print(f"{username_form_post_url=}")

      # post the username, extract the password login form from the redirect
      machine.succeed(
          f"curl -sSf -b sso_cookies.txt -c sso_cookies.txt -o password_page.html -d 'username=${kanidmUsername}' -d 'password=' -d 'totp=' '{username_form_post_url}'",
          "htmlq '#login' --attribute action --filename password_page.html --output password_form_post_url.txt",
      )
      password_form_post_url: str = "${kanidmFrontendUrl}" + machine.succeed("cat password_form_post_url.txt").rstrip()
      print(f"{password_form_post_url=}")

      # post the password form and get the resume session redirect
      resume_session_url: str = machine.succeed(
          f"curl -sSf -b sso_cookies.txt -c sso_cookies.txt -w %{{redirect_url}} -d 'password=${kanidmUserPassword}' '{password_form_post_url}'",
      ).rstrip()
      print(f"{resume_session_url=}")
      assert resume_session_url.startswith("https://"), "Invalid resume session URL"

      # post the resume session url, get the consent page
      machine.succeed(
          f"curl -sSf -b sso_cookies.txt -c sso_cookies.txt -o consent_page.html '{resume_session_url}'",
          "htmlq '#login' --attribute action --filename consent_page.html --output consent_post_url.txt",
          "htmlq '#consent_token' --attribute value --filename consent_page.html --output consent_token.txt",
      )
      consent_form_post_url: str = "${kanidmFrontendUrl}" + machine.succeed("cat consent_post_url.txt").rstrip()
      consent_token: str = machine.succeed("cat consent_token.txt").rstrip()
      print(f"{consent_form_post_url=}")
      print(f"{consent_token=}")

      # post the consent form, get the callback
      post_login_redirect_url: str = machine.succeed(
          f"curl -sSf -b sso_cookies.txt -c sso_cookies.txt -w %{{redirect_url}} -d 'consent_token={consent_token}' '{consent_form_post_url}'",
      ).rstrip()
      print(f"{post_login_redirect_url=}")

      # make the callback
      index_html: str = machine.succeed(
          f"curl -L -sSf -b pages_cookies.txt '{post_login_redirect_url}'",
      )
      print(index_html)

      # check that authentication succeeded
      assert authenticated in index_html, "Authenticated string not in index"
      assert unauthenticated not in index_html, "Unauthenticated string in index"

      # check index.html only lists the pages we are authorized for
      assert "notes" in index_html, "notes not listed in index"
      assert "top_secret" not in index_html, "top_secret listed in index"

      # check that we can only view the pages we are authorized for
      machine.succeed(
          'curl -sS -b pages_cookies.txt -o /dev/null -w "%{http_code}" ${oidcPagesFrontendUrl}/p/notes/index.html | grep -q "^200$"',
          'curl -sS -b pages_cookies.txt -o /dev/null -w "%{http_code}" ${oidcPagesFrontendUrl}/p/top_secret/index.html | grep -q "^404$"',
      )

      # check that a correct page with invalid path results in a 404
      machine.succeed(
          'curl -sS -b pages_cookies.txt -o /dev/null -w "%{http_code}" ${oidcPagesFrontendUrl}/p/notes/not_a_real_page.html | grep -q "^404$"',
      )

      # basic directory traversal attack check
      machine.succeed(
          'curl -sS -b pages_cookies.txt -o /dev/null -w "%{http_code}" ${oidcPagesFrontendUrl}/p/notes/../../top_secret/index.html | grep -q "^404$"',
      )
    '';
  }
