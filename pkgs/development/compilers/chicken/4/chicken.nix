{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  darwin,
  bootstrap-chicken ? null,
}:

let
  version = "4.13.0";
  platform =
    with stdenv;
    if isDarwin then
      "macosx"
    else if isCygwin then
      "cygwin"
    else if (isFreeBSD || isOpenBSD) then
      "bsd"
    else if isSunOS then
      "solaris"
    else
      "linux"; # Should be a sane default
in
stdenv.mkDerivation {
  pname = "chicken";
  inherit version;

  binaryVersion = 8;

  src = fetchurl {
    url = "https://code.call-cc.org/releases/${version}/chicken-${version}.tar.gz";
    sha256 = "0hvckhi5gfny3mlva6d7y9pmx7cbwvq0r7mk11k3sdiik9hlkmdd";
  };

  postPatch = lib.optionalString stdenv.hostPlatform.isDarwin ''
    # There is not enough space in the load command to accomodate a full path to the store,
    # so use `@executable_path` to specify a relative path to chicken’s lib folder.
    sed -e '/POSTINSTALL_PROGRAM_FLAGS = /{s|$(LIBDIR)|@executable_path/../lib|}' \
      -i Makefile.macosx
  '';

  setupHook = lib.optional (bootstrap-chicken != null) ./setup-hook.sh;

  # -fno-strict-overflow is not a supported argument in clang on darwin
  hardeningDisable = lib.optionals stdenv.hostPlatform.isDarwin [ "strictoverflow" ];

  makeFlags = [
    "PLATFORM=${platform}"
    "PREFIX=$(out)"
    "VARDIR=$(out)/var/lib"
  ]
  ++ (lib.optionals stdenv.hostPlatform.isDarwin [
    "XCODE_TOOL_PATH=${darwin.binutils.bintools}/bin"
    "C_COMPILER=$(CC)"
    "POSTINSTALL_PROGRAM=${stdenv.cc.targetPrefix}install_name_tool"
  ]);

  # We need a bootstrap-chicken to regenerate the c-files after
  # applying a patch to add support for CHICKEN_REPOSITORY_EXTRA
  patches = lib.optionals (bootstrap-chicken != null) [
    ./0001-Introduce-CHICKEN_REPOSITORY_EXTRA.patch
  ];

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64) [
    darwin.autoSignDarwinBinariesHook
  ];

  buildInputs = lib.optionals (bootstrap-chicken != null) [
    bootstrap-chicken
  ];

  preBuild = lib.optionalString (bootstrap-chicken != null) ''
    # Backup the build* files - those are generated from hostname,
    # git-tag, etc. and we don't need/want that
    mkdir -p build-backup
    mv buildid buildbranch buildtag.h build-backup

    # Regenerate eval.c after the patch
    make spotless $makeFlags

    mv build-backup/* .
  '';

  postInstall = ''
    for f in $out/bin/*
    do
      wrapProgram $f \
        --prefix PATH : ${stdenv.cc}/bin
    done
  '';

  # TODO: Assert csi -R files -p '(pathname-file (repository-path))' == binaryVersion

  meta = {
    homepage = "http://www.call-cc.org/";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ corngood ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin; # Maybe other Unix
    description = "Portable compiler for the Scheme programming language";
    longDescription = ''
      CHICKEN is a compiler for the Scheme programming language.
      CHICKEN produces portable and efficient C, supports almost all
      of the R5RS Scheme language standard, and includes many
      enhancements and extensions. CHICKEN runs on Linux, macOS,
      Windows, and many Unix flavours.
    '';
  };
}
