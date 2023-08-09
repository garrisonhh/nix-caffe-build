{
  inputs.nixpkgs.url = github:NixOs/nixpkgs/nixos-22.11;

  outputs = { self, nixpkgs }:
    let
      # project config
      name = "caffe";
      system = "x86_64-linux";

      pkgs = (import nixpkgs) {
        inherit system;
        config.allowUnfree = true; # needed for cuda
      };

      pyPkgs = pkgs.python311Packages;
      inherit (pkgs.stdenv) mkDerivation;

      # packages
      caffePkgs = with pkgs; [
        git
        glog
        gflags
        protobuf3_8
        opencv2
        openblas
        boost
        hdf5-cpp
        lmdb
        leveldb
        snappy
        cudatoolkit
        pyPkgs.python
        pyPkgs.numpy
        pyPkgs.boost
      ];

      # caffe
      caffeMakefileConfig = builtins.toFile "Makefile.config" ''
        BLAS := open

        CUDA_DIR := CUDA_DIR_REPLACEME
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
        from sys import argv, prefix, version_info
        import os
        import numpy as np

        input_path, output_path = argv[1], argv[2]

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

        # patch config
        with open(input_path, 'r') as f:
          text = f.read()

        text = text.replace('PYTHON_INCLUDE_REPLACEME', includes)
        text = text.replace('PYTHON_LIB_REPLACEME', libs)
        text = text.replace('CUDA_DIR_REPLACEME', os.getenv('CUDA_DIR'))

        with open(output_path, 'w') as f:
          f.write(text)
      '';

      mkCaffe = config: mkDerivation {
        inherit name;
        src = builtins.fetchGit {
          inherit name;
          url = "https://github.com/BVLC/caffe.git";
          ref = "refs/tags/1.0";
          rev = "eeebdab16155d34ff8f5f42137da7df4d1c7eab0";
        };

        buildInputs = caffePkgs;

        configurePhase = ''
          export BOOST_LIB="${pyPkgs.boost.outPath}/lib"
          export CUDA_DIR="${pkgs.cudatoolkit.outPath}/"

          python ${pythonConfigPatcher} ${caffeMakefileConfig} Makefile.config
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
        default = mkCaffe {};
        release = mkCaffe {};
      };
    in {
      packages.${system} = packages;
    };
}
