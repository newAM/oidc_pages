# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added a configuration option `client_secret_file_path` to pass the client secret by file path instead of environment variable.

## [2.0.0] - 2025-02-08

### Added

- Added `bindPath` and `socketUser` options to the NixOS module.
- Added support for Kanidm
  - Added a `additional_scopes` option to the NixOS module.
  - Added a `roles_path` option to the NixOS module.

### Removed

- Removed the `bind_addrs` configuration option.

## [1.1.0] - 2024-07-20

### Added

- Added pretty page titles. Pages now display the HTML title instead of directory path.
- Added a `robots.txt` endpoint to the server.
- Added additional systemd hardening.

### Fixed

- Fixed missing favicon and CSS in NixOS release.
- Fixed missing audience mapper instructions in keycloak setup documentation.
- Fixed user receiving authentication errors if they have no roles.

## [1.0.0] - 2024-07-07

Initial release.

[Unreleased]: https://github.com/newAM/oidc_pages/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/newAM/oidc_pages/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/newAM/oidc_pages/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/newAM/oidc_pages/releases/tag/v1.0.0
