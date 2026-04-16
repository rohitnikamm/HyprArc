# Releasing HyprArc

Manual release workflow. Automate once cadence is stable (see Phase 6 of the
Homebrew distribution plan for the GitHub Actions sketch).

## Prerequisites (one-time)

1. Developer ID certificate in login keychain.
2. Notarization credentials stored:
   ```bash
   xcrun notarytool store-credentials "HyprArc" \
     --apple-id "<apple-id>" --team-id "26H5KWS9TD"
   ```
3. `gh` CLI authenticated: `gh auth status`.
4. Push access to both `rohitnikamm/HyprArc` and `rohitnikamm/homebrew-hyprarc`.

## Cut a release

1. **Bump version** in Xcode — target HyprArc → General tab → `MARKETING_VERSION`
   (update `CURRENT_PROJECT_VERSION` only when build metadata matters). Commit.

2. **Tag + push**
   ```bash
   git commit -am "bump: vX.Y.Z"
   git tag -a vX.Y.Z -m "HyprArc X.Y.Z"
   git push && git push --tags
   ```

3. **Build signed + notarized DMG**
   ```bash
   ./scripts/build-dmg.sh
   # → build/HyprArc.dmg
   ```

4. **Publish GitHub Release**
   ```bash
   gh release create vX.Y.Z build/HyprArc.dmg \
     --title "HyprArc X.Y.Z" \
     --notes-from-tag
   ```

5. **Capture SHA-256**
   ```bash
   shasum -a 256 build/HyprArc.dmg
   ```

6. **Update the cask** in `rohitnikamm/homebrew-hyprarc`:
   ```bash
   cd ~/dev/homebrew-hyprarc
   # In Casks/hyprarc.rb: bump `version` + `sha256`
   brew audit --cask Casks/hyprarc.rb   # must be clean
   git commit -am "hyprarc X.Y.Z"
   git push
   ```

7. **Verify** — on a second Mac or after `brew untap rohitnikamm/hyprarc`:
   ```bash
   brew tap rohitnikamm/hyprarc
   brew install --cask hyprarc
   brew livecheck hyprarc   # should show current version
   ```

8. **Announce** (optional). Users upgrade with `brew upgrade --cask hyprarc`.

## Gotchas

- **Notarization takes ~3–8 minutes** — it's a network call to Apple.
- **`gh release create` fails silently** if the tag isn't pushed yet. Always
  `git push --tags` first.
- **Cask URL must match exactly** — one typo breaks install for everyone.
  `curl -IL` the URL before pushing the cask update.
- **`shasum` must be re-run** every release. The DMG changes even if source
  is identical (notarization ticket + timestamps).
- **Deployment target bumps** — if `MACOSX_DEPLOYMENT_TARGET` moves, update
  `depends_on macos:` in the cask.
