using Repology
using Repology: Identification, identify, parse_tag_version
using TOML
using Test

include("export.jl")

@testset "identify_upstream" begin
    @test Repology.identify_upstream("https://www.cairographics.org/releases/cairo-1.32.0.tar.xz", "") == ("cairo-graphics-library", "1.32.0")
    @test Repology.identify_upstream("https://download.gnome.org/sources/glib-networking/2.74/glib-networking-2.74.0.tar.xz", "") == ("glib-networking", "2.74.0")
    @test Repology.identify_upstream("https://downloads.sourceforge.net/project/gnuplot/gnuplot/6.0.3/gnuplot-6.0.3.tar.gz", "") == ("gnuplot", "6.0.3")
    @test Repology.identify_upstream("https://sourceforge.net/projects/graphicsmagick/files/graphicsmagick/1.3.45/GraphicsMagick-1.3.45.tar.xz", "") == ("graphicsmagick", "1.3.45")
    @test Repology.identify_upstream("https://sourceforge.net/projects/libpng/files/libpng16/1.6.54/libpng-1.6.54.tar.gz", "") == ("libpng", "1.6.54")

    @test Repology.identify_upstream("https://github.com/libexpat/libexpat/releases/download/R_2_2_7/expat-2.2.7.tar.xz", "") == ("expat", "2.2.7")
    @test Repology.identify_upstream("https://github.com/Singular/Singular/releases/download/Release-4-4-1p5/singular-4.4.1p5.tar.gz", "") == ("singular", "4.4.1p5")
end

@testset "identify provenance" begin
    @test identify("https://github.com/libexpat/libexpat/releases/download/R_2_8_3/expat-2.8.3.tar.xz") == Identification("expat", "2.8.3", "url-pattern")
    @test identify("https://zlib.net/zlib-1.2.11.tar.gz") == Identification("zlib", "1.2.11", "url-pattern")
    @test identify("https://github.com/libexpat/libexpat/releases/download/R_2_9_0/expat-2.9.0.tar.xz").version == "2.9.0"
    @test identify("https://github.com/wolfSSL/wolfssl/archive/refs/tags/v5.9.3-stable.tar.gz") == Identification("wolfssl", "5.9.3", "tag-scheme")
    @test identify("https://github.com/postgres/postgres/archive/refs/tags/REL_16_9.tar.gz") == Identification("postgresql", "16.9", "tag-scheme")
    @test identify("https://example.invalid/not-a-real-project-1.2.3.tar.gz") == Identification(nothing, nothing, nothing)
    for url in ("https://github.com/libexpat/libexpat/releases/download/R_2_8_3/expat-2.8.3.tar.xz",
                "https://github.com/postgres/postgres/archive/refs/tags/REL_16_9.tar.gz")
        @test identify(url).provenance in Repology.PROVENANCES
    end
    # Hand-verified sources take precedence over everything else
    Repology.overrides()[("https://example.invalid/override-1.0.tar.gz", "")] = Identification("example", "1.0", "override")
    @test identify("https://example.invalid/override-1.0.tar.gz") == Identification("example", "1.0", "override")
    @test identify("https://example.invalid/override-1.0.tar.gz"; use_overrides=false).provenance != "override"
    delete!(Repology.overrides(), ("https://example.invalid/override-1.0.tar.gz", ""))
    # Curated repositories take precedence over Repology's, and tag_patterns pick between projects sharing a repository
    @test Repology.repository_projects("https://github.com/open-policy-agent/opa") == ["openpolicyagent"]
    @test Repology.repository_projects("https://github.com/apache/tvm-ffi") == ["python:apache-tvm-ffi"]
    @test Repology.tag_project(["sdl2", "sdl3"], "release-2.32.10") == "sdl2"
    @test Repology.tag_project(["sdl2", "sdl3"], "release-3.2.0") == "sdl3"
    @test Repology.tag_project(["sdl2", "sdl3"], "prerelease-3.1.10") == "sdl3"
    @test Repology.tag_project(["sdl2", "sdl3"], "v3.2.0") === nothing
    @test Repology.version_from_tag("sdl3", "release-3.2.0") == "3.2.0"
end

@testset "LMDB releases in the OpenLDAP repository" begin
    releases = [("cfb061a8f7879f865536fee7d1d8d9737833bbdb", "0.9.35"),
                ("2562c3297402d82bbc049c7e645515edb4079eba", "1.0.0"),
                ("c279e0477c713076893e8c2b1a6337e421c15867", "1.0.2"),
                ("d4dc8e21ddbcb0c3d6a53b3c19c87559fad2b402", "1.0.3")]
    for repo in ("https://git.openldap.org/openldap/openldap.git", "https://github.com/openldap/openldap.git")
        remote = something(first(Repology.forge_repository(repo)), repo)
        previous = get(Repology._LS_REMOTE_CACHE, remote, nothing)
        try
            Repology._LS_REMOTE_CACHE[remote] = Dict(sha => ["LMDB_" * version] for (sha, version) in releases)
            Repology._LS_REMOTE_CACHE[remote]["e460f00874352c3d2cdbca8a00a4112c7bc633ab"] = ["OPENLDAP_REL_ENG_2_6_9"]
            for (sha, version) in releases
                @test identify(repo; commit=sha) == Identification("lmdb", version, "git-tag")
            end
            @test identify(repo; commit="e460f00874352c3d2cdbca8a00a4112c7bc633ab") == Identification("openldap", "2.6.9", "git-tag")
            @test identify(repo) == Identification("openldap", nothing, "repository")
        finally
            isnothing(previous) ? delete!(Repology._LS_REMOTE_CACHE, remote) : (Repology._LS_REMOTE_CACHE[remote] = previous)
        end
    end
    for scheme in ("http", "https"), version in ("0.9.25", "0.9.27", "0.9.33", "0.9.35", "1.0.0", "1.0.2", "1.0.3")
        for url in ("$scheme://git.openldap.org/openldap/openldap/-/archive/LMDB_$version/openldap-LMDB_$version.tar.gz",
                    "$scheme://github.com/openldap/openldap/archive/refs/tags/LMDB_$version.tar.gz",
                    "$scheme://github.com/openldap/openldap/archive/LMDB_$version.zip")
            @test identify(url) == Identification("lmdb", version, "url-pattern")
        end
    end
    @test Repology.tag_project(["lmdb", "openldap"], "LMDB_1.0.3") == "lmdb"
    @test identify("https://github.com/openldap/openldap/archive/refs/tags/OPENLDAP_REL_ENG_2_6_9.tar.gz") == Identification("openldap", "2.6.9", "tag-scheme")
    full = identify("https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-2.5.19.tgz")
    @test (full.project, full.version) == ("openldap", "2.5.19")
    patterns = Regex.(Repology.additional_info()["lmdb"]["url_patterns"])
    for url in ("", "https://git.openldap.org/openldap/openldap/-/archive/LMDB_1.0.3/openldap-LMDB_1.0.2.tar.gz",
                "https://git.openldap.org/openldap/openldap/-/archive/LMDB_1.0.3/openldap-LMDB_1.0.3.tar.gz.asc",
                "https://github.com/openldap/openldap/archive/refs/tags/LMDB_1.0.3.tar.gz.sig",
                "https://github.com/other/openldap/archive/refs/tags/LMDB_1.0.3.tar.gz",
                "https://github.com/openldap/openldap/archive/refs/tags/OPENLDAP_REL_ENG_2_6_9.tar.gz")
        @test !any(p -> occursin(p, url), patterns)
    end
    @test Repology.tag_project(["lmdb", "openldap"], "LMDB_1.0.3.asc") === nothing
    @test Repology.tag_project(["lmdb", "openldap"], "LMDB_1.0") === nothing
end

@testset "handwritten source regressions" begin
    @test identify("https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz") == Identification("libiconv", "1.18", "url-pattern")
    @test identify("https://github.com/git-for-windows/git/releases/download/v2.42.0.windows.2/Git-2.42.0.2-32-bit.tar.bz2") == Identification("git-for-windows", "2.42.0.windows.2", "url-pattern")
end

@testset "GNU mirror archives" begin
    for (project, version) in (("binutils", "2.41"), ("libiconv", "1.16")),
        prefix in ("https://ftp.gnu.org/gnu/", "https://ftp.gnu.org/pub/gnu/",
                   "https://ftpmirror.gnu.org/gnu/", "https://ftpmirror.gnu.org/"),
        compression in ("gz", "bz2", "xz", "lz")
        url = prefix * project * "/" * project * "-" * version * ".tar." * compression
        @test identify(url) == Identification(project, version, "url-pattern")
    end
end

@testset "canonical source URL boundaries" begin
    patterns = Repology.curated_url_patterns()
    for url in ("", "https://example.invalid/Python-3.11.12.tar.xz",
                "https://www.python.org/ftp/python/3.11.12/Python-3.11.12.tar.xz.asc",
                "https://nodejs.org/dist/v16.0.0/node-v18.0.0-linux-x64.tar.gz",
                "https://nodejs.org/dist/v16.0.0/SHASUMS256.txt",
                "https://ftp.gnu.org/gnu/binutils/binutils-2.41.tar.xz.sig",
                "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.16.tar.gz.sig",
                "https://github.com/denoland/deno/releases/download/v2.9.8/deno.zip.sha256sum")
        @test !any(p -> occursin(first(p), url), patterns)
    end
end

@testset "curated export regressions" begin
    @test Repology.repository_projects("https://github.com/intel/opencl-clang") == ["opencl-clang"]
    for (url, project, version) in (
        ("https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz", "gnumpc", "1.3.1"),
        ("https://ftpmirror.gnu.org/mpc/mpc-1.3.1.tar.lz", "gnumpc", "1.3.1"),
        ("https://downloads.sourceforge.net/sourceforge/mpg123/mpg123-1.29.3.tar.bz2", "mpg123", "1.29.3"),
        ("https://downloads.sourceforge.net/sourceforge/mpg123/mpg123-1.33.7.tar.bz2", "mpg123", "1.33.7"),
        ("https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.2/libclc-20.1.2.src.tar.xz", "llvm", "20.1.2"),
        ("https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.2/clang-20.1.2.src.tar.xz", "llvm", "20.1.2"))
        @test identify(url) == Identification(project, version, "url-pattern")
    end
    for module_name in ("qtcharts", "qtquick3d", "qtquicktimeline", "qtsvg", "qttools")
        url = "https://download.qt.io/official_releases/qt/6.10/6.10.2/submodules/$module_name-everywhere-src-6.10.2.tar.xz"
        @test identify(url) == Identification("qt", "6.10.2", "url-pattern")
    end
    for url in ("", "https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz.sig",
                "https://download.qt.io/official_releases/qt/6.10/6.10.2/submodules/qtsvg-everywhere-src-6.10.1.tar.xz",
                "https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.2/libclc-19.1.2.src.tar.xz")
        @test !any(p -> occursin(first(p), url), Repology.curated_url_patterns())
    end
end

@testset "curated legacy LLVM and Qt5 sources" begin
    for version in ("11.0.0", "11.0.1", "12.0.1")
        url = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/libunwind-$version.src.tar.xz"
        @test identify(url) == Identification("llvm", version, "url-pattern")
    end
    for module_name in ("qtcharts", "qtsvg", "qttools")
        url = "https://download.qt.io/official_releases/qt/5.15/5.15.2/submodules/$module_name-everywhere-src-5.15.2.tar.xz"
        @test identify(url) == Identification("qt", "5.15.2", "url-pattern")
        qt6_url = "https://download.qt.io/official_releases/qt/6.10/6.10.2/submodules/$module_name-everywhere-src-6.10.2.tar.xz"
        @test identify(qt6_url) == Identification("qt", "6.10.2", "url-pattern")
    end
    @test identify("https://download.qt.io/official_releases/qt/5.15/5.15.2/submodules/qtbase-everywhere-src-5.15.2.tar.xz").project == "qt"
    for url in ("", "https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/libunwind-11.0.1.src.tar.xz",
                "https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/libunwind-11.0.0.src.tar.xz.asc",
                "https://download.qt.io/official_releases/qt/5.15/5.15.2/submodules/qtsvg-everywhere-src-5.15.3.tar.xz",
                "https://download.qt.io/official_releases/qt/5.15/5.15.2/submodules/qtsvg-everywhere-src-6.10.2.tar.xz",
                "https://download.qt.io/official_releases/qt/6.10/5.15.2/submodules/qtsvg-everywhere-src-5.15.2.tar.xz")
        @test !any(p -> occursin(first(p), url), Repology.curated_url_patterns())
    end
end

@testset "monolithic Qt source archives" begin
    components=("qt3d","qtconnectivity","qtdatavis3d","qtdeclarative","qtimageformats","qtlocation",
        "qtmultimedia","qtnetworkauth","qtpositioning","qtremoteobjects","qtscxml","qtsensors",
        "qtserialbus","qtserialport","qtshadertools","qtspeech","qttranslations","qtvirtualkeyboard",
        "qtwayland","qtwebchannel","qtwebsockets","qtwebview","qtbase","qtcharts","qtquick3d",
        "qtquicktimeline","qtsvg","qttools","qtgraphs","qt5compat","qtquickcontrols","qtquickcontrols2",
        "qtfuturecomponent")
    patterns=Repology.curated_url_patterns()
    for scheme in ("http","https"), root in ("download.qt.io","mirrors.dotsrc.org/qtproject","ftp.fau.de/qtproject"),
        directory in ("official_releases","archive"),
        (series,version) in (("5.15","5.15.2"),("515","5.15.1"),("6.12","6.12.0"),("612","6.12.0")),
        source in ("src","opensource-src"), extension in ("xz","gz")
        base="$scheme://$root/$directory/qt/$series/$version"
        for component in components
            url="$base/submodules/$component-everywhere-$source-$version.tar.$extension"
            @test identify(url)==Identification("qt",version,"url-pattern")
        end
        @test identify("$base/single/qt-everywhere-$source-$version.tar.$extension")==Identification("qt",version,"url-pattern")
    end
    for scheme in ("http","https"), directory in ("official_releases","archive")
        base="$scheme://download.qt.io/$directory/qt"
        for path in ("6.12/6.12.0/submodules/qtbase-everywhere-src-6.12.1.tar.xz",
                     "6.12/6.12.0/submodules/qtbase-everywhere-src-5.15.2.tar.xz",
                     "6.11/6.12.0/submodules/qtbase-everywhere-src-6.12.0.tar.xz",
                     "5.12/6.12.0/submodules/qtbase-everywhere-src-6.12.0.tar.xz",
                     "611/6.12.0/submodules/qtbase-everywhere-src-6.12.0.tar.xz",
                     "512/6.12.0/single/qt-everywhere-src-6.12.0.tar.xz",
                     "6.12/6.12.0/submodules/qtbase-everywhere-src-6.12.0.tar.xz.asc",
                     "6.12/6.12.0/submodules/qtbase-everywhere-src-6.12.0.tar.gz.sig",
                     "6.12/6.12.0/submodules/qtbase-everywhere-src-6.12.0.tar.xz/extra",
                     "6.12/6.12.0/submodules/other-everywhere-src-6.12.0.tar.xz",
                     "6.12/6.12.0/single/qt-everywhere-src-6.12.1.tar.xz",
                     "6.12/6.12.0/single/qt-everywhere-src-6.12.0.tar.xz.asc",
                     "4.8/4.8.7/submodules/qtbase-everywhere-src-4.8.7.tar.xz")
            @test !any(p->occursin(first(p),"$base/$path"),patterns)
        end
    end
    for url in ("", "http://example.invalid/qtbase-everywhere-src-6.12.0.tar.xz",
                "ftp://download.qt.io/archive/qt/6.12/6.12.0/submodules/qtbase-everywhere-src-6.12.0.tar.xz")
        @test !any(p->occursin(first(p),url),patterns)
    end
end

@testset "curated upstream ownership" begin
    for (url, project) in (("https://github.com/dankamongmen/notcurses", "notcurses"),
                           ("https://github.com/google/s2geometry.git", "s2geometry"),
                           ("https://github.com/apache/arrow-nanoarrow", "nanoarrow"),
                           ("https://github.com/ROCm/llvm-project", "rocm-llvm"))
        @test Repology.repository_projects(url) == [project]
    end
    for (url, project, version) in (
        ("https://sourceforge.net/projects/mingw-w64/files/mingw-w64/mingw-w64-release/mingw-w64-v11.0.1.tar.bz2", "mingw-w64", "11.0.1"),
        ("https://github.com/dankamongmen/notcurses/archive/refs/tags/v3.0.17.tar.gz", "notcurses", "3.0.17"),
        ("https://github.com/google/s2geometry/archive/refs/tags/v0.12.0.tar.gz", "s2geometry", "0.12.0"),
        ("https://github.com/apache/arrow-nanoarrow/archive/refs/tags/apache-arrow-nanoarrow-0.6.0.tar.gz", "nanoarrow", "0.6.0"),
        ("https://github.com/indygreg/PyOxidizer/archive/refs/tags/apple-codesign/0.17.0.tar.gz", "rust:apple-codesign", "0.17.0"),
        ("https://github.com/samtools/htslib/releases/download/1.10.2/htslib-1.10.2.tar.bz2", "htslib", "1.10.2"),
        ("https://s3.amazonaws.com/json-c_releases/releases/json-c-0.17.tar.gz", "json-c", "0.17"),
        ("https://github.com/openssl/openssl/releases/download/openssl-3.0.15/openssl-3.0.15.tar.gz", "openssl", "3.0.15"),
        ("https://github.com/openPMD/openPMD-api/archive/refs/tags/0.13.4.tar.gz", "openpmd-api", "0.13.4"),
        ("https://tukaani.org/xz/xz-5.4.3.tar.xz", "xz", "5.4.3"),
        ("https://zlib.net/zlib-1.2.12.tar.gz", "zlib", "1.2.12"))
        @test identify(url) == Identification(project, version, "url-pattern")
    end
    @test Repology.version_from_tag("rocm-llvm", "rocm-7.2.0") == "7.2.0"
    @test Repology.version_from_tag("nanoarrow", "apache-arrow-nanoarrow-0.6.0") == "0.6.0"
    for url in ("", "https://github.com/other/s2geometry/archive/v0.12.0.tar.gz",
                "https://zlib.net/zlib-1.2.12.tar.gz.asc",
                "https://sourceforge.net/projects/mingw-w64/files/mingw-w64/mingw-w64-release/mingw-w64-v11.0.1.tar.bz2.sig",
                "https://github.com/openssl/openssl/releases/download/openssl-3.0.15/openssl-3.0.16.tar.gz")
        @test !any(p -> occursin(first(p), url), Repology.curated_url_patterns())
    end
end

@testset "tag parsing" begin
    for (tag, ver) in ("R_2_8_3" => "2.8.3", "REL_16_9" => "16.9", "V_9_2_P1" => "9.2p1", "v5.9.3-stable" => "5.9.3",
                       "Release_2022_09_1" => "2022.09.1", "PCRE2-10.42" => "10.42", "openssl-3.5.8" => "3.5.8",
                       "v1.10.0-rc3" => "1.10.0-rc3", "llvmorg-17.0.6" => "17.0.6", "cares-1_34_5" => "1.34.5",
                       "Release-4-4-1p5" => "4.4.1p5", "tectonic@0.11.0" => "0.11.0", "v2.0" => "2.0", "7" => "7")
        @test parse_tag_version(tag) == ver
    end
    @test parse_tag_version("nightly") === nothing
    @test parse_tag_version("7.1.2-1") === nothing
    @test parse_tag_version("ImageMagick-7.1.1-47") === nothing
    @test parse_tag_version("v2.30.7-1") === nothing
    @test Repology.version_from_tag("nccl", "v2.30.7-1") == "2.30.7-1"
    @test Repology.version_from_tag("imagemagick", "7.1.2-27") == "7.1.2-27"
    @test Repology.version_from_tag("minio", "RELEASE.2025-07-23T15-54-02Z") == "2025-07-23T15-54-02Z"
    @test Repology.version_from_tag("llama.cpp", "b7821") == "b7821"
    @test parse_tag_version("processing-1434-4.5.6") == "4.5.6"
    @test parse_tag_version("RELEASE.2025-09-07T16-13-09Z") === nothing
    @test parse_tag_version("release.1.2.3") == "1.2.3"
    @test parse_tag_version("3a5f1c2") === nothing
    @test parse_tag_version("20190702") == "20190702"
    @test parse_tag_version("0123abc4567def") === nothing
    @test Repology.is_git_commit("3564038")
    @test !Repology.is_git_commit(repeat("a", 64))
    # Munged versions are never returned
    @test !Repology.is_plausible_version("expat", "8_3")
    @test !Repology.is_plausible_version("expat", "v2.8.3")
    @test !Repology.is_plausible_version("expat", nothing)
    @test Repology.is_plausible_version("llama.cpp", "b7821")
    @test !Repology.is_plausible_version("llama.cpp", "3bcc129")
    @test !Repology.is_plausible_version("gdk-pixbuf", "3c7740498fd31b6746dd7e04601886766a6644b7")
    @test "git" in Repology.known_versions()["vim"] && !Repology.is_plausible_version("vim", "git")
    @test !Repology.is_plausible_version("expat", "b2.8.3")
    @test Repology.is_plausible_version("crosstool-ng", "1.25.0_rc1")
end

# A corpus of known-good source => (project, version) mappings, harvested from GeneralMetadata.jl by
# scripts/build_corpus.jl. "manual" entries were hand-corrected; "jll-version" entries are those whose upstream
# version equalled the JLL version. Both must match project and version exactly.
# Git sources (with a commit) require network access and are only checked if REPOLOGY_TEST_NETWORK is set.
@testset "vercmp" begin
    using Repology: vercmp, version_scheme, version_features, VersionScheme, P_IS_PATCH
    # libversion defaults
    @test vercmp("1.2.0-dev", "1.2.0") == -1
    @test vercmp("1.2.0-rc1", "1.2.0") == -1
    @test vercmp("7.1.2-1", "7.1.2") == 1
    @test vercmp("1.10", "1.9") == 1
    @test vercmp("7.1.2-9", "7.1.2.9") == 0
    @test vercmp("9.2p1", "9.2") == -1
    @test vercmp("9.2p1", "9.2"; flags=P_IS_PATCH) == 1

    @test version_features("1.2.3") == Set()
    @test version_features("1.2.3-rc1") == Set()
    @test version_features("7.1.2-1") == Set([:hyphen_number])
    @test version_features("9.2p1") == Set([:p_number])
    @test version_features("1.0.2u") == Set([:letter_suffix])
    @test version_features("1.2a1") == Set([:word])
    @test version_features("1.2foo") == Set([:word])

    # Unambiguous versions compare without knowing anything about the project
    @test vercmp(nothing, "1.10", "1.9") == 1
    @test vercmp(nothing, "2.0.0-rc1", "2.0.0") == -1
    @test vercmp("expat", "2.8.3", "2.10.0") == -1
    # Ambiguous ones need a scheme
    @test vercmp(nothing, "1.2.0-1", "1.2.0") === nothing
    @test vercmp(nothing, "9.2p1", "9.2") === nothing
    @test vercmp("expat", "2.8.3-1", "2.8.3") === nothing
    # Curated schemes
    @test vercmp("imagemagick", "7.1.2-1", "7.1.2") == 1
    @test vercmp("imagemagick", "7.1.2-10", "7.1.2-9") == 1
    @test vercmp("openssh", "9.2p1", "9.2") == 1
    @test vercmp("openssh", "9.3", "9.2p2") == 1
    semver = VersionScheme(:semver, 0, true, Set{Symbol}())
    @test vercmp(semver, "1.2.0-1", "1.2.0") == -1
    @test vercmp(semver, "1.2.0-dev", "1.2.0") == -1
    @test vercmp(semver, "1.2.0+build", "not a version") === nothing
    @test vercmp(semver, "1.2.0+build.1", "1.2.0+build.2") == 0
    @test vercmp(semver, "1.2.0+build", "1.2.0") == 0
    @test vercmp(semver, "1.2.1+build", "1.2.0") == 1
    # Inferred schemes follow the forms a project has already released
    inferred = VersionScheme(:libversion, 0, false, Set([:hyphen_number]))
    @test vercmp(inferred, "7.1.2-1", "7.1.2") == 1
    @test vercmp(inferred, "9.2p1", "9.2") === nothing
    scheme = version_scheme("imagemagick")
    @test scheme.curated && scheme.kind === :libversion
    @test version_scheme("openssh").flags == P_IS_PATCH
    @test !version_scheme("expat").curated
end

@testset "corpus" begin
    corpus = TOML.parsefile(joinpath(@__DIR__, "corpus.toml"))["entry"]
    known_failures = Set((e["url"], get(e, "hash", "")) for e in get(TOML.parsefile(joinpath(@__DIR__, "known_failures.toml")), "failure", []))
    network = !isempty(get(ENV, "REPOLOGY_TEST_NETWORK", ""))
    # Set when refreshing data, so that newly-fixed known failures don't block the refresh (only regressions do)
    allow_fixed = !isempty(get(ENV, "REPOLOGY_ALLOW_FIXED", ""))
    for e in corpus
        haskey(e, "hash") && !network && continue
        id = identify(e["url"]; commit=get(e, "hash", nothing), use_overrides=false)
        ok = id.version == e["version"] && id.project == e["project"]
        if (e["url"], get(e, "hash", "")) in known_failures
            allow_fixed && ok ? (@test ok) : (@test_broken ok)
        else
            ok || @info "corpus mismatch" e id
            @test ok
        end
    end
end
