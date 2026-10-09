{
    flake.modules.nixos.sabnzbd = { lib, ... }: {
        nixpkgs.config.allowUnfreePredicate = pkg:
            builtins.elem (lib.getName pkg) [
                "unrar"
            ];

        services.sabnzbd = {
            enable = true;
            openFirewall = false;
            allowConfigWrite = true;
        };
    };
}