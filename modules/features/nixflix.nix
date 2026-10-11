{ inputs, config, ... }:
let
	nixosModules = config.flake.modules.nixos;
in
{
	flake.modules.nixos.nixflix = { config, lib, ... }: {
		imports = [
			inputs.nixflix.nixosModules.default
			nixosModules.sops
		];

		# SABnzbd needs unrar to unpack downloaded archives.
		nixpkgs.config.allowUnfreePredicate = package: lib.getName package == "unrar";

		nixflix = {
			enable = true;
			mediaDir = "/data/media";
			downloadsDir = "/data/downloads";
			stateDir = "/var/lib";
			mediaUsers = [ "admin" ];
			serviceDependencies = [ "sops-install-secrets.service" ];

			sonarr = {
				enable = true;
				openFirewall = true;
				config = {
					apiKey._secret = config.sops.secrets."sonarr-api-key".path;
					hostConfig.password._secret = config.sops.secrets."sonarr-password".path;
				};
			};

			radarr = {
				enable = true;
				openFirewall = true;
				config = {
					apiKey._secret = config.sops.secrets."radarr-api-key".path;
					hostConfig.password._secret = config.sops.secrets."radarr-password".path;
				};
			};

			prowlarr = {
				enable = true;
				openFirewall = true;
				config = {
					apiKey._secret = config.sops.secrets."prowlarr-api-key".path;
					hostConfig.password._secret = config.sops.secrets."prowlarr-password".path;
				};
			};

			usenetClients.sabnzbd = {
				enable = true;
				openFirewall = true;
				settings.misc = {
					api_key._secret = config.sops.secrets."sabnzbd-api-key".path;
					nzb_key._secret = config.sops.secrets."sabnzbd-nzb-key".path;
					username = "admin";
					password._secret = config.sops.secrets."sabnzbd-password".path;
					inet_exposure = 4;
					host_whitelist = config.networking.hostName;
				};
			};

			jellyfin = {
				enable = true;
				apiKey._secret = config.sops.secrets."jellyfin-api-key".path;
				users.admin = {
					mutable = false;
					policy.isAdministrator = true;
					password._secret = config.sops.secrets."jellyfin-password".path;
				};
			};
		};

		systemd.services = lib.genAttrs [ "sonarr" "radarr" "prowlarr" "sabnzbd" "jellyfin" ]
			(name: {
				unitConfig.RequiresMountsFor = [
					config.nixflix.mediaDir
					config.nixflix.downloadsDir
					config.nixflix.stateDir
				];
			} // lib.optionalAttrs (name == "sabnzbd") {
				# SABnzbd does not use NixFlix's shared serviceDependencies option.
				after = [ "sops-install-secrets.service" ];
				requires = [ "sops-install-secrets.service" ];
			});

		# NixFlix requires root-owned, traversable parent directories.
		systemd.tmpfiles.settings."10-nixflix"."/data".d = {
			mode = "0755";
			user = "root";
			group = "root";
		};

		sops.secrets = lib.genAttrs [
			"sonarr-api-key" "sonarr-password"
			"radarr-api-key" "radarr-password"
			"prowlarr-api-key" "prowlarr-password"
			"sabnzbd-api-key" "sabnzbd-nzb-key" "sabnzbd-password"
			"jellyfin-api-key" "jellyfin-password"
		] (_: {
			# Reapply API configuration and cross-service connections on rotation.
			restartUnits = map (name: "${name}.service") (lib.filter
				(name: lib.any
					(service: name == service || lib.hasPrefix "${service}-" name)
					[ "sonarr" "radarr" "prowlarr" "sabnzbd" "jellyfin" ])
				(lib.attrNames config.systemd.services));
		});

		# Open only Jellyfin's HTTP port; discovery and HTTPS are not configured.
		networking.firewall.allowedTCPPorts = [ 8096 ];
	};
}
