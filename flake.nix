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
        python27
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

        PYTHON_INCLUDE := /usr/include/python2.7 \
            /usr/lib/python2.7/dist-packages/numpy/core/include
        PYTHON_LIB := /usr/lib

        INCLUDE_DIRS := $(PYTHON_INCLUDE) /usr/local/include
        LIBRARY_DIRS := $(PYTHON_LIB) /usr/local/lib /usr/lib

        BUILD_DIR := build
        DISTRIBUTE_DIR := distribute

        TEST_GPUID := 0

        Q ?= @
      '';

      mkCaffe = cripple: mkDerivation {
        inherit name;
        src = builtins.fetchGit {
          url = "https://github.com/BVLC/caffe.git";
          ref = "refs/tags/1.0";
          rev = "eeebdab16155d34ff8f5f42137da7df4d1c7eab0";
        };

        buildInputs = caffePkgs cripple;

        configurePhase = ''
          cp ${caffeMakefileConfig} Makefile.config
        '';

        buildPhase = ''
          make -j`nproc` all
        '';

        checkPhase = ''
          make test
          make runtest
        '';

        installPhase = ''
          mkdir -p $out/
          cp -r ./build/* $out/
          cp -r ./include/ $out/
        '';
      };

      packages = {
        default = mkCaffe false;
        release = mkCaffe false;
        crippled = mkCaffe true;
      };
    in {
      packages.${system} = packages;
    };
}
