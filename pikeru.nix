{ lib
, rustPlatform
, pkg-config
, scdoc
, makeWrapper
, ffmpeg
, poppler-utils
, fontconfig
, freetype
, sqlite
, vulkan-loader
, libGL
, wayland
, libxkbcommon
, libx11
, libxcursor
, libxi
, libxrandr
, src
, version ? "1.16-unstable"
}:

let
  # Libraries iced/wgpu dlopen()s at runtime; they must be on the loader path.
  runtimeLibs = [
    vulkan-loader
    libGL
    wayland
    libxkbcommon
    fontconfig
    freetype
    libx11
    libxcursor
    libxi
    libxrandr
  ];
in
rustPlatform.buildRustPackage {
  pname = "pikeru";
  inherit version src;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };

  # The portal integration tests assume a live session (real HOME, /usr wrapper
  # paths, a running display) and fail in the build sandbox.
  doCheck = false;

  nativeBuildInputs = [
    pkg-config
    scdoc
    makeWrapper
    # Sets LIBCLANG_PATH so video-rs's ffmpeg bindgen build works.
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    ffmpeg # libav* for video-rs (thumbnails)
    fontconfig
    freetype
    sqlite # rusqlite is bundled, but harmless to have
  ];

  # buildRustPackage builds the whole workspace, producing both the
  # `pikeru` and `portal` binaries in target/release.
  postInstall = ''
    # The portal backend binary lives in libexec, matching the dbus/systemd units.
    install -Dm755 "$out/bin/portal" "$out/libexec/xdg-desktop-portal-pikeru"
    rm "$out/bin/portal"

    # Wrapper script the portal invokes. Bake in the store path to `pikeru`
    # and the runtime PATH it needs (ffmpeg, pdftoppm).
    install -Dm755 xdg_portal/pikeru-wrapper.sh \
      "$out/share/xdg-desktop-portal-pikeru/pikeru-wrapper.sh"
    substituteInPlace "$out/share/xdg-desktop-portal-pikeru/pikeru-wrapper.sh" \
      --replace-fail 'pikeru -m' "$out/bin/pikeru -m"

    install -Dm755 xdg_portal/postprocess.example.sh \
      "$out/share/xdg-desktop-portal-pikeru/postprocess.example.sh"
    install -Dm755 indexer/img_indexer.py \
      "$out/share/xdg-desktop-portal-pikeru/img_indexer.py"

    # The .portal advertisement file. @cur_desktop@ is the upstream install
    # hook for appending an unlisted desktop; sway/wlroots are already listed,
    # so we substitute it away.
    install -dm755 "$out/share/xdg-desktop-portal/portals"
    substitute xdg_portal/pikeru.portal.in \
      "$out/share/xdg-desktop-portal/portals/pikeru.portal" \
      --replace-fail '@cur_desktop@' ""

    # D-Bus activation service pointing at the store binary.
    install -dm755 "$out/share/dbus-1/services"
    cat > "$out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.pikeru.service" <<EOF
    [D-BUS Service]
    Name=org.freedesktop.impl.portal.desktop.pikeru
    Exec=$out/libexec/xdg-desktop-portal-pikeru
    SystemdService=xdg-desktop-portal-pikeru.service
    EOF

    # systemd user unit (xdg-desktop-portal also starts it via dbus activation).
    install -dm755 "$out/share/systemd/user"
    cat > "$out/share/systemd/user/xdg-desktop-portal-pikeru.service" <<EOF
    [Unit]
    Description=Portal service (pikeru file picker implementation)
    PartOf=graphical-session.target
    After=graphical-session.target

    [Service]
    Type=dbus
    BusName=org.freedesktop.impl.portal.desktop.pikeru
    ExecStart=$out/libexec/xdg-desktop-portal-pikeru
    Restart=on-failure
    EOF

    install -Dm644 xdg_portal/xdg-desktop-portal-pikeru.5.scd /dev/stdout \
      | scdoc > "$out/share/man/man5/xdg-desktop-portal-pikeru.5" || true

    # pikeru itself dlopens the graphics stack at runtime.
    wrapProgram "$out/bin/pikeru" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}" \
      --prefix PATH : "${lib.makeBinPath [ ffmpeg poppler-utils ]}"
  '';

  meta = {
    description = "File picker with good thumbnails, search, and an xdg-desktop-portal backend";
    homepage = "https://github.com/dvhar/pikeru";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "pikeru";
  };
}
