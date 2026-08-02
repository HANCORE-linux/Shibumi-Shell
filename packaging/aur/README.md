# AUR package candidate

`PKGBUILD` installs only the immutable Shibumi payload and the stable
`/usr/bin/shibumi-shell` command. It has no install hook and never writes to a
user home directory.

The unversioned `omarchy` dependency is intentional. Quattro's `omarchy-dev`
package provides `omarchy` without a virtual version, so a dependency such as
`omarchy>=4` would reject a valid Quattro development host. Shibumi verifies
its required Quattro APIs before any user-state mutation instead.

Publication remains blocked while `_source_sha256` is `SKIP`. For local package
rehearsal, run:

```bash
./scripts/rehearse-aur-package
```

For release checks after publishing the immutable GitHub release asset, run:

```bash
./scripts/check-aur-package --publish-check
```
