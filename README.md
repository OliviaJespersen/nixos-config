# nixos-config

`cassiopeia` is a headless NixOS server. Feature files under `modules/features`
define `flake.modules.nixos` modules; `import-tree` discovers those files, and the
host explicitly imports its selected features. The NixFlix integration follows
this dendritic pattern, including a reusable sops-nix feature.

[NixFlix](https://kiriwalawren.github.io/nixflix/) manages only SABnzbd, Prowlarr,
Sonarr, Radarr and Jellyfin here. Other media services, reverse proxies,
PostgreSQL, VPN routing and Recyclarr remain disabled. NixFlix automatically
connects Prowlarr to Sonarr/Radarr, registers SABnzbd as their download client,
creates download categories, and creates Jellyfin's Shows and Movies libraries.

## Deploy and access

Include the new files in Git before using a Git-backed flake:

```sh
git add modules/features/nixflix.nix modules/features/sops.nix .sops.yaml secrets/cassiopeia.yaml
sudo nixos-rebuild switch --flake .#cassiopeia
```

Run the rebuild on `cassiopeia`. The five HTTP ports are opened in its firewall.
Use the server's IP address if its hostname does not resolve on your network.

| Service | Address | Username | Password file |
| --- | --- | --- | --- |
| SABnzbd | `http://cassiopeia:8080` | `admin` | `sabnzbd-password` |
| Prowlarr | `http://cassiopeia:9696` | `prowlarr` | `prowlarr-password` |
| Sonarr | `http://cassiopeia:8989` | `sonarr` | `sonarr-password` |
| Radarr | `http://cassiopeia:7878` | `radarr` | `radarr-password` |
| Jellyfin | `http://cassiopeia:8096` | `admin` | `jellyfin-password` |

Credentials are encrypted in `secrets/cassiopeia.yaml` using
[sops-nix](https://github.com/Mic92/sops-nix). During activation, sops-nix decrypts
them into root-only files under `/run/secrets`. All five services wait for secret
installation; changing a secret restarts the media services and their API
configuration units to apply API keys, inter-service connections and supported
password changes. **Jellyfin user passwords are only set during user creation**;
changing the SOPS secret does not change an existing user's password. See
"Changing credentials" below. Retrieve the initial Jellyfin password on the
server with:

```sh
sudo cat /run/secrets/jellyfin-password
```

Back up the decryption identities along with service state. Secrets are read at
runtime via NixFlix's `_secret` references; only ciphertext enters Git and the
Nix store. SABnzbd's `unrar` dependency is the only unfree package explicitly
permitted.

Media lives in `/data/media/tv` and `/data/media/movies`; Usenet downloads live
under `/data/downloads/usenet`. Service state lives under `/var/lib`. These paths
currently use the server's root filesystem; mount storage under `/data` before
downloading if you want to use another disk. The `admin` OS user has media group
access.

`/data` is explicitly created with root ownership and mode `0755`. NixFlix
manages the media/download directories and group permissions beneath it. If you
use another storage path, its parent directories must also be root-owned and
traversable by service users, as required by the
[directory options](https://kiriwalawren.github.io/nixflix/reference/core/).

## Encryption keys and editing secrets

The encrypted file contains eleven randomly generated local service credentials.
It is encrypted to both your existing local age public key and cassiopeia's
SSH-derived age public key, recorded as `admin` and `cassiopeia` in `.sops.yaml`.
Your local private identity remains outside this repo at
`~/.config/sops/age/keys.txt`.

The server is configured to decrypt using its existing SSH Ed25519 host private
key at `/etc/ssh/ssh_host_ed25519_key`. Its encryption recipient is already
configured. If that host key is replaced, obtain the new public key through an
already trusted connection or the server console:

```sh
# On cassiopeia:
cat /etc/ssh/ssh_host_ed25519_key.pub
```

Convert that public key on your workstation:

```sh
nix shell nixpkgs#ssh-to-age --command ssh-to-age < cassiopeia-host-key.pub
```

Replace the `&cassiopeia` public recipient under `keys` in `.sops.yaml` with the
resulting `age1...` value, then re-encrypt the existing data key to both recipients:

```sh
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
nix shell nixpkgs#sops --command sops updatekeys secrets/cassiopeia.yaml
nix shell nixpkgs#sops --command sops secrets/cassiopeia.yaml
```

The second command opens the secrets in your editor. For ordinary secret edits,
only that command is needed. Keep private keys out of Git; after changing an
encryption recipient, run `updatekeys` before deploying.

If you deployed the earlier credential generator, use its existing values from
`/var/lib/nixflix/secrets` to replace the new values in the SOPS editor before
migration, preserving existing passwords and API keys. The generator has been
removed from this configuration.

## Changing credentials

For API keys and Sonarr/Radarr/Prowlarr/SABnzbd passwords, edit the encrypted
file with SOPS and rebuild. Secret changes restart the five services and their
configuration units; expect a brief interruption to downloads and playback.

Jellyfin's `admin` user has `mutable = false`: NixFlix reapplies its configured
user settings and policy on rebuild. Passwords are a separate upstream
limitation: NixFlix does not update existing Jellyfin user passwords, regardless
of `mutable`. Change the password in Jellyfin's web interface, then record that
same password under `jellyfin-password` in the encrypted SOPS file to keep the
initialization/recovery value current. Do not delete and recreate the user to
rotate its password. See the
[Jellyfin user reference](https://kiriwalawren.github.io/nixflix/reference/jellyfin/users/).

## Supply your Usenet provider and indexers

Provider and indexer accounts are not supplied by this repository. Add your
actual settings inside `flake.modules.nixos.cassiopeia` in
`modules/hosts/cassiopeia.nix`, for example:

```nix
sops.secrets = {
  usenet-username = { restartUnits = [ "sabnzbd.service" ]; };
  usenet-password = { restartUnits = [ "sabnzbd.service" ]; };
  indexer-api-key = { restartUnits = [ "prowlarr-indexers.service" ]; };
};

nixflix.usenetClients.sabnzbd.settings.servers = [
  {
    name = "My Usenet provider";
    host = "news.example.com";
    port = 563;
    ssl = true;
    connections = 10; # Use your provider's allowed connection count.
    username._secret = config.sops.secrets.usenet-username.path;
    password._secret = config.sops.secrets.usenet-password.path;
  }
];

nixflix.prowlarr.config.indexers = [
  {
    name = "My indexer";
    schemaName = "Generic Newznab";
    baseUrl = "https://indexer.example.com";
    apiKey._secret = config.sops.secrets.indexer-api-key.path;
  }
];
```

Replace the example hosts with your provider/indexer details, then add
`usenet-username`, `usenet-password` and
`indexer-api-key` to the encrypted YAML file using the SOPS editor and rebuild.
These account secrets must contain the credentials issued by your providers.

Declare providers and indexers in Nix: SABnzbd's configuration is regenerated on
startup, and NixFlix removes Prowlarr indexers absent from the declared list.
Changes made solely in their web interfaces will not persist reliably.

## Required checks after deployment

Run these checks on `cassiopeia` after the first rebuild and after adding your
provider/indexer accounts:

1. Verify secret installation and service startup:

   ```sh
   sudo systemctl status sops-install-secrets sonarr radarr prowlarr sabnzbd jellyfin
   sudo systemctl --failed
   ```

   Confirm the NixFlix configuration units have also succeeded. If secret
   installation fails, check the encrypted file's recipient against the
   server's current SSH host key. Inspect failures with
   `sudo journalctl -b -u sops-install-secrets` or the failing unit's name.

2. Confirm storage is mounted where intended and has enough space:

   ```sh
   findmnt -T /data/media
   findmnt -T /data/downloads
   df -h /data/media /data/downloads /var/lib
   namei -l /data/media/tv /data/media/movies /data/downloads/usenet
   ```

   Paths use the root filesystem until you declare another mount in the host
   configuration. Configure storage before downloading. For storage that needs
   an unlock or preparation service, add it to `nixflix.serviceDependencies`
   and also to SABnzbd's `after` and `requires` lists: SABnzbd does not inherit
   that shared option. All five services already declare `RequiresMountsFor`
   for the configured media, downloads and state paths, so systemd waits for
   mounts declared for those paths.

3. Supply your actual Usenet provider and indexer accounts using the preceding
   section. Test the provider connection in SABnzbd and each indexer in
   Prowlarr. In Prowlarr, verify the automatically created Sonarr and Radarr
   applications can connect and synchronize indexers.

4. In Sonarr and Radarr, test the SABnzbd download client and confirm their root
   folders are `/data/media/tv` and `/data/media/movies`. Download a small item
   you are authorized to access and verify the full download/import flow.

5. Log into Jellyfin, confirm the Shows and Movies libraries contain the
   imported files, and test playback. Hardware acceleration is not configured;
   transcoding currently uses the CPU.

6. Reboot and repeat the service/storage checks to confirm secrets, mounts and
   services come up correctly without manual intervention.

7. Arrange backups of the encrypted secrets, your local age identity,
   cassiopeia's SSH host identity, and each service's state directory under
   `/var/lib`. Back up databases while the services are
   stopped or through a consistent application backup. Keep private identities
   out of Git and verify a restore can decrypt the secrets.

## Optional tuning after identifying the hardware

SABnzbd's cache currently uses the default `512M`. Its
[cache documentation](https://kiriwalawren.github.io/nixflix/reference/usenetClients/sabnzbd/settings/misc/)
recommends 25% of available RAM. Check `free -h` on the server under normal load
and leave room for Jellyfin, the Arr services and unpacking; then set
`nixflix.usenetClients.sabnzbd.settings.misc.cache_limit` to an appropriate size
in the host module. No RAM size is assumed by this configuration.

Jellyfin's `hardwareAccelerationType` defaults to `"none"`. If you want GPU
transcoding, identify the GPU and supported codecs first, configure the
corresponding NixOS graphics drivers, and set
`nixflix.jellyfin.encoding.hardwareAccelerationType` and supported decoding
codecs in the host module. Verify device access and actual transcoding after
rebuilding; choosing an unsupported backend can break playback. See the
[encoding reference](https://kiriwalawren.github.io/nixflix/reference/jellyfin/encoding/).

## Validate

```sh
nix flake check --no-build
nix eval --raw .#nixosConfigurations.cassiopeia.config.system.build.toplevel.drvPath
```
