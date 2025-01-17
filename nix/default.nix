{ stdenv
, lib
, odin

, version ? "git"
, debug ? false
}:
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

  meta = {
    description = "A very simple program to quickly copy frequently used file to the current directory.";
    mainProgram = "pasteme";
    homepage = "https://github.com/spitulax/pasteme";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
