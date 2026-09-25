# Single-disk cloud VM layout (GPT, BIOS boot + ext4 root), like hosts/replay, with the device
# as a parameter: providers differ in what they call the boot disk.
{ syncCheck, ... }:
{
  disko.devices.disk.main = {
    device = syncCheck.disk;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02"; # BIOS boot partition (GRUB on GPT)
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
