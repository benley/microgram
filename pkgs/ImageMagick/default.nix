{ lib
, stdenv
, fetchurl
, pkgconfig
, bzip2
, fontconfig
, freetype
, ghostscript ? null
, libjpeg
, libpng
, libtiff
, libxml2
, zlib
, libtool
, jasper
, libX11
, tetex ? null
, librsvg ? null
}:

let

  version = "6.9.2-10";

  arch =
    if stdenv.system == "i686-linux" then "i686"
    else if stdenv.system == "x86_64-linux" || stdenv.system == "x86_64-darwin" then "x86-64"
    else throw "ImageMagick is not supported on this platform.";

  ghostscriptEnabled = (stdenv.system != "x86_64-darwin" && ghostscript != null);

in

stdenv.mkDerivation rec {
  name = "ImageMagick-${version}";

  src = fetchurl {
    urls = [
      "http://ftp.sunet.se/pub/multimedia/graphics/ImageMagick/releases/${name}.tar.xz"
      "http://distfiles.macports.org/ImageMagick/ImageMagick-${version}.tar.xz"
      "mirror://imagemagick/releases/${name}.tar.xz"
    ];
    sha256 = "0g01q8rygrf977d9rpixg1bhnavqfwzz30qpn7fj17yn8fx6ybys";
  };

  enableParallelBuilding = true;

  preConfigure = if tetex != null then
    ''
      export DVIDecodeDelegate=${tetex}/bin/dvips
    '' else "";

  configureFlags =
    [ "--with-frozenpaths" ]
    ++ [ "--with-gcc-arch=${arch}" ]
    ++ lib.optional (librsvg != null) "--with-rsvg"
    ++ lib.optionals ghostscriptEnabled
      [ "--with-gs-font-dir=${ghostscript}/share/ghostscript/fonts"
        "--with-gslib"
      ];

  propagatedBuildInputs =
    [ bzip2 fontconfig freetype libjpeg libpng libtiff libxml2 zlib librsvg
      libtool jasper libX11
    ] ++ lib.optional ghostscriptEnabled ghostscript;

  buildInputs = [ tetex pkgconfig ];

  postInstall = ''(cd "$out/include" && ln -s ImageMagick* ImageMagick)'';

  meta = with stdenv.lib; {
    homepage = http://www.imagemagick.org/;
    description = "A software suite to create, edit, compose, or convert bitmap images";
    platforms = platforms.linux ++ [ "x86_64-darwin" ];
  };
}
