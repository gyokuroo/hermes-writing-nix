{ lib
, bash
, coreutils
, findutils
, git
, gnugrep
, jq
, psmisc
, rsync
, sqlite
, util-linux
, writeShellScriptBin
}:

let
  path = lib.makeBinPath [ bash coreutils findutils git gnugrep jq psmisc rsync sqlite util-linux ];
in
writeShellScriptBin "hermes-writing-backup" ''
    export PATH=${path}:$PATH
    exec ${bash}/bin/bash ${./backup-hermes.sh} "$@"
''
