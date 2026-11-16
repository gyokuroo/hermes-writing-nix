{ config, lib, pkgs, ... }:

let
  cfg = config.services.hermes-writing;
  q = lib.escapeShellArg;
  githubHome = cfg.github.home;
  githubWrapper = pkgs.writeShellApplication {
    name = "hermes-gh";
    runtimeInputs = with pkgs; [ coreutils gh ];
    text = ''
      export HERMES_GITHUB_HOME=${q githubHome}
      export HERMES_GITHUB_USER=${q cfg.github.user}
      export HERMES_REAL_GH_BIN=${q "${pkgs.gh}/bin/gh"}
      ${builtins.readFile ./scripts/hermes-gh.sh}
    '';
  };
  githubCredential = pkgs.writeShellApplication {
    name = "hermes-gh-git-credential";
    runtimeInputs = with pkgs; [ coreutils gh ];
    text = ''
      export HERMES_GITHUB_HOME=${q githubHome}
      export HERMES_GITHUB_USER=${q cfg.github.user}
      export HERMES_REAL_GH_BIN=${q "${pkgs.gh}/bin/gh"}
      ${builtins.readFile ./scripts/hermes-gh-git-credential.sh}
    '';
  };
  githubUserCheck = pkgs.writeShellApplication {
    name = "hermes-gh-user";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      export HERMES_GITHUB_HOME=${q githubHome}
      export HERMES_GITHUB_USER=${q cfg.github.user}
      export HERMES_GH_WRAPPER=${q "${githubWrapper}/bin/hermes-gh"}
      ${builtins.readFile ./scripts/hermes-gh-user.sh}
    '';
  };
  gitIdentity = pkgs.writeShellApplication {
    name = "hermes-writing-git";
    runtimeInputs = with pkgs; [ coreutils git ];
    text = ''
      export HERMES_GITHUB_HOME=${q githubHome}
      export HERMES_GITHUB_USER=${q cfg.github.user}
      export HERMES_GIT_AUTHOR_EMAIL=${q cfg.github.authorEmail}
      export HERMES_GIT_BIN=${q "${pkgs.git}/bin/git"}
      export HERMES_GH_CREDENTIAL_HELPER=${q "${githubCredential}/bin/hermes-gh-git-credential"}
      ${builtins.readFile ./scripts/hermes-writing-git.sh}
    '';
  };
  nativeShim = pkgs.runCommand "hermes-github-native-shim" { } ''
    mkdir -p "$out/bin"
    ln -s ${githubWrapper}/bin/hermes-gh "$out/bin/gh"
    ln -s ${gitIdentity}/bin/hermes-writing-git "$out/bin/git"
  '';
in
{
  options.programs.hermes-agent.writingGithub = {
    nativeShim = lib.mkOption { default = nativeShim; readOnly = true; type = lib.types.package; };
    path = lib.mkOption { default = "${nativeShim}/bin"; readOnly = true; type = lib.types.str; };
    ghWrapper = lib.mkOption { default = "${githubWrapper}/bin/hermes-gh"; readOnly = true; type = lib.types.str; };
    gitWrapper = lib.mkOption { default = "${gitIdentity}/bin/hermes-writing-git"; readOnly = true; type = lib.types.str; };
    credentialHelper = lib.mkOption { default = "${githubCredential}/bin/hermes-gh-git-credential"; readOnly = true; type = lib.types.str; };
  };
  config = lib.mkIf config.services.hermes-writing.enable {
    home.packages = [ githubCredential githubWrapper githubUserCheck gitIdentity ];
    services.hermes-agent.extraPackages = [ githubCredential githubWrapper gitIdentity ];
    home.activation.hermesGithubState = lib.hm.dag.entryAfter [ "hermesWritingStorageCheck" ] ''
      ${pkgs.coreutils}/bin/install -d -m 0700 ${q githubHome}
      ${pkgs.coreutils}/bin/install -d -m 0700 ${q "${githubHome}/gh"}
    '';
  };
}
