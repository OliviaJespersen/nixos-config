{
    flake.modules.nixos.jellyfin = { ... }: {
        services.jellyfin = {
            enable = true;
            openFirewall = false;
        };

        # Permit access to the web interface on port 8096.
        networking.firewall.allowedTCPPorts = [ 8096 ];

        # Create a directory for media files.
        systemd.tmpfiles.rules = [
            "d /srv/media 0755 root root -"
            "d /srv/media/movies 0755 root root -"
            "d /srv/media/tv 0755 root root -"
        ];
    };
}