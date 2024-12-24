{ stdenv
, lib
, odin

, debug ? false
}:
let
  version = lib.trim (lib.readFile ../VERSION);
in
stdenv.mkDerivation {
  pname = "pasteme";
  inherit version;
  src = lib.cleanSource ./..;

  nativeBuildInputs = [
    odin
  ];

  buildInputs = [

  ];

  makeFlags = [
    (if debug then "debug" else "release")
  ];

  installFlags = [
    "install"
    "PREFIX=$(out)"
  ];
}
