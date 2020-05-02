with import <nixpkgs> {};

mkShell {
  buildInputs = [
    haskellPackages.stack
    libiconv
    zlib
  ];
}
