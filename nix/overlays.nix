{ self, lib, inputs }:
let
  mkDate = longDate: (lib.concatStringsSep "-" [
    (builtins.substring 0 4 longDate)
    (builtins.substring 4 2 longDate)
    (builtins.substring 6 2 longDate)
  ]);

  version = lib.trim (lib.readFile ../VERSION)
    + "+date=" + (mkDate (self.lastModifiedDate or "19700101"))
    + "_" + (self.shortRev or "dirty");
in
{
  default = final: prev: {
    pasteme = final.callPackage ./default.nix { inherit version; };
    pasteme-debug = final.callPackage ./default.nix { inherit version; debug = true; };
  };
}
