# Ephemeral sync-check machine: one Nethermind+ETC node from a published release bundle, for a
# release gate that watches it sync. Parametrized by `syncCheck` (passed via specialArgs in
# flake.nix): { kind, version, hash, rpcAllowFrom, disk }.
#   kind = "snap"    → the release's own config (snap from its shipped pivot), without ancient
#                      bodies/receipts: the gate is reaching head, not a full history.
#   kind = "genesis" → full sync from block 0.
# The node is the whole box: whoever provisioned it polls its JSON-RPC and destroys it. Nothing
# on the box reports back or holds a provider credential.
{
  lib,
  pkgs,
  syncCheck,
  ...
}:
let
  rpcPort = 8545;
in
{
  imports = [
    ./disko.nix
    ../../modules/base.nix
    ../../modules/clients/nethermind.nix
  ];

  networking.hostName = "sync-check-${syncCheck.kind}";

  etc.nethermind.instances.check = {
    package = pkgs.callPackage ../../pkgs/nethermind-etc-bin.nix {
      inherit (syncCheck) version hash;
    };
    network = "classic";
    jsonRpc = {
      host = "0.0.0.0";
      port = rpcPort;
      modules = [
        "Eth"
        "Net"
      ];
    };
    metrics.enable = false;
    # The module defaults (1 GiB + 512 MiB) are sized for standing nodes; the genesis box is
    # the cheapest plan and only replays early, small blocks.
    pruning = lib.mkIf (syncCheck.kind == "genesis") {
      cacheMb = 256;
      dirtyCacheMb = 256;
    };
    extraArgs =
      {
        genesis = [
          "--Sync.FastSync"
          "false"
          "--Sync.SnapSync"
          "false"
        ];
        snap = [
          "--Sync.DownloadBodiesInFastSync"
          "false"
          "--Sync.DownloadReceiptsInFastSync"
          "false"
        ];
      }
      .${syncCheck.kind};
  };

  # JSON-RPC answers only the poller. The p2p port is opened by the nethermind module.
  networking.firewall.extraCommands = lib.concatMapStrings (src: ''
    iptables -A nixos-fw -p tcp -s ${src} --dport ${toString rpcPort} -j nixos-fw-accept
  '') syncCheck.rpcAllowFrom;
}
