{ inputs, ... }:
{
	flake.modules.nixos.sops = { ... }: {
		imports = [ inputs.sops-nix.nixosModules.sops ];

		sops = {
			useSystemdActivation = true;
			age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
			gnupg.sshKeyPaths = [];
		};
	};
}
