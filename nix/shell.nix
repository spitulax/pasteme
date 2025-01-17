{ self
, pkgs
, mkShell
}:
mkShell {
  name = "pasteme-shell";
  nativeBuildInputs = with pkgs; [
    odin
  ];
  inputsFrom = [
    self.packages.${pkgs.system}.default
  ];
}
