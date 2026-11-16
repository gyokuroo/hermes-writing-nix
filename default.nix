{ config, lib, pkgs, ... }:

let
  cfg = config.services.hermes-writing;
  q = lib.escapeShellArg;
  githubShimPath = config.programs.hermes-agent.writingGithub.path;
  lockRunner = pkgs.writeText "hermes-writing-lock.py" (builtins.readFile ./scripts/hermes-writing-lock.py);
  shellInit = pkgs.writeText "hermes-writing-shell-init" ''
    export PATH=${githubShimPath}:${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.git ]}:$PATH
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_TERMINAL_PROMPT=0
    export GH_CONFIG_DIR=${q "${cfg.github.home}/gh"}
    export GH_HOST=github.com
    export GH_PROMPT_DISABLED=1
    export GCM_INTERACTIVE=Never
    unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
    unset GIT_ASKPASS SSH_ASKPASS GIT_SSH_COMMAND GIT_SSH GIT_SSH_VARIANT
  '';
  shellWrapper = pkgs.writeShellScriptBin "bash" ''
    if [[ $# -eq 2 && ( "$1" == "-lic" || "$1" == "-lc" ) ]]; then
      exec ${pkgs.bash}/bin/bash --noprofile --norc -c "source ${shellInit}; $2"
    fi
    exec ${pkgs.bash}/bin/bash --noprofile --norc "$@"
  '';
  readyHelper = pkgs.writeShellApplication {
    name = "hermes-writing-ready";
    runtimeInputs = with pkgs; [ coreutils git util-linux ];
    text = ''
      export HERMES_STORAGE_MOUNT=${q cfg.storageMount}
      export HERMES_WRITING_STATE=${q cfg.hermesHome}
      export HERMES_WRITING_WORKTREE=${q cfg.workingDirectory}
      export HERMES_WRITING_BRANCH=${q cfg.branch}
      export HERMES_WRITING_REPO=${q cfg.repository}
      export HERMES_GIT_BIN=${q config.programs.hermes-agent.writingGithub.gitWrapper}
      ${builtins.readFile ./scripts/hermes-writing-ready.sh}
    '';
  };
  helperNames = [ "hermes-writing-init" "hermes-writing-checkpoint" "hermes-writing-commit" "hermes-writing-status" "hermes-writing-start" ];
  helper = name: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = with pkgs; [ config.services.hermes-agent.package coreutils findutils git gnugrep python3 ];
    text = ''
      export HERMES_WRITING_LOCK_RUNNER=${lockRunner}
      export HERMES_HOME=${q cfg.hermesHome}
      export HERMES_GIT_BIN=${q config.programs.hermes-agent.writingGithub.gitWrapper}
      export HERMES_WRITING_REPO=${q cfg.repository}
      export HERMES_WRITING_STATE=${q cfg.hermesHome}
      export HERMES_WRITING_WORKTREE=${q cfg.workingDirectory}
      export HERMES_WRITING_BRANCH=${q cfg.branch}
      export HERMES_STORAGE_MOUNT=${q cfg.storageMount}
      export HERMES_WRITING_READY=${q "${readyHelper}/bin/hermes-writing-ready"}
      ${builtins.readFile (./scripts + "/${name}.sh")}
    '';
  };
  helperPackages = map helper helperNames;
  gatewayPathPackages = [ config.services.hermes-agent.package pkgs.bash pkgs.coreutils pkgs.git readyHelper shellWrapper ]
    ++ config.services.hermes-agent.extraPackages ++ helperPackages;
in
{
  imports = [ ./github.nix ];

  options.services.hermes-writing = {
    enable = lib.mkEnableOption "Hermes writing agent";
    hermesHome = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
    workingDirectory = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
    repository = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
    branch = lib.mkOption { type = lib.types.str; default = "agent/hermes-writing"; };
    storageMount = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
    environmentFiles = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    github = {
      home = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
      user = lib.mkOption { type = lib.types.str; default = "gyokuroo"; };
      authorEmail = lib.mkOption { type = lib.types.str; default = "357243118+gyokuroo@users.noreply.github.com"; };
    };
    provider = lib.mkOption { type = lib.types.str; default = "openai-codex"; };
    model = lib.mkOption { type = lib.types.str; default = "gpt-6-sol"; };
  };

  config = lib.mkIf cfg.enable {
    assertions = map (name: { assertion = cfg.${name} != null; message = "services.hermes-writing.${name} must be set when Hermes writing is enabled"; })
      [ "hermesHome" "workingDirectory" "repository" "storageMount" ] ++ [{
        assertion = cfg.github.home != null;
        message = "services.hermes-writing.github.home must be set when Hermes writing is enabled";
      }];
    programs.hermes-agent.enable = true;
    services.hermes-agent = {
      enable = true;
      gateway.enable = true;
      hermesHome = cfg.hermesHome;
      workingDirectory = cfg.workingDirectory;
      environmentFiles = cfg.environmentFiles;
      settings = {
        model = { provider = cfg.provider; default = cfg.model; };
        cron = { allow_agent_scheduling = true; catch_up_missed = true; max_parallel_jobs = 1; model = cfg.model; model_provider = cfg.provider; preflight = true; retry_unreachable = true; };
        security = { redact_secrets = true; protected_instruction_files = true; };
        terminal = { auto_source_bashrc = false; shell_init_files = [ "${shellInit}" ]; };
      };
      hermesHomeFiles = {
        "SOUL.md" = ./SOUL.md;
        "writing/.hermes.md" = ./.hermes.md;
        "writing/prompt.md" = ./prompt.md;
        "writing/workflow.md" = ./workflow.md;
      };
    };
    home.activation.hermesWritingStorageCheck = lib.hm.dag.entryBefore [ "hermesAgentSetup" ] ''
      ${pkgs.util-linux}/bin/mountpoint -q ${q cfg.storageMount} || {
        printf '%s\n' ${q "Hermes writing storage is not mounted: ${cfg.storageMount}"} >&2
        exit 1
      }
    '';
    systemd.user.services.hermes-agent.Unit.ConditionPathExists = lib.mkIf (cfg.environmentFiles != []) (builtins.head cfg.environmentFiles);
    systemd.user.services.hermes-agent.Service.Environment = lib.mkAfter [ "PATH=${config.programs.hermes-agent.writingGithub.path}:${lib.makeBinPath gatewayPathPackages}" "SHELL=${shellWrapper}/bin/bash" ];
    systemd.user.services.hermes-agent.Service.ExecCondition = "${readyHelper}/bin/hermes-writing-ready";
    home.packages = [ readyHelper ] ++ helperPackages;
  };
}
