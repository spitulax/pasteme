{ self, lib, inputs }: {
  default = final: prev: {
    pasteme = final.callPackage ./default.nix { };
    pasteme-debug = final.callPackage ./default.nix { debug = true; };
  };
}
