{ inputs, config, ... }:
let
	nixosModules = config.flake.modules.nixos;
in
{
	flake.modules.nixos.cassiopeia = { config, ... }: {
		imports = [
			./_hardware-configuration.nix
			nixosModules.ssh
			nixosModules.btop
			nixosModules.fastfetch
			nixosModules.nixflix
		];

		networking.hostName = "cassiopeia";
		sops.defaultSopsFile = ../../secrets/cassiopeia.yaml;
		networking.useDHCP = true;

		boot.loader.systemd-boot.enable = true;
		boot.loader.efi.canTouchEfiVariables = true;

		users.users.admin = {
			isNormalUser = true;
			extraGroups = [ "wheel" ];

			openssh.authorizedKeys.keys = [
				"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPl+cv4jCSqSGRxFe7TjzBMob+sjx3A+RggRpSOjtjW/ puppy@Olivias-MacBook-Pro.local"
			];
		};

		nix.settings.experimental-features = [
			"nix-command"
			"flakes"
		];

		system.stateVersion = "26.05";
	};

	flake.nixosConfigurations.cassiopeia = 
		inputs.nixpkgs.lib.nixosSystem {
			modules = [
				config.flake.modules.nixos.cassiopeia
			];
		};
}
