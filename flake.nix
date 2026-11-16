{
  description = "Hermes Agent NixOS writing module";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hermes-agent = {
      url = "github:NousResearch/hermes-agent/v0.23.1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = { self, nixpkgs, hermes-agent, home-manager, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkHermes = pkgs:
        let
          patchelf0192 = pkgs.patchelf.overrideAttrs (_: {
            version = "0.19.2";
            src = pkgs.fetchurl {
              url = "https://github.com/NixOS/patchelf/releases/download/0.19.2/patchelf-0.19.2.tar.bz2";
              hash = "sha256-1K2aTlxongkRnOLzCpSw6LT5jHhZASPqIWZeNMaSiAE=";
            };
            patches = [ ];
          });
          pmPackages = pkgs.callPackage "${hermes-agent}/nix/pm-packages.nix" { patchelf = patchelf0192; };
        in
        {
          package = hermes-agent.packages.${pkgs.system}.default.override { inherit pmPackages; };
          inherit pmPackages;
        };
    in {
      homeManagerModules.default = {
        imports = [
          hermes-agent.homeManagerModules.default
          ./default.nix
          ({ lib, pkgs, ... }: {
            services.hermes-agent.package = lib.mkDefault (mkHermes pkgs).package;
          })
        ];
      };
      packages = forAllSystems (system: {
        hermes-agent = (mkHermes nixpkgs.legacyPackages.${system}).package;
        hermes-writing-backup = nixpkgs.legacyPackages.${system}.callPackage ./packages/backup.nix { };
      });
      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          hermesBuild = mkHermes pkgs;
          hermesPackage = hermesBuild.package;
          makeConfig = module: home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeManagerModules.default
              module
            ];
          };
          enabled = makeConfig {
            home.username = "test";
            home.homeDirectory = "/home/test";
            home.stateVersion = "24.05";
            services.hermes-writing = {
              enable = true;
              hermesHome = "/srv/hermes";
              workingDirectory = "/srv/worktree";
              repository = "/srv/repository";
              storageMount = "/srv";
              environmentFiles = [ "/srv/hermes.env" ];
              github.home = "/srv/github";
              github.user = "gyokuroo";
              github.authorEmail = "357243118+gyokuroo@users.noreply.github.com";
            };
          };
          disabled = makeConfig {
            home.username = "test";
            home.homeDirectory = "/home/test";
            home.stateVersion = "24.05";
          };
          environment = enabled.config.systemd.user.services.hermes-agent.Service.Environment;
          pathEntries = builtins.filter (entry: pkgs.lib.hasPrefix "PATH=" entry) environment;
          homePackageNames = builtins.map (package: package.name or "") enabled.config.home.packages;
          check = assert enabled.config.services.hermes-agent.hermesHome == "/srv/hermes";
            assert enabled.config.services.hermes-agent.workingDirectory == "/srv/worktree";
            assert enabled.config.services.hermes-agent.package.drvPath == hermesPackage.drvPath;
            assert enabled.config.programs.hermes-agent.package.drvPath == hermesPackage.drvPath;
            assert enabled.config.systemd.user.services.hermes-agent.Unit.ConditionPathExists == "/srv/hermes.env";
            assert pathEntries != [];
            assert pkgs.lib.hasPrefix "PATH=${enabled.config.programs.hermes-agent.writingGithub.path}:" (builtins.elemAt pathEntries ((builtins.length pathEntries) - 1));
            assert builtins.all (name: builtins.elem name homePackageNames) [
              "hermes-writing-ready"
              "hermes-writing-init"
              "hermes-writing-checkpoint"
              "hermes-writing-commit"
              "hermes-writing-status"
              "hermes-writing-start"
            ];
            assert !(builtins.elem enabled.config.programs.hermes-agent.writingGithub.nativeShim enabled.config.home.packages);
            assert builtins.all (name: !(pkgs.lib.hasInfix "hermes" name))
              (builtins.map (package: package.name or "") disabled.config.home.packages);
            pkgs.runCommand "hermes-writing-module-check" { } "touch $out";
        in {
          module = check;
          hermes-agent = pkgs.runCommand "hermes-agent-build-smoke" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
            mkdir -p "$out" "$TMPDIR/home" "$TMPDIR/hermes"
            test -x ${hermesPackage}/bin/hermes
            HOME="$TMPDIR/home" HERMES_HOME="$TMPDIR/hermes" ${hermesPackage}/bin/hermes --version > "$out/hermes-version" 2>&1
            grep -qi hermes "$out/hermes-version"
            ${hermesBuild.pmPackages.node}/bin/node --version > "$out/node-version"
            ${hermesBuild.pmPackages.pnpm}/bin/pnpm --version > "$out/pnpm-version"
            ${hermesBuild.pmPackages.python}/bin/python3 --version > "$out/python-version"
          '';
        });
    };
}
