{ self, lib, inputs }: {
  default = final: prev: rec {
    pasteme = final.callPackage ./default.nix { };
    pasteme-debug = pasteme.override { debug = true; };
  };
}
