{
  inputs = {
    nixpkgs.url = github:NixOs/nixpkgs/nixos-22.11;
    atlas.url = github:garrisonhh/nix-atlas-build;
  };

  outputs = { self, nixpkgs, atlas }:
    let
      # project config
      name = "caffe";
      system = "x86_64-linux";

      pkgs = nixpkgs.legacyPackages.${system};
      pyPkgs = pkgs.python311Packages;
      atlasPkgs = atlas.packages.${system};
      inherit (pkgs.stdenv) mkDerivation;

      # packages
      caffePkgs = cripple: with pkgs; [
        git
        glog
        gflags
        protobuf3_8
        caffe
        cudaPackages.cudatoolkit
        opencv2
        boost
        hdf5-cpp
        lmdb
        leveldb
        snappy
        pyPkgs.python
        pyPkgs.numpy
        pyPkgs.boost
        (if (cripple) then atlasPkgs.crippled else atlasPkgs.release)
      ];

      # caffe
      caffeMakefileConfig = builtins.toFile "Makefile.config" ''
        BLAS := atlas

        CUDA_DIR := /usr/local/cuda
        CUDA_ARCH := \
            -gencode arch=compute_50,code=sm_50 \
            -gencode arch=compute_52,code=sm_52 \
            -gencode arch=compute_60,code=sm_60 \
            -gencode arch=compute_61,code=sm_61 \
            -gencode arch=compute_61,code=compute_61

        PYTHON_LIBRARIES := boost_python311 python3.11
        PYTHON_INCLUDE := /usr/include PYTHON_INCLUDE_REPLACEME
        PYTHON_LIB := /usr/lib PYTHON_LIB_REPLACEME

        INCLUDE_DIRS := $(PYTHON_INCLUDE) /usr/local/include /usr/include
        LIBRARY_DIRS := $(PYTHON_LIB) /usr/local/lib /usr/lib

        BUILD_DIR := build
        DISTRIBUTE_DIR := distribute

        TEST_GPUID := 0

        Q ?= @
      '';

      # patches Makefile.config to automatically detected python include dirs
      pythonConfigPatcher = builtins.toFile "include_patcher.py" ''
        from sys import prefix, version_info
        import os
        import numpy as np

        # get include folders
        version = f"python{version_info.major}.{version_info.minor}"

        includes = " ".join([
            f"{prefix}/include/{version}",
            np.get_include(),
        ])

        # get extra lib folders
        libs = " ".join([
          os.getenv("BOOST_LIB"),
        ])

        # patch Makefile.config
        config_path = os.path.join(os.getcwd(), 'Makefile.config')

        with open(config_path, 'r') as f:
          text = f.read()

        text = text.replace('PYTHON_INCLUDE_REPLACEME', includes)
        text = text.replace('PYTHON_LIB_REPLACEME', libs)

        with open(config_path, 'w') as f:
          f.write(text)
      '';

      mkCaffe = config: mkDerivation {
        inherit name;
        src = builtins.fetchGit {
          url = "https://github.com/BVLC/caffe.git";
          ref = "refs/tags/1.0";
          rev = "eeebdab16155d34ff8f5f42137da7df4d1c7eab0";
        };

        buildInputs = caffePkgs config.cripple;

        configurePhase = ''
          export BOOST_LIB="${pyPkgs.boost.outPath}/lib"

          cp ${caffeMakefileConfig} Makefile.config
          chmod +rw Makefile.config
          python ${pythonConfigPatcher}
        '';

        buildPhase = ''
          make -j`nproc` distribute
        '';

        installPhase = ''
          mkdir -p $out/
          cp -r ./distribute/* $out/
        '';
      };

      packages = {
        default        = mkCaffe { cripple = false; };
        release        = mkCaffe { cripple = false; };
        crippled       = mkCaffe { cripple = true; };
      };
    in {
      packages.${system} = packages;
    };
}
