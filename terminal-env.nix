{ pkgs, unstable, isGraphical, agenix, ... }:
let
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    ipython pandas matplotlib seaborn pyyaml
    boto3 tqdm duckdb
  ]);
  vim-with-custom-rc = pkgs.vim-full.customize {
    vimrcConfig = {
      customRC = ''
        filetype plugin indent on
        syntax on
        set number relativenumber
        set tabstop=4
        set softtabstop=4
        set expandtab
        set shiftwidth=4
        set smarttab
        set clipboard=unnamed
        set noerrorbells
        set vb t_vb=
        colorscheme torte
      '';
    };
  };
in {
  environment.systemPackages = with pkgs; [
    git
    unstable.lunarvim
    ripgrep # for project-wide search in emacs
    fzf # for reverse history search in fish shell
    wget
    bat
    tree
    zip
    unzip
    nmap
    gnupg
    sl
    btop
    file
    iotop
    jq
    pythonEnv
    kitty
    xclip
    vim-with-custom-rc
    broot
    unstable.zellij
    pgbackrest
    agenix.packages.${system}.agenix
    rclone
    restic
    awscli2
    bashmount
    docker
    pgcli
    gh
    nettools
    pkgs.fishPlugins.fzf
    (pkgs.fishPlugins.buildFishPlugin {
      pname = "batman";
      version = "hello";
      src = pkgs.fetchFromGitHub {
        owner = "oh-my-fish";
        repo = "theme-batman";
        rev = "2a76bd81f4805debd7f137cb98828bff34570562";
        sha256 = "Ko4w9tMnIi17db174FzW44LgUdui/bUzPFEHEHv//t4=";
      };
    })
  ] ++ (if isGraphical then [
    (unstable.wrapFirefox (unstable.firefox-unwrapped.override { pipewireSupport = true;}) {})
    vlc
    pulsemixer
    libreoffice
    simplescreenrecorder
    unstable.slack
    unstable.zoom-us
    libnotify
  ] else []);
}
