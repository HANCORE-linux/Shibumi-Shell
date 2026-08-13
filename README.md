<div align="center">

# Shibumi Shell

<img src="docs/screenshots/shibumi-hikiryo-landing.png"
     alt="Shibumi Shell project artwork"
     width="100%">

<h3>A native bar and plugin suite for Omarchy Quattro</h3>

<p><sub>Shibumi brings the approved QS Rise V1 and V2 layouts, controls,
widgets, panels, and interaction model into Omarchy's existing shell
process.</sub></p>

[Get started](docs/getting-started.md) ·
[Documentation](docs/README.md) ·
[Release status](docs/release-readiness.md)

The current `0.1.1-beta.8` candidate is reviewed against Omarchy
`4.0.0.r1664.gb99fd91-1` and Quickshell
`0.3.0.r20.g28771c7-1`. See the
[Shibumi host compatibility record](docs/architecture/quattro-compatibility.md)
for the latest validated host versions.

</div>

<table>
  <tr>
    <td align="center" width="50%">
      <strong>Quick</strong><br>
      <img src="docs/screenshots/shibumi-quick.png"
           alt="Shibumi Quick controls with V2 active"
           width="100%">
    </td>
    <td align="center" width="50%">
      <strong>Configure</strong><br>
      <img src="docs/screenshots/shibumi-configure.png"
           alt="Shibumi Configure landing page"
           width="100%">
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <strong>Bars</strong><br>
      <img src="docs/screenshots/shibumi-bars.png"
           alt="Shibumi V2 bar form controls"
           width="100%">
    </td>
    <td align="center" width="50%">
      <strong>Plugins</strong><br>
      <img src="docs/screenshots/shibumi-plugins.png"
           alt="Shibumi plugin catalog"
           width="100%">
    </td>
  </tr>
</table>

## Install

> [!IMPORTANT]
> `0.1.1-beta.8` is a package candidate. AUR registration is currently
> unavailable, so the package is not published there yet.
> Until its release asset and AUR package are published, use the source path
> below. Shibumi supports Omarchy Quattro only.

After AUR publication, the supported one-command installation is:

```bash
omarchy pkg aur add shibumi-shell && shibumi-shell install --yes
```

Pacman resolves the required runtime packages and skips dependencies already
provided by the system. The explicit Shibumi command then stages and verifies
the 24 user plugins without a root package hook touching the user's config.

Until the AUR package is released, use this transitional source installation:

```bash
sudo pacman -S --needed python jq curl networkmanager power-profiles-daemon upower xdg-utils libnotify wl-clipboard ttf-material-symbols-variable ttf-jetbrains-mono-nerd-basic noto-fonts-cjk adwaita-fonts
git clone https://github.com/HANCORE-linux/Shibumi-Shell.git
cd Shibumi-Shell
./scripts/shibumi-suite install --yes
```

Update the transitional source installation with:

```sh
cd Shibumi-Shell
git pull --ff-only
./scripts/shibumi-suite update --yes
```

This transitional source command asks for root privileges only while Pacman
installs missing runtime commands and fonts. The Shibumi lifecycle itself runs
as the desktop user and writes only user-scoped plugin state.

[Installation, updates, recovery, and removal](docs/install.md)

### Uninstall

Remove all managed Shibumi plugins and restore the stock Omarchy bar:

```bash
shibumi-shell uninstall --yes && omarchy pkg drop shibumi-shell
```

For the transitional source installation, run this from its checkout instead:

```bash
./scripts/shibumi-suite uninstall --yes
```

Do not run `omarchy pkg drop shibumi-shell` after a source uninstall: that
workflow did not install a `shibumi-shell` package. Pacman-managed runtime
dependencies remain installed because they may be shared with other software.

[Uninstall options and settings preservation](docs/install.md#uninstall)

## Documentation

- [Get started](docs/getting-started.md)
- [Install, update, repair, or remove Shibumi](docs/install.md)
- [Configure the shell](docs/configuration.md)
- [Explore the plugin catalog](docs/plugins/README.md)
- [Use Shibumi plugins with other bars](docs/plugin-compatibility.md)
- [Troubleshoot a problem](docs/development/troubleshooting.md)
- [Understand the architecture](docs/architecture/overview.md)
- [Check Omarchy Quattro compatibility](docs/architecture/quattro-compatibility.md)
- [Review current release readiness](docs/release-readiness.md)
- [Browse all documentation](docs/README.md)
- Credit: [Lacuna Shell](https://github.com/OldJobobo/lacuna-shell) by
  [@OldJobobo](https://github.com/OldJobobo) provided structural inspiration
  for the Omarchy Quattro plugin-suite layout

[Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md) ·
[MIT License](LICENSE)
