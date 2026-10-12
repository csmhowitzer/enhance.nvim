# Structured Helper Packaging

## Purpose
- Maintainer procedure for shipping pinned SQL Server/MySQL and PostgreSQL executables with zero user-side compilation, SDK/runtime installation, PATH changes, or helper configuration.
- All three structured query paths passed C03 live acceptance. Publication is separate: public manifests remain disabled until target validation, asset publication, and public installation checks pass. CLI tools are still needed for probes/completion/explorer/catalog operations.

## Installer Contract
- `~/plugins/enhance.nvim/build.lua` is automatically discovered by lazy.nvim when the user's spec has no explicit `build` hook. It loads the installer by filename, independently of runtimepath.
- `~/plugins/enhance.nvim/helper-release.json` ships the exact immutable helper tag and per-platform SHA-256 hashes. Never use a remote `latest` pointer or accept a downloaded checksum as the trust anchor.
- `~/plugins/enhance.nvim/helper-postgres-release.json` independently pins the PostgreSQL companion. The build hook installs both; neither depends on the developer resolver or parent plugins checkout.
- `~/plugins/enhance.nvim/lua/enhance/helper_install.lua` verifies both downloads and cache hits. It stages downloads beside their final destination, verifies them, sets executable permissions, then renames them into place. Failed updates do not remove older releases.
- Release assets are individual self-contained executables, not archives. This avoids archive traversal and eliminates user extraction tools.
- Cache layout: `stdpath('data')/enhance/helper/<release>/<rid>/<sha256>-<asset>`. Nothing is added to PATH. Path lookup and health checks never download.
- Initial release targets: macOS ARM64 and Ubuntu 24.04 Linux x64/ARM64 (including WSL2). AL's CPU and exact Ubuntu version are unconfirmed; preparing both Linux architectures avoids guessing. WSL2 uses Linux executables. Native Windows, Intel macOS, other distributions, and Alpine/musl are outside the initial verification scope. Only advertise targets validated with the actual drivers.
- Installer prerequisites are standard OS tools: curl plus shasum, sha256sum, or Windows PowerShell Get-FileHash. Self-contained .NET still depends on OS libraries, certificate trust, and authentication prerequisites.

## Build Artifacts
- `~/plugins/enhance.nvim/helper/enhance-helper.csproj` emits `enhance-helper` (or `enhance-helper.exe` on Windows). Dependencies were added through dotnet CLI: Microsoft.Data.SqlClient 7.1.1, with `~/plugins/enhance.nvim/helper/packages.lock.json` generated through package restore.
- Use a supported, security-patched .NET 10 LTS SDK/runtime and pinned driver versions. Start without trimming or Native AOT; validate actual authentication/driver paths. Explicitly set EnhanceReleaseTargetFramework=net10.0: `~/plugins/enhance.nvim/Directory.Build.targets` applies it to the helper and test project references. Ordinary developer builds remain net8.0 to preserve the existing setup; they are not public release builds.
- Publish separately for osx-arm64, linux-x64, and linux-arm64. Select the current stable security-patched runtime from official release metadata; the candidate built on ML used SDK 10.0.401/runtime 10.0.12. Never rely on the old developer SDK's default runtime.

```sh
dotnet publish helper/enhance-helper.csproj -c Release -r linux-x64 --self-contained true \
  -p:EnhanceReleaseTargetFramework=net10.0 -p:RuntimeFrameworkVersion=10.0.12 \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:DebugType=None -p:DebugSymbols=false -o dist/release-publish/linux-x64
```

- Single-file extraction must use a private writable location. Native dependencies and macOS signing/notarization behavior need validation on actual clean machines; bundling alone does not establish portability.
- Keep only the executable in each runtime output directory. The packager refuses sidecars rather than silently dropping runtime dependencies.
- Build the Go companion separately with CGO_ENABLED=0, GOOS=linux/darwin, and GOARCH=amd64/arm64. Package with --helper postgres into a distinct output directory. Toolchain/build instructions belong to `~/plugins/ENHANCE_DEVELOPMENT.md`, not user installation instructions.

## Package a Release
- Run from `~/plugins/enhance.nvim/`. Python 3 is a maintainer/test dependency only; end-users do not need it.

```sh
python3 scripts/package-helper.py \
  --publish-dir dist/release-publish \
  --output-dir dist/release-main \
  --release helper-vMAJOR.MINOR.PATCH
```

- `~/plugins/enhance.nvim/scripts/package-helper.py` produces one asset per provided runtime directory and a matching `helper-release.json`. It hashes exact binary bytes and refuses empty executables, sidecars, unsupported targets, oversized files, mutable release names, and existing output directories.
- Package only binaries smoke-tested on their target OS/CPU. Fixture tests prove packaging integrity, not that .NET/SqlClient executes on every target.

## Publish and Pin
- Publishing and repository changes remain user-controlled; no git or publishing operations were performed by the agent.
- Upload generated executable assets to the matching release tag at `csmhowitzer/enhance.nvim`. Never replace assets under an existing published tag; issue a new helper version instead.
- Copy the generated manifest into `~/plugins/enhance.nvim/helper-release.json` through a reviewed targeted change after the assets are available. The checked-in `release: false` currently prevents development installs from fetching nonexistent artifacts.
- Before distributing that plugin checkout, verify all advertised downloads, checksums, installation/update behavior, and offline cache reuse. Run `nvt ~/plugins/enhance.nvim`.
- Maintain runtime security updates by rebuilding and issuing new pinned helper releases. A self-contained helper does not inherit system .NET patches.

## Failure and Recovery
- An installation failure is surfaced to lazy.nvim; there is no raw-output or unverified-executable fallback.
- Previously verified versions remain on disk, but a newly pinned version is not silently replaced with an older one.
- Rebuild through lazy.nvim after fixing network/permissions problems. For offline installation, place the published executable at the exact manifest-derived cache path with executable permissions; integrity is still checked.
- A crash can leave the per-target `.lock` directory. Confirm no installer is running before removing only the reported lock directory; do not clear broad caches.

## Verification Boundary
- Regression tests cover install pinning, validation, corruption repair, cache reuse, update failures, locks, permissions, real binary hashing/filesystem operations, lazy.nvim build dispatch, health diagnostics, and maintainer asset generation.
- The .NET protocol harness runs through `~/plugins/enhance.nvim/tests/helper_protocol_spec.lua` under nvt. Set ENHANCE_TEST_DOTNET10 to an explicit .NET 10 executable to restore/build/run both projects against the release target, including all 14 behavior scenarios. SDKs are development-only requirements.
- On ML, .NET 10 candidates passed the 575-test opted-in run, including six real SQL Server/MySQL/PostgreSQL checks and copy/popup fidelity. Set ENHANCE_TEST_RELEASE_CANDIDATE to a directory with main/postgres packaged manifests and ENHANCE_C03_LIVE=1 to explicitly verify candidate packages against the already-authorized Docker connections. Ordinary runs do not contact databases.
- Linux acceptance passed on 2026-10-11 (ML): **587 tests, 0 failures**, consisting of 571 ordinary tests plus 16 opt-in checks in `~/plugins/enhance.nvim/tests/helper_linux_release_spec.lua`. Actual main/PostgreSQL candidate binaries passed version/private-malformed-input checks and read-only SQL Server/MySQL/PostgreSQL fidelity/later-error checks on Ubuntu 24.04 ARM64 and x64. Exact SHA-256 bytes were verified before launching. x64 ran under Docker Desktop emulation on ARM64, not a native x64 host; neither architecture's container checks establish AL's actual WSL2 GitHub-based installation.
- Clean Ubuntu images used only apt-provided libicu74, ca-certificates, libssl3t64, and libgssapi-krb5-2, plus their normal dependencies. No SDK/runtime/compiler was installed. The user's minimal-Ubuntu check reproduced an ICU abort; installing libicu74 restored structured invalid_request responses. This is the tested library set, not proof that every listed package is independently necessary. Public setup also needs curl for downloads and Ubuntu's standard sha256sum. Do not ask end-users to install .NET/Go or silently run apt/sudo from the plugin installer. User commands are in `~/plugins/enhance.nvim/README.md` and `~/plugins/enhance.nvim/doc/enhance.txt`.
- The documented GitHub/lazy.nvim specifications now use Enhance as the repository and Dadbod/completion in dependencies. Two failing example checks reproduced the old positional-repository error before correction; `~/plugins/enhance.nvim/tests/installation_examples_spec.lua` verifies the executable Lua examples. Normal offline suite: **571 passing**; parent developer suite: **8 passing**. No personal credentials/Docker access occurs without explicit test opt-in.
- Both macOS candidate executables passed codesign --verify --strict and checksum verification. Their signatures are ad-hoc, not Developer ID signatures or notarization; this does not establish Gatekeeper behavior on a clean downloaded installation.
- Public release download/pinning, clean macOS download/signing behavior, fresh GitHub/lazy.nvim installation/update/offline reuse, and AL WSL2 verification remain gates. No git or publication operation was performed.
