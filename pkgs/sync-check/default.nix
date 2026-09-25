# Operator side of a sync-check box (lib.mkSyncCheck):
#   sync-check install <snap|genesis> <vm-ipv4> <plugin-version> <bundle-sha256-hex>
#     installs the box onto a fresh VM with nixos-anywhere;
#   sync-check logs <vm-ipv4>
#     prints the tail of the node's journal (post-mortem before the VM is destroyed).
# Meant to be the forced command of a dedicated SSH key on the orchestrating host, so every
# argument is validated: whoever holds that key can only do the above, not run arbitrary commands.
#
# Host-side settings (environment, never caller-controlled):
#   SYNC_CHECK_RPC_ALLOW   poller address(es) allowed to reach the node JSON-RPC, space-separated
#   SYNC_CHECK_IDENTITY    SSH key the VM was created with (root login)
#   SYNC_CHECK_ADMIN_KEYS  optional file of public keys for the box's admin account
{
  writeShellApplication,
  nix,
  nixos-anywhere,
  openssh,
  etc-nix,
}:
writeShellApplication {
  name = "sync-check";
  runtimeInputs = [
    nix
    nixos-anywhere
    openssh
  ];
  text = ''
    # Called directly or as a forced command (arguments then arrive in SSH_ORIGINAL_COMMAND).
    if [ "$#" -eq 0 ] && [ -n "''${SSH_ORIGINAL_COMMAND:-}" ]; then
      read -r -a args <<<"$SSH_ORIGINAL_COMMAND"
      set -- "''${args[@]}"
    fi

    usage() {
      echo "usage: sync-check install <snap|genesis> <vm-ipv4> <plugin-version> <bundle-sha256-hex>" >&2
      echo "       sync-check logs <vm-ipv4>" >&2
      exit 2
    }
    check_ip() {
      [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "bad ip: $1" >&2; exit 2; }
    }

    : "''${SYNC_CHECK_IDENTITY:?SSH key the VM was created with}"
    # Ephemeral VMs reuse addresses: never trust or record their host keys.
    ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

    case "''${1:-}" in
      install)
        [ "$#" -eq 5 ] || usage
        kind=$2 ip=$3 version=$4 sha256=$5
        [[ "$kind" =~ ^(snap|genesis)$ ]] || { echo "bad kind: $kind" >&2; exit 2; }
        check_ip "$ip"
        [[ "$version" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || { echo "bad version: $version" >&2; exit 2; }
        [[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || { echo "bad sha256: $sha256" >&2; exit 2; }
        : "''${SYNC_CHECK_RPC_ALLOW:?poller address(es) allowed to reach the node JSON-RPC}"

        allow=""
        for a in $SYNC_CHECK_RPC_ALLOW; do allow+="\"$a\" "; done
        admin_keys=""
        if [ -n "''${SYNC_CHECK_ADMIN_KEYS:-}" ]; then
          while IFS= read -r key; do
            [ -n "$key" ] && admin_keys+="\"$key\" "
          done <"$SYNC_CHECK_ADMIN_KEYS"
        fi
        sri=$(nix --extra-experimental-features nix-command hash convert --hash-algo sha256 --to sri "$sha256")

        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT
        cat >"$work/flake.nix" <<EOF
    {
      inputs.etc-nix.url = "path:${etc-nix}";
      outputs = { etc-nix, ... }: {
        nixosConfigurations.box = etc-nix.lib.mkSyncCheck {
          kind = "$kind";
          version = "$version";
          hash = "$sri";
          rpcAllowFrom = [ $allow];
          sshKeys = [ $admin_keys];
        };
      };
    }
    EOF
        opt_args=()
        for o in "''${ssh_opts[@]}"; do [ "$o" = -o ] || opt_args+=(--ssh-option "$o"); done
        nixos-anywhere \
          --flake "$work#box" \
          --build-on-remote \
          -i "$SYNC_CHECK_IDENTITY" \
          "''${opt_args[@]}" \
          "root@$ip"
        ;;
      logs)
        [ "$#" -eq 2 ] || usage
        check_ip "$2"
        ssh "''${ssh_opts[@]}" -o ConnectTimeout=20 -i "$SYNC_CHECK_IDENTITY" "root@$2" \
          journalctl -u nethermind-check --no-pager -o cat -n 300
        ;;
      *) usage ;;
    esac
  '';
}
