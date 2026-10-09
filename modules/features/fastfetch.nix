{
    flake.modules.nixos.fastfetch = { pkgs, ... }: {
        environment.systemPackages = [
            pkgs.fastfetch
        ];
    };
}