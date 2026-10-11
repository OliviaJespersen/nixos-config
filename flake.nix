{
	description = "My headless NixOS server";

	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

		flake-parts.url = "github:hercules-ci/flake-parts";

		import-tree.url = "github:denful/import-tree";

		nixflix = {
			url = "github:kiriwalawren/nixflix";
			inputs.nixpkgs.follows = "nixpkgs";
		};

		sops-nix = {
			url = "github:Mic92/sops-nix";
			inputs.nixpkgs.follows = "nixpkgs";
		};
	};

	outputs = inputs:
		inputs.flake-parts.lib.mkFlake { inherit inputs; } {
			imports = [
				inputs.flake-parts.flakeModules.modules
				(inputs.import-tree ./modules)
			];

			systems = [];
		};
}
